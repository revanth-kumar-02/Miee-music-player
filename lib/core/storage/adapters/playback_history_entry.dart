import 'package:hive/hive.dart';
import 'track_hive_model.dart';

/// Stores a single playback session record — useful for recommendations.
///
/// TypeId 4 is permanently reserved for this model.
class PlaybackHistoryEntry extends HiveObject {
  final TrackHiveModel track;
  final DateTime startTime;

  /// Proportion of the song completed: 0.0 – 1.0.
  final double completionPercent;

  PlaybackHistoryEntry({
    required this.track,
    required this.startTime,
    required this.completionPercent,
  });
}

/// Manual [TypeAdapter] for [PlaybackHistoryEntry].
class PlaybackHistoryEntryAdapter extends TypeAdapter<PlaybackHistoryEntry> {
  @override
  final int typeId = 4;

  @override
  PlaybackHistoryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaybackHistoryEntry(
      track: fields[0] as TrackHiveModel,
      startTime: fields[1] as DateTime,
      completionPercent: fields[2] as double,
    );
  }

  @override
  void write(BinaryWriter writer, PlaybackHistoryEntry obj) {
    writer
      ..writeByte(3)
      ..writeByte(0)
      ..write(obj.track)
      ..writeByte(1)
      ..write(obj.startTime)
      ..writeByte(2)
      ..write(obj.completionPercent);
  }
}
