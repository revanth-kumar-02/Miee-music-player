import 'package:hive/hive.dart';
import 'track_hive_model.dart';

/// Hive-persisted user playlist containing an ordered list of tracks.
///
/// TypeId 2 is permanently reserved for this model.
class PlaylistHiveModel extends HiveObject {
  String id;
  String name;
  List<TrackHiveModel> tracks;
  DateTime createdAt;

  PlaylistHiveModel({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
  });
}

/// Manual [TypeAdapter] for [PlaylistHiveModel].
class PlaylistHiveModelAdapter extends TypeAdapter<PlaylistHiveModel> {
  @override
  final int typeId = 2;

  @override
  PlaylistHiveModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PlaylistHiveModel(
      id: fields[0] as String,
      name: fields[1] as String,
      tracks: (fields[2] as List).cast<TrackHiveModel>(),
      createdAt: fields[3] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, PlaylistHiveModel obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.tracks)
      ..writeByte(3)
      ..write(obj.createdAt);
  }
}
