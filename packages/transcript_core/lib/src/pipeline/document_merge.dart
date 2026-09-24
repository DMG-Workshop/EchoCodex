/// Stitches the per-window partial documents of a long recording into one document,
/// without asking a model.
///
/// Why this exists: merging with the model is bounded by the model's context, and the
/// input to that merge grows with the length of the recording. Every partial is a whole
/// NoteDocument — summary, sections, tasks, decisions, and a verbatim quote behind each
/// item — so past a certain length the merge prompt does not fit, and the note that should
/// have been produced comes back as "the model could not produce a valid note" instead.
/// That length is short when the server will not say how big its context is: an assumed
/// 8k window leaves about 2,500 tokens for the merge, which is less than two partials.
///
/// Everything a merge actually has to do is mechanical: union the roster, keep the sections
/// in recording order, drop the repeats, take the lowest confidence, keep every id unique
/// and every reference pointing at the thing it pointed at before. So it is done here —
/// deterministically, for free, and with no upper bound on how long the recording was.
///
/// What this deliberately does not do is write prose. A whole-recording summary wants a
/// model; [stitchNoteDocuments] joins the section summaries so the document is always
/// complete, and the caller replaces that with one small model pass over the section
/// summaries alone, which fits any context.
library;

/// Merges [partials] into a single NoteDocument-shaped map.
///
/// The result validates against the same schema the partials do: this is a merge, not a
/// transformation. Items are kept in the order the recording produced them.
Map<String, dynamic> stitchNoteDocuments(List<Map<String, dynamic>> partials) {
  if (partials.isEmpty) {
    throw ArgumentError.value(partials, 'partials', 'nothing to stitch');
  }
  if (partials.length == 1) return partials.single;

  final stitch = _Stitch();
  for (final partial in partials) {
    stitch.add(partial);
  }
  return stitch.build();
}

/// The accumulator. One instance per merge; [add] is called once per window, in order.
class _Stitch {
  final List<Map<String, dynamic>> _metas = [];

  // Identity key -> merged item, in first-seen order. A LinkedHashMap by default, which
  // is what keeps the output in recording order without a separate sort.
  final Map<String, Map<String, dynamic>> _participants = {};
  final Map<String, Map<String, dynamic>> _sections = {};
  final Map<String, Map<String, dynamic>> _tasks = {};
  final Map<String, Map<String, dynamic>> _decisions = {};
  final Map<String, Map<String, dynamic>> _questions = {};
  final Map<String, Map<String, dynamic>> _risks = {};
  final Map<String, Map<String, dynamic>> _anchors = {};
  final Map<String, Map<String, dynamic>> _concepts = {};
  final Map<String, Map<String, dynamic>> _flashcards = {};
  final Map<String, Map<String, dynamic>> _quiz = {};

  /// Whether any window supplied study aids at all. The schema distinguishes an empty
  /// list ("asked for, none warranted") from null ("not asked for"), and flattening the
  /// two would turn the study tab on for every recording.
  var _sawConcepts = false;
  var _sawFlashcards = false;
  var _sawQuiz = false;

  /// Every id handed out so far, across all kinds. Two windows that numbered a different
  /// task `t1` must not collapse into one card on the board.
  final Set<String> _usedIds = {};

