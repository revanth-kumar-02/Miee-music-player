import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/utils/display_title_normalizer.dart';
import '../../metadata/domain/itunes_song.dart';
import '../../metadata/domain/musicbrainz_models.dart';
import 'youtube_metadata_cleaner.dart';

/// Strongly-typed domain model representing a YouTube search result.
class YouTubeVideo implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  @override
  final String duration; // e.g. "3:45"
  final String viewCount; // e.g. "124K views" or "1.2M views"
  final String? rawTitle;
  final String? rawChannelTitle;
  final String? audioStreamUrl;
  final int? rawViewCount;
  final String? channelId;

  /// Canonical song title resolved from Apple iTunes catalogue.
  final String? canonicalTitle;

  /// Canonical artist name resolved from Apple iTunes catalogue.
  final String? canonicalArtist;

  /// Canonical album collection name resolved from Apple iTunes catalogue.
  final String? albumName;

  /// High-resolution album artwork URL (`600x600bb.jpg`) from iTunes mzstatic CDN.
  final String? highResArtworkUrl;

  /// Metadata provider identifier (e.g. 'itunes' or 'youtube').
  final String? metadataProvider;

  /// Provider-specific track identifier (e.g. iTunes trackId).
  final String? metadataIdentifier;

  /// Canonical MusicBrainz Recording identifier (MBID UUID).
  final String? mbid;

  /// Canonical Recording MBID specifically.
  final String? recordingMbid;

  /// Canonical Release MBID specifically.
  final String? releaseMbid;

  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.duration,
    required this.viewCount,
    this.rawTitle,
    this.rawChannelTitle,
    this.audioStreamUrl,
    this.rawViewCount,
    this.channelId,
    this.canonicalTitle,
    this.canonicalArtist,
    this.albumName,
    this.highResArtworkUrl,
    this.metadataProvider,
    this.metadataIdentifier,
    this.mbid,
    this.recordingMbid,
    this.releaseMbid,
  });

  YouTubeVideo copyWith({
    String? id,
    String? title,
    String? channelTitle,
    String? thumbnailUrl,
    String? duration,
    String? viewCount,
    String? rawTitle,
    String? rawChannelTitle,
    String? audioStreamUrl,
    int? rawViewCount,
    String? channelId,
    String? canonicalTitle,
    String? canonicalArtist,
    String? albumName,
    String? highResArtworkUrl,
    String? metadataProvider,
    String? metadataIdentifier,
    String? mbid,
    String? recordingMbid,
    String? releaseMbid,
  }) {
    return YouTubeVideo(
      id: id ?? this.id,
      title: title ?? (canonicalTitle ?? this.title),
      channelTitle: channelTitle ?? (canonicalArtist ?? this.channelTitle),
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      viewCount: viewCount ?? this.viewCount,
      rawTitle: rawTitle ?? this.rawTitle,
      rawChannelTitle: rawChannelTitle ?? this.rawChannelTitle,
      audioStreamUrl: audioStreamUrl ?? this.audioStreamUrl,
      rawViewCount: rawViewCount ?? this.rawViewCount,
      channelId: channelId ?? this.channelId,
      canonicalTitle: canonicalTitle ?? this.canonicalTitle,
      canonicalArtist: canonicalArtist ?? this.canonicalArtist,
      albumName: albumName ?? this.albumName,
      highResArtworkUrl: highResArtworkUrl ?? this.highResArtworkUrl,
      metadataProvider: metadataProvider ?? this.metadataProvider,
      metadataIdentifier: metadataIdentifier ?? this.metadataIdentifier,
      mbid: mbid ?? this.mbid,
      recordingMbid: recordingMbid ?? this.recordingMbid,
      releaseMbid: releaseMbid ?? this.releaseMbid,
    );
  }

  /// Creates a [YouTubeVideo] from an official [MusicBrainzRecording] entry.
  factory YouTubeVideo.fromMusicBrainzRecording(
    MusicBrainzRecording recording, {
    String? resolvedVideoId,
    String? audioStreamUrl,
    String? viewCount,
    int? rawViewCount,
    String? channelId,
    String? artworkUrl,
  }) {
    final effectiveId = resolvedVideoId ?? 'mb_${recording.mbid}';
    final cover = artworkUrl ?? recording.frontCoverUrl ?? recording.coverArtArchiveUrl ?? '';
    return YouTubeVideo(
      id: effectiveId,
      title: recording.title,
      channelTitle: recording.artistCredit,
      thumbnailUrl: cover,
      duration: recording.formattedDuration,
      viewCount: viewCount ?? 'MusicBrainz Verified',
      rawTitle: recording.title,
      rawChannelTitle: recording.artistCredit,
      audioStreamUrl: audioStreamUrl,
      rawViewCount: rawViewCount,
      channelId: channelId,
      canonicalTitle: recording.title,
      canonicalArtist: recording.artistCredit,
      albumName: recording.albumTitle,
      highResArtworkUrl: cover.isNotEmpty ? cover : null,
      metadataProvider: 'musicbrainz',
      metadataIdentifier: recording.mbid,
      mbid: recording.mbid,
      recordingMbid: recording.mbid,
      releaseMbid: recording.releaseMbid,
    );
  }

  /// Creates a [YouTubeVideo] from an official [ItunesSong] entry.
  ///
  /// This establishes the music-first discovery identity:
  /// - Canonical song title, artist, album, and high-resolution studio artwork
  ///   are locked from the start.
  /// - Playback source ID defaults to `itunes_${song.trackId}` until resolved to
  ///   an authentic playable YouTube video stream.
  factory YouTubeVideo.fromItunesSong(
    ItunesSong song, {
    String? resolvedVideoId,
    String? audioStreamUrl,
    String? viewCount,
    int? rawViewCount,
    String? channelId,
  }) {
    final effectiveId = resolvedVideoId ?? 'itunes_${song.trackId}';
    final artwork = song.highResArtworkUrl.isNotEmpty
        ? song.highResArtworkUrl
        : song.artworkUrl100;
    return YouTubeVideo(
      id: effectiveId,
      title: song.trackName,
      channelTitle: song.artistName,
      thumbnailUrl: artwork,
      duration: song.formattedDuration,
      viewCount: viewCount ?? 'Apple Music',
      rawTitle: song.trackName,
      rawChannelTitle: song.artistName,
      audioStreamUrl: audioStreamUrl,
      rawViewCount: rawViewCount,
      channelId: channelId,
      canonicalTitle: song.trackName,
      canonicalArtist: song.artistName,
      albumName: song.collectionName,
      highResArtworkUrl: artwork.isNotEmpty ? artwork : null,
      metadataProvider: 'itunes',
      metadataIdentifier: song.trackId.toString(),
    );
  }

  /// The standard watch page URL for this video.
  String get videoUrl => 'https://www.youtube.com/watch?v=$id';

  /// The watch page URL optimized for YouTube Music.
  String get musicUrl => 'https://music.youtube.com/watch?v=$id';

  @override
  String get artist => canonicalArtist ?? channelTitle;

  @override
  String get displayTitle => DisplayTitleNormalizer.normalize(canonicalTitle ?? title);

  @override
  String get imageUrl => highResArtworkUrl ?? thumbnailUrl;

  @override
  String get effectiveArtworkUrl => highResArtworkUrl ?? thumbnailUrl;

  @override
  String get filePath => audioStreamUrl ?? videoUrl;

  @override
  bool get isYoutube => audioStreamUrl == null || !audioStreamUrl!.startsWith('http') || audioStreamUrl!.contains('youtube.com');

  /// Converts this YouTube result into a standard [Track] model so it can be
  /// played or queued by Miee's playback engine.
  Track toTrack({String? reliableArtist, String? reliableTitle}) {
    final cleaned = YouTubeMetadataCleaner.clean(
      rawTitle: rawTitle ?? title,
      rawChannel: rawChannelTitle ?? channelTitle,
      reliableArtist: reliableArtist ?? canonicalArtist,
      reliableTitle: reliableTitle ?? canonicalTitle,
    );
    final hasHighRes = highResArtworkUrl != null && highResArtworkUrl!.isNotEmpty;
    return Track(
      id: 'youtube_$id',
      title: canonicalTitle ?? cleaned.title,
      artist: canonicalArtist ?? cleaned.artist,
      imageUrl: hasHighRes ? highResArtworkUrl! : thumbnailUrl,
      duration: duration,
      filePath: audioStreamUrl ?? videoUrl, // Playback engine will recognize direct audio stream or YouTube URL
      isFavorited: false,
      rawTitle: rawTitle ?? title,
      rawArtist: rawChannelTitle ?? channelTitle,
      artistId: channelId,
      albumName: albumName,
      metadataProvider: metadataProvider ?? (hasHighRes ? 'itunes' : 'youtube'),
      metadataIdentifier: metadataIdentifier,
      sourceProvider: 'youtube',
      sourceId: id,
      rawViewCount: rawViewCount,
      viewCount: viewCount,
      youtubeThumbnailUrl: thumbnailUrl,
      albumArtworkUrl: hasHighRes ? highResArtworkUrl : null,
      artworkSource: hasHighRes ? (metadataProvider ?? 'itunes') : 'youtube',
      artworkMatchConfidence: hasHighRes ? 0.95 : 0.5,
      resolvedArtworkUrl: hasHighRes ? highResArtworkUrl : thumbnailUrl,
      mbid: mbid,
      recordingMbid: recordingMbid,
      releaseMbid: releaseMbid,
    );
  }
}

