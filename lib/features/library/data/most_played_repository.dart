import 'package:hive/hive.dart';

import '../../../core/storage/hive_boxes.dart';

/// Tracks play-count integers per track id.
///
/// Keys are track ids; values are raw integer play counts.
class MostPlayedRepository {
  Box<int> get _box => Hive.box<int>(HiveBoxes.mostPlayed);

  /// Increments the play count for [trackId] by 1.
  Future<void> incrementCount(String trackId) async {
    final current = _box.get(trackId, defaultValue: 0)!;
    await _box.put(trackId, current + 1);
  }

  /// Returns the play count for [trackId]. Returns 0 if never played.
  int getCount(String trackId) => _box.get(trackId, defaultValue: 0)!;

  /// Returns track ids sorted by play count descending, limited to [limit].
  List<MapEntry<String, int>> getMostPlayed({int limit = 20}) {
    final entries = _box.keys
        .map((key) => MapEntry(key as String, _box.get(key, defaultValue: 0)!))
        .toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList(growable: false);
  }

  /// Resets the play count for [trackId] to zero.
  Future<void> resetCount(String trackId) async => _box.delete(trackId);

  /// Clears all play counts.
  Future<void> clearAll() async => _box.clear();
}
