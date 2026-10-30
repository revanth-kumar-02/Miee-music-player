import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/providers.dart';

class SleepTimerState {
  final bool isActive;
  final int? selectedMinutes;
  final Duration remaining;
  final DateTime? targetTime;

  const SleepTimerState({
    this.isActive = false,
    this.selectedMinutes,
    this.remaining = Duration.zero,
    this.targetTime,
  });

  String get formattedRemaining {
    if (!isActive || remaining <= Duration.zero) return '';
    final m = remaining.inMinutes;
    final s = remaining.inSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final Ref _ref;
  Timer? _ticker;

  SleepTimerNotifier(this._ref) : super(const SleepTimerState());

  /// Starts or updates a sleep timer for [minutes].
  ///
  /// When the timer elapses, audio smoothly fades out over 12 seconds
  /// rather than stopping abruptly.
  void setTimer(int minutes) {
    _ticker?.cancel();
    if (minutes <= 0) {
      cancelTimer();
      return;
    }

    final target = DateTime.now().add(Duration(minutes: minutes));
    state = SleepTimerState(
      isActive: true,
      selectedMinutes: minutes,
      remaining: Duration(minutes: minutes),
      targetTime: target,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      if (state.targetTime == null || now.isAfter(state.targetTime!)) {
        timer.cancel();
        _executeSleepFadeOut();
      } else {
        final diff = state.targetTime!.difference(now);
        state = SleepTimerState(
          isActive: true,
          selectedMinutes: state.selectedMinutes,
          remaining: diff > Duration.zero ? diff : Duration.zero,
          targetTime: state.targetTime,
        );
      }
    });
  }

  void cancelTimer() {
    _ticker?.cancel();
    _ticker = null;
    state = const SleepTimerState();
  }

  Future<void> _executeSleepFadeOut() async {
    state = const SleepTimerState();
    try {
      final handler = _ref.read(audioHandlerProvider);
      debugPrint('[SleepTimer] Timer elapsed. Initiating gentle fade-out.');
      // Fade out smoothly over 12 seconds
      await handler.fadeOutAndPause(duration: const Duration(seconds: 12));
      debugPrint('[SleepTimer] Fade-out complete. Player paused.');
    } catch (e) {
      debugPrint('[SleepTimer] Error during sleep fade-out: $e');
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>((ref) {
  return SleepTimerNotifier(ref);
});