  void add(Map<String, dynamic> partial) {
    _metas.add(_asMap(partial['meta']));

    // Ids first, in two maps, because they are the only ones anything refers to:
    // assigneeId and decidedBy point at participants, dependsOn points at tasks. Both
    // have to be settled before the items that cite them are rewritten.
    final people =
        _planIds(_list(partial, 'participants'), _participants, _personKey);
    final tasks = _planIds(_list(partial, 'tasks'), _tasks, _taskKey);

    for (final person in _list(partial, 'participants')) {
      _absorb(
          _participants,
          _personKey,
          {
            ...person,
            'id': people[_text(person['id'])] ?? _text(person['id']),
          },
          _mergePerson);
    }

    for (final section in _list(partial, 'sections')) {
      _absorb(_sections, _sectionKey, section, _mergeSection);
    }

    for (final task in _list(partial, 'tasks')) {
      _absorb(
          _tasks,
          _taskKey,
          {
            ...task,
            'id': tasks[_text(task['id'])] ?? _text(task['id']),
            'assigneeId': _remap(task['assigneeId'], people),
            'dependsOn': [
              for (final dep in _strings(task, 'dependsOn')) tasks[dep] ?? dep,
            ],
          },
          _mergeTask);
    }

    for (final decision in _list(partial, 'decisions')) {
      _absorb(
          _decisions,
          _decisionKey,
          {
            ...decision,
            'id': _reserveFor(_decisions, _decisionKey, decision),
            'decidedBy': _remap(decision['decidedBy'], people),
          },
          _fillNulls);
    }

    for (final question in _list(partial, 'openQuestions')) {
      _absorb(
          _questions,
          _questionKey,
          {
            ...question,
            'id': _reserveFor(_questions, _questionKey, question),
            'raisedBy': _remap(question['raisedBy'], people),
          },
          _fillNulls);
    }

    for (final risk in _list(partial, 'risks')) {
      _absorb(
          _risks,
          _riskKey,
          {
            ...risk,
            'id': _reserveFor(_risks, _riskKey, risk),
          },
          _fillNulls);
    }

    for (final anchor in _list(partial, 'timelineAnchors')) {
      _absorb(_anchors, _anchorKey, anchor, _fillNulls);
    }

    _sawConcepts |= partial['keyConcepts'] is List;
    for (final concept in _list(partial, 'keyConcepts')) {
      _absorb(_concepts, (m) => _norm(m['term']), concept, _fillNulls);
    }
    _sawFlashcards |= partial['flashcards'] is List;
    for (final card in _list(partial, 'flashcards')) {
      _absorb(_flashcards, (m) => _norm(m['front']), card, _fillNulls);
    }
    _sawQuiz |= partial['quiz'] is List;
    for (final question in _list(partial, 'quiz')) {
      _absorb(_quiz, (m) => _norm(m['question']), question, _fillNulls);
    }
  }

  Map<String, dynamic> build() => {
        'meta': _meta(),
        'participants': _participants.values.toList(),
        'sections': _sections.values.toList(),
        'decisions': _decisions.values.toList(),
        'openQuestions': _questions.values.toList(),
        'tasks': _tasks.values.toList(),
        'risks': _risks.values.toList(),
        'timelineAnchors': _anchors.values.toList(),
        'keyConcepts': _sawConcepts ? _concepts.values.toList() : null,
        'flashcards': _sawFlashcards ? _flashcards.values.toList() : null,
        'quiz': _sawQuiz ? _quiz.values.toList() : null,
      };

  /// The section summaries, joined. Placeholder prose: readable, complete, and replaced
  /// by [StructuringPipeline] with a model-written summary whenever one can be had.
  Map<String, dynamic> _meta() {
    final summaries = <String>[];
    for (final meta in _metas) {
      final summary = _text(meta['summary']).trim();
      if (summary.isNotEmpty && !summaries.contains(summary)) {
        summaries.add(summary);
      }
    }
    return {
      'title': _metas
          .map((m) => _text(m['title']).trim())
          .firstWhere((t) => t.isNotEmpty, orElse: () => 'Recording'),
      'summary': summaries.join(' '),
      'recordingType': _commonest(
          [for (final m in _metas) _text(m['recordingType'])], 'other'),
      'language':
          _commonest([for (final m in _metas) _text(m['language'])], 'en'),
      // A merged document is only as trustworthy as its least trustworthy window, which
      // is also what the model-led merge is told to do.
      'extractionConfidence': _lowestConfidence(),
    };
  }

  String _lowestConfidence() {
    const order = ['low', 'medium', 'high'];
    var lowest = 2;
    for (final meta in _metas) {
      final index = order.indexOf(_text(meta['extractionConfidence']));
      if (index >= 0 && index < lowest) lowest = index;
    }
    return order[lowest];
  }

