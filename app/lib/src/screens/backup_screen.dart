import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as encryption;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../recording/recording_controller.dart';

class BackupScreen extends ConsumerWidget {
  const BackupScreen({super.key});

  Future<String?> _passphrase(BuildContext context,
      {required String title}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Continue')),
        ],
      ),
    );
    controller.dispose();
    return result?.trim().isEmpty == true ? null : result;
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final passphrase =
        await _passphrase(context, title: 'Encrypt device backup');
    if (passphrase == null) return;
    final recordings = await ref.read(repositoryProvider).all();
    final archive = Archive();
    for (final recording in recordings) {
      archive.addFile(ArchiveFile.string(
        'recordings/${recording.id}.json',
        jsonEncode({
          'id': recording.id,
          'title': recording.title,
          'startedAt': recording.startedAt.toIso8601String(),
          'durationMs': recording.durationMs,
          'transcriptionProviderId': recording.transcriptionProviderId,
          'structuringProviderId': recording.structuringProviderId,
          'structuringModel': recording.structuringModel,
          'noteJson': recording.noteJson,
          'transcriptText': recording.transcriptText,
          'cleanedTranscriptText': recording.cleanedTranscriptText,
          'localOnly': recording.localOnly,
        }),
      ));
      final audioPath = recording.audioPath;
      if (audioPath != null && File(audioPath).existsSync()) {
        archive.addFile(ArchiveFile.bytes(
          'audio/${recording.id}${p.extension(audioPath)}',
          File(audioPath).readAsBytesSync(),
        ));
      }
    }
    final plain = ZipEncoder().encodeBytes(archive);
    final key = encryption.Key(Uint8List.fromList(
        crypto.sha256.convert(utf8.encode(passphrase)).bytes));
    final iv = encryption.IV.fromSecureRandom(16);
    final cipher =
        encryption.Encrypter(encryption.AES(key)).encryptBytes(plain, iv: iv);
    final bytes = [
      ...utf8.encode('ECHO-CODEX-BACKUP-V1\n'),
      ...iv.bytes,
      ...cipher.bytes
    ];
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'echo-codex-backup.zip.enc'));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'application/octet-stream')],
      subject: 'Echo Codex encrypted backup',
    ));
  }

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    final path = picked?.files.single.path;
    if (path == null) return;
    final passphrase =
        await _passphrase(context, title: 'Decrypt device backup');
    if (passphrase == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      const header = 'ECHO-CODEX-BACKUP-V1\n';
      final headerBytes = utf8.encode(header);
      if (bytes.length <= headerBytes.length + 16 ||
          utf8.decode(bytes.sublist(0, headerBytes.length)) != header) {
        throw const FormatException('Not an Echo Codex backup');
      }
      final key = encryption.Key(Uint8List.fromList(
          crypto.sha256.convert(utf8.encode(passphrase)).bytes));
      final iv = encryption.IV(Uint8List.fromList(
          bytes.sublist(headerBytes.length, headerBytes.length + 16)));
      final encrypted = encryption.Encrypter(encryption.AES(key));
      final plain = encrypted.decryptBytes(
        encryption.Encrypted(
            Uint8List.fromList(bytes.sublist(headerBytes.length + 16))),
        iv: iv,
      );
      final archive = ZipDecoder().decodeBytes(plain);
      var restored = 0;
      for (final file in archive.files
          .where((file) => file.name.startsWith('recordings/'))) {
        final metadata = jsonDecode(utf8.decode(file.content as List<int>))
            as Map<String, dynamic>;
        final id = metadata['id'] as String?;
        List<int>? audio;
        String? audioExtension;
        if (id != null) {
          final audioFile = archive.files
              .where((candidate) => candidate.name.startsWith('audio/$id.'))
              .firstOrNull;
          if (audioFile != null) {
            audio = audioFile.content as List<int>;
            audioExtension = p.extension(audioFile.name);
          }
        }
        await ref.read(repositoryProvider).restoreBackupRecording(
              metadata,
              audioBytes: audio,
              audioExtension: audioExtension,
            );
        restored++;
      }
      await ref
          .read(repositoryProvider)
          .recordPrivacyAudit('backup_restored', '$restored recordings');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Restored $restored recordings')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not decrypt that backup.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        appBar: AppBar(title: const Text('Encrypted device backup')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
                'Back up notes, transcripts, and recording metadata to move them to another device. The passphrase never leaves this device.'),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => _export(context, ref),
              icon: const Icon(Icons.upload_file),
              label: const Text('Create encrypted backup'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _restore(context, ref),
              icon: const Icon(Icons.download),
              label: const Text('Restore encrypted backup'),
            ),
          ],
        ),
      );
}
