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

/// Utility to compare two track IDs while normalizing optional `youtube_` prefixes.
bool isSameTrackId(String? a, String? b) {
  if (a == null || b == null) return false;
  final normA = a.startsWith('youtube_') ? a.replaceFirst('youtube_', '') : a;
  final normB = b.startsWith('youtube_') ? b.replaceFirst('youtube_', '') : b;
  return normA == normB;
}

/// Immutable data class holding the current playback status, duration metrics,
/// selected track, shuffle settings, repeat modes, and active preparation states.
class PlaybackState {
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final MusicItem? currentTrack;
  final bool isShuffleEnabled;
  final RepeatMode repeatMode;
  final String? errorMessage;
  final double volume;
  final String? playingFrom;

  /// The ID of the track currently being resolved or prepared over the network.
  /// Null if no track is actively resolving or if playback has begun / failed.
  final String? loadingTrackId;

  const PlaybackState({
    required this.status,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
    this.currentTrack,
    this.isShuffleEnabled = false,
    this.repeatMode = RepeatMode.off,
    this.errorMessage,
    this.volume = 1.0,
    this.playingFrom,
    this.loadingTrackId,
  });

  /// Factory constructor for initial empty state.
  factory PlaybackState.initial() => const PlaybackState(
        status: PlaybackStatus.idle,
      );

  /// Returns a copy with updated fields.
  ///
  /// To explicitly clear [errorMessage] or [loadingTrackId] to null, pass
  /// [clearErrorMessage]=true or [clearLoadingTrackId]=true.
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
    double? volume,
    String? playingFrom,
    String? loadingTrackId,
    bool clearLoadingTrackId = false,
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
      volume: volume ?? this.volume,
      playingFrom: playingFrom ?? this.playingFrom,
      loadingTrackId:
          clearLoadingTrackId ? null : (loadingTrackId ?? this.loadingTrackId),
    );
  }
}
