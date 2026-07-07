import 'package:hive/hive.dart';

import '../../../core/storage/adapters/playback_history_entry.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';

/// Records detailed playback sessions for future recommendations.
class PlaybackHistoryRepository {
  Box<PlaybackHistoryEntry> get _box =>
      Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory);

  /// Records a completed or abandoned playback session.
  ///
  /// [completionPercent] should be between 0.0 and 1.0.
  Future<void> recordSession({
    required Track track,
    required DateTime startTime,
    required double completionPercent,
  }) async {
    await _box.add(PlaybackHistoryEntry(
      track: TrackHiveModel.fromTrack(track),
      startTime: startTime,
      completionPercent: completionPercent.clamp(0.0, 1.0),
    ));
  }

  /// Returns all history entries, newest first.
  List<PlaybackHistoryEntry> getHistory() {
    final entries = _box.values.toList();
    entries.sort((a, b) => b.startTime.compareTo(a.startTime));
    return entries;
  }

  /// Clears all history.
  Future<void> clearAll() async => _box.clear();
}
