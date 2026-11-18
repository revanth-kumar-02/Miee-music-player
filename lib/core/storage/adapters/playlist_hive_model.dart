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
  DateTime lastModified;

  /// Optional user-selected custom cover image path.
  /// When set, takes priority over auto-derived artwork.
  String? customCoverPath;

  /// Visibility and collaboration mode ('private', 'shared', 'collaborative').
  String type;

  /// Auth user ID of the owner.
  String? ownerId;

  /// Current user's permission role ('owner', 'editor', 'viewer').
  String role;

  /// Optional playlist description.
  String? description;

  /// Monotonically increasing revision version.
  int version;

  PlaylistHiveModel({
    required this.id,
    required this.name,
    required this.tracks,
    required this.createdAt,
    DateTime? lastModified,
    this.customCoverPath,
    this.type = 'private',
    this.ownerId,
    this.role = 'owner',
    this.description = '',
    this.version = 1,
  }) : lastModified = lastModified ?? createdAt;
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

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? fallback;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return fallback;
    }

    final now = DateTime.now();
    final createdAt = parseDate(fields[3], now);
    final lastModified = parseDate(fields[4], createdAt);

    final tracks = <TrackHiveModel>[];
    final rawTracks = fields[2];
    if (rawTracks is List) {
      for (final item in rawTracks) {
        if (item is TrackHiveModel) {
          tracks.add(item);
        } else if (item is Map) {
          tracks.add(TrackHiveModel(
            id: (item['id'] ?? '').toString(),
            title: (item['title'] ?? 'Unknown Title').toString(),
            artist: (item['artist'] ?? 'Unknown Artist').toString(),
            imageUrl: (item['imageUrl'] ?? item['image_url'] ?? '').toString(),
            duration: (item['duration'] ?? '0:00').toString(),
            filePath: item['filePath'] as String?,
          ));
        }
      }
    }

    return PlaylistHiveModel(
      id: (fields[0] ?? '').toString(),
      name: (fields[1] ?? 'Untitled Playlist').toString(),
      tracks: tracks,
      createdAt: createdAt,
      lastModified: lastModified,
      customCoverPath: fields[5]?.toString(),
      type: (fields[6] ?? 'private').toString(),
      ownerId: fields[7]?.toString(),
      role: (fields[8] ?? 'owner').toString(),
      description: fields[9]?.toString() ?? '',
      version: (fields[10] as int?) ?? 1,
    );
  }

  @override
  void write(BinaryWriter writer, PlaylistHiveModel obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.tracks)
      ..writeByte(3)
      ..write(obj.createdAt)
      ..writeByte(4)
      ..write(obj.lastModified)
      ..writeByte(5)
      ..write(obj.customCoverPath)
      ..writeByte(6)
      ..write(obj.type)
      ..writeByte(7)
      ..write(obj.ownerId)
      ..writeByte(8)
      ..write(obj.role)
      ..writeByte(9)
      ..write(obj.description)
      ..writeByte(10)
      ..write(obj.version);
  }
}

