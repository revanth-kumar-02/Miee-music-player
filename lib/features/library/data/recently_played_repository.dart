import 'package:hive/hive.dart';

import '../../../core/storage/adapters/history_entry.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';

/// Stores and retrieves the most recently played tracks (latest 100).
class RecentlyPlayedRepository {
  static const int _maxEntries = 100;

  Box<HistoryEntry> get _box =>
      Hive.box<HistoryEntry>(HiveBoxes.recentlyPlayed);

  /// Records [track] as played right now.
  ///
  /// Automatically trims the box to [_maxEntries] oldest entries.
  Future<void> recordPlay(Track track) async {
    await _box.add(HistoryEntry(
      track: TrackHiveModel.fromTrack(track),
      playedAt: DateTime.now(),
    ));

    // Keep only the most recent _maxEntries entries.
    if (_box.length > _maxEntries) {
      final excess = _box.length - _maxEntries;
      final keysToDelete = _box.keys.take(excess).toList();
      await _box.deleteAll(keysToDelete);
    }
  }

  /// Returns all recently played entries, newest first.
  List<HistoryEntry> getRecentlyPlayed() {
    final entries = _box.values.toList();
    entries.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return entries;
  }

  /// Returns the most recently played [Track] objects (newest first).
  List<Track> getRecentTracks() =>
      getRecentlyPlayed().map((e) => e.track.toTrack()).toList(growable: false);

  /// Stream that emits whenever the history changes.
  Stream<List<HistoryEntry>> watchRecentlyPlayed() =>
      _box.watch().map((_) => getRecentlyPlayed());

  /// Clears all recently played history.
  Future<void> clear() async => _box.clear();
}
