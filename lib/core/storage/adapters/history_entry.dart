import 'package:hive/hive.dart';
import 'track_hive_model.dart';

/// Represents a single "recently played" entry stored in Hive.
///
/// TypeId 3 is permanently reserved for this model.
class HistoryEntry extends HiveObject {
  final TrackHiveModel track;
  final DateTime playedAt;

  HistoryEntry({required this.track, required this.playedAt});
}

/// Manual [TypeAdapter] for [HistoryEntry].
class HistoryEntryAdapter extends TypeAdapter<HistoryEntry> {
  @override
  final int typeId = 3;

  @override
  HistoryEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return HistoryEntry(
      track: fields[0] as TrackHiveModel,
      playedAt: fields[1] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, HistoryEntry obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)
      ..write(obj.track)
      ..writeByte(1)
      ..write(obj.playedAt);
  }
}
