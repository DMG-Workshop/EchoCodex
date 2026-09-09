import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encryption;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:transcript_core/transcript_core.dart';

import '../data/database.dart' as db;
import '../export/outbound_integrations.dart';
import '../recording/recording_controller.dart';
import '../settings/provider_config.dart';

String _followUpEmail(NoteDocument note) {
  final actions = note.tasks
      .map((task) =>
          '- ${task.title}${task.dueDate == null ? '' : ' (due ${task.dueDate})'}')
      .join('\n');
  final decisions =
      note.decisions.map((decision) => '- ${decision.statement}').join('\n');
  return 'Subject: Follow-up — ${note.meta.title}\n\n'
      'Hi all,\n\n${note.meta.summary}\n\n'
      'Decisions\n$decisions\n\nAction items\n$actions\n\n'
      'Sent from Echo Codex.';
}

String _actionDigest(NoteDocument note) {
  final tasks = note.tasks
      .where((task) => task.status != TaskStatus.done)
      .map((task) =>
          '- ${task.title}${task.dueDate == null ? '' : ' — due ${task.dueDate}'}')
      .join('\n');
  return '# ${note.meta.title}\n\n${note.meta.summary}\n\n'
      '## Open action items\n$tasks\n\n'
      'Source: Echo Codex';
}

String _obsidianMarkdown(NoteDocument note, {String? recordedOn}) {
  final slug =
      note.meta.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return '---\ntitle: ${note.meta.title}\nrecorded: ${recordedOn ?? ''}\ntags:\n  - echo-codex\n---\n\n'
      '${NoteExporters.markdown(note, recordedOn: recordedOn)}\n\n'
      '---\nsource: echo-codex\nslug: $slug\n';
}

/// What a note can be turned into on its way out of the app.
enum ExportFormat {
  archive(
    label: 'Complete archive (ZIP)',
    detail: 'Note, transcript, metadata, and source audio when available.',
    extension: 'zip.enc',
    mime: 'application/octet-stream',
  ),
  json(
    label: 'JSON',
    detail: 'The structured note in Echo Codex format.',
    extension: 'json',
    mime: 'application/json',
  ),
  markdown(
    label: 'Markdown',
    detail: 'Notes, decisions and action items, for pasting into a doc.',
    extension: 'md',
    mime: 'text/markdown',
  ),
  followUpEmail(
    label: 'Follow-up email',
    detail: 'Decisions and action items formatted for a meeting follow-up.',
    extension: 'txt',
    mime: 'text/plain',
  ),
  actionDigest(
    label: 'Action-item digest',
    detail: 'A concise shareable list for people who missed the meeting.',
    extension: 'txt',
    mime: 'text/plain',
  ),
  obsidian(
    label: 'Obsidian Markdown',
    detail: 'Markdown with frontmatter for an Obsidian vault.',
    extension: 'md',
    mime: 'text/markdown',
  ),
  pdf(
    label: 'PDF',
    detail: 'A paginated, shareable document.',
    extension: 'pdf',
    mime: 'application/pdf',
  ),
  docx(
    label: 'DOCX',
    detail: 'An editable Microsoft Word document.',
    extension: 'docx',
    mime:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ),
  csv(
    label: 'Spreadsheet (CSV)',
    detail:
        'One row per action item, with a column saying how each date was known.',
    extension: 'csv',
    mime: 'text/csv',
  ),
  jira(
    label: 'Jira CSV',
    detail:
        'Ready for Jira\'s importer. Only spoken dates fill the due-date field.',
    extension: 'csv',
    mime: 'text/csv',
  ),
  calendar(
    label: 'Add to phone calendar (.ics)',
    detail:
        'Share with Google Calendar, Apple Calendar, Outlook, or another calendar app.',
    extension: 'ics',
    mime: 'text/calendar',
  );

  const ExportFormat({
    required this.label,
    required this.detail,
    required this.extension,
    required this.mime,
  });

  final String label;
  final String detail;
  final String extension;
  final String mime;

  String render(NoteDocument note, {String? recordedOn}) => switch (this) {
        ExportFormat.json =>
          const JsonEncoder.withIndent('  ').convert(note.toJson()),
        ExportFormat.archive =>
          const JsonEncoder.withIndent('  ').convert(note.toJson()),
        ExportFormat.markdown =>
          NoteExporters.markdown(note, recordedOn: recordedOn),
        ExportFormat.obsidian =>
          _obsidianMarkdown(note, recordedOn: recordedOn),
        ExportFormat.followUpEmail => _followUpEmail(note),
        ExportFormat.actionDigest => _actionDigest(note),
        ExportFormat.pdf ||
        ExportFormat.docx =>
          NoteExporters.markdown(note, recordedOn: recordedOn),
        ExportFormat.csv => NoteExporters.tasksCsv(note),
        ExportFormat.jira => NoteExporters.jiraCsv(note),
        ExportFormat.calendar => NoteExporters.ics(note),
      };
}