  /// Decides the final id for every id [items] declares, before anything is absorbed.
  ///
  /// Three outcomes: an item matching one already merged takes that item's id, so the two
  /// windows' references converge; a free id is kept, because a slug the model chose is
  /// more legible than one generated here; a clash with a different thing is suffixed.
  Map<String, String> _planIds(
    List<Map<String, dynamic>> items,
    Map<String, Map<String, dynamic>> into,
    String Function(Map<String, dynamic>) identity,
  ) {
    final rename = <String, String>{};
    // Two items in the SAME window can share an identity; the second must resolve to the
    // first's id rather than reserving a second one.
    final withinWindow = <String, String>{};

    for (final item in items) {
      final key = identity(item);
      final settled = _text(into[key]?['id']);
      final taken = settled.isNotEmpty ? settled : withinWindow[key];
      final original = _text(item['id']);
      if (taken != null) {
        rename[original] = taken;
        continue;
      }
      final assigned = _reserve(original.isEmpty ? key : original);
      withinWindow[key] = assigned;
      rename[original] = assigned;
    }
    return rename;
  }

  /// The final id for an item of a kind nothing refers to, so no rename map is needed.
  String _reserveFor(
    Map<String, Map<String, dynamic>> into,
    String Function(Map<String, dynamic>) identity,
    Map<String, dynamic> item,
  ) {
    final existing = _text(into[identity(item)]?['id']);
    if (existing.isNotEmpty) return existing;
    final original = _text(item['id']);
    return _reserve(original.isEmpty ? identity(item) : original);
  }

  String _reserve(String id) {
    final base = id.isEmpty ? 'item' : id;
    if (_usedIds.add(base)) return base;
    for (var n = 2;; n++) {
      final candidate = '${base}_$n';
      if (_usedIds.add(candidate)) return candidate;
    }
  }

  static void _absorb(
    Map<String, Map<String, dynamic>> into,
    String Function(Map<String, dynamic>) identity,
    Map<String, dynamic> item,
    void Function(Map<String, dynamic> kept, Map<String, dynamic> incoming)
        merge,
  ) {
    final key = identity(item);
    // Nothing to identify it by — an empty heading or title. It still gets a place: losing
    // part of the meeting to make the bookkeeping work is not a trade this makes. The key
    // is one no normalised text can produce, so two of them stay separate.
    final kept = key.isEmpty ? null : into[key];
    if (kept == null) {
      into[key.isEmpty ? '\u0000${into.length}' : key] =
          Map<String, dynamic>.of(item);
      return;
    }
    merge(kept, item);
  }

  static void _mergePerson(
      Map<String, dynamic> kept, Map<String, dynamic> incoming) {
    // Every form the same person was heard as is worth keeping: it is what lets a later
    // recording recognise them, and what the speaker-naming UI offers as suggestions.
    final aliases = _strings(kept, 'aliases');
    for (final alias in [
      ..._strings(incoming, 'aliases'),
      _text(incoming['displayName']),
    ]) {
      if (alias.isNotEmpty &&
          _norm(alias) != _norm(kept['displayName']) &&
          !aliases.any((a) => _norm(a) == _norm(alias))) {
        aliases.add(alias);
      }
    }
    kept['aliases'] = aliases;
    _fillNulls(kept, incoming);
  }

  static void _mergeSection(
      Map<String, dynamic> kept, Map<String, dynamic> incoming) {
    // Two windows that both discussed "Release planning" become one section rather than
    // two with the same heading, which reads as a transcription glitch.
    final bullets = _strings(kept, 'bullets');
    for (final bullet in _strings(incoming, 'bullets')) {
      if (bullet.isNotEmpty && !bullets.any((b) => _norm(b) == _norm(bullet))) {
        bullets.add(bullet);
      }
    }
    kept['bullets'] = bullets;
  }

