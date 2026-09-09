import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:transcript_core/transcript_core.dart';

import '../recording/recording_controller.dart';

/// Picks a recording made elsewhere and hands it to the pipeline.
///
/// Shared by every entry point that offers import, so the picker filter and the
/// "watch it process on the record screen" behaviour stay identical wherever it is
/// started from.
Future<void> importRecordingFile(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(recordingControllerProvider.notifier);
  final navigator = Navigator.of(context);

  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ImportFormat.pickerExtensions,
    withData: false,
  );

  final path = picked?.files.singleOrNull?.path;
  if (path == null) return; // cancelled

  // Back to the record screen first: it is what renders progress, the failure remedy and
  // the jump to the finished note, and it has to be listening before the import starts.
  navigator.popUntil((route) => route.isFirst);
  unawaited(controller.importRecording(path));
}

/// Imports several files in order. The durable processing queue remains the source of
/// truth for progress after each file is handed to the controller.
Future<void> importRecordingFiles(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(recordingControllerProvider.notifier);
  final navigator = Navigator.of(context);
  final picked = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ImportFormat.pickerExtensions,
    allowMultiple: true,
    withData: false,
  );
  final paths = [
    for (final file in picked?.files ?? const <PlatformFile>[]) file.path,
  ].whereType<String>().toList();
  if (paths.isEmpty) return;
  navigator.popUntil((route) => route.isFirst);
  for (final path in paths) {
    await controller.importRecording(path);
  }
}
