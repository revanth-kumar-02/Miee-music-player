import 'package:flutter_test/flutter_test.dart';
import 'package:audio_session/audio_session.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Audio Interruption & Focus Safety Tests', () {
    late MieeAudioHandler handler;

    setUp(() {
      handler = MieeAudioHandler();
    });

    tearDown(() async {
      try {
        await handler.disposeHandler();
      } catch (_) {}
    });

    test('Initial state: playInterrupted is false', () {
      expect(handler.playInterrupted, isFalse);
    });

    test(
      'External app focus transition (e.g. Instagram Reels swipe) while Miee is paused NEVER auto-plays',
      () {
        // Given Miee is paused / idle
        expect(handler.isPlaying, isFalse);
        expect(handler.playInterrupted, isFalse);

        // 1. Instagram starts Reel (transient audio focus loss)
        handler.handleInterruptionEvent(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );
        expect(handler.playInterrupted, isFalse,
            reason: 'Should not flag resume intent when app was already paused');
        expect(handler.isPlaying, isFalse);

        // 2. User swipes to next Reel (transient audio focus restored briefly)
        handler.handleInterruptionEvent(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        expect(handler.playInterrupted, isFalse);
        expect(handler.isPlaying, isFalse,
            reason: 'Miee must remain completely silent and not play on Reel swipe');

        // 3. User swipes another 5 reels
        for (int i = 0; i < 5; i++) {
          handler.handleInterruptionEvent(
            AudioInterruptionEvent(true, AudioInterruptionType.pause),
          );
          expect(handler.playInterrupted, isFalse);
          expect(handler.isPlaying, isFalse);

          handler.handleInterruptionEvent(
            AudioInterruptionEvent(false, AudioInterruptionType.pause),
          );
          expect(handler.playInterrupted, isFalse);
          expect(handler.isPlaying, isFalse);
        }
      },
    );

    test(
      'Permanent focus loss (AudioInterruptionType.unknown) clears resume intent',
      () {
        // Even if an interruption event arrives
        handler.handleInterruptionEvent(
          AudioInterruptionEvent(true, AudioInterruptionType.unknown),
        );
        expect(handler.playInterrupted, isFalse);

        // Interruption ends
        handler.handleInterruptionEvent(
          AudioInterruptionEvent(false, AudioInterruptionType.unknown),
        );
        expect(handler.playInterrupted, isFalse);
        expect(handler.isPlaying, isFalse);
      },
    );

    test('pause() and stop() always reset playInterrupted to false', () async {
      // Manually set or verify pause() resets flag
      await handler.pause();
      expect(handler.playInterrupted, isFalse);

      await handler.stop();
      expect(handler.playInterrupted, isFalse);
    });

    test(
      'If user pauses during an interruption, resume intent is revoked',
      () async {
        // Simulate an interruption that might have started
        handler.handleInterruptionEvent(
          AudioInterruptionEvent(true, AudioInterruptionType.pause),
        );

        // User explicitly pauses from notification shade or app
        await handler.pause();
        expect(handler.playInterrupted, isFalse);

        // Interruption ends
        handler.handleInterruptionEvent(
          AudioInterruptionEvent(false, AudioInterruptionType.pause),
        );
        expect(handler.playInterrupted, isFalse);
        expect(handler.isPlaying, isFalse);
      },
    );

    test('Queue skip operations reset playInterrupted to false', () async {
      await handler.skipToNext();
      expect(handler.playInterrupted, isFalse);

      await handler.skipToPrevious();
      expect(handler.playInterrupted, isFalse);

      await handler.skipToQueueItem(0);
      expect(handler.playInterrupted, isFalse);
    });
  });
}
