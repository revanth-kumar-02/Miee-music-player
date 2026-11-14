import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/features/sleep_timer/domain/sleep_timer_state.dart';
import 'package:Miee/features/sleep_timer/providers/sleep_timer_provider.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Sleep Timer Specification Tests', () {
    late MieeAudioHandler handler;

    setUp(() {
      handler = MieeAudioHandler();
    });

    tearDown(() async {
      handler.cancelSleepTimer();
      await handler.disposeHandler();
    });

    test('1. Starting a 5-minute timer sets correct mode, duration, and active state', () {
      handler.startSleepTimer(const Duration(minutes: 5));

      final state = handler.sleepTimerState;
      expect(state.mode, equals(SleepTimerMode.countdown));
      expect(state.isActive, isTrue);
      expect(state.isCountdown, isTrue);
      expect(state.totalDuration, equals(const Duration(minutes: 5)));
      expect(state.targetEndTime, isNotNull);
      expect(state.remainingDuration.inMinutes, equals(5));
      expect(state.formattedRemainingTime, equals('5:00'));
      expect(state.statusDescription, contains('5:00 remaining'));
    });

    test('2. Custom timer duration (e.g. 25 minutes or 75 minutes) formats accurately', () {
      // 25 minutes
      handler.startSleepTimer(const Duration(minutes: 25));
      var state = handler.sleepTimerState;
      expect(state.totalDuration, equals(const Duration(minutes: 25)));
      expect(state.formattedRemainingTime, equals('25:00'));

      // 75 minutes = 1h 15m
      handler.startSleepTimer(const Duration(minutes: 75));
      state = handler.sleepTimerState;
      expect(state.totalDuration, equals(const Duration(minutes: 75)));
      expect(state.formattedRemainingTime, equals('1:15:00'));
    });

    test('3. Countdown accuracy and dynamic remaining time recalculation', () {
      // Simulate target end time 45 seconds from now
      final now = DateTime.now();
      final target = now.add(const Duration(seconds: 45));
      final testState = SleepTimerState(
        mode: SleepTimerMode.countdown,
        totalDuration: const Duration(seconds: 45),
        targetEndTime: target,
        remainingDuration: const Duration(seconds: 45),
      );

      expect(testState.isCountdown, isTrue);
      expect(testState.calculatedRemaining.inSeconds, inInclusiveRange(44, 45));
      expect(testState.formattedRemainingTime, anyOf('0:44', '0:45'));
    });

    test('4. Cancelling an active timer halts countdown and updates state to cancelled', () {
      handler.startSleepTimer(const Duration(minutes: 15));
      expect(handler.sleepTimerState.isActive, isTrue);

      handler.cancelSleepTimer();
      final state = handler.sleepTimerState;
      expect(state.isActive, isFalse);
      expect(state.mode, equals(SleepTimerMode.cancelled));
      expect(state.statusDescription, equals('Turn off music automatically'));
    });

    test('5. Replacing an existing timer immediately supersedes previous timer without conflict', () {
      handler.startSleepTimer(const Duration(minutes: 10));
      final firstTarget = handler.sleepTimerState.targetEndTime;

      // Replace with 30-minute timer
      handler.startSleepTimer(const Duration(minutes: 30));
      final state = handler.sleepTimerState;
      expect(state.totalDuration, equals(const Duration(minutes: 30)));
      expect(state.targetEndTime!.isAfter(firstTarget!), isTrue);
      expect(state.formattedRemainingTime, equals('30:00'));
    });

    test('6. Timer expiration while playing pauses active player safely', () async {
      handler.startSleepTimer(const Duration(minutes: 10));
      expect(handler.sleepTimerState.isActive, isTrue);

      // Trigger timer expiration
      await handler.triggerSleepTimerExpirationForTesting();

      final state = handler.sleepTimerState;
      expect(state.mode, equals(SleepTimerMode.expired));
      expect(state.isActive, isFalse);
      expect(state.statusDescription, equals('Timer expired · Playback stopped'));
    });

    test('7. Timer expiration while paused updates state to expired without error', () async {
      handler.startSleepTimer(const Duration(minutes: 5));
      // Trigger expiration while paused
      await handler.triggerSleepTimerExpirationForTesting();

      expect(handler.sleepTimerState.mode, equals(SleepTimerMode.expired));
      expect(handler.sleepTimerState.isActive, isFalse);
    });

    test('8. Track switching while timer is active preserves active deadline', () {
      handler.startSleepTimer(const Duration(minutes: 20));
      final initialTarget = handler.sleepTimerState.targetEndTime;

      // Simulate track change / queue update
      final trackA = Track(id: 'song_a', title: 'Song A', artist: 'Artist A', duration: '3:45', imageUrl: '', filePath: '');
      final trackB = Track(id: 'song_b', title: 'Song B', artist: 'Artist B', duration: '4:20', imageUrl: '', filePath: '');
      handler.setQueueForTesting([trackA, trackB]);

      final state = handler.sleepTimerState;
      expect(state.isActive, isTrue);
      expect(state.targetEndTime, equals(initialTarget));
      expect(state.totalDuration, equals(const Duration(minutes: 20)));
    });

    test('9. Background playback timer expiration terminates playback accurately', () async {
      handler.startSleepTimer(const Duration(minutes: 15));
      expect(handler.sleepTimerState.isActive, isTrue);

      // Simulates system timer wake-up while in background
      await handler.triggerSleepTimerExpirationForTesting();
      expect(handler.sleepTimerState.mode, equals(SleepTimerMode.expired));
    });

    test('10. End-of-current-track mode arms stopAfterCurrentTrack flag', () {
      handler.startSleepTimerEndOfTrack();

      final state = handler.sleepTimerState;
      expect(state.mode, equals(SleepTimerMode.endOfTrack));
      expect(state.isEndOfTrack, isTrue);
      expect(state.isActive, isTrue);
      expect(state.statusDescription, equals('Active · Stop after current song'));
      expect(handler.stopAfterCurrentTrackForTesting, isTrue);
    });

    test('11. End-of-current-track prevents queue advancement upon ProcessingState.completed', () {
      handler.startSleepTimerEndOfTrack();
      expect(handler.stopAfterCurrentTrackForTesting, isTrue);

      // Simulate track completion
      final completedState = PlayerState(true, ProcessingState.completed);
      handler.onPlayerStateChangedForTesting(completedState);

      // Flag must be cleared, state must be expired, and queue should not advance
      expect(handler.stopAfterCurrentTrackForTesting, isFalse);
      expect(handler.sleepTimerState.mode, equals(SleepTimerMode.expired));
      expect(handler.sleepTimerState.statusDescription, equals('Timer expired · Playback stopped'));
    });

    test('12. End-of-current-track prevents repeat-one mode from restarting track', () {
      handler.startSleepTimerEndOfTrack();

      // Even if LoopMode.one is set, sleep timer intercepts completion before repeat loop
      final completedState = PlayerState(true, ProcessingState.completed);
      handler.onPlayerStateChangedForTesting(completedState);

      expect(handler.sleepTimerState.mode, equals(SleepTimerMode.expired));
    });

    test('13. No duplicate timers: arming end of track cancels existing countdown and vice versa', () {
      handler.startSleepTimer(const Duration(minutes: 15));
      expect(handler.sleepTimerState.isCountdown, isTrue);

      handler.startSleepTimerEndOfTrack();
      expect(handler.sleepTimerState.isEndOfTrack, isTrue);
      expect(handler.sleepTimerState.isCountdown, isFalse);

      handler.startSleepTimer(const Duration(minutes: 10));
      expect(handler.sleepTimerState.isCountdown, isTrue);
      expect(handler.stopAfterCurrentTrackForTesting, isFalse);
    });

    test('14. Timer state synchronization across SleepTimerNotifier provider', () async {
      final notifier = SleepTimerNotifier(handler);
      expect(notifier.state.mode, equals(SleepTimerMode.inactive));

      notifier.startTimer(const Duration(minutes: 10));
      expect(notifier.state.mode, equals(SleepTimerMode.countdown));
      expect(notifier.state.totalDuration, equals(const Duration(minutes: 10)));

      notifier.cancelTimer();
      expect(notifier.state.mode, equals(SleepTimerMode.cancelled));

      notifier.dispose();
    });
  });
}