  static void _mergeTask(
      Map<String, dynamic> kept, Map<String, dynamic> incoming) {
    final deps = _strings(kept, 'dependsOn');
    for (final dep in _strings(incoming, 'dependsOn')) {
      if (dep.isNotEmpty && !deps.contains(dep)) deps.add(dep);
    }
    kept['dependsOn'] = deps;

    // A commitment reported as finished later in the recording is finished, and one that
    // grew more urgent is more urgent. Nothing here ever walks a task backwards.
    const statuses = ['todo', 'in_progress', 'blocked', 'done'];
    if (statuses.indexOf(_text(incoming['status'])) >
        statuses.indexOf(_text(kept['status']))) {
      kept['status'] = incoming['status'];
    }
    const priorities = ['low', 'medium', 'high', 'critical'];
    if (priorities.indexOf(_text(incoming['priority'])) >
        priorities.indexOf(_text(kept['priority']))) {
      kept['priority'] = incoming['priority'];
    }

    // An explicit date beats an inferred one, and the basis travels with it. Never the
    // other way round: a guess must not overwrite something that was actually said.
    if (_text(incoming['dateBasis']) == 'explicit' &&
        _text(kept['dateBasis']) != 'explicit') {
      kept['startDate'] = incoming['startDate'];
      kept['dueDate'] = incoming['dueDate'];
      kept['dateBasis'] = 'explicit';
    }

    _fillNulls(kept, incoming);
  }

  /// Takes anything the kept copy is missing. Never overwrites: the first window to say
  /// something is the one closest to where it was said.
  static void _fillNulls(
      Map<String, dynamic> kept, Map<String, dynamic> incoming) {
    for (final entry in incoming.entries) {
      if (entry.key == 'id') continue;
      final current = kept[entry.key];
      final missing = current == null ||
          (current is String && current.isEmpty) ||
          (current is List && current.isEmpty);
      if (missing && entry.value != null) kept[entry.key] = entry.value;
    }
  }
}

// --- Identity -----------------------------------------------------------------------
//
// What makes two items "the same item in two windows". Normalised text rather than the
// model's id, because the ids are per-window and the text is what the user reads.

String _personKey(Map<String, dynamic> m) {
  final name = _norm(m['displayName']);
  return name.isNotEmpty ? 'name:$name' : 'id:${_norm(m['id'])}';
}

String _sectionKey(Map<String, dynamic> m) => _norm(m['heading']);

String _taskKey(Map<String, dynamic> m) => _norm(m['title']);

String _decisionKey(Map<String, dynamic> m) => _norm(m['statement']);

String _questionKey(Map<String, dynamic> m) => _norm(m['question']);

String _riskKey(Map<String, dynamic> m) => _norm(m['description']);

String _anchorKey(Map<String, dynamic> m) =>
    '${_norm(m['label'])}@${_text(m['date'])}';

// --- Plumbing -----------------------------------------------------------------------

/// Lower-cased, punctuation-stripped, whitespace-collapsed. Enough to see that
/// "Send Priya the deck." and "send priya the deck" are one task, and not so aggressive
/// that two genuinely different items merge.
String _norm(Object? value) => _text(value)
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String _text(Object? value) => value == null ? '' : value.toString();

/// The value most windows agreed on, or [fallback] if none of them said anything.
///
/// A vote rather than the first window's answer: one section of a lecture that reads like
/// a conversation should not relabel the whole recording.
String _commonest(Iterable<String> values, String fallback) {
  final counts = <String, int>{};
  for (final value in values) {
    if (value.isNotEmpty) counts[value] = (counts[value] ?? 0) + 1;
  }
  if (counts.isEmpty) return fallback;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

/// Whatever is at [key], as a list. A malformed partial gives nothing rather than
/// throwing: this runs after schema validation, but the merge is the last thing standing
/// between a long recording and no note at all.
List<Map<String, dynamic>> _list(Map<String, dynamic> owner, String key) {
  final value = owner[key];
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) item.cast<String, dynamic>(),
  ];
}

/// Whatever is at [key], as a list of non-empty strings.
List<String> _strings(Map<String, dynamic> owner, String key) {
  final value = owner[key];
  if (value is! List) return <String>[];
  return [
    for (final item in value)
      if (item != null && _text(item).isNotEmpty) _text(item),
  ];
}

Object? _remap(Object? id, Map<String, String> rename) =>
    id == null ? null : rename[_text(id)] ?? id;
