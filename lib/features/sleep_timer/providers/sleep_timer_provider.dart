import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/audio_handler.dart';
import '../../../core/audio/providers.dart';
import '../domain/sleep_timer_state.dart';

/// Notifier managing sleep timer state synchronized with [MieeAudioHandler].
class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final MieeAudioHandler _audioHandler;
  StreamSubscription<SleepTimerState>? _sub;

  SleepTimerNotifier(this._audioHandler)
      : super(_audioHandler.sleepTimerState) {
    _sub = _audioHandler.sleepTimerStateStream.listen((newState) {
      if (mounted) {
        state = newState;
      }
    });
  }

  /// Starts a countdown sleep timer with the given [duration].
  void startTimer(Duration duration) {
    _audioHandler.startSleepTimer(duration);
    state = _audioHandler.sleepTimerState;
  }

  /// Arms the sleep timer to stop playback after the currently playing song completes.
  void startEndOfTrack() {
    _audioHandler.startSleepTimerEndOfTrack();
    state = _audioHandler.sleepTimerState;
  }

  /// Cancels any active sleep timer or end-of-track listener.
  void cancelTimer() {
    _audioHandler.cancelSleepTimer();
    state = _audioHandler.sleepTimerState;
  }

  /// Recalculates remaining time upon app lifecycle resume.
  void recalculateRemaining() {
    if (state.mode == SleepTimerMode.countdown && state.targetEndTime != null) {
      final diff = state.calculatedRemaining;
      state = state.copyWith(remainingDuration: diff);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Provider exposing the active [SleepTimerState] and actions.
final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  final audioHandler = ref.watch(audioHandlerProvider);
  return SleepTimerNotifier(audioHandler);
});
