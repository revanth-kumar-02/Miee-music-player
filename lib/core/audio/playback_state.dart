import '../../shared/models/music_item.dart';

/// Strongly typed playback status.
enum PlaybackStatus {
  idle,
  loading,
  playing,
  paused,
  buffering,
  completed,
  error,
}

/// Strongly typed repeat mode enum.
enum RepeatMode {
  off,
  one,
  all,
}

/// Immutable data class holding the current playback status, duration metrics,
/// selected track, shuffle settings, and repeat modes.
class PlaybackState {
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final MusicItem? currentTrack;
  final bool isShuffleEnabled;
  final RepeatMode repeatMode;
  final String? errorMessage;

  const PlaybackState({
    required this.status,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.currentTrack,
    this.isShuffleEnabled = false,
    this.repeatMode = RepeatMode.off,
    this.errorMessage,
  });

  /// Factory constructor for initial empty state.
  factory PlaybackState.initial() => const PlaybackState(
        status: PlaybackStatus.idle,
      );

  /// Returns a copy with updated fields.
  ///
  /// To explicitly clear [errorMessage] to null, pass [clearErrorMessage]=true.
  /// Passing [errorMessage]=null without the flag preserves the existing value,
  /// because the `??` operator cannot distinguish "null as a value" from
  /// "not supplied" without a sentinel.
  PlaybackState copyWith({
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    MusicItem? currentTrack,
    bool? isShuffleEnabled,
    RepeatMode? repeatMode,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return PlaybackState(
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      currentTrack: currentTrack ?? this.currentTrack,
      isShuffleEnabled: isShuffleEnabled ?? this.isShuffleEnabled,
      repeatMode: repeatMode ?? this.repeatMode,
      errorMessage:
          clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
