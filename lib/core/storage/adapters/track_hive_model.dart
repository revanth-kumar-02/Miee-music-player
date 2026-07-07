import 'package:hive/hive.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';

/// Hive-persisted representation of a [Track].
///
/// Written manually — no code generation required.
/// TypeId 1 is permanently reserved for this model; never reuse it.
class TrackHiveModel extends HiveObject {
  final String id;
  final String title;
  final String artist;
  final String imageUrl;
  final String duration;
  final String? filePath;

  TrackHiveModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.duration,
    this.filePath,
  });

  /// Converts a domain [MusicItem] into a [TrackHiveModel].
  factory TrackHiveModel.fromTrack(MusicItem track) => TrackHiveModel(
        id: track.id,
        title: track.title,
        artist: track.artist,
        imageUrl: track.imageUrl,
        duration: track.duration,
        filePath: track.filePath,
      );


  /// Converts back to the domain [Track] model.
  Track toTrack() => Track(
        id: id,
        title: title,
        artist: artist,
        imageUrl: imageUrl,
        duration: duration,
        filePath: filePath,
      );
}

/// Manual [TypeAdapter] for [TrackHiveModel].
class TrackHiveModelAdapter extends TypeAdapter<TrackHiveModel> {
  @override
  final int typeId = 1;

  @override
  TrackHiveModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TrackHiveModel(
      id: fields[0] as String,
      title: fields[1] as String,
      artist: fields[2] as String,
      imageUrl: fields[3] as String,
      duration: fields[4] as String,
      filePath: fields[5] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TrackHiveModel obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.artist)
      ..writeByte(3)
      ..write(obj.imageUrl)
      ..writeByte(4)
      ..write(obj.duration)
      ..writeByte(5)
      ..write(obj.filePath);
  }
}
