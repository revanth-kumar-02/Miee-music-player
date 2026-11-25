import 'package:hive/hive.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/utils/display_title_normalizer.dart';

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
  final String? albumName;
  final String? metadataProvider;
  final String? metadataIdentifier;
  final String? sourceProvider;
  final String? sourceId;
  final String? rawTitle;
  final String? rawArtist;
  final String? youtubeThumbnailUrl;
  final String? albumArtworkUrl;
  final String? artworkSource;
  final double? artworkMatchConfidence;
  final String? mbid;
  final String? recordingMbid;
  final String? releaseMbid;

  String get displayTitle => DisplayTitleNormalizer.normalize(title);

  TrackHiveModel({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.duration,
    this.filePath,
    this.albumName,
    this.metadataProvider,
    this.metadataIdentifier,
    this.sourceProvider,
    this.sourceId,
    this.rawTitle,
    this.rawArtist,
    this.youtubeThumbnailUrl,
    this.albumArtworkUrl,
    this.artworkSource,
    this.artworkMatchConfidence,
    this.mbid,
    this.recordingMbid,
    this.releaseMbid,
  });

  /// Converts a domain [MusicItem] into a [TrackHiveModel].
  factory TrackHiveModel.fromTrack(MusicItem track) {
    String finalId = track.id;
    if (track.isYoutube && !finalId.startsWith('youtube_')) {
      finalId = 'youtube_${track.id}';
    }

    final resolvedImage = track.imageUrl;

    if (track is Track) {
      return TrackHiveModel(
        id: finalId,
        title: track.title,
        artist: track.artist,
        imageUrl: resolvedImage,
        duration: track.duration,
        filePath: track.filePath,
        albumName: track.albumName,
        metadataProvider: track.metadataProvider,
        metadataIdentifier: track.metadataIdentifier,
        sourceProvider: track.sourceProvider,
        sourceId: track.sourceId,
        rawTitle: track.rawTitle,
        rawArtist: track.rawArtist,
        youtubeThumbnailUrl: track.youtubeThumbnailUrl,
        albumArtworkUrl: track.albumArtworkUrl,
        artworkSource: track.artworkSource,
        artworkMatchConfidence: track.artworkMatchConfidence,
        mbid: track.mbid,
        recordingMbid: track.recordingMbid,
        releaseMbid: track.releaseMbid,
      );
    }

    return TrackHiveModel(
      id: finalId,
      title: track.title,
      artist: track.artist,
      imageUrl: resolvedImage,
      duration: track.duration,
      filePath: track.filePath,
    );
  }

  /// Converts back to the domain [Track] model.
  Track toTrack() {
    final finalImage = imageUrl;

    return Track(
      id: id,
      title: title,
      artist: artist,
      imageUrl: finalImage,
      duration: duration,
      filePath: filePath,
      albumName: albumName,
      metadataProvider: metadataProvider,
      metadataIdentifier: metadataIdentifier,
      sourceProvider: sourceProvider,
      sourceId: sourceId,
      rawTitle: rawTitle,
      rawArtist: rawArtist,
      youtubeThumbnailUrl: youtubeThumbnailUrl,
      albumArtworkUrl: albumArtworkUrl,
      artworkSource: artworkSource,
      artworkMatchConfidence: artworkMatchConfidence,
      mbid: mbid,
      recordingMbid: recordingMbid,
      releaseMbid: releaseMbid,
    );
  }
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
      id: (fields[0] ?? '').toString(),
      title: (fields[1] ?? 'Unknown Title').toString(),
      artist: (fields[2] ?? 'Unknown Artist').toString(),
      imageUrl: (fields[3] ?? '').toString(),
      duration: (fields[4] ?? '0:00').toString(),
      filePath: fields[5]?.toString(),
      albumName: fields[6]?.toString(),
      metadataProvider: fields[7]?.toString(),
      metadataIdentifier: fields[8]?.toString(),
      sourceProvider: fields[9]?.toString(),
      sourceId: fields[10]?.toString(),
      rawTitle: fields[11]?.toString(),
      rawArtist: fields[12]?.toString(),
      youtubeThumbnailUrl: fields[13]?.toString(),
      albumArtworkUrl: fields[14]?.toString(),
      artworkSource: fields[15]?.toString(),
      artworkMatchConfidence:
          fields[16] != null ? (fields[16] as num).toDouble() : null,
      mbid: fields[17]?.toString(),
      recordingMbid: fields[18]?.toString(),
      releaseMbid: fields[19]?.toString(),
    );
  }

  @override
  void write(BinaryWriter writer, TrackHiveModel obj) {
    writer
      ..writeByte(20)
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
      ..write(obj.filePath)
      ..writeByte(6)
      ..write(obj.albumName)
      ..writeByte(7)
      ..write(obj.metadataProvider)
      ..writeByte(8)
      ..write(obj.metadataIdentifier)
      ..writeByte(9)
      ..write(obj.sourceProvider)
      ..writeByte(10)
      ..write(obj.sourceId)
      ..writeByte(11)
      ..write(obj.rawTitle)
      ..writeByte(12)
      ..write(obj.rawArtist)
      ..writeByte(13)
      ..write(obj.youtubeThumbnailUrl)
      ..writeByte(14)
      ..write(obj.albumArtworkUrl)
      ..writeByte(15)
      ..write(obj.artworkSource)
      ..writeByte(16)
      ..write(obj.artworkMatchConfidence)
      ..writeByte(17)
      ..write(obj.mbid)
      ..writeByte(18)
      ..write(obj.recordingMbid)
      ..writeByte(19)
      ..write(obj.releaseMbid);
  }
}
