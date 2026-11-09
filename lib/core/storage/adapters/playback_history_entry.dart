import 'package:hive/hive.dart';
import 'track_hive_model.dart';

/// Stores a single playback session record — useful for recommendations and taste profile.
///
/// TypeId 4 is permanently reserved for this model.
class PlaybackHistoryEntry extends HiveObject {
  final TrackHiveModel track;
  final DateTime startTime;

  /// Proportion of the song completed: 0.0 – 1.0.
  final double completionPercent;

  /// Authenticated user ID (ensures account isolation across sign-ins).
  final String? userId;

  PlaybackHistoryEntry({
    required this.track,
    required this.startTime,
    required this.completionPercent,
    this.userId,
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

    double parseDouble(dynamic val, double fallback) {
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? fallback;
      return fallback;
    }

    return PlaybackHistoryEntry(
      track: parseTrack(fields[0]),
      startTime: parseDate(fields[1], DateTime.now()),
      completionPercent: parseDouble(fields[2], 0.0),
      userId: fields[3]?.toString(),
    );
  }

  @override
  void write(BinaryWriter writer, PlaybackHistoryEntry obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.track)
      ..writeByte(1)
      ..write(obj.startTime)
      ..writeByte(2)
      ..write(obj.completionPercent)
      ..writeByte(3)
      ..write(obj.userId);
  }
}
