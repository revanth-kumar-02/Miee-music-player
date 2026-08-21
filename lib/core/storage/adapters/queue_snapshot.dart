import 'package:hive/hive.dart';
import 'track_hive_model.dart';

/// Captures the complete playback queue state so it can be restored after
/// the app is closed and reopened.
///
/// TypeId 5 is permanently reserved for this model.
class QueueSnapshot extends HiveObject {
  /// The full ordered list of queued tracks.
  final List<TrackHiveModel> queue;

  /// Index of the currently playing track in [queue].
  final int currentIndex;

  /// Playback position in milliseconds at the time the snapshot was saved.
  final int positionMs;

  /// Whether shuffle was active.
  final bool isShuffleEnabled;

  /// Repeat mode string: 'off' | 'one' | 'all'.
  final String repeatMode;

  QueueSnapshot({
    required this.queue,
    required this.currentIndex,
    required this.positionMs,
    required this.isShuffleEnabled,
    required this.repeatMode,
  });
}

/// Manual [TypeAdapter] for [QueueSnapshot].
class QueueSnapshotAdapter extends TypeAdapter<QueueSnapshot> {
  @override
  final int typeId = 5;

  @override
  QueueSnapshot read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return QueueSnapshot(
      queue: (fields[0] as List).cast<TrackHiveModel>(),
      currentIndex: fields[1] as int,
      positionMs: fields[2] as int,
      isShuffleEnabled: fields[3] as bool,
      repeatMode: fields[4] as String,
    );
  }

  @override
  void write(BinaryWriter writer, QueueSnapshot obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.queue)
      ..writeByte(1)
      ..write(obj.currentIndex)
      ..writeByte(2)
      ..write(obj.positionMs)
      ..writeByte(3)
      ..write(obj.isShuffleEnabled)
      ..writeByte(4)
      ..write(obj.repeatMode);
  }
}
