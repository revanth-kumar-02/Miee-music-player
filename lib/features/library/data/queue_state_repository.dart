import 'package:hive/hive.dart';

import '../../../core/storage/adapters/queue_snapshot.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';

/// Saves and restores the full playback queue state across app restarts.
class QueueStateRepository {
  Box<QueueSnapshot> get _box =>
      Hive.box<QueueSnapshot>(HiveBoxes.queueState);

  /// Persists the current queue state. Overwrites any previous snapshot.
  Future<void> saveSnapshot({
    required List<Track> queue,
    required int currentIndex,
    required int positionMs,
    required bool isShuffleEnabled,
    required String repeatMode,
  }) async {
    final snapshot = QueueSnapshot(
      queue: queue.map(TrackHiveModel.fromTrack).toList(),
      currentIndex: currentIndex,
      positionMs: positionMs,
      isShuffleEnabled: isShuffleEnabled,
      repeatMode: repeatMode,
    );
    await _box.put(HiveBoxes.queueSnapshotKey, snapshot);
  }

  /// Returns the last saved [QueueSnapshot], or null if none exists.
  QueueSnapshot? loadSnapshot() =>
      _box.get(HiveBoxes.queueSnapshotKey);

  /// Converts the snapshot's track list back to domain [Track] objects.
  List<Track>? loadQueueTracks() =>
      loadSnapshot()?.queue.map((m) => m.toTrack()).toList();

  /// Clears the persisted snapshot.
  Future<void> clear() async => _box.delete(HiveBoxes.queueSnapshotKey);
}
