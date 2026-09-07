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
