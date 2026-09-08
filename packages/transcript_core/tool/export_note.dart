import 'dart:convert';
import 'dart:io';

import 'package:transcript_core/transcript_core.dart';

/// Convert an Echo Codex JSON note export into Markdown for shell workflows.
///
/// Usage:
///   dart run tool/export_note.dart note.json note.md
///   dart run tool/export_note.dart note.json --webhook https://example.test/hook
void main(List<String> args) {
  if (args.length != 2 && args.length != 3) {
    stderr.writeln(
        'Usage: dart run tool/export_note.dart input.json output.md | --webhook URL');
    exitCode = 64;
    return;
  }
  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('Input file does not exist: ${args[0]}');
    exitCode = 66;
    return;
  }
  final note = NoteDocument.fromJson(
    jsonDecode(input.readAsStringSync()) as Map<String, dynamic>,
  );
  if (args[1] == '--webhook' && args.length == 3) {
    final client = HttpClient();
    client.postUrl(Uri.parse(args[2])).then((request) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(note.toJson()));
      return request.close();
    }).then((response) async {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        stderr.writeln('Webhook returned HTTP ${response.statusCode}.');
        exitCode = 1;
      }
      client.close();
    }).catchError((Object error) {
      stderr.writeln('Webhook request failed: $error');
      client.close();
      exitCode = 1;
    });
    return;
  }
  final output = File(args[1]);
  output.writeAsStringSync(NoteExporters.markdown(note));
}