Future<void> openExportSheet(
  BuildContext context, {
  required NoteDocument note,
  db.Recording? recording,
  String? recordedOn,
}) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ExportSheet(
        note: note,
        recording: recording,
        recordedOn: recordedOn,
      ),
    );

/// Offers the note in each format, with a plain description of what each one keeps.
class ExportSheet extends ConsumerWidget {
  const ExportSheet(
      {super.key, required this.note, this.recording, this.recordedOn});

  final NoteDocument note;
  final db.Recording? recording;
  final String? recordedOn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsStoreProvider);
    final inferred =
        note.tasks.where((t) => t.dateBasis == DateBasis.inferred).length;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
              child: Text('Export', style: theme.textTheme.titleMedium),
            ),
            if (inferred > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Text(
                  '$inferred date${inferred == 1 ? ' was' : 's were'} inferred from the '
                  'recording rather than stated. Every export says so.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.tertiary),
                ),
              ),
            for (final format in ExportFormat.values)
              ListTile(
                title: Text(format.label),
                subtitle: Text(format.detail),
                trailing: const Icon(Icons.ios_share),
                onTap: () => _share(context, format),
                onLongPress: () => _copy(context, format),
              ),
            if (settings.webhookUrl.isNotEmpty)
              ListTile(
                title: const Text('Webhook'),
                subtitle: const Text('POST this note to the URL in Settings.'),
                trailing: const Icon(Icons.send_outlined),
                onTap: () => _sendWebhook(context, ref),
              ),
            ListTile(
              title: const Text('Notion database'),
              subtitle: const Text(
                  'Create a page in the Notion database configured in Settings.'),
              trailing: const Icon(Icons.cloud_upload_outlined),
              onTap: () => _sendNotion(context, ref),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Long-press to copy instead of sharing.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context, ExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final redact = await _askRedaction(context);
      if (!context.mounted) return;
      final passphrase =
          format == ExportFormat.archive ? await _askPassphrase(context) : null;
      if (format == ExportFormat.archive && passphrase == null) return;
      final file = await _write(
        format,
        passphrase: passphrase,
        redact: redact,
      );
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: format.mime)],
        subject: note.meta.title,
      ));
      navigator.pop();
    } catch (e) {
      // Sharing can fail for reasons entirely outside the app — no handler installed,
      // storage full. Say so rather than closing the sheet as if it worked.
      messenger.showSnackBar(
        SnackBar(content: Text('Could not share the ${format.label} export.')),
      );
    }
  }

  Future<void> _sendWebhook(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await const OutboundIntegrations().postWebhook(
        url: ref.read(settingsStoreProvider).webhookUrl,
        note: note,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Note posted to the webhook.')),
      );
    } on OutboundIntegrationException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _sendNotion(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final settings = ref.read(settingsStoreProvider);
    final token = await ref.read(keyStoreProvider).read('notion');
    try {
      await const OutboundIntegrations().postNotionPage(
        token: token ?? '',
        databaseId: settings.notionDatabaseId,
        note: note,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Note posted to Notion.')),
      );
    } on OutboundIntegrationException catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(error.remedy == null
            ? error.message
            : '${error.message} ${error.remedy}'),
      ));
    }
  }

  Future<bool> _askRedaction(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Redact sensitive details?'),
        content: const Text(
          'Remove email addresses, phone numbers, and street addresses locally before '
          'creating this export. The original note stays unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep details'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Redact'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _askPassphrase(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Protect archive'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Passphrase',
            helperText: 'You will need this to open the archive later.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Encrypt'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result;
  }

  Future<void> _copy(BuildContext context, ExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    final redact = await _askRedaction(context);
    await Clipboard.setData(
      ClipboardData(
        text: _redactText(
          format.render(note, recordedOn: recordedOn),
          enabled: redact,
        ),
      ),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('${format.label} copied.')),
    );
  }

  Future<File> _write(
    ExportFormat format, {
    String? passphrase,
    bool redact = false,
  }) async {
    final dir = await getTemporaryDirectory();
    final name = '${_slug(note.meta.title)}.${format.extension}';
    final file = File(p.join(dir.path, name));
    final bytes = switch (format) {
      ExportFormat.archive =>
        await _encryptedArchiveBytes(passphrase!, redact: redact),
      ExportFormat.pdf => await _pdfBytes(redact: redact),
      ExportFormat.docx => _docxBytes(redact: redact),
      _ => utf8.encode(
          _redactText(format.render(note, recordedOn: recordedOn),
              enabled: redact),
        ),
    };
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<List<int>> _encryptedArchiveBytes(
    String passphrase, {
    required bool redact,
  }) async {
    final plain = await _archiveBytes(redact: redact);
    final keyBytes = crypto.sha256.convert(utf8.encode(passphrase)).bytes;
    final key = encryption.Key(Uint8List.fromList(keyBytes));
    final iv = encryption.IV.fromSecureRandom(16);
    final encrypted = encryption.Encrypter(encryption.AES(key)).encryptBytes(
      plain,
      iv: iv,
    );
    return [
      ...utf8.encode('ECHO-CODEX-ARCHIVE-V1\n'),
      ...iv.bytes,
      ...encrypted.bytes,
    ];
  }

  Future<List<int>> _archiveBytes({bool redact = false}) async {
    final archive = Archive();
    archive.addFile(ArchiveFile.string(
      'note.json',
      _redactText(
        const JsonEncoder.withIndent('  ').convert(note.toJson()),
        enabled: redact,
      ),
    ));
    if (recording != null) {
      archive.addFile(ArchiveFile.string(
        'metadata.json',
        const JsonEncoder.withIndent('  ').convert({
          'id': recording!.id,
          'title': _redactText(recording!.title, enabled: redact),
          'startedAt': recording!.startedAt.toIso8601String(),
          'durationMs': recording!.durationMs,
          'transcriptionProviderId': recording!.transcriptionProviderId,
          'structuringProviderId': recording!.structuringProviderId,
          'structuringModel': recording!.structuringModel,
          'noteSchemaVersion': recording!.noteSchemaVersion,
          'promptVersion': recording!.promptVersion,
          'localOnly': recording!.localOnly,
        }),
      ));
      if (recording!.transcriptText != null) {
        archive.addFile(ArchiveFile.string(
          'transcript.txt',
          _redactText(recording!.transcriptText!, enabled: redact),
        ));
      }
      final audioPath = recording!.audioPath;
      if (audioPath != null) {
        final audio = File(audioPath);
        if (audio.existsSync()) {
          archive.addFile(ArchiveFile.bytes(
            p.basename(audioPath),
            audio.readAsBytesSync(),
          ));
        }
      }
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static String _redactText(String text, {required bool enabled}) {
    if (!enabled) return text;
    return text
        .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '[redacted email]')
        .replaceAll(
          RegExp(r'(?<!\w)\+?\d[\d ()-]{7,}\d(?!\w)'),
          '[redacted phone]',
        )
        .replaceAll(
          RegExp(
            r'\b\d{1,5}\s+\w+(?:\s+\w+){0,3}\s+(?:St|Street|Rd|Road|Ave|Avenue|Blvd|Lane|Ln)\b',
            caseSensitive: false,
          ),
          '[redacted address]',
        );
  }

  Future<List<int>> _pdfBytes({required bool redact}) async {
    final document = pw.Document(title: note.meta.title);
    final lines = _redactText(
      NoteExporters.markdown(note, recordedOn: recordedOn),
      enabled: redact,
    ).split('\n');
    document.addPage(pw.MultiPage(
      build: (_) => [
        for (final line in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Text(line.isEmpty ? ' ' : line),
          ),
      ],
    ));
    return document.save();
  }

  List<int> _docxBytes({required bool redact}) {
    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRelationships))
      ..addFile(
          ArchiveFile.string('word/document.xml', _documentXml(redact: redact)))
      ..addFile(ArchiveFile.string(
          'word/_rels/document.xml.rels', _documentRelationships));
    return ZipEncoder().encodeBytes(archive);
  }

  String _documentXml({required bool redact}) {
    final paragraphs = _redactText(
      NoteExporters.markdown(note, recordedOn: recordedOn),
      enabled: redact,
    )
        .split('\n')
        .map((line) =>
            '<w:p><w:r><w:t xml:space="preserve">${_xml(line.isEmpty ? ' ' : line)}</w:t></w:r></w:p>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$paragraphs<w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr></w:body></w:document>''';
  }

  static String _xml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static const _contentTypes =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>''';

  static const _rootRelationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>''';

  static const _documentRelationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>''';

  static String _slug(String title) {
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'transcript-note' : slug;
  }
}
