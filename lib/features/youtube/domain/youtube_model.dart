import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
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
    );
  }

  /// The standard watch page URL for this video.
  String get videoUrl => 'https://www.youtube.com/watch?v=$id';

  /// The watch page URL optimized for YouTube Music.
  String get musicUrl => 'https://music.youtube.com/watch?v=$id';

  @override
  String get artist => canonicalArtist ?? channelTitle;

  @override
  String get imageUrl => highResArtworkUrl ?? thumbnailUrl;

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
    return Track(
      id: 'youtube_$id',
      title: canonicalTitle ?? cleaned.title,
      artist: canonicalArtist ?? cleaned.artist,
      imageUrl: highResArtworkUrl ?? thumbnailUrl,
      duration: duration,
      filePath: audioStreamUrl ?? videoUrl, // Playback engine will recognize direct audio stream or YouTube URL
      isFavorited: false,
      rawTitle: rawTitle ?? title,
      rawArtist: rawChannelTitle ?? channelTitle,
      artistId: channelId,
      albumName: albumName,
      metadataProvider: metadataProvider ?? 'youtube',
      metadataIdentifier: metadataIdentifier,
      sourceProvider: 'youtube',
      sourceId: id,
    );
  }
}

