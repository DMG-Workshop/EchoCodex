// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RecordingsTable extends Recordings
    with TableInfo<$RecordingsTable, Recording> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _startedAtMeta =
      const VerificationMeta('startedAt');
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
      'started_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _audioPathMeta =
      const VerificationMeta('audioPath');
  @override
  late final GeneratedColumn<String> audioPath = GeneratedColumn<String>(
      'audio_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _transcriptionProviderIdMeta =
      const VerificationMeta('transcriptionProviderId');
  @override
  late final GeneratedColumn<String> transcriptionProviderId =
      GeneratedColumn<String>('transcription_provider_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _structuringProviderIdMeta =
      const VerificationMeta('structuringProviderId');
  @override
  late final GeneratedColumn<String> structuringProviderId =
      GeneratedColumn<String>('structuring_provider_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _structuringModelMeta =
      const VerificationMeta('structuringModel');
  @override
  late final GeneratedColumn<String> structuringModel = GeneratedColumn<String>(
      'structuring_model', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteJsonMeta =
      const VerificationMeta('noteJson');
  @override
  late final GeneratedColumn<String> noteJson = GeneratedColumn<String>(
      'note_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _noteSchemaVersionMeta =
      const VerificationMeta('noteSchemaVersion');
  @override
  late final GeneratedColumn<String> noteSchemaVersion =
      GeneratedColumn<String>('note_schema_version', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _promptVersionMeta =
      const VerificationMeta('promptVersion');
  @override
  late final GeneratedColumn<String> promptVersion = GeneratedColumn<String>(
      'prompt_version', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _inputTokensMeta =
      const VerificationMeta('inputTokens');
  @override
  late final GeneratedColumn<int> inputTokens = GeneratedColumn<int>(
      'input_tokens', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _outputTokensMeta =
      const VerificationMeta('outputTokens');
  @override
  late final GeneratedColumn<int> outputTokens = GeneratedColumn<int>(
      'output_tokens', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _transcriptTextMeta =
      const VerificationMeta('transcriptText');
  @override
  late final GeneratedColumn<String> transcriptText = GeneratedColumn<String>(
      'transcript_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _transcriptSegmentsJsonMeta =
      const VerificationMeta('transcriptSegmentsJson');
  @override
  late final GeneratedColumn<String> transcriptSegmentsJson =
      GeneratedColumn<String>('transcript_segments_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _speakerNamesJsonMeta =
      const VerificationMeta('speakerNamesJson');
  @override
  late final GeneratedColumn<String> speakerNamesJson = GeneratedColumn<String>(
      'speaker_names_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _cleanedTranscriptTextMeta =
      const VerificationMeta('cleanedTranscriptText');
  @override
  late final GeneratedColumn<String> cleanedTranscriptText =
      GeneratedColumn<String>('cleaned_transcript_text', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _priorityMeta =
      const VerificationMeta('priority');
  @override
  late final GeneratedColumn<bool> priority = GeneratedColumn<bool>(
      'priority', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("priority" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _localOnlyMeta =
      const VerificationMeta('localOnly');
  @override
  late final GeneratedColumn<bool> localOnly = GeneratedColumn<bool>(
      'local_only', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("local_only" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _templateIdMeta =
      const VerificationMeta('templateId');
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
      'template_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        title,
        startedAt,
        durationMs,
        audioPath,
        transcriptionProviderId,
        structuringProviderId,
        structuringModel,
        noteJson,
        noteSchemaVersion,
        promptVersion,
        inputTokens,
        outputTokens,
        transcriptText,
        transcriptSegmentsJson,
        speakerNamesJson,
        cleanedTranscriptText,
        priority,
        localOnly,
        templateId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recordings';
  @override
  VerificationContext validateIntegrity(Insertable<Recording> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    }
    if (data.containsKey('started_at')) {
      context.handle(_startedAtMeta,
          startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta));
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('audio_path')) {
      context.handle(_audioPathMeta,
          audioPath.isAcceptableOrUnknown(data['audio_path']!, _audioPathMeta));
    }
    if (data.containsKey('transcription_provider_id')) {
      context.handle(
          _transcriptionProviderIdMeta,
          transcriptionProviderId.isAcceptableOrUnknown(
              data['transcription_provider_id']!,
              _transcriptionProviderIdMeta));
    }
    if (data.containsKey('structuring_provider_id')) {
      context.handle(
          _structuringProviderIdMeta,
          structuringProviderId.isAcceptableOrUnknown(
              data['structuring_provider_id']!, _structuringProviderIdMeta));
    }
    if (data.containsKey('structuring_model')) {
      context.handle(
          _structuringModelMeta,
          structuringModel.isAcceptableOrUnknown(
              data['structuring_model']!, _structuringModelMeta));
    }
    if (data.containsKey('note_json')) {
      context.handle(_noteJsonMeta,
          noteJson.isAcceptableOrUnknown(data['note_json']!, _noteJsonMeta));
    }
    if (data.containsKey('note_schema_version')) {
      context.handle(
          _noteSchemaVersionMeta,
          noteSchemaVersion.isAcceptableOrUnknown(
              data['note_schema_version']!, _noteSchemaVersionMeta));
    }
    if (data.containsKey('prompt_version')) {
      context.handle(
          _promptVersionMeta,
          promptVersion.isAcceptableOrUnknown(
              data['prompt_version']!, _promptVersionMeta));
    }
    if (data.containsKey('input_tokens')) {
      context.handle(
          _inputTokensMeta,
          inputTokens.isAcceptableOrUnknown(
              data['input_tokens']!, _inputTokensMeta));
    }
    if (data.containsKey('output_tokens')) {
      context.handle(
          _outputTokensMeta,
          outputTokens.isAcceptableOrUnknown(
              data['output_tokens']!, _outputTokensMeta));
    }
    if (data.containsKey('transcript_text')) {
      context.handle(
          _transcriptTextMeta,
          transcriptText.isAcceptableOrUnknown(
              data['transcript_text']!, _transcriptTextMeta));
    }
    if (data.containsKey('transcript_segments_json')) {
      context.handle(
          _transcriptSegmentsJsonMeta,
          transcriptSegmentsJson.isAcceptableOrUnknown(
              data['transcript_segments_json']!, _transcriptSegmentsJsonMeta));
    }
    if (data.containsKey('speaker_names_json')) {
      context.handle(
          _speakerNamesJsonMeta,
          speakerNamesJson.isAcceptableOrUnknown(
              data['speaker_names_json']!, _speakerNamesJsonMeta));
    }
    if (data.containsKey('cleaned_transcript_text')) {
      context.handle(
          _cleanedTranscriptTextMeta,
          cleanedTranscriptText.isAcceptableOrUnknown(
              data['cleaned_transcript_text']!, _cleanedTranscriptTextMeta));
    }
    if (data.containsKey('priority')) {
      context.handle(_priorityMeta,
          priority.isAcceptableOrUnknown(data['priority']!, _priorityMeta));
    }
    if (data.containsKey('local_only')) {
      context.handle(_localOnlyMeta,
          localOnly.isAcceptableOrUnknown(data['local_only']!, _localOnlyMeta));
    }
    if (data.containsKey('template_id')) {
      context.handle(
          _templateIdMeta,
          templateId.isAcceptableOrUnknown(
              data['template_id']!, _templateIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Recording map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Recording(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      startedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}started_at'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      audioPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}audio_path']),
      transcriptionProviderId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}transcription_provider_id']),
      structuringProviderId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}structuring_provider_id']),
      structuringModel: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}structuring_model']),
      noteJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note_json']),
      noteSchemaVersion: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}note_schema_version']),
      promptVersion: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}prompt_version']),
      inputTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}input_tokens']),
      outputTokens: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}output_tokens']),
      transcriptText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}transcript_text']),
      transcriptSegmentsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}transcript_segments_json']),
      speakerNamesJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}speaker_names_json']),
      cleanedTranscriptText: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}cleaned_transcript_text']),
      priority: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}priority'])!,
      localOnly: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}local_only'])!,
      templateId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}template_id']),
    );
  }

  @override
  $RecordingsTable createAlias(String alias) {
    return $RecordingsTable(attachedDatabase, alias);
  }
}

class Recording extends DataClass implements Insertable<Recording> {
  final String id;
  final String title;
  final DateTime startedAt;
  final int durationMs;

  /// Path to the compressed copy kept for playback. The working PCM is deleted once
  /// every chunk reaches a terminal state.
  final String? audioPath;
  final String? transcriptionProviderId;
  final String? structuringProviderId;

  /// The model that actually produced the note, as the provider reported it. The
  /// provider id alone says nothing about the rate, so the cost meter prices on this.
  final String? structuringModel;

  /// The note document as returned, so a schema change never orphans an old note.
  final String? noteJson;
  final String? noteSchemaVersion;
  final String? promptVersion;
  final int? inputTokens;
  final int? outputTokens;

  /// The assembled transcript exactly as spoken, before any cleanup. Kept even when
  /// [cleanedTranscriptText] exists, so nothing the user said is ever only reachable
  /// through an edited version of it.
  final String? transcriptText;

  /// Timestamped transcript segments, including provider speaker labels.
  final String? transcriptSegmentsJson;

  /// User-edited names keyed by the provider's speaker label.
  final String? speakerNamesJson;

  /// [transcriptText] with filler words and stutters removed, when the punctuation and
  /// filler cleanup workflow feature is on. Null when the feature is off or cleanup has
  /// not run for this recording.
  final String? cleanedTranscriptText;

  /// Marked to jump the backlog when several recordings are waiting to be transcribed —
  /// see the priority transcription queue workflow feature.
  final bool priority;

  /// When true, this recording may only use on-device or user-owned local providers.
  final bool localOnly;

  /// The template used to structure this recording, if any.
  final String? templateId;
  const Recording(
      {required this.id,
      required this.title,
      required this.startedAt,
      required this.durationMs,
      this.audioPath,
      this.transcriptionProviderId,
      this.structuringProviderId,
      this.structuringModel,
      this.noteJson,
      this.noteSchemaVersion,
      this.promptVersion,
      this.inputTokens,
      this.outputTokens,
      this.transcriptText,
      this.transcriptSegmentsJson,
      this.speakerNamesJson,
      this.cleanedTranscriptText,
      required this.priority,
      required this.localOnly,
      this.templateId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['title'] = Variable<String>(title);
    map['started_at'] = Variable<DateTime>(startedAt);
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || audioPath != null) {
      map['audio_path'] = Variable<String>(audioPath);
    }
    if (!nullToAbsent || transcriptionProviderId != null) {
      map['transcription_provider_id'] =
          Variable<String>(transcriptionProviderId);
    }
    if (!nullToAbsent || structuringProviderId != null) {
      map['structuring_provider_id'] = Variable<String>(structuringProviderId);
    }
    if (!nullToAbsent || structuringModel != null) {
      map['structuring_model'] = Variable<String>(structuringModel);
    }
    if (!nullToAbsent || noteJson != null) {
      map['note_json'] = Variable<String>(noteJson);
    }
    if (!nullToAbsent || noteSchemaVersion != null) {
      map['note_schema_version'] = Variable<String>(noteSchemaVersion);
    }
    if (!nullToAbsent || promptVersion != null) {
      map['prompt_version'] = Variable<String>(promptVersion);
    }
    if (!nullToAbsent || inputTokens != null) {
      map['input_tokens'] = Variable<int>(inputTokens);
    }
    if (!nullToAbsent || outputTokens != null) {
      map['output_tokens'] = Variable<int>(outputTokens);
    }
    if (!nullToAbsent || transcriptText != null) {
      map['transcript_text'] = Variable<String>(transcriptText);
    }
    if (!nullToAbsent || transcriptSegmentsJson != null) {
      map['transcript_segments_json'] =
          Variable<String>(transcriptSegmentsJson);
    }
    if (!nullToAbsent || speakerNamesJson != null) {
      map['speaker_names_json'] = Variable<String>(speakerNamesJson);
    }
    if (!nullToAbsent || cleanedTranscriptText != null) {
      map['cleaned_transcript_text'] = Variable<String>(cleanedTranscriptText);
    }
    map['priority'] = Variable<bool>(priority);
    map['local_only'] = Variable<bool>(localOnly);
    if (!nullToAbsent || templateId != null) {
      map['template_id'] = Variable<String>(templateId);
    }
    return map;
  }

