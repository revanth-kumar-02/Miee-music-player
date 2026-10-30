import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/player/providers/sleep_timer_provider.dart';

class MockAudioHandlerForSleep extends MieeAudioHandler {
  bool fadeOutCalled = false;
  Duration? lastFadeDuration;

  @override
  Future<void> fadeOutAndPause({
    Duration duration = const Duration(milliseconds: 180),
  }) async {
    fadeOutCalled = true;
    lastFadeDuration = duration;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sleep Timer with Gentle Fade-Out Tests', () {
    late ProviderContainer container;
    late MockAudioHandlerForSleep mockHandler;

    setUp(() {
      mockHandler = MockAudioHandlerForSleep();
      container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(mockHandler),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Initial state is inactive and zero remaining', () {
      final state = container.read(sleepTimerProvider);
      expect(state.isActive, isFalse);
      expect(state.selectedMinutes, isNull);
      expect(state.remaining, Duration.zero);
      expect(state.formattedRemaining, '');
    });

    test('Setting a timer activates state with correct remaining duration', () {
      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.setTimer(15);

      final state = container.read(sleepTimerProvider);
      expect(state.isActive, isTrue);
      expect(state.selectedMinutes, 15);
      expect(state.remaining.inMinutes, 15);
      expect(state.formattedRemaining, contains('15:00'));

      notifier.cancelTimer();
      final cancelledState = container.read(sleepTimerProvider);
      expect(cancelledState.isActive, isFalse);
    });

    test('Setting 0 or negative minutes cancels active timer', () {
      final notifier = container.read(sleepTimerProvider.notifier);
      notifier.setTimer(30);
      expect(container.read(sleepTimerProvider).isActive, isTrue);

      notifier.setTimer(0);
      expect(container.read(sleepTimerProvider).isActive, isFalse);
    });
  });
}

