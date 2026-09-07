import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:transcript_core/transcript_core.dart';

/// What a note can be turned into on its way out of the app.
enum ExportFormat {
  markdown(
    label: 'Markdown',
    detail: 'Notes, decisions and action items, for pasting into a doc.',
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
    label: 'Calendar (.ics)',
    detail:
        'Dated tasks and milestones. Undated work is left out rather than guessed.',
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
        ExportFormat.markdown =>
          NoteExporters.markdown(note, recordedOn: recordedOn),
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
  String? recordedOn,
}) =>
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => ExportSheet(note: note, recordedOn: recordedOn),
    );

/// Offers the note in each format, with a plain description of what each one keeps.
class ExportSheet extends StatelessWidget {
  const ExportSheet({super.key, required this.note, this.recordedOn});

  final NoteDocument note;
  final String? recordedOn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inferred =
        note.tasks.where((t) => t.dateBasis == DateBasis.inferred).length;

    return SafeArea(
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
    );
  }

  Future<void> _share(BuildContext context, ExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final file = await _write(format);
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

  Future<void> _copy(BuildContext context, ExportFormat format) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(text: format.render(note, recordedOn: recordedOn)),
    );
    messenger.showSnackBar(
      SnackBar(content: Text('${format.label} copied.')),
    );
  }

  Future<File> _write(ExportFormat format) async {
    final dir = await getTemporaryDirectory();
    final name = '${_slug(note.meta.title)}.${format.extension}';
    final file = File(p.join(dir.path, name));
    final bytes = switch (format) {
      ExportFormat.pdf => await _pdfBytes(),
      ExportFormat.docx => _docxBytes(),
      _ => utf8.encode(format.render(note, recordedOn: recordedOn)),
    };
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<List<int>> _pdfBytes() async {
    final document = pw.Document(title: note.meta.title);
    final lines =
        NoteExporters.markdown(note, recordedOn: recordedOn).split('\n');
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

  List<int> _docxBytes() {
    final archive = Archive()
      ..addFile(ArchiveFile.string('[Content_Types].xml', _contentTypes))
      ..addFile(ArchiveFile.string('_rels/.rels', _rootRelationships))
      ..addFile(ArchiveFile.string('word/document.xml', _documentXml()))
      ..addFile(ArchiveFile.string(
          'word/_rels/document.xml.rels', _documentRelationships));
    return ZipEncoder().encodeBytes(archive);
  }

  String _documentXml() {
    final paragraphs = NoteExporters.markdown(note, recordedOn: recordedOn)
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