  RecordingsCompanion toCompanion(bool nullToAbsent) {
    return RecordingsCompanion(
      id: Value(id),
      title: Value(title),
      startedAt: Value(startedAt),
      durationMs: Value(durationMs),
      audioPath: audioPath == null && nullToAbsent
          ? const Value.absent()
          : Value(audioPath),
      transcriptionProviderId: transcriptionProviderId == null && nullToAbsent
          ? const Value.absent()
          : Value(transcriptionProviderId),
      structuringProviderId: structuringProviderId == null && nullToAbsent
          ? const Value.absent()
          : Value(structuringProviderId),
      structuringModel: structuringModel == null && nullToAbsent
          ? const Value.absent()
          : Value(structuringModel),
      noteJson: noteJson == null && nullToAbsent
          ? const Value.absent()
          : Value(noteJson),
      noteSchemaVersion: noteSchemaVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(noteSchemaVersion),
      promptVersion: promptVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(promptVersion),
      inputTokens: inputTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(inputTokens),
      outputTokens: outputTokens == null && nullToAbsent
          ? const Value.absent()
          : Value(outputTokens),
      transcriptText: transcriptText == null && nullToAbsent
          ? const Value.absent()
          : Value(transcriptText),
      transcriptSegmentsJson: transcriptSegmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(transcriptSegmentsJson),
      speakerNamesJson: speakerNamesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(speakerNamesJson),
      cleanedTranscriptText: cleanedTranscriptText == null && nullToAbsent
          ? const Value.absent()
          : Value(cleanedTranscriptText),
      priority: Value(priority),
      localOnly: Value(localOnly),
      templateId: templateId == null && nullToAbsent
          ? const Value.absent()
          : Value(templateId),
    );
  }

