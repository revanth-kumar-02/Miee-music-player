/// Representation of the sleep timer state in Miee.
enum SleepTimerMode {
  inactive,
  countdown,
  endOfTrack,
  expired,
  cancelled,
}

class SleepTimerState {
  final SleepTimerMode mode;
  final Duration? totalDuration;
  final DateTime? targetEndTime;
  final Duration remainingDuration;

  const SleepTimerState({
    this.mode = SleepTimerMode.inactive,
    this.totalDuration,
    this.targetEndTime,
    this.remainingDuration = Duration.zero,
  });

  const SleepTimerState.inactive()
      : mode = SleepTimerMode.inactive,
        totalDuration = null,
        targetEndTime = null,
        remainingDuration = Duration.zero;

  const SleepTimerState.cancelled()
      : mode = SleepTimerMode.cancelled,
        totalDuration = null,
        targetEndTime = null,
        remainingDuration = Duration.zero;

  const SleepTimerState.expired()
      : mode = SleepTimerMode.expired,
        totalDuration = null,
        targetEndTime = null,
        remainingDuration = Duration.zero;

  const SleepTimerState.endOfTrack()
      : mode = SleepTimerMode.endOfTrack,
        totalDuration = null,
        targetEndTime = null,
        remainingDuration = Duration.zero;

  bool get isActive =>
      mode == SleepTimerMode.countdown || mode == SleepTimerMode.endOfTrack;
  bool get isCountdown => mode == SleepTimerMode.countdown;
  bool get isEndOfTrack => mode == SleepTimerMode.endOfTrack;

  /// Recalculates remaining duration against the system clock ground truth.
  Duration get calculatedRemaining {
    if (mode != SleepTimerMode.countdown || targetEndTime == null) {
      return Duration.zero;
    }
    final diff = targetEndTime!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String get formattedRemainingTime {
    if (!isCountdown) return '';
    final dur = targetEndTime != null ? calculatedRemaining : remainingDuration;
    // Round to nearest second to avoid truncation jitter (e.g. 299.98s becoming 4:59 instead of 5:00)
    final totalSeconds = (dur.inMilliseconds + 500) ~/ 1000;
    if (totalSeconds <= 0) return '0:00';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    final h = m ~/ 60;
    final remM = m % 60;
    if (h > 0) {
      return '$h:${remM.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$remM:${s.toString().padLeft(2, '0')}';
  }

  String get statusDescription {
    switch (mode) {
      case SleepTimerMode.inactive:
      case SleepTimerMode.cancelled:
        return 'Turn off music automatically';
      case SleepTimerMode.expired:
        return 'Timer expired · Playback stopped';
      case SleepTimerMode.endOfTrack:
        return 'Active · Stop after current song';
      case SleepTimerMode.countdown:
        return 'Active · $formattedRemainingTime remaining';
    }
  }

  SleepTimerState copyWith({
    SleepTimerMode? mode,
    Duration? totalDuration,
    DateTime? targetEndTime,
    Duration? remainingDuration,
  }) {
    return SleepTimerState(
      mode: mode ?? this.mode,
      totalDuration: totalDuration ?? this.totalDuration,
      targetEndTime: targetEndTime ?? this.targetEndTime,
      remainingDuration: remainingDuration ?? this.remainingDuration,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SleepTimerState &&
          runtimeType == other.runtimeType &&
          mode == other.mode &&
          totalDuration == other.totalDuration &&
          targetEndTime == other.targetEndTime &&
          remainingDuration.inSeconds == other.remainingDuration.inSeconds;

  @override
  int get hashCode =>
      mode.hashCode ^
      totalDuration.hashCode ^
      targetEndTime.hashCode ^
      remainingDuration.inSeconds.hashCode;
}
