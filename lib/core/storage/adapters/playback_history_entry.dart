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
    return PlaybackHistoryEntry(
      track: fields[0] as TrackHiveModel,
      startTime: fields[1] as DateTime,
      completionPercent: (fields[2] as num).toDouble(),
      userId: fields[3] as String?,
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
