import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/hive_boxes.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/offline_operation.dart';

/// Tracks play-count integers per track id with cloud synchronization.
class MostPlayedRepository {
  final Ref _ref;

  MostPlayedRepository(this._ref);

  Box<int> get _box => Hive.box<int>(HiveBoxes.mostPlayed);

  /// Increments the play count for [trackId] by 1.
  Future<void> incrementCount(String trackId) async {
    final current = _box.get(trackId, defaultValue: 0)!;
    final nextVal = current + 1;
    await _box.put(trackId, nextVal);

    final op = OfflineOperation(
      id: 'mp_inc_${trackId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'most_played_increment',
      payload: {
        'trackId': trackId,
        'count': nextVal,
      },
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
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
  Future<void> resetCount(String trackId) async {
    await _box.delete(trackId);
    
    final op = OfflineOperation(
      id: 'mp_reset_${trackId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'most_played_increment',
      payload: {
        'trackId': trackId,
        'count': 0,
      },
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
  }

  /// Clears all play counts.
  Future<void> clearAll() async => _box.clear();
}
