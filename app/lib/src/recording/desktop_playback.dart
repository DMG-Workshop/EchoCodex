import 'dart:io';

import 'package:just_audio_media_kit/just_audio_media_kit.dart';

/// Why audio cannot be played here, or null when it can.
///
/// One seam carrying the reason rather than a bool plus a platform check at the place
/// the message is written. The reason is the whole value of this: reaching it on Linux
/// means one specific, fixable thing — libmpv is not installed — and a vague "not
/// available on this platform" would send someone looking for a missing feature instead
/// of a missing package.
///
/// A replaceable function rather than a constant because `flutter test` runs on the host,
/// usually Linux, so a hard platform check would mean the working branch was never
/// exercised by any test on any machine, and that is the branch every phone takes.
///
/// The default is the conservative answer for a process that never called
/// [initializeDesktopPlayback]: desktop has nothing registered, everything else does.
String? Function() audioPlaybackUnavailable = _unregistered;

String? _unregistered() => Platform.isLinux || Platform.isWindows
    ? playbackUnavailableReason(linux: Platform.isLinux)
    : null;

/// What to tell someone who has no play button.
///
/// Said in one sentence with the remedy in it where there is one, and always alongside
/// the fact that the recording itself is safe — someone who recorded an hour of a meeting
/// and then cannot find the play control needs to know the audio is not what went
/// missing.
///
/// Takes [linux] rather than reading [Platform] so both answers are reachable from a
/// test. `flutter test` runs on one host, and a message nobody can read back is a message
/// that quietly rots.
String playbackUnavailableReason({required bool linux}) => linux
    ? 'Playing audio here needs libmpv, which is not installed — try '
        '"sudo apt install libmpv2" or your distribution\'s equivalent. The '
        'recording is still saved, and still exports.'
    : 'Playback is not available on this platform yet. The recording is still '
        'saved, and still exports.';

/// Registers a just_audio implementation for Linux and Windows.
///
/// just_audio ships native implementations for Android, iOS and macOS only. On the two
/// desktop platforms it had none, so building an `AudioPlayer` reached an unimplemented
/// platform channel — which is why the Transcript tab there said playback was
/// unavailable, and why for a while it took the readable transcript down on the way in.
///
/// `just_audio_media_kit` fills that gap by backing the same just_audio API with libmpv,
/// so not a line of the player code changes. What does change is that initialization can
/// genuinely fail: Windows gets its libraries from `media_kit_libs_windows_audio`, but on
/// Linux libmpv is a system package and a machine without it has nothing to load. So this
/// records what actually happened rather than assuming — a play button that throws when
/// pressed is worse than one that was never offered.
Future<void> initializeDesktopPlayback() async {
  if (!Platform.isLinux && !Platform.isWindows) {
    audioPlaybackUnavailable = () => null;
    return;
  }
  try {
    JustAudioMediaKit.ensureInitialized(linux: true, windows: true);
    audioPlaybackUnavailable = () => null;
  } catch (_) {
    // Almost always a missing libmpv. Swallowed rather than rethrown because the app's
    // job is reading transcripts and writing notes; losing playback is a degraded
    // feature, not a reason to refuse to start.
    final reason = playbackUnavailableReason(linux: Platform.isLinux);
    audioPlaybackUnavailable = () => reason;
  }
}
