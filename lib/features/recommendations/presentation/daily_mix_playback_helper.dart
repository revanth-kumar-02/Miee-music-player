import '../../../core/audio/player_controller.dart';
import '../domain/daily_mix.dart';

/// Extension providing clean playback integration between [DailyMix] and [PlayerController].
extension DailyMixPlaybackExtension on PlayerController {
  /// Starts playback of the given [mix], queuing its tracks in deterministic order.
  ///
  /// Preserves the user's active audio handler session and sets the playingFrom context.
  void playDailyMix(DailyMix mix, {int startIndex = 0}) {
    if (mix.tracks.isEmpty) return;
    final clampedIndex = (startIndex >= 0 && startIndex < mix.tracks.length)
        ? startIndex
        : 0;

    setQueue(
      mix.tracks,
      startIndex: clampedIndex,
      playingFrom: 'Daily Mix: ${mix.title}',
    );
  }
}