  factory Recording.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Recording(
      id: serializer.fromJson<String>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      audioPath: serializer.fromJson<String?>(json['audioPath']),
      transcriptionProviderId:
          serializer.fromJson<String?>(json['transcriptionProviderId']),
      structuringProviderId:
          serializer.fromJson<String?>(json['structuringProviderId']),
      structuringModel: serializer.fromJson<String?>(json['structuringModel']),
      noteJson: serializer.fromJson<String?>(json['noteJson']),
      noteSchemaVersion:
          serializer.fromJson<String?>(json['noteSchemaVersion']),
      promptVersion: serializer.fromJson<String?>(json['promptVersion']),
      inputTokens: serializer.fromJson<int?>(json['inputTokens']),
      outputTokens: serializer.fromJson<int?>(json['outputTokens']),
      transcriptText: serializer.fromJson<String?>(json['transcriptText']),
      transcriptSegmentsJson:
          serializer.fromJson<String?>(json['transcriptSegmentsJson']),
      speakerNamesJson: serializer.fromJson<String?>(json['speakerNamesJson']),
      cleanedTranscriptText:
          serializer.fromJson<String?>(json['cleanedTranscriptText']),
      priority: serializer.fromJson<bool>(json['priority']),
      localOnly: serializer.fromJson<bool>(json['localOnly']),
      templateId: serializer.fromJson<String?>(json['templateId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'title': serializer.toJson<String>(title),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'durationMs': serializer.toJson<int>(durationMs),
      'audioPath': serializer.toJson<String?>(audioPath),
      'transcriptionProviderId':
          serializer.toJson<String?>(transcriptionProviderId),
      'structuringProviderId':
          serializer.toJson<String?>(structuringProviderId),
      'structuringModel': serializer.toJson<String?>(structuringModel),
      'noteJson': serializer.toJson<String?>(noteJson),
      'noteSchemaVersion': serializer.toJson<String?>(noteSchemaVersion),
      'promptVersion': serializer.toJson<String?>(promptVersion),
      'inputTokens': serializer.toJson<int?>(inputTokens),
      'outputTokens': serializer.toJson<int?>(outputTokens),
      'transcriptText': serializer.toJson<String?>(transcriptText),
      'transcriptSegmentsJson':
          serializer.toJson<String?>(transcriptSegmentsJson),
      'speakerNamesJson': serializer.toJson<String?>(speakerNamesJson),
      'cleanedTranscriptText':
          serializer.toJson<String?>(cleanedTranscriptText),
      'priority': serializer.toJson<bool>(priority),
      'localOnly': serializer.toJson<bool>(localOnly),
      'templateId': serializer.toJson<String?>(templateId),
    };
  }

  Recording copyWith(
          {String? id,
          String? title,
          DateTime? startedAt,
          int? durationMs,
          Value<String?> audioPath = const Value.absent(),
          Value<String?> transcriptionProviderId = const Value.absent(),
          Value<String?> structuringProviderId = const Value.absent(),
          Value<String?> structuringModel = const Value.absent(),
          Value<String?> noteJson = const Value.absent(),
          Value<String?> noteSchemaVersion = const Value.absent(),
          Value<String?> promptVersion = const Value.absent(),
          Value<int?> inputTokens = const Value.absent(),
          Value<int?> outputTokens = const Value.absent(),
          Value<String?> transcriptText = const Value.absent(),
          Value<String?> transcriptSegmentsJson = const Value.absent(),
          Value<String?> speakerNamesJson = const Value.absent(),
          Value<String?> cleanedTranscriptText = const Value.absent(),
          bool? priority,
          bool? localOnly,
          Value<String?> templateId = const Value.absent()}) =>
      Recording(
        id: id ?? this.id,
        title: title ?? this.title,
        startedAt: startedAt ?? this.startedAt,
        durationMs: durationMs ?? this.durationMs,
        audioPath: audioPath.present ? audioPath.value : this.audioPath,
        transcriptionProviderId: transcriptionProviderId.present
            ? transcriptionProviderId.value
            : this.transcriptionProviderId,
        structuringProviderId: structuringProviderId.present
            ? structuringProviderId.value
            : this.structuringProviderId,
        structuringModel: structuringModel.present
            ? structuringModel.value
            : this.structuringModel,
        noteJson: noteJson.present ? noteJson.value : this.noteJson,
        noteSchemaVersion: noteSchemaVersion.present
            ? noteSchemaVersion.value
            : this.noteSchemaVersion,
        promptVersion:
            promptVersion.present ? promptVersion.value : this.promptVersion,
        inputTokens: inputTokens.present ? inputTokens.value : this.inputTokens,
        outputTokens:
            outputTokens.present ? outputTokens.value : this.outputTokens,
        transcriptText:
            transcriptText.present ? transcriptText.value : this.transcriptText,
        transcriptSegmentsJson: transcriptSegmentsJson.present
            ? transcriptSegmentsJson.value
            : this.transcriptSegmentsJson,
        speakerNamesJson: speakerNamesJson.present
            ? speakerNamesJson.value
            : this.speakerNamesJson,
        cleanedTranscriptText: cleanedTranscriptText.present
            ? cleanedTranscriptText.value
            : this.cleanedTranscriptText,
        priority: priority ?? this.priority,
        localOnly: localOnly ?? this.localOnly,
        templateId: templateId.present ? templateId.value : this.templateId,
      );
  Recording copyWithCompanion(RecordingsCompanion data) {
    return Recording(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      audioPath: data.audioPath.present ? data.audioPath.value : this.audioPath,
      transcriptionProviderId: data.transcriptionProviderId.present
          ? data.transcriptionProviderId.value
          : this.transcriptionProviderId,
      structuringProviderId: data.structuringProviderId.present
          ? data.structuringProviderId.value
          : this.structuringProviderId,
      structuringModel: data.structuringModel.present
          ? data.structuringModel.value
          : this.structuringModel,
      noteJson: data.noteJson.present ? data.noteJson.value : this.noteJson,
      noteSchemaVersion: data.noteSchemaVersion.present
          ? data.noteSchemaVersion.value
          : this.noteSchemaVersion,
      promptVersion: data.promptVersion.present
          ? data.promptVersion.value
          : this.promptVersion,
      inputTokens:
          data.inputTokens.present ? data.inputTokens.value : this.inputTokens,
      outputTokens: data.outputTokens.present
          ? data.outputTokens.value
          : this.outputTokens,
      transcriptText: data.transcriptText.present
          ? data.transcriptText.value
          : this.transcriptText,
      transcriptSegmentsJson: data.transcriptSegmentsJson.present
          ? data.transcriptSegmentsJson.value
          : this.transcriptSegmentsJson,
      speakerNamesJson: data.speakerNamesJson.present
          ? data.speakerNamesJson.value
          : this.speakerNamesJson,
      cleanedTranscriptText: data.cleanedTranscriptText.present
          ? data.cleanedTranscriptText.value
          : this.cleanedTranscriptText,
      priority: data.priority.present ? data.priority.value : this.priority,
      localOnly: data.localOnly.present ? data.localOnly.value : this.localOnly,
      templateId:
          data.templateId.present ? data.templateId.value : this.templateId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Recording(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('audioPath: $audioPath, ')
          ..write('transcriptionProviderId: $transcriptionProviderId, ')
          ..write('structuringProviderId: $structuringProviderId, ')
          ..write('structuringModel: $structuringModel, ')
          ..write('noteJson: $noteJson, ')
          ..write('noteSchemaVersion: $noteSchemaVersion, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('transcriptText: $transcriptText, ')
          ..write('transcriptSegmentsJson: $transcriptSegmentsJson, ')
          ..write('speakerNamesJson: $speakerNamesJson, ')
          ..write('cleanedTranscriptText: $cleanedTranscriptText, ')
          ..write('priority: $priority, ')
          ..write('localOnly: $localOnly, ')
          ..write('templateId: $templateId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      title,
      startedAt,
      durationMs,
      audioPath,
      transcriptionProviderId,
      structuringProviderId,
      structuringModel,
      noteJson,
      noteSchemaVersion,
      promptVersion,
      inputTokens,
      outputTokens,
      transcriptText,
      transcriptSegmentsJson,
      speakerNamesJson,
      cleanedTranscriptText,
      priority,
      localOnly,
      templateId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Recording &&
          other.id == this.id &&
          other.title == this.title &&
          other.startedAt == this.startedAt &&
          other.durationMs == this.durationMs &&
          other.audioPath == this.audioPath &&
          other.transcriptionProviderId == this.transcriptionProviderId &&
          other.structuringProviderId == this.structuringProviderId &&
          other.structuringModel == this.structuringModel &&
          other.noteJson == this.noteJson &&
          other.noteSchemaVersion == this.noteSchemaVersion &&
          other.promptVersion == this.promptVersion &&
          other.inputTokens == this.inputTokens &&
          other.outputTokens == this.outputTokens &&
          other.transcriptText == this.transcriptText &&
          other.transcriptSegmentsJson == this.transcriptSegmentsJson &&
          other.speakerNamesJson == this.speakerNamesJson &&
          other.cleanedTranscriptText == this.cleanedTranscriptText &&
          other.priority == this.priority &&
          other.localOnly == this.localOnly &&
          other.templateId == this.templateId);
}

class RecordingsCompanion extends UpdateCompanion<Recording> {
  final Value<String> id;
  final Value<String> title;
  final Value<DateTime> startedAt;
  final Value<int> durationMs;
  final Value<String?> audioPath;
  final Value<String?> transcriptionProviderId;
  final Value<String?> structuringProviderId;
  final Value<String?> structuringModel;
  final Value<String?> noteJson;
  final Value<String?> noteSchemaVersion;
  final Value<String?> promptVersion;
  final Value<int?> inputTokens;
  final Value<int?> outputTokens;
  final Value<String?> transcriptText;
  final Value<String?> transcriptSegmentsJson;
  final Value<String?> speakerNamesJson;
  final Value<String?> cleanedTranscriptText;
  final Value<bool> priority;
  final Value<bool> localOnly;
  final Value<String?> templateId;
  final Value<int> rowid;
  const RecordingsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.transcriptionProviderId = const Value.absent(),
    this.structuringProviderId = const Value.absent(),
    this.structuringModel = const Value.absent(),
    this.noteJson = const Value.absent(),
    this.noteSchemaVersion = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.transcriptText = const Value.absent(),
    this.transcriptSegmentsJson = const Value.absent(),
    this.speakerNamesJson = const Value.absent(),
    this.cleanedTranscriptText = const Value.absent(),
    this.priority = const Value.absent(),
    this.localOnly = const Value.absent(),
    this.templateId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RecordingsCompanion.insert({
    required String id,
    this.title = const Value.absent(),
    required DateTime startedAt,
    this.durationMs = const Value.absent(),
    this.audioPath = const Value.absent(),
    this.transcriptionProviderId = const Value.absent(),
    this.structuringProviderId = const Value.absent(),
    this.structuringModel = const Value.absent(),
    this.noteJson = const Value.absent(),
    this.noteSchemaVersion = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.inputTokens = const Value.absent(),
    this.outputTokens = const Value.absent(),
    this.transcriptText = const Value.absent(),
    this.transcriptSegmentsJson = const Value.absent(),
    this.speakerNamesJson = const Value.absent(),
    this.cleanedTranscriptText = const Value.absent(),
    this.priority = const Value.absent(),
    this.localOnly = const Value.absent(),
    this.templateId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        startedAt = Value(startedAt);
  static Insertable<Recording> custom({
    Expression<String>? id,
    Expression<String>? title,
    Expression<DateTime>? startedAt,
    Expression<int>? durationMs,
    Expression<String>? audioPath,
    Expression<String>? transcriptionProviderId,
    Expression<String>? structuringProviderId,
    Expression<String>? structuringModel,
    Expression<String>? noteJson,
    Expression<String>? noteSchemaVersion,
    Expression<String>? promptVersion,
    Expression<int>? inputTokens,
    Expression<int>? outputTokens,
    Expression<String>? transcriptText,
    Expression<String>? transcriptSegmentsJson,
    Expression<String>? speakerNamesJson,
    Expression<String>? cleanedTranscriptText,
    Expression<bool>? priority,
    Expression<bool>? localOnly,
    Expression<String>? templateId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (startedAt != null) 'started_at': startedAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (audioPath != null) 'audio_path': audioPath,
      if (transcriptionProviderId != null)
        'transcription_provider_id': transcriptionProviderId,
      if (structuringProviderId != null)
        'structuring_provider_id': structuringProviderId,
      if (structuringModel != null) 'structuring_model': structuringModel,
      if (noteJson != null) 'note_json': noteJson,
      if (noteSchemaVersion != null) 'note_schema_version': noteSchemaVersion,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (inputTokens != null) 'input_tokens': inputTokens,
      if (outputTokens != null) 'output_tokens': outputTokens,
      if (transcriptText != null) 'transcript_text': transcriptText,
      if (transcriptSegmentsJson != null)
        'transcript_segments_json': transcriptSegmentsJson,
      if (speakerNamesJson != null) 'speaker_names_json': speakerNamesJson,
      if (cleanedTranscriptText != null)
        'cleaned_transcript_text': cleanedTranscriptText,
      if (priority != null) 'priority': priority,
      if (localOnly != null) 'local_only': localOnly,
      if (templateId != null) 'template_id': templateId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RecordingsCompanion copyWith(
      {Value<String>? id,
      Value<String>? title,
      Value<DateTime>? startedAt,
      Value<int>? durationMs,
      Value<String?>? audioPath,
      Value<String?>? transcriptionProviderId,
      Value<String?>? structuringProviderId,
      Value<String?>? structuringModel,
      Value<String?>? noteJson,
      Value<String?>? noteSchemaVersion,
      Value<String?>? promptVersion,
      Value<int?>? inputTokens,
      Value<int?>? outputTokens,
      Value<String?>? transcriptText,
      Value<String?>? transcriptSegmentsJson,
      Value<String?>? speakerNamesJson,
      Value<String?>? cleanedTranscriptText,
      Value<bool>? priority,
      Value<bool>? localOnly,
      Value<String?>? templateId,
      Value<int>? rowid}) {
    return RecordingsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      startedAt: startedAt ?? this.startedAt,
      durationMs: durationMs ?? this.durationMs,
      audioPath: audioPath ?? this.audioPath,
      transcriptionProviderId:
          transcriptionProviderId ?? this.transcriptionProviderId,
      structuringProviderId:
          structuringProviderId ?? this.structuringProviderId,
      structuringModel: structuringModel ?? this.structuringModel,
      noteJson: noteJson ?? this.noteJson,
      noteSchemaVersion: noteSchemaVersion ?? this.noteSchemaVersion,
      promptVersion: promptVersion ?? this.promptVersion,
      inputTokens: inputTokens ?? this.inputTokens,
      outputTokens: outputTokens ?? this.outputTokens,
      transcriptText: transcriptText ?? this.transcriptText,
      transcriptSegmentsJson:
          transcriptSegmentsJson ?? this.transcriptSegmentsJson,
      speakerNamesJson: speakerNamesJson ?? this.speakerNamesJson,
      cleanedTranscriptText:
          cleanedTranscriptText ?? this.cleanedTranscriptText,
      priority: priority ?? this.priority,
      localOnly: localOnly ?? this.localOnly,
      templateId: templateId ?? this.templateId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (audioPath.present) {
      map['audio_path'] = Variable<String>(audioPath.value);
    }
    if (transcriptionProviderId.present) {
      map['transcription_provider_id'] =
          Variable<String>(transcriptionProviderId.value);
    }
    if (structuringProviderId.present) {
      map['structuring_provider_id'] =
          Variable<String>(structuringProviderId.value);
    }
    if (structuringModel.present) {
      map['structuring_model'] = Variable<String>(structuringModel.value);
    }
    if (noteJson.present) {
      map['note_json'] = Variable<String>(noteJson.value);
    }
    if (noteSchemaVersion.present) {
      map['note_schema_version'] = Variable<String>(noteSchemaVersion.value);
    }
    if (promptVersion.present) {
      map['prompt_version'] = Variable<String>(promptVersion.value);
    }
    if (inputTokens.present) {
      map['input_tokens'] = Variable<int>(inputTokens.value);
    }
    if (outputTokens.present) {
      map['output_tokens'] = Variable<int>(outputTokens.value);
    }
    if (transcriptText.present) {
      map['transcript_text'] = Variable<String>(transcriptText.value);
    }
    if (transcriptSegmentsJson.present) {
      map['transcript_segments_json'] =
          Variable<String>(transcriptSegmentsJson.value);
    }
    if (speakerNamesJson.present) {
      map['speaker_names_json'] = Variable<String>(speakerNamesJson.value);
    }
    if (cleanedTranscriptText.present) {
      map['cleaned_transcript_text'] =
          Variable<String>(cleanedTranscriptText.value);
    }
    if (priority.present) {
      map['priority'] = Variable<bool>(priority.value);
    }
    if (localOnly.present) {
      map['local_only'] = Variable<bool>(localOnly.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordingsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('startedAt: $startedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('audioPath: $audioPath, ')
          ..write('transcriptionProviderId: $transcriptionProviderId, ')
          ..write('structuringProviderId: $structuringProviderId, ')
          ..write('structuringModel: $structuringModel, ')
          ..write('noteJson: $noteJson, ')
          ..write('noteSchemaVersion: $noteSchemaVersion, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('inputTokens: $inputTokens, ')
          ..write('outputTokens: $outputTokens, ')
          ..write('transcriptText: $transcriptText, ')
          ..write('transcriptSegmentsJson: $transcriptSegmentsJson, ')
          ..write('speakerNamesJson: $speakerNamesJson, ')
          ..write('cleanedTranscriptText: $cleanedTranscriptText, ')
          ..write('priority: $priority, ')
          ..write('localOnly: $localOnly, ')
          ..write('templateId: $templateId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ChunksTable extends Chunks with TableInfo<$ChunksTable, Chunk> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChunksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordingIdMeta =
      const VerificationMeta('recordingId');
  @override
  late final GeneratedColumn<String> recordingId = GeneratedColumn<String>(
      'recording_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES recordings (id) ON DELETE CASCADE'));
  static const VerificationMeta _chunkIndexMeta =
      const VerificationMeta('chunkIndex');
  @override
  late final GeneratedColumn<int> chunkIndex = GeneratedColumn<int>(
      'index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _startMsMeta =
      const VerificationMeta('startMs');
  @override
  late final GeneratedColumn<int> startMs = GeneratedColumn<int>(
      'start_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _contentStartMsMeta =
      const VerificationMeta('contentStartMs');
  @override
  late final GeneratedColumn<int> contentStartMs = GeneratedColumn<int>(
      'content_start_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _endMsMeta = const VerificationMeta('endMs');
  @override
  late final GeneratedColumn<int> endMs = GeneratedColumn<int>(
      'end_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<int> bytes = GeneratedColumn<int>(
      'bytes', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  late final GeneratedColumnWithTypeConverter<ChunkState, String> state =
      GeneratedColumn<String>('state', aliasedName, false,
              type: DriftSqlType.string, requiredDuringInsert: true)
          .withConverter<ChunkState>($ChunksTable.$converterstate);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _nextAttemptAtMeta =
      const VerificationMeta('nextAttemptAt');
  @override
  late final GeneratedColumn<DateTime> nextAttemptAt =
      GeneratedColumn<DateTime>('next_attempt_at', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _transcriptTextMeta =
      const VerificationMeta('transcriptText');
  @override
  late final GeneratedColumn<String> transcriptText = GeneratedColumn<String>(
      'text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _segmentsJsonMeta =
      const VerificationMeta('segmentsJson');
  @override
  late final GeneratedColumn<String> segmentsJson = GeneratedColumn<String>(
      'segments_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
      'error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        recordingId,
        chunkIndex,
        startMs,
        contentStartMs,
        endMs,
        path,
        bytes,
        state,
        attempts,
        nextAttemptAt,
        transcriptText,
        segmentsJson,
        error
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chunks';
  @override
  VerificationContext validateIntegrity(Insertable<Chunk> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recording_id')) {
      context.handle(
          _recordingIdMeta,
          recordingId.isAcceptableOrUnknown(
              data['recording_id']!, _recordingIdMeta));
    } else if (isInserting) {
      context.missing(_recordingIdMeta);
    }
    if (data.containsKey('index')) {
      context.handle(_chunkIndexMeta,
          chunkIndex.isAcceptableOrUnknown(data['index']!, _chunkIndexMeta));
    } else if (isInserting) {
      context.missing(_chunkIndexMeta);
    }
    if (data.containsKey('start_ms')) {
      context.handle(_startMsMeta,
          startMs.isAcceptableOrUnknown(data['start_ms']!, _startMsMeta));
    } else if (isInserting) {
      context.missing(_startMsMeta);
    }
    if (data.containsKey('content_start_ms')) {
      context.handle(
          _contentStartMsMeta,
          contentStartMs.isAcceptableOrUnknown(
              data['content_start_ms']!, _contentStartMsMeta));
    } else if (isInserting) {
      context.missing(_contentStartMsMeta);
    }
    if (data.containsKey('end_ms')) {
      context.handle(
          _endMsMeta, endMs.isAcceptableOrUnknown(data['end_ms']!, _endMsMeta));
    } else if (isInserting) {
      context.missing(_endMsMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    }
    if (data.containsKey('bytes')) {
      context.handle(
          _bytesMeta, bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta));
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('next_attempt_at')) {
      context.handle(
          _nextAttemptAtMeta,
          nextAttemptAt.isAcceptableOrUnknown(
              data['next_attempt_at']!, _nextAttemptAtMeta));
    }
    if (data.containsKey('text')) {
      context.handle(
          _transcriptTextMeta,
          transcriptText.isAcceptableOrUnknown(
              data['text']!, _transcriptTextMeta));
    }
    if (data.containsKey('segments_json')) {
      context.handle(
          _segmentsJsonMeta,
          segmentsJson.isAcceptableOrUnknown(
              data['segments_json']!, _segmentsJsonMeta));
    }
    if (data.containsKey('error')) {
      context.handle(
          _errorMeta, error.isAcceptableOrUnknown(data['error']!, _errorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chunk map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chunk(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      recordingId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}recording_id'])!,
      chunkIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}index'])!,
      startMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}start_ms'])!,
      contentStartMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}content_start_ms'])!,
      endMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}end_ms'])!,
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path']),
      bytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}bytes']),
      state: $ChunksTable.$converterstate.fromSql(attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!),
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      nextAttemptAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}next_attempt_at']),
      transcriptText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}text']),
      segmentsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}segments_json']),
      error: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}error']),
    );
  }

  @override
  $ChunksTable createAlias(String alias) {
    return $ChunksTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<ChunkState, String, String> $converterstate =
      const EnumNameConverter<ChunkState>(ChunkState.values);
}

class Chunk extends DataClass implements Insertable<Chunk> {
  final String id;
  final String recordingId;

  /// Position in the recording. Reassembly is ordered by this, never by completion.
  /// `index` is a SQL keyword; drift quotes it, but the Dart-side name stays explicit.
  final int chunkIndex;
  final int startMs;

  /// Where this chunk's new content begins; everything before it repeats the previous
  /// chunk's tail and is de-duplicated on reassembly.
  final int contentStartMs;
  final int endMs;

  /// Audio is sliced out of the recording's WAV on demand, so a chunk owns no file of
  /// its own. Kept nullable for a future streaming recorder that writes chunks directly.
  final String? path;
  final int? bytes;
  final ChunkState state;
  final int attempts;
  final DateTime? nextAttemptAt;

  /// Named `transcriptText` rather than `text`: a column getter called `text` shadows
  /// drift's own `Table.text()` builder and breaks every other column in the table.
  final String? transcriptText;

  /// Segment timings as JSON, so absolute offsets survive a restart.
  final String? segmentsJson;
  final String? error;
  const Chunk(
      {required this.id,
      required this.recordingId,
      required this.chunkIndex,
      required this.startMs,
      required this.contentStartMs,
      required this.endMs,
      this.path,
      this.bytes,
      required this.state,
      required this.attempts,
      this.nextAttemptAt,
      this.transcriptText,
      this.segmentsJson,
      this.error});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recording_id'] = Variable<String>(recordingId);
    map['index'] = Variable<int>(chunkIndex);
    map['start_ms'] = Variable<int>(startMs);
    map['content_start_ms'] = Variable<int>(contentStartMs);
    map['end_ms'] = Variable<int>(endMs);
    if (!nullToAbsent || path != null) {
      map['path'] = Variable<String>(path);
    }
    if (!nullToAbsent || bytes != null) {
      map['bytes'] = Variable<int>(bytes);
    }
    {
      map['state'] =
          Variable<String>($ChunksTable.$converterstate.toSql(state));
    }
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextAttemptAt != null) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt);
    }
    if (!nullToAbsent || transcriptText != null) {
      map['text'] = Variable<String>(transcriptText);
    }
    if (!nullToAbsent || segmentsJson != null) {
      map['segments_json'] = Variable<String>(segmentsJson);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    return map;
  }

  ChunksCompanion toCompanion(bool nullToAbsent) {
    return ChunksCompanion(
      id: Value(id),
      recordingId: Value(recordingId),
      chunkIndex: Value(chunkIndex),
      startMs: Value(startMs),
      contentStartMs: Value(contentStartMs),
      endMs: Value(endMs),
      path: path == null && nullToAbsent ? const Value.absent() : Value(path),
      bytes:
          bytes == null && nullToAbsent ? const Value.absent() : Value(bytes),
      state: Value(state),
      attempts: Value(attempts),
      nextAttemptAt: nextAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextAttemptAt),
      transcriptText: transcriptText == null && nullToAbsent
          ? const Value.absent()
          : Value(transcriptText),
      segmentsJson: segmentsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(segmentsJson),
      error:
          error == null && nullToAbsent ? const Value.absent() : Value(error),
    );
  }

  factory Chunk.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chunk(
      id: serializer.fromJson<String>(json['id']),
      recordingId: serializer.fromJson<String>(json['recordingId']),
      chunkIndex: serializer.fromJson<int>(json['chunkIndex']),
      startMs: serializer.fromJson<int>(json['startMs']),
      contentStartMs: serializer.fromJson<int>(json['contentStartMs']),
      endMs: serializer.fromJson<int>(json['endMs']),
      path: serializer.fromJson<String?>(json['path']),
      bytes: serializer.fromJson<int?>(json['bytes']),
      state: $ChunksTable.$converterstate
          .fromJson(serializer.fromJson<String>(json['state'])),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextAttemptAt: serializer.fromJson<DateTime?>(json['nextAttemptAt']),
      transcriptText: serializer.fromJson<String?>(json['transcriptText']),
      segmentsJson: serializer.fromJson<String?>(json['segmentsJson']),
      error: serializer.fromJson<String?>(json['error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recordingId': serializer.toJson<String>(recordingId),
      'chunkIndex': serializer.toJson<int>(chunkIndex),
      'startMs': serializer.toJson<int>(startMs),
      'contentStartMs': serializer.toJson<int>(contentStartMs),
      'endMs': serializer.toJson<int>(endMs),
      'path': serializer.toJson<String?>(path),
      'bytes': serializer.toJson<int?>(bytes),
      'state':
          serializer.toJson<String>($ChunksTable.$converterstate.toJson(state)),
      'attempts': serializer.toJson<int>(attempts),
      'nextAttemptAt': serializer.toJson<DateTime?>(nextAttemptAt),
      'transcriptText': serializer.toJson<String?>(transcriptText),
      'segmentsJson': serializer.toJson<String?>(segmentsJson),
      'error': serializer.toJson<String?>(error),
    };
  }

  Chunk copyWith(
          {String? id,
          String? recordingId,
          int? chunkIndex,
          int? startMs,
          int? contentStartMs,
          int? endMs,
          Value<String?> path = const Value.absent(),
          Value<int?> bytes = const Value.absent(),
          ChunkState? state,
          int? attempts,
          Value<DateTime?> nextAttemptAt = const Value.absent(),
          Value<String?> transcriptText = const Value.absent(),
          Value<String?> segmentsJson = const Value.absent(),
          Value<String?> error = const Value.absent()}) =>
      Chunk(
        id: id ?? this.id,
        recordingId: recordingId ?? this.recordingId,
        chunkIndex: chunkIndex ?? this.chunkIndex,
        startMs: startMs ?? this.startMs,
        contentStartMs: contentStartMs ?? this.contentStartMs,
        endMs: endMs ?? this.endMs,
        path: path.present ? path.value : this.path,
        bytes: bytes.present ? bytes.value : this.bytes,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        nextAttemptAt:
            nextAttemptAt.present ? nextAttemptAt.value : this.nextAttemptAt,
        transcriptText:
            transcriptText.present ? transcriptText.value : this.transcriptText,
        segmentsJson:
            segmentsJson.present ? segmentsJson.value : this.segmentsJson,
        error: error.present ? error.value : this.error,
      );
  Chunk copyWithCompanion(ChunksCompanion data) {
    return Chunk(
      id: data.id.present ? data.id.value : this.id,
      recordingId:
          data.recordingId.present ? data.recordingId.value : this.recordingId,
      chunkIndex:
          data.chunkIndex.present ? data.chunkIndex.value : this.chunkIndex,
      startMs: data.startMs.present ? data.startMs.value : this.startMs,
      contentStartMs: data.contentStartMs.present
          ? data.contentStartMs.value
          : this.contentStartMs,
      endMs: data.endMs.present ? data.endMs.value : this.endMs,
      path: data.path.present ? data.path.value : this.path,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      state: data.state.present ? data.state.value : this.state,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextAttemptAt: data.nextAttemptAt.present
          ? data.nextAttemptAt.value
          : this.nextAttemptAt,
      transcriptText: data.transcriptText.present
          ? data.transcriptText.value
          : this.transcriptText,
      segmentsJson: data.segmentsJson.present
          ? data.segmentsJson.value
          : this.segmentsJson,
      error: data.error.present ? data.error.value : this.error,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chunk(')
          ..write('id: $id, ')
          ..write('recordingId: $recordingId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('startMs: $startMs, ')
          ..write('contentStartMs: $contentStartMs, ')
          ..write('endMs: $endMs, ')
          ..write('path: $path, ')
          ..write('bytes: $bytes, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('transcriptText: $transcriptText, ')
          ..write('segmentsJson: $segmentsJson, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      recordingId,
      chunkIndex,
      startMs,
      contentStartMs,
      endMs,
      path,
      bytes,
      state,
      attempts,
      nextAttemptAt,
      transcriptText,
      segmentsJson,
      error);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chunk &&
          other.id == this.id &&
          other.recordingId == this.recordingId &&
          other.chunkIndex == this.chunkIndex &&
          other.startMs == this.startMs &&
          other.contentStartMs == this.contentStartMs &&
          other.endMs == this.endMs &&
          other.path == this.path &&
          other.bytes == this.bytes &&
          other.state == this.state &&
          other.attempts == this.attempts &&
          other.nextAttemptAt == this.nextAttemptAt &&
          other.transcriptText == this.transcriptText &&
          other.segmentsJson == this.segmentsJson &&
          other.error == this.error);
}

class ChunksCompanion extends UpdateCompanion<Chunk> {
  final Value<String> id;
  final Value<String> recordingId;
  final Value<int> chunkIndex;
  final Value<int> startMs;
  final Value<int> contentStartMs;
  final Value<int> endMs;
  final Value<String?> path;
  final Value<int?> bytes;
  final Value<ChunkState> state;
  final Value<int> attempts;
  final Value<DateTime?> nextAttemptAt;
  final Value<String?> transcriptText;
  final Value<String?> segmentsJson;
  final Value<String?> error;
  final Value<int> rowid;
  const ChunksCompanion({
    this.id = const Value.absent(),
    this.recordingId = const Value.absent(),
    this.chunkIndex = const Value.absent(),
    this.startMs = const Value.absent(),
    this.contentStartMs = const Value.absent(),
    this.endMs = const Value.absent(),
    this.path = const Value.absent(),
    this.bytes = const Value.absent(),
    this.state = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.transcriptText = const Value.absent(),
    this.segmentsJson = const Value.absent(),
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChunksCompanion.insert({
    required String id,
    required String recordingId,
    required int chunkIndex,
    required int startMs,
    required int contentStartMs,
    required int endMs,
    this.path = const Value.absent(),
    this.bytes = const Value.absent(),
    required ChunkState state,
    this.attempts = const Value.absent(),
    this.nextAttemptAt = const Value.absent(),
    this.transcriptText = const Value.absent(),
    this.segmentsJson = const Value.absent(),
    this.error = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        recordingId = Value(recordingId),
        chunkIndex = Value(chunkIndex),
        startMs = Value(startMs),
        contentStartMs = Value(contentStartMs),
        endMs = Value(endMs),
        state = Value(state);
  static Insertable<Chunk> custom({
    Expression<String>? id,
    Expression<String>? recordingId,
    Expression<int>? chunkIndex,
    Expression<int>? startMs,
    Expression<int>? contentStartMs,
    Expression<int>? endMs,
    Expression<String>? path,
    Expression<int>? bytes,
    Expression<String>? state,
    Expression<int>? attempts,
    Expression<DateTime>? nextAttemptAt,
    Expression<String>? transcriptText,
    Expression<String>? segmentsJson,
    Expression<String>? error,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordingId != null) 'recording_id': recordingId,
      if (chunkIndex != null) 'index': chunkIndex,
      if (startMs != null) 'start_ms': startMs,
      if (contentStartMs != null) 'content_start_ms': contentStartMs,
      if (endMs != null) 'end_ms': endMs,
      if (path != null) 'path': path,
      if (bytes != null) 'bytes': bytes,
      if (state != null) 'state': state,
      if (attempts != null) 'attempts': attempts,
      if (nextAttemptAt != null) 'next_attempt_at': nextAttemptAt,
      if (transcriptText != null) 'text': transcriptText,
      if (segmentsJson != null) 'segments_json': segmentsJson,
      if (error != null) 'error': error,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChunksCompanion copyWith(
      {Value<String>? id,
      Value<String>? recordingId,
      Value<int>? chunkIndex,
      Value<int>? startMs,
      Value<int>? contentStartMs,
      Value<int>? endMs,
      Value<String?>? path,
      Value<int?>? bytes,
      Value<ChunkState>? state,
      Value<int>? attempts,
      Value<DateTime?>? nextAttemptAt,
      Value<String?>? transcriptText,
      Value<String?>? segmentsJson,
      Value<String?>? error,
      Value<int>? rowid}) {
    return ChunksCompanion(
      id: id ?? this.id,
      recordingId: recordingId ?? this.recordingId,
      chunkIndex: chunkIndex ?? this.chunkIndex,
      startMs: startMs ?? this.startMs,
      contentStartMs: contentStartMs ?? this.contentStartMs,
      endMs: endMs ?? this.endMs,
      path: path ?? this.path,
      bytes: bytes ?? this.bytes,
      state: state ?? this.state,
      attempts: attempts ?? this.attempts,
      nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
      transcriptText: transcriptText ?? this.transcriptText,
      segmentsJson: segmentsJson ?? this.segmentsJson,
      error: error ?? this.error,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recordingId.present) {
      map['recording_id'] = Variable<String>(recordingId.value);
    }
    if (chunkIndex.present) {
      map['index'] = Variable<int>(chunkIndex.value);
    }
    if (startMs.present) {
      map['start_ms'] = Variable<int>(startMs.value);
    }
    if (contentStartMs.present) {
      map['content_start_ms'] = Variable<int>(contentStartMs.value);
    }
    if (endMs.present) {
      map['end_ms'] = Variable<int>(endMs.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<int>(bytes.value);
    }
    if (state.present) {
      map['state'] =
          Variable<String>($ChunksTable.$converterstate.toSql(state.value));
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextAttemptAt.present) {
      map['next_attempt_at'] = Variable<DateTime>(nextAttemptAt.value);
    }
    if (transcriptText.present) {
      map['text'] = Variable<String>(transcriptText.value);
    }
    if (segmentsJson.present) {
      map['segments_json'] = Variable<String>(segmentsJson.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChunksCompanion(')
          ..write('id: $id, ')
          ..write('recordingId: $recordingId, ')
          ..write('chunkIndex: $chunkIndex, ')
          ..write('startMs: $startMs, ')
          ..write('contentStartMs: $contentStartMs, ')
          ..write('endMs: $endMs, ')
          ..write('path: $path, ')
          ..write('bytes: $bytes, ')
          ..write('state: $state, ')
          ..write('attempts: $attempts, ')
          ..write('nextAttemptAt: $nextAttemptAt, ')
          ..write('transcriptText: $transcriptText, ')
          ..write('segmentsJson: $segmentsJson, ')
          ..write('error: $error, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $NoteTemplatesTable extends NoteTemplates
    with TableInfo<$NoteTemplatesTable, NoteTemplate> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NoteTemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _instructionsMeta =
      const VerificationMeta('instructions');
  @override
  late final GeneratedColumn<String> instructions = GeneratedColumn<String>(
      'instructions', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, instructions, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'note_templates';
  @override
  VerificationContext validateIntegrity(Insertable<NoteTemplate> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('instructions')) {
      context.handle(
          _instructionsMeta,
          instructions.isAcceptableOrUnknown(
              data['instructions']!, _instructionsMeta));
    } else if (isInserting) {
      context.missing(_instructionsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  NoteTemplate map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return NoteTemplate(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      instructions: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}instructions'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $NoteTemplatesTable createAlias(String alias) {
    return $NoteTemplatesTable(attachedDatabase, alias);
  }
}

class NoteTemplate extends DataClass implements Insertable<NoteTemplate> {
  final String id;
  final String name;
  final String instructions;
  final DateTime createdAt;
  final DateTime updatedAt;
  const NoteTemplate(
      {required this.id,
      required this.name,
      required this.instructions,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['instructions'] = Variable<String>(instructions);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  NoteTemplatesCompanion toCompanion(bool nullToAbsent) {
    return NoteTemplatesCompanion(
      id: Value(id),
      name: Value(name),
      instructions: Value(instructions),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory NoteTemplate.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return NoteTemplate(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      instructions: serializer.fromJson<String>(json['instructions']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'instructions': serializer.toJson<String>(instructions),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  NoteTemplate copyWith(
          {String? id,
          String? name,
          String? instructions,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      NoteTemplate(
        id: id ?? this.id,
        name: name ?? this.name,
        instructions: instructions ?? this.instructions,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  NoteTemplate copyWithCompanion(NoteTemplatesCompanion data) {
    return NoteTemplate(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      instructions: data.instructions.present
          ? data.instructions.value
          : this.instructions,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('NoteTemplate(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('instructions: $instructions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, instructions, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NoteTemplate &&
          other.id == this.id &&
          other.name == this.name &&
          other.instructions == this.instructions &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class NoteTemplatesCompanion extends UpdateCompanion<NoteTemplate> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> instructions;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const NoteTemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.instructions = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NoteTemplatesCompanion.insert({
    required String id,
    required String name,
    required String instructions,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        instructions = Value(instructions),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<NoteTemplate> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? instructions,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (instructions != null) 'instructions': instructions,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NoteTemplatesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? instructions,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return NoteTemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      instructions: instructions ?? this.instructions,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (instructions.present) {
      map['instructions'] = Variable<String>(instructions.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NoteTemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('instructions: $instructions, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ActionRemindersTable extends ActionReminders
    with TableInfo<$ActionRemindersTable, ActionReminder> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ActionRemindersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _recordingIdMeta =
      const VerificationMeta('recordingId');
  @override
  late final GeneratedColumn<String> recordingId = GeneratedColumn<String>(
      'recording_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES recordings (id) ON DELETE CASCADE'));
  static const VerificationMeta _taskIdMeta = const VerificationMeta('taskId');
  @override
  late final GeneratedColumn<String> taskId = GeneratedColumn<String>(
      'task_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
      'title', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _remindAtMeta =
      const VerificationMeta('remindAt');
  @override
  late final GeneratedColumn<DateTime> remindAt = GeneratedColumn<DateTime>(
      'remind_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _enabledMeta =
      const VerificationMeta('enabled');
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
      'enabled', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("enabled" IN (0, 1))'),
      defaultValue: const Constant(true));
  static const VerificationMeta _completedMeta =
      const VerificationMeta('completed');
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
      'completed', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("completed" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns =>
      [id, recordingId, taskId, title, remindAt, enabled, completed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'action_reminders';
  @override
  VerificationContext validateIntegrity(Insertable<ActionReminder> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('recording_id')) {
      context.handle(
          _recordingIdMeta,
          recordingId.isAcceptableOrUnknown(
              data['recording_id']!, _recordingIdMeta));
    } else if (isInserting) {
      context.missing(_recordingIdMeta);
    }
    if (data.containsKey('task_id')) {
      context.handle(_taskIdMeta,
          taskId.isAcceptableOrUnknown(data['task_id']!, _taskIdMeta));
    } else if (isInserting) {
      context.missing(_taskIdMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
          _titleMeta, title.isAcceptableOrUnknown(data['title']!, _titleMeta));
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('remind_at')) {
      context.handle(_remindAtMeta,
          remindAt.isAcceptableOrUnknown(data['remind_at']!, _remindAtMeta));
    } else if (isInserting) {
      context.missing(_remindAtMeta);
    }
    if (data.containsKey('enabled')) {
      context.handle(_enabledMeta,
          enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta));
    }
    if (data.containsKey('completed')) {
      context.handle(_completedMeta,
          completed.isAcceptableOrUnknown(data['completed']!, _completedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ActionReminder map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ActionReminder(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      recordingId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}recording_id'])!,
      taskId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}task_id'])!,
      title: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}title'])!,
      remindAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}remind_at'])!,
      enabled: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}enabled'])!,
      completed: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}completed'])!,
    );
  }

  @override
  $ActionRemindersTable createAlias(String alias) {
    return $ActionRemindersTable(attachedDatabase, alias);
  }
}

class ActionReminder extends DataClass implements Insertable<ActionReminder> {
  final String id;
  final String recordingId;
  final String taskId;
  final String title;
  final DateTime remindAt;
  final bool enabled;
  final bool completed;
  const ActionReminder(
      {required this.id,
      required this.recordingId,
      required this.taskId,
      required this.title,
      required this.remindAt,
      required this.enabled,
      required this.completed});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['recording_id'] = Variable<String>(recordingId);
    map['task_id'] = Variable<String>(taskId);
    map['title'] = Variable<String>(title);
    map['remind_at'] = Variable<DateTime>(remindAt);
    map['enabled'] = Variable<bool>(enabled);
    map['completed'] = Variable<bool>(completed);
    return map;
  }

  ActionRemindersCompanion toCompanion(bool nullToAbsent) {
    return ActionRemindersCompanion(
      id: Value(id),
      recordingId: Value(recordingId),
      taskId: Value(taskId),
      title: Value(title),
      remindAt: Value(remindAt),
      enabled: Value(enabled),
      completed: Value(completed),
    );
  }

  factory ActionReminder.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ActionReminder(
      id: serializer.fromJson<String>(json['id']),
      recordingId: serializer.fromJson<String>(json['recordingId']),
      taskId: serializer.fromJson<String>(json['taskId']),
      title: serializer.fromJson<String>(json['title']),
      remindAt: serializer.fromJson<DateTime>(json['remindAt']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      completed: serializer.fromJson<bool>(json['completed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'recordingId': serializer.toJson<String>(recordingId),
      'taskId': serializer.toJson<String>(taskId),
      'title': serializer.toJson<String>(title),
      'remindAt': serializer.toJson<DateTime>(remindAt),
      'enabled': serializer.toJson<bool>(enabled),
      'completed': serializer.toJson<bool>(completed),
    };
  }

  ActionReminder copyWith(
          {String? id,
          String? recordingId,
          String? taskId,
          String? title,
          DateTime? remindAt,
          bool? enabled,
          bool? completed}) =>
      ActionReminder(
        id: id ?? this.id,
        recordingId: recordingId ?? this.recordingId,
        taskId: taskId ?? this.taskId,
        title: title ?? this.title,
        remindAt: remindAt ?? this.remindAt,
        enabled: enabled ?? this.enabled,
        completed: completed ?? this.completed,
      );
  ActionReminder copyWithCompanion(ActionRemindersCompanion data) {
    return ActionReminder(
      id: data.id.present ? data.id.value : this.id,
      recordingId:
          data.recordingId.present ? data.recordingId.value : this.recordingId,
      taskId: data.taskId.present ? data.taskId.value : this.taskId,
      title: data.title.present ? data.title.value : this.title,
      remindAt: data.remindAt.present ? data.remindAt.value : this.remindAt,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      completed: data.completed.present ? data.completed.value : this.completed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ActionReminder(')
          ..write('id: $id, ')
          ..write('recordingId: $recordingId, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('remindAt: $remindAt, ')
          ..write('enabled: $enabled, ')
          ..write('completed: $completed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, recordingId, taskId, title, remindAt, enabled, completed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ActionReminder &&
          other.id == this.id &&
          other.recordingId == this.recordingId &&
          other.taskId == this.taskId &&
          other.title == this.title &&
          other.remindAt == this.remindAt &&
          other.enabled == this.enabled &&
          other.completed == this.completed);
}

class ActionRemindersCompanion extends UpdateCompanion<ActionReminder> {
  final Value<String> id;
  final Value<String> recordingId;
  final Value<String> taskId;
  final Value<String> title;
  final Value<DateTime> remindAt;
  final Value<bool> enabled;
  final Value<bool> completed;
  final Value<int> rowid;
  const ActionRemindersCompanion({
    this.id = const Value.absent(),
    this.recordingId = const Value.absent(),
    this.taskId = const Value.absent(),
    this.title = const Value.absent(),
    this.remindAt = const Value.absent(),
    this.enabled = const Value.absent(),
    this.completed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ActionRemindersCompanion.insert({
    required String id,
    required String recordingId,
    required String taskId,
    required String title,
    required DateTime remindAt,
    this.enabled = const Value.absent(),
    this.completed = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        recordingId = Value(recordingId),
        taskId = Value(taskId),
        title = Value(title),
        remindAt = Value(remindAt);
  static Insertable<ActionReminder> custom({
    Expression<String>? id,
    Expression<String>? recordingId,
    Expression<String>? taskId,
    Expression<String>? title,
    Expression<DateTime>? remindAt,
    Expression<bool>? enabled,
    Expression<bool>? completed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (recordingId != null) 'recording_id': recordingId,
      if (taskId != null) 'task_id': taskId,
      if (title != null) 'title': title,
      if (remindAt != null) 'remind_at': remindAt,
      if (enabled != null) 'enabled': enabled,
      if (completed != null) 'completed': completed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ActionRemindersCompanion copyWith(
      {Value<String>? id,
      Value<String>? recordingId,
      Value<String>? taskId,
      Value<String>? title,
      Value<DateTime>? remindAt,
      Value<bool>? enabled,
      Value<bool>? completed,
      Value<int>? rowid}) {
    return ActionRemindersCompanion(
      id: id ?? this.id,
      recordingId: recordingId ?? this.recordingId,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      remindAt: remindAt ?? this.remindAt,
      enabled: enabled ?? this.enabled,
      completed: completed ?? this.completed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (recordingId.present) {
      map['recording_id'] = Variable<String>(recordingId.value);
    }
    if (taskId.present) {
      map['task_id'] = Variable<String>(taskId.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (remindAt.present) {
      map['remind_at'] = Variable<DateTime>(remindAt.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ActionRemindersCompanion(')
          ..write('id: $id, ')
          ..write('recordingId: $recordingId, ')
          ..write('taskId: $taskId, ')
          ..write('title: $title, ')
          ..write('remindAt: $remindAt, ')
          ..write('enabled: $enabled, ')
          ..write('completed: $completed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PrivacyAuditsTable extends PrivacyAudits
    with TableInfo<$PrivacyAuditsTable, PrivacyAudit> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrivacyAuditsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
      'action', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
      'detail', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, createdAt, action, detail];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'privacy_audits';
  @override
  VerificationContext validateIntegrity(Insertable<PrivacyAudit> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('action')) {
      context.handle(_actionMeta,
          action.isAcceptableOrUnknown(data['action']!, _actionMeta));
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('detail')) {
      context.handle(_detailMeta,
          detail.isAcceptableOrUnknown(data['detail']!, _detailMeta));
    } else if (isInserting) {
      context.missing(_detailMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PrivacyAudit map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrivacyAudit(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      action: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}action'])!,
      detail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}detail'])!,
    );
  }

  @override
  $PrivacyAuditsTable createAlias(String alias) {
    return $PrivacyAuditsTable(attachedDatabase, alias);
  }
}

class PrivacyAudit extends DataClass implements Insertable<PrivacyAudit> {
  final String id;
  final DateTime createdAt;
  final String action;
  final String detail;
  const PrivacyAudit(
      {required this.id,
      required this.createdAt,
      required this.action,
      required this.detail});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['action'] = Variable<String>(action);
    map['detail'] = Variable<String>(detail);
    return map;
  }

  PrivacyAuditsCompanion toCompanion(bool nullToAbsent) {
    return PrivacyAuditsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      action: Value(action),
      detail: Value(detail),
    );
  }

  factory PrivacyAudit.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrivacyAudit(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      action: serializer.fromJson<String>(json['action']),
      detail: serializer.fromJson<String>(json['detail']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'action': serializer.toJson<String>(action),
      'detail': serializer.toJson<String>(detail),
    };
  }

  PrivacyAudit copyWith(
          {String? id, DateTime? createdAt, String? action, String? detail}) =>
      PrivacyAudit(
        id: id ?? this.id,
        createdAt: createdAt ?? this.createdAt,
        action: action ?? this.action,
        detail: detail ?? this.detail,
      );
  PrivacyAudit copyWithCompanion(PrivacyAuditsCompanion data) {
    return PrivacyAudit(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      action: data.action.present ? data.action.value : this.action,
      detail: data.detail.present ? data.detail.value : this.detail,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrivacyAudit(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('action: $action, ')
          ..write('detail: $detail')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, createdAt, action, detail);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrivacyAudit &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.action == this.action &&
          other.detail == this.detail);
}

class PrivacyAuditsCompanion extends UpdateCompanion<PrivacyAudit> {
  final Value<String> id;
  final Value<DateTime> createdAt;
  final Value<String> action;
  final Value<String> detail;
  final Value<int> rowid;
  const PrivacyAuditsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.action = const Value.absent(),
    this.detail = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PrivacyAuditsCompanion.insert({
    required String id,
    required DateTime createdAt,
    required String action,
    required String detail,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        createdAt = Value(createdAt),
        action = Value(action),
        detail = Value(detail);
  static Insertable<PrivacyAudit> custom({
    Expression<String>? id,
    Expression<DateTime>? createdAt,
    Expression<String>? action,
    Expression<String>? detail,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (action != null) 'action': action,
      if (detail != null) 'detail': detail,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PrivacyAuditsCompanion copyWith(
      {Value<String>? id,
      Value<DateTime>? createdAt,
      Value<String>? action,
      Value<String>? detail,
      Value<int>? rowid}) {
    return PrivacyAuditsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      action: action ?? this.action,
      detail: detail ?? this.detail,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrivacyAuditsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('action: $action, ')
          ..write('detail: $detail, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$TranscriptDatabase extends GeneratedDatabase {
  _$TranscriptDatabase(QueryExecutor e) : super(e);
  $TranscriptDatabaseManager get managers => $TranscriptDatabaseManager(this);
  late final $RecordingsTable recordings = $RecordingsTable(this);
  late final $ChunksTable chunks = $ChunksTable(this);
  late final $NoteTemplatesTable noteTemplates = $NoteTemplatesTable(this);
  late final $ActionRemindersTable actionReminders =
      $ActionRemindersTable(this);
  late final $PrivacyAuditsTable privacyAudits = $PrivacyAuditsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [recordings, chunks, noteTemplates, actionReminders, privacyAudits];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('recordings',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('chunks', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('recordings',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('action_reminders', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$RecordingsTableCreateCompanionBuilder = RecordingsCompanion Function({
  required String id,
  Value<String> title,
  required DateTime startedAt,
  Value<int> durationMs,
  Value<String?> audioPath,
  Value<String?> transcriptionProviderId,
  Value<String?> structuringProviderId,
  Value<String?> structuringModel,
  Value<String?> noteJson,
  Value<String?> noteSchemaVersion,
  Value<String?> promptVersion,
  Value<int?> inputTokens,
  Value<int?> outputTokens,
  Value<String?> transcriptText,
  Value<String?> transcriptSegmentsJson,
  Value<String?> speakerNamesJson,
  Value<String?> cleanedTranscriptText,
  Value<bool> priority,
  Value<bool> localOnly,
  Value<String?> templateId,
  Value<int> rowid,
});
typedef $$RecordingsTableUpdateCompanionBuilder = RecordingsCompanion Function({
  Value<String> id,
  Value<String> title,
  Value<DateTime> startedAt,
  Value<int> durationMs,
  Value<String?> audioPath,
  Value<String?> transcriptionProviderId,
  Value<String?> structuringProviderId,
  Value<String?> structuringModel,
  Value<String?> noteJson,
  Value<String?> noteSchemaVersion,
  Value<String?> promptVersion,
  Value<int?> inputTokens,
  Value<int?> outputTokens,
  Value<String?> transcriptText,
  Value<String?> transcriptSegmentsJson,
  Value<String?> speakerNamesJson,
  Value<String?> cleanedTranscriptText,
  Value<bool> priority,
  Value<bool> localOnly,
  Value<String?> templateId,
  Value<int> rowid,
});

final class $$RecordingsTableReferences
    extends BaseReferences<_$TranscriptDatabase, $RecordingsTable, Recording> {
  $$RecordingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$ChunksTable, List<Chunk>> _chunksRefsTable(
          _$TranscriptDatabase db) =>
      MultiTypedResultKey.fromTable(db.chunks,
          aliasName: 'recordings__id__chunks__recording_id');

  $$ChunksTableProcessedTableManager get chunksRefs {
    final manager = $$ChunksTableTableManager($_db, $_db.chunks)
        .filter((f) => f.recordingId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_chunksRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$ActionRemindersTable, List<ActionReminder>>
      _actionRemindersRefsTable(_$TranscriptDatabase db) =>
          MultiTypedResultKey.fromTable(db.actionReminders,
              aliasName: 'recordings__id__action_reminders__recording_id');

  $$ActionRemindersTableProcessedTableManager get actionRemindersRefs {
    final manager = $$ActionRemindersTableTableManager(
            $_db, $_db.actionReminders)
        .filter((f) => f.recordingId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_actionRemindersRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$RecordingsTableFilterComposer
    extends Composer<_$TranscriptDatabase, $RecordingsTable> {
  $$RecordingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get audioPath => $composableBuilder(
      column: $table.audioPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transcriptionProviderId => $composableBuilder(
      column: $table.transcriptionProviderId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get structuringProviderId => $composableBuilder(
      column: $table.structuringProviderId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get structuringModel => $composableBuilder(
      column: $table.structuringModel,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get noteJson => $composableBuilder(
      column: $table.noteJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get noteSchemaVersion => $composableBuilder(
      column: $table.noteSchemaVersion,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get promptVersion => $composableBuilder(
      column: $table.promptVersion, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get inputTokens => $composableBuilder(
      column: $table.inputTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get outputTokens => $composableBuilder(
      column: $table.outputTokens, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transcriptText => $composableBuilder(
      column: $table.transcriptText,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transcriptSegmentsJson => $composableBuilder(
      column: $table.transcriptSegmentsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get speakerNamesJson => $composableBuilder(
      column: $table.speakerNamesJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cleanedTranscriptText => $composableBuilder(
      column: $table.cleanedTranscriptText,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get localOnly => $composableBuilder(
      column: $table.localOnly, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => ColumnFilters(column));

  Expression<bool> chunksRefs(
      Expression<bool> Function($$ChunksTableFilterComposer f) f) {
    final $$ChunksTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.chunks,
        getReferencedColumn: (t) => t.recordingId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChunksTableFilterComposer(
              $db: $db,
              $table: $db.chunks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> actionRemindersRefs(
      Expression<bool> Function($$ActionRemindersTableFilterComposer f) f) {
    final $$ActionRemindersTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.actionReminders,
        getReferencedColumn: (t) => t.recordingId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ActionRemindersTableFilterComposer(
              $db: $db,
              $table: $db.actionReminders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RecordingsTableOrderingComposer
    extends Composer<_$TranscriptDatabase, $RecordingsTable> {
  $$RecordingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
      column: $table.startedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get audioPath => $composableBuilder(
      column: $table.audioPath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transcriptionProviderId => $composableBuilder(
      column: $table.transcriptionProviderId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get structuringProviderId => $composableBuilder(
      column: $table.structuringProviderId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get structuringModel => $composableBuilder(
      column: $table.structuringModel,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get noteJson => $composableBuilder(
      column: $table.noteJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get noteSchemaVersion => $composableBuilder(
      column: $table.noteSchemaVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get promptVersion => $composableBuilder(
      column: $table.promptVersion,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get inputTokens => $composableBuilder(
      column: $table.inputTokens, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get outputTokens => $composableBuilder(
      column: $table.outputTokens,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transcriptText => $composableBuilder(
      column: $table.transcriptText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transcriptSegmentsJson => $composableBuilder(
      column: $table.transcriptSegmentsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get speakerNamesJson => $composableBuilder(
      column: $table.speakerNamesJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cleanedTranscriptText => $composableBuilder(
      column: $table.cleanedTranscriptText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get priority => $composableBuilder(
      column: $table.priority, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get localOnly => $composableBuilder(
      column: $table.localOnly, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => ColumnOrderings(column));
}

class $$RecordingsTableAnnotationComposer
    extends Composer<_$TranscriptDatabase, $RecordingsTable> {
  $$RecordingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<String> get audioPath =>
      $composableBuilder(column: $table.audioPath, builder: (column) => column);

  GeneratedColumn<String> get transcriptionProviderId => $composableBuilder(
      column: $table.transcriptionProviderId, builder: (column) => column);

  GeneratedColumn<String> get structuringProviderId => $composableBuilder(
      column: $table.structuringProviderId, builder: (column) => column);

  GeneratedColumn<String> get structuringModel => $composableBuilder(
      column: $table.structuringModel, builder: (column) => column);

  GeneratedColumn<String> get noteJson =>
      $composableBuilder(column: $table.noteJson, builder: (column) => column);

  GeneratedColumn<String> get noteSchemaVersion => $composableBuilder(
      column: $table.noteSchemaVersion, builder: (column) => column);

  GeneratedColumn<String> get promptVersion => $composableBuilder(
      column: $table.promptVersion, builder: (column) => column);

  GeneratedColumn<int> get inputTokens => $composableBuilder(
      column: $table.inputTokens, builder: (column) => column);

  GeneratedColumn<int> get outputTokens => $composableBuilder(
      column: $table.outputTokens, builder: (column) => column);

  GeneratedColumn<String> get transcriptText => $composableBuilder(
      column: $table.transcriptText, builder: (column) => column);

  GeneratedColumn<String> get transcriptSegmentsJson => $composableBuilder(
      column: $table.transcriptSegmentsJson, builder: (column) => column);

  GeneratedColumn<String> get speakerNamesJson => $composableBuilder(
      column: $table.speakerNamesJson, builder: (column) => column);

  GeneratedColumn<String> get cleanedTranscriptText => $composableBuilder(
      column: $table.cleanedTranscriptText, builder: (column) => column);

  GeneratedColumn<bool> get priority =>
      $composableBuilder(column: $table.priority, builder: (column) => column);

  GeneratedColumn<bool> get localOnly =>
      $composableBuilder(column: $table.localOnly, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
      column: $table.templateId, builder: (column) => column);

  Expression<T> chunksRefs<T extends Object>(
      Expression<T> Function($$ChunksTableAnnotationComposer a) f) {
    final $$ChunksTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.chunks,
        getReferencedColumn: (t) => t.recordingId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChunksTableAnnotationComposer(
              $db: $db,
              $table: $db.chunks,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> actionRemindersRefs<T extends Object>(
      Expression<T> Function($$ActionRemindersTableAnnotationComposer a) f) {
    final $$ActionRemindersTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.actionReminders,
        getReferencedColumn: (t) => t.recordingId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ActionRemindersTableAnnotationComposer(
              $db: $db,
              $table: $db.actionReminders,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RecordingsTableTableManager extends RootTableManager<
    _$TranscriptDatabase,
    $RecordingsTable,
    Recording,
    $$RecordingsTableFilterComposer,
    $$RecordingsTableOrderingComposer,
    $$RecordingsTableAnnotationComposer,
    $$RecordingsTableCreateCompanionBuilder,
    $$RecordingsTableUpdateCompanionBuilder,
    (Recording, $$RecordingsTableReferences),
    Recording,
    PrefetchHooks Function({bool chunksRefs, bool actionRemindersRefs})> {
  $$RecordingsTableTableManager(_$TranscriptDatabase db, $RecordingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<DateTime> startedAt = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            Value<String?> audioPath = const Value.absent(),
            Value<String?> transcriptionProviderId = const Value.absent(),
            Value<String?> structuringProviderId = const Value.absent(),
            Value<String?> structuringModel = const Value.absent(),
            Value<String?> noteJson = const Value.absent(),
            Value<String?> noteSchemaVersion = const Value.absent(),
            Value<String?> promptVersion = const Value.absent(),
            Value<int?> inputTokens = const Value.absent(),
            Value<int?> outputTokens = const Value.absent(),
            Value<String?> transcriptText = const Value.absent(),
            Value<String?> transcriptSegmentsJson = const Value.absent(),
            Value<String?> speakerNamesJson = const Value.absent(),
            Value<String?> cleanedTranscriptText = const Value.absent(),
            Value<bool> priority = const Value.absent(),
            Value<bool> localOnly = const Value.absent(),
            Value<String?> templateId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecordingsCompanion(
            id: id,
            title: title,
            startedAt: startedAt,
            durationMs: durationMs,
            audioPath: audioPath,
            transcriptionProviderId: transcriptionProviderId,
            structuringProviderId: structuringProviderId,
            structuringModel: structuringModel,
            noteJson: noteJson,
            noteSchemaVersion: noteSchemaVersion,
            promptVersion: promptVersion,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            transcriptText: transcriptText,
            transcriptSegmentsJson: transcriptSegmentsJson,
            speakerNamesJson: speakerNamesJson,
            cleanedTranscriptText: cleanedTranscriptText,
            priority: priority,
            localOnly: localOnly,
            templateId: templateId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String> title = const Value.absent(),
            required DateTime startedAt,
            Value<int> durationMs = const Value.absent(),
            Value<String?> audioPath = const Value.absent(),
            Value<String?> transcriptionProviderId = const Value.absent(),
            Value<String?> structuringProviderId = const Value.absent(),
            Value<String?> structuringModel = const Value.absent(),
            Value<String?> noteJson = const Value.absent(),
            Value<String?> noteSchemaVersion = const Value.absent(),
            Value<String?> promptVersion = const Value.absent(),
            Value<int?> inputTokens = const Value.absent(),
            Value<int?> outputTokens = const Value.absent(),
            Value<String?> transcriptText = const Value.absent(),
            Value<String?> transcriptSegmentsJson = const Value.absent(),
            Value<String?> speakerNamesJson = const Value.absent(),
            Value<String?> cleanedTranscriptText = const Value.absent(),
            Value<bool> priority = const Value.absent(),
            Value<bool> localOnly = const Value.absent(),
            Value<String?> templateId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RecordingsCompanion.insert(
            id: id,
            title: title,
            startedAt: startedAt,
            durationMs: durationMs,
            audioPath: audioPath,
            transcriptionProviderId: transcriptionProviderId,
            structuringProviderId: structuringProviderId,
            structuringModel: structuringModel,
            noteJson: noteJson,
            noteSchemaVersion: noteSchemaVersion,
            promptVersion: promptVersion,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            transcriptText: transcriptText,
            transcriptSegmentsJson: transcriptSegmentsJson,
            speakerNamesJson: speakerNamesJson,
            cleanedTranscriptText: cleanedTranscriptText,
            priority: priority,
            localOnly: localOnly,
            templateId: templateId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$RecordingsTable, Recording>(table),
                    $$RecordingsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {chunksRefs = false, actionRemindersRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (chunksRefs) db.chunks,
                if (actionRemindersRefs) db.actionReminders
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (chunksRefs)
                    await $_getPrefetchedData<Recording, $RecordingsTable,
                            Chunk>(
                        currentTable: table,
                        referencedTable:
                            $$RecordingsTableReferences._chunksRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RecordingsTableReferences(db, table, p0)
                                .chunksRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.recordingId == item.id),
                        typedResults: items),
                  if (actionRemindersRefs)
                    await $_getPrefetchedData<Recording, $RecordingsTable,
                            ActionReminder>(
                        currentTable: table,
                        referencedTable: $$RecordingsTableReferences
                            ._actionRemindersRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RecordingsTableReferences(db, table, p0)
                                .actionRemindersRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.recordingId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$RecordingsTableProcessedTableManager = ProcessedTableManager<
    _$TranscriptDatabase,
    $RecordingsTable,
    Recording,
    $$RecordingsTableFilterComposer,
    $$RecordingsTableOrderingComposer,
    $$RecordingsTableAnnotationComposer,
    $$RecordingsTableCreateCompanionBuilder,
    $$RecordingsTableUpdateCompanionBuilder,
    (Recording, $$RecordingsTableReferences),
    Recording,
    PrefetchHooks Function({bool chunksRefs, bool actionRemindersRefs})>;
typedef $$ChunksTableCreateCompanionBuilder = ChunksCompanion Function({
  required String id,
  required String recordingId,
  required int chunkIndex,
  required int startMs,
  required int contentStartMs,
  required int endMs,
  Value<String?> path,
  Value<int?> bytes,
  required ChunkState state,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
  Value<String?> transcriptText,
  Value<String?> segmentsJson,
  Value<String?> error,
  Value<int> rowid,
});
typedef $$ChunksTableUpdateCompanionBuilder = ChunksCompanion Function({
  Value<String> id,
  Value<String> recordingId,
  Value<int> chunkIndex,
  Value<int> startMs,
  Value<int> contentStartMs,
  Value<int> endMs,
  Value<String?> path,
  Value<int?> bytes,
  Value<ChunkState> state,
  Value<int> attempts,
  Value<DateTime?> nextAttemptAt,
  Value<String?> transcriptText,
  Value<String?> segmentsJson,
  Value<String?> error,
  Value<int> rowid,
});

final class $$ChunksTableReferences
    extends BaseReferences<_$TranscriptDatabase, $ChunksTable, Chunk> {
  $$ChunksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RecordingsTable _recordingIdTable(_$TranscriptDatabase db) =>
      db.recordings.createAlias('chunks__recording_id__recordings__id');

  $$RecordingsTableProcessedTableManager get recordingId {
    final $_column = $_itemColumn<String>('recording_id')!;

    final manager = $$RecordingsTableTableManager($_db, $_db.recordings)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recordingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ChunksTableFilterComposer
    extends Composer<_$TranscriptDatabase, $ChunksTable> {
  $$ChunksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get chunkIndex => $composableBuilder(
      column: $table.chunkIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get contentStartMs => $composableBuilder(
      column: $table.contentStartMs,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnFilters(column));

  ColumnWithTypeConverterFilters<ChunkState, ChunkState, String> get state =>
      $composableBuilder(
          column: $table.state,
          builder: (column) => ColumnWithTypeConverterFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transcriptText => $composableBuilder(
      column: $table.transcriptText,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get segmentsJson => $composableBuilder(
      column: $table.segmentsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnFilters(column));

  $$RecordingsTableFilterComposer get recordingId {
    final $$RecordingsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordingId,
        referencedTable: $db.recordings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecordingsTableFilterComposer(
              $db: $db,
              $table: $db.recordings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ChunksTableOrderingComposer
    extends Composer<_$TranscriptDatabase, $ChunksTable> {
  $$ChunksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get chunkIndex => $composableBuilder(
      column: $table.chunkIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get startMs => $composableBuilder(
      column: $table.startMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get contentStartMs => $composableBuilder(
      column: $table.contentStartMs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get endMs => $composableBuilder(
      column: $table.endMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get path => $composableBuilder(
      column: $table.path, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get bytes => $composableBuilder(
      column: $table.bytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transcriptText => $composableBuilder(
      column: $table.transcriptText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get segmentsJson => $composableBuilder(
      column: $table.segmentsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get error => $composableBuilder(
      column: $table.error, builder: (column) => ColumnOrderings(column));

  $$RecordingsTableOrderingComposer get recordingId {
    final $$RecordingsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordingId,
        referencedTable: $db.recordings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecordingsTableOrderingComposer(
              $db: $db,
              $table: $db.recordings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ChunksTableAnnotationComposer
    extends Composer<_$TranscriptDatabase, $ChunksTable> {
  $$ChunksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get chunkIndex => $composableBuilder(
      column: $table.chunkIndex, builder: (column) => column);

  GeneratedColumn<int> get startMs =>
      $composableBuilder(column: $table.startMs, builder: (column) => column);

  GeneratedColumn<int> get contentStartMs => $composableBuilder(
      column: $table.contentStartMs, builder: (column) => column);

  GeneratedColumn<int> get endMs =>
      $composableBuilder(column: $table.endMs, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumnWithTypeConverter<ChunkState, String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextAttemptAt => $composableBuilder(
      column: $table.nextAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get transcriptText => $composableBuilder(
      column: $table.transcriptText, builder: (column) => column);

  GeneratedColumn<String> get segmentsJson => $composableBuilder(
      column: $table.segmentsJson, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  $$RecordingsTableAnnotationComposer get recordingId {
    final $$RecordingsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordingId,
        referencedTable: $db.recordings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecordingsTableAnnotationComposer(
              $db: $db,
              $table: $db.recordings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ChunksTableTableManager extends RootTableManager<
    _$TranscriptDatabase,
    $ChunksTable,
    Chunk,
    $$ChunksTableFilterComposer,
    $$ChunksTableOrderingComposer,
    $$ChunksTableAnnotationComposer,
    $$ChunksTableCreateCompanionBuilder,
    $$ChunksTableUpdateCompanionBuilder,
    (Chunk, $$ChunksTableReferences),
    Chunk,
    PrefetchHooks Function({bool recordingId})> {
  $$ChunksTableTableManager(_$TranscriptDatabase db, $ChunksTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChunksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChunksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChunksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> recordingId = const Value.absent(),
            Value<int> chunkIndex = const Value.absent(),
            Value<int> startMs = const Value.absent(),
            Value<int> contentStartMs = const Value.absent(),
            Value<int> endMs = const Value.absent(),
            Value<String?> path = const Value.absent(),
            Value<int?> bytes = const Value.absent(),
            Value<ChunkState> state = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<DateTime?> nextAttemptAt = const Value.absent(),
            Value<String?> transcriptText = const Value.absent(),
            Value<String?> segmentsJson = const Value.absent(),
            Value<String?> error = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChunksCompanion(
            id: id,
            recordingId: recordingId,
            chunkIndex: chunkIndex,
            startMs: startMs,
            contentStartMs: contentStartMs,
            endMs: endMs,
            path: path,
            bytes: bytes,
            state: state,
            attempts: attempts,
            nextAttemptAt: nextAttemptAt,
            transcriptText: transcriptText,
            segmentsJson: segmentsJson,
            error: error,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String recordingId,
            required int chunkIndex,
            required int startMs,
            required int contentStartMs,
            required int endMs,
            Value<String?> path = const Value.absent(),
            Value<int?> bytes = const Value.absent(),
            required ChunkState state,
            Value<int> attempts = const Value.absent(),
            Value<DateTime?> nextAttemptAt = const Value.absent(),
            Value<String?> transcriptText = const Value.absent(),
            Value<String?> segmentsJson = const Value.absent(),
            Value<String?> error = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChunksCompanion.insert(
            id: id,
            recordingId: recordingId,
            chunkIndex: chunkIndex,
            startMs: startMs,
            contentStartMs: contentStartMs,
            endMs: endMs,
            path: path,
            bytes: bytes,
            state: state,
            attempts: attempts,
            nextAttemptAt: nextAttemptAt,
            transcriptText: transcriptText,
            segmentsJson: segmentsJson,
            error: error,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ChunksTable, Chunk>(table),
                    $$ChunksTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({recordingId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (recordingId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.recordingId,
                    referencedTable:
                        $$ChunksTableReferences._recordingIdTable(db),
                    referencedColumn:
                        $$ChunksTableReferences._recordingIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ChunksTableProcessedTableManager = ProcessedTableManager<
    _$TranscriptDatabase,
    $ChunksTable,
    Chunk,
    $$ChunksTableFilterComposer,
    $$ChunksTableOrderingComposer,
    $$ChunksTableAnnotationComposer,
    $$ChunksTableCreateCompanionBuilder,
    $$ChunksTableUpdateCompanionBuilder,
    (Chunk, $$ChunksTableReferences),
    Chunk,
    PrefetchHooks Function({bool recordingId})>;
typedef $$NoteTemplatesTableCreateCompanionBuilder = NoteTemplatesCompanion
    Function({
  required String id,
  required String name,
  required String instructions,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$NoteTemplatesTableUpdateCompanionBuilder = NoteTemplatesCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String> instructions,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$NoteTemplatesTableFilterComposer
    extends Composer<_$TranscriptDatabase, $NoteTemplatesTable> {
  $$NoteTemplatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get instructions => $composableBuilder(
      column: $table.instructions, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$NoteTemplatesTableOrderingComposer
    extends Composer<_$TranscriptDatabase, $NoteTemplatesTable> {
  $$NoteTemplatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get instructions => $composableBuilder(
      column: $table.instructions,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$NoteTemplatesTableAnnotationComposer
    extends Composer<_$TranscriptDatabase, $NoteTemplatesTable> {
  $$NoteTemplatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get instructions => $composableBuilder(
      column: $table.instructions, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$NoteTemplatesTableTableManager extends RootTableManager<
    _$TranscriptDatabase,
    $NoteTemplatesTable,
    NoteTemplate,
    $$NoteTemplatesTableFilterComposer,
    $$NoteTemplatesTableOrderingComposer,
    $$NoteTemplatesTableAnnotationComposer,
    $$NoteTemplatesTableCreateCompanionBuilder,
    $$NoteTemplatesTableUpdateCompanionBuilder,
    (
      NoteTemplate,
      BaseReferences<_$TranscriptDatabase, $NoteTemplatesTable, NoteTemplate>
    ),
    NoteTemplate,
    PrefetchHooks Function()> {
  $$NoteTemplatesTableTableManager(
      _$TranscriptDatabase db, $NoteTemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NoteTemplatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NoteTemplatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NoteTemplatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> instructions = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              NoteTemplatesCompanion(
            id: id,
            name: name,
            instructions: instructions,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required String instructions,
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              NoteTemplatesCompanion.insert(
            id: id,
            name: name,
            instructions: instructions,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$NoteTemplatesTable, NoteTemplate>(table),
                    BaseReferences<_$TranscriptDatabase, $NoteTemplatesTable,
                        NoteTemplate>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$NoteTemplatesTableProcessedTableManager = ProcessedTableManager<
    _$TranscriptDatabase,
    $NoteTemplatesTable,
    NoteTemplate,
    $$NoteTemplatesTableFilterComposer,
    $$NoteTemplatesTableOrderingComposer,
    $$NoteTemplatesTableAnnotationComposer,
    $$NoteTemplatesTableCreateCompanionBuilder,
    $$NoteTemplatesTableUpdateCompanionBuilder,
    (
      NoteTemplate,
      BaseReferences<_$TranscriptDatabase, $NoteTemplatesTable, NoteTemplate>
    ),
    NoteTemplate,
    PrefetchHooks Function()>;
typedef $$ActionRemindersTableCreateCompanionBuilder = ActionRemindersCompanion
    Function({
  required String id,
  required String recordingId,
  required String taskId,
  required String title,
  required DateTime remindAt,
  Value<bool> enabled,
  Value<bool> completed,
  Value<int> rowid,
});
typedef $$ActionRemindersTableUpdateCompanionBuilder = ActionRemindersCompanion
    Function({
  Value<String> id,
  Value<String> recordingId,
  Value<String> taskId,
  Value<String> title,
  Value<DateTime> remindAt,
  Value<bool> enabled,
  Value<bool> completed,
  Value<int> rowid,
});

final class $$ActionRemindersTableReferences extends BaseReferences<
    _$TranscriptDatabase, $ActionRemindersTable, ActionReminder> {
  $$ActionRemindersTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $RecordingsTable _recordingIdTable(_$TranscriptDatabase db) =>
      db.recordings
          .createAlias('action_reminders__recording_id__recordings__id');

  $$RecordingsTableProcessedTableManager get recordingId {
    final $_column = $_itemColumn<String>('recording_id')!;

    final manager = $$RecordingsTableTableManager($_db, $_db.recordings)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_recordingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$ActionRemindersTableFilterComposer
    extends Composer<_$TranscriptDatabase, $ActionRemindersTable> {
  $$ActionRemindersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get remindAt => $composableBuilder(
      column: $table.remindAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnFilters(column));

  $$RecordingsTableFilterComposer get recordingId {
    final $$RecordingsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordingId,
        referencedTable: $db.recordings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecordingsTableFilterComposer(
              $db: $db,
              $table: $db.recordings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ActionRemindersTableOrderingComposer
    extends Composer<_$TranscriptDatabase, $ActionRemindersTable> {
  $$ActionRemindersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get taskId => $composableBuilder(
      column: $table.taskId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get title => $composableBuilder(
      column: $table.title, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get remindAt => $composableBuilder(
      column: $table.remindAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get enabled => $composableBuilder(
      column: $table.enabled, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get completed => $composableBuilder(
      column: $table.completed, builder: (column) => ColumnOrderings(column));

  $$RecordingsTableOrderingComposer get recordingId {
    final $$RecordingsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordingId,
        referencedTable: $db.recordings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecordingsTableOrderingComposer(
              $db: $db,
              $table: $db.recordings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ActionRemindersTableAnnotationComposer
    extends Composer<_$TranscriptDatabase, $ActionRemindersTable> {
  $$ActionRemindersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get taskId =>
      $composableBuilder(column: $table.taskId, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get remindAt =>
      $composableBuilder(column: $table.remindAt, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  $$RecordingsTableAnnotationComposer get recordingId {
    final $$RecordingsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.recordingId,
        referencedTable: $db.recordings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RecordingsTableAnnotationComposer(
              $db: $db,
              $table: $db.recordings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$ActionRemindersTableTableManager extends RootTableManager<
    _$TranscriptDatabase,
    $ActionRemindersTable,
    ActionReminder,
    $$ActionRemindersTableFilterComposer,
    $$ActionRemindersTableOrderingComposer,
    $$ActionRemindersTableAnnotationComposer,
    $$ActionRemindersTableCreateCompanionBuilder,
    $$ActionRemindersTableUpdateCompanionBuilder,
    (ActionReminder, $$ActionRemindersTableReferences),
    ActionReminder,
    PrefetchHooks Function({bool recordingId})> {
  $$ActionRemindersTableTableManager(
      _$TranscriptDatabase db, $ActionRemindersTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ActionRemindersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ActionRemindersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ActionRemindersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> recordingId = const Value.absent(),
            Value<String> taskId = const Value.absent(),
            Value<String> title = const Value.absent(),
            Value<DateTime> remindAt = const Value.absent(),
            Value<bool> enabled = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ActionRemindersCompanion(
            id: id,
            recordingId: recordingId,
            taskId: taskId,
            title: title,
            remindAt: remindAt,
            enabled: enabled,
            completed: completed,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String recordingId,
            required String taskId,
            required String title,
            required DateTime remindAt,
            Value<bool> enabled = const Value.absent(),
            Value<bool> completed = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ActionRemindersCompanion.insert(
            id: id,
            recordingId: recordingId,
            taskId: taskId,
            title: title,
            remindAt: remindAt,
            enabled: enabled,
            completed: completed,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ActionRemindersTable, ActionReminder>(table),
                    $$ActionRemindersTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({recordingId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (recordingId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.recordingId,
                    referencedTable:
                        $$ActionRemindersTableReferences._recordingIdTable(db),
                    referencedColumn: $$ActionRemindersTableReferences
                        ._recordingIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$ActionRemindersTableProcessedTableManager = ProcessedTableManager<
    _$TranscriptDatabase,
    $ActionRemindersTable,
    ActionReminder,
    $$ActionRemindersTableFilterComposer,
    $$ActionRemindersTableOrderingComposer,
    $$ActionRemindersTableAnnotationComposer,
    $$ActionRemindersTableCreateCompanionBuilder,
    $$ActionRemindersTableUpdateCompanionBuilder,
    (ActionReminder, $$ActionRemindersTableReferences),
    ActionReminder,
    PrefetchHooks Function({bool recordingId})>;
typedef $$PrivacyAuditsTableCreateCompanionBuilder = PrivacyAuditsCompanion
    Function({
  required String id,
  required DateTime createdAt,
  required String action,
  required String detail,
  Value<int> rowid,
});
typedef $$PrivacyAuditsTableUpdateCompanionBuilder = PrivacyAuditsCompanion
    Function({
  Value<String> id,
  Value<DateTime> createdAt,
  Value<String> action,
  Value<String> detail,
  Value<int> rowid,
});

class $$PrivacyAuditsTableFilterComposer
    extends Composer<_$TranscriptDatabase, $PrivacyAuditsTable> {
  $$PrivacyAuditsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnFilters(column));
}

class $$PrivacyAuditsTableOrderingComposer
    extends Composer<_$TranscriptDatabase, $PrivacyAuditsTable> {
  $$PrivacyAuditsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get action => $composableBuilder(
      column: $table.action, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get detail => $composableBuilder(
      column: $table.detail, builder: (column) => ColumnOrderings(column));
}

class $$PrivacyAuditsTableAnnotationComposer
    extends Composer<_$TranscriptDatabase, $PrivacyAuditsTable> {
  $$PrivacyAuditsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);
}

class $$PrivacyAuditsTableTableManager extends RootTableManager<
    _$TranscriptDatabase,
    $PrivacyAuditsTable,
    PrivacyAudit,
    $$PrivacyAuditsTableFilterComposer,
    $$PrivacyAuditsTableOrderingComposer,
    $$PrivacyAuditsTableAnnotationComposer,
    $$PrivacyAuditsTableCreateCompanionBuilder,
    $$PrivacyAuditsTableUpdateCompanionBuilder,
    (
      PrivacyAudit,
      BaseReferences<_$TranscriptDatabase, $PrivacyAuditsTable, PrivacyAudit>
    ),
    PrivacyAudit,
    PrefetchHooks Function()> {
  $$PrivacyAuditsTableTableManager(
      _$TranscriptDatabase db, $PrivacyAuditsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrivacyAuditsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrivacyAuditsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrivacyAuditsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String> action = const Value.absent(),
            Value<String> detail = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PrivacyAuditsCompanion(
            id: id,
            createdAt: createdAt,
            action: action,
            detail: detail,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required DateTime createdAt,
            required String action,
            required String detail,
            Value<int> rowid = const Value.absent(),
          }) =>
              PrivacyAuditsCompanion.insert(
            id: id,
            createdAt: createdAt,
            action: action,
            detail: detail,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$PrivacyAuditsTable, PrivacyAudit>(table),
                    BaseReferences<_$TranscriptDatabase, $PrivacyAuditsTable,
                        PrivacyAudit>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PrivacyAuditsTableProcessedTableManager = ProcessedTableManager<
    _$TranscriptDatabase,
    $PrivacyAuditsTable,
    PrivacyAudit,
    $$PrivacyAuditsTableFilterComposer,
    $$PrivacyAuditsTableOrderingComposer,
    $$PrivacyAuditsTableAnnotationComposer,
    $$PrivacyAuditsTableCreateCompanionBuilder,
    $$PrivacyAuditsTableUpdateCompanionBuilder,
    (
      PrivacyAudit,
      BaseReferences<_$TranscriptDatabase, $PrivacyAuditsTable, PrivacyAudit>
    ),
    PrivacyAudit,
    PrefetchHooks Function()>;

class $TranscriptDatabaseManager {
  final _$TranscriptDatabase _db;
  $TranscriptDatabaseManager(this._db);
  $$RecordingsTableTableManager get recordings =>
      $$RecordingsTableTableManager(_db, _db.recordings);
  $$ChunksTableTableManager get chunks =>
      $$ChunksTableTableManager(_db, _db.chunks);
  $$NoteTemplatesTableTableManager get noteTemplates =>
      $$NoteTemplatesTableTableManager(_db, _db.noteTemplates);
  $$ActionRemindersTableTableManager get actionReminders =>
      $$ActionRemindersTableTableManager(_db, _db.actionReminders);
  $$PrivacyAuditsTableTableManager get privacyAudits =>
      $$PrivacyAuditsTableTableManager(_db, _db.privacyAudits);
}
