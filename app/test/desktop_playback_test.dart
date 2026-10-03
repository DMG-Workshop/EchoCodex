import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:echo_codex_app/src/recording/desktop_playback.dart';

/// just_audio has no Linux or Windows implementation of its own; media_kit supplies one
/// backed by libmpv. Windows gets the libraries bundled, Linux does not — so on Linux
/// playback is a thing that can be absent for a reason the user can fix, and these are
/// the tests that keep that reason worth reading.
///
/// Deliberately does not call [initializeDesktopPlayback]: whether it succeeds depends on
/// whether the host has libmpv, which differs between this machine and CI, and a test
/// whose outcome depends on that is a test that will lie one day.
void main() {
  group('the reason shown when there is no play button', () {
    test('on Linux it names libmpv and how to get it', () {
      final reason = playbackUnavailableReason(linux: true);

      expect(reason, contains('libmpv'));
      expect(reason, contains('install'),
          reason: 'this is a missing package, not a missing feature, and the '
              'difference decides whether the user goes looking in the right '
              'place');
    });

    test('elsewhere it does not send anyone installing anything', () {
      final reason = playbackUnavailableReason(linux: false);

      expect(reason, isNot(contains('libmpv')),
          reason: 'Windows gets its libraries bundled, so libmpv advice there '
              'is a wild goose chase');
    });

    test('either way it says the recording itself is safe', () {
      for (final linux in [true, false]) {
        expect(playbackUnavailableReason(linux: linux), contains('still saved'),
            reason: 'the one thing someone fears when the play button is gone '
                'is that the audio went with it');
      }
    });
  });

  group('before anything is registered', () {
    test('desktop reports a reason and the rest report none', () {
      final reason = audioPlaybackUnavailable();

      if (Platform.isLinux || Platform.isWindows) {
        expect(reason, isNotNull,
            reason: 'nothing has been registered yet, so building an '
                'AudioPlayer would reach an unimplemented channel');
        expect(reason, contains('still saved'));
      } else {
        expect(reason, isNull,
            reason: 'these platforms have had a real implementation all along');
      }
    });
  });
}
