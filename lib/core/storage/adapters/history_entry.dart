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

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? fallback;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return fallback;
    }

    TrackHiveModel parseTrack(dynamic val) {
      if (val is TrackHiveModel) return val;
      if (val is Map) {
        return TrackHiveModel(
          id: (val['id'] ?? '').toString(),
          title: (val['title'] ?? 'Unknown Title').toString(),
          artist: (val['artist'] ?? 'Unknown Artist').toString(),
          imageUrl: (val['imageUrl'] ?? val['image_url'] ?? '').toString(),
          duration: (val['duration'] ?? '0:00').toString(),
          filePath: val['filePath']?.toString(),
        );
      }
      return TrackHiveModel(
        id: '',
        title: 'Unknown Title',
        artist: 'Unknown Artist',
        imageUrl: '',
        duration: '0:00',
      );
    }

    return HistoryEntry(
      track: parseTrack(fields[0]),
      playedAt: parseDate(fields[1], DateTime.now()),
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
