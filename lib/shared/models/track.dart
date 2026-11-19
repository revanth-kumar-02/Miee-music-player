import 'package:flutter/foundation.dart';
import 'music_item.dart';
import '../utils/display_title_normalizer.dart';

/// Model representing a music track.
class Track implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String duration;
  
  final String? localFilePath;
  final double progress;
  final bool isPlaying;
  final bool isFavorited;

  /// Original source title preserved for diagnostics and parser debugging.
  final String? rawTitle;

  /// Original source artist / author preserved for diagnostics.
  final String? rawArtist;

  /// Stable artist identifier (e.g. Deezer ID, Curated ID, or YouTube Channel ID).
  final String? artistId;

  /// Album name if known from iTunes or metadata tags.
  final String? albumName;

  /// Identifier of the metadata provider (e.g. 'itunes' or 'youtube').
  final String? metadataProvider;

  /// Provider-specific identifier for metadata tracking (e.g. iTunes trackId).
  final String? metadataIdentifier;

  /// Primary source provider for playback audio (e.g. 'youtube', 'local').
  final String? sourceProvider;

  /// Raw audio source identifier (e.g. 11-char YouTube videoId).
  final String? sourceId;

  /// Raw numeric view count if available (for quality verification and ranking).
  final int? rawViewCount;

  /// Human-readable view count string (e.g. "776.7M views").
  final String? viewCount;

  /// Dedicated original YouTube video thumbnail URL (preserved as last-resort fallback).
  final String? youtubeThumbnailUrl;

  /// Verified external high-confidence studio album cover artwork URL (e.g. Apple iTunes 600x600).
  final String? albumArtworkUrl;

  /// File path to embedded local cover art on disk (for local tracks).
  final String? embeddedArtworkPath;

  /// The active resolved artwork URL or local file path chosen by the resolution engine.
  final String? resolvedArtworkUrl;

  /// Artwork source identifier ('itunes', 'deezer', 'local', 'youtube', 'neutralFallback').
  final String? artworkSource;

  /// Confidence score of the artwork match (0.0 to 1.0). High confidence is >= 0.80.
  final double? artworkMatchConfidence;

  /// Canonical MusicBrainz Recording identifier (MBID UUID).
  final String? mbid;

  /// Canonical Recording MBID specifically.
  final String? recordingMbid;

  /// Canonical Release MBID specifically.
  final String? releaseMbid;

  /// Canonical Artist MBID specifically.
  final String? artistMbid;

  final String _rawImageUrl;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required String imageUrl,
    required this.duration,
    String? filePath,
    this.progress = 0.0,
    this.isPlaying = false,
    this.isFavorited = false,
    this.rawTitle,
    this.rawArtist,
    this.artistId,
    this.albumName,
    this.metadataProvider,
    this.metadataIdentifier,
    this.sourceProvider,
    this.sourceId,
    this.rawViewCount,
    this.viewCount,
    this.youtubeThumbnailUrl,
    this.albumArtworkUrl,
    this.embeddedArtworkPath,
    this.resolvedArtworkUrl,
    this.artworkSource,
    this.artworkMatchConfidence,
    this.mbid,
    this.recordingMbid,
    this.releaseMbid,
    this.artistMbid,
  })  : _rawImageUrl = imageUrl,
        localFilePath = filePath;

  @override
  String get filePath => localFilePath ?? '';

  @override
  String get displayTitle => DisplayTitleNormalizer.normalize(title);

  /// Deterministic artwork source priority getter:
  /// 1. Verified high-confidence external studio album artwork (iTunes, Deezer, CoverArtArchive)
  /// 2. Valid embedded local album artwork
  /// 3. Active resolved studio artwork URL
  /// 4. YouTube video thumbnail fallback
  /// 5. Raw initial image URL
  @override
  String get imageUrl {
    if (albumArtworkUrl != null &&
        albumArtworkUrl!.isNotEmpty &&
        !albumArtworkUrl!.contains('ytimg.com') &&
        !albumArtworkUrl!.contains('youtube.com')) {
      return albumArtworkUrl!;
    }
    if (embeddedArtworkPath != null && embeddedArtworkPath!.isNotEmpty) {
      return embeddedArtworkPath!;
    }
    if (resolvedArtworkUrl != null &&
        resolvedArtworkUrl!.isNotEmpty &&
        !resolvedArtworkUrl!.contains('ytimg.com') &&
        !resolvedArtworkUrl!.contains('youtube.com')) {
      return resolvedArtworkUrl!;
    }
    if (_rawImageUrl.isNotEmpty &&
        !_rawImageUrl.contains('ytimg.com') &&
        !_rawImageUrl.contains('youtube.com')) {
      return _rawImageUrl;
    }
    if (youtubeThumbnailUrl != null && youtubeThumbnailUrl!.isNotEmpty) {
      return youtubeThumbnailUrl!;
    }
    return _rawImageUrl;
  }

  @override
  String get effectiveArtworkUrl => imageUrl;

  @override
  String? get album => albumName;

  @override
  bool get isYoutube =>
      kIsWeb ||
      id.startsWith('youtube_') ||
      id.startsWith('wm_') ||
      RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id) ||
      (localFilePath?.contains('youtube.com') ?? false) ||
      (localFilePath?.startsWith('http') ?? false);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Track &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? imageUrl,
    String? duration,
    String? filePath,
    double? progress,
    bool? isPlaying,
    bool? isFavorited,
    String? rawTitle,
    String? rawArtist,
    String? artistId,
    String? albumName,
    String? metadataProvider,
    String? metadataIdentifier,
    String? sourceProvider,
    String? sourceId,
    int? rawViewCount,
    String? viewCount,
    String? youtubeThumbnailUrl,
    String? albumArtworkUrl,
    String? embeddedArtworkPath,
    String? resolvedArtworkUrl,
    String? artworkSource,
    double? artworkMatchConfidence,
    String? mbid,
    String? recordingMbid,
    String? releaseMbid,
    String? artistMbid,
  }) {
    String resolvedImage = (imageUrl != null && imageUrl.isNotEmpty)
        ? imageUrl
        : _rawImageUrl;

    final targetId = id ?? this.id;
    final isYt = targetId.startsWith('youtube_') ||
        (sourceProvider == 'youtube') ||
        (filePath?.contains('youtube.com') ?? false) ||
        (localFilePath?.contains('youtube.com') ?? false);

    if (isYt && (resolvedImage.isEmpty || !resolvedImage.startsWith('http'))) {
      final cleanId = (sourceId ?? targetId).replaceFirst('youtube_', '').trim();
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(cleanId)) {
        resolvedImage = 'https://i.ytimg.com/vi/$cleanId/hqdefault.jpg';
      }
    }

    final newAlbumArtwork = albumArtworkUrl ?? this.albumArtworkUrl;
    final newYoutubeThumbnail = youtubeThumbnailUrl ??
        this.youtubeThumbnailUrl ??
        (isYt && (resolvedImage.contains('ytimg.com') || resolvedImage.contains('youtube.com'))
            ? resolvedImage
            : null);

    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      imageUrl: (newAlbumArtwork != null && newAlbumArtwork.isNotEmpty) ? newAlbumArtwork : resolvedImage,
      duration: duration ?? this.duration,
      filePath: filePath ?? localFilePath,
      progress: progress ?? this.progress,
      isPlaying: isPlaying ?? this.isPlaying,
      isFavorited: isFavorited ?? this.isFavorited,
      rawTitle: rawTitle ?? this.rawTitle,
      rawArtist: rawArtist ?? this.rawArtist,
      artistId: artistId ?? this.artistId,
      albumName: albumName ?? this.albumName,
      metadataProvider: metadataProvider ?? this.metadataProvider,
      metadataIdentifier: metadataIdentifier ?? this.metadataIdentifier,
      sourceProvider: sourceProvider ?? this.sourceProvider,
      sourceId: sourceId ?? this.sourceId,
      rawViewCount: rawViewCount ?? this.rawViewCount,
      viewCount: viewCount ?? this.viewCount,
      youtubeThumbnailUrl: newYoutubeThumbnail,
      albumArtworkUrl: newAlbumArtwork,
      embeddedArtworkPath: embeddedArtworkPath ?? this.embeddedArtworkPath,
      resolvedArtworkUrl: resolvedArtworkUrl ?? this.resolvedArtworkUrl ?? newAlbumArtwork,
      artworkSource: artworkSource ?? this.artworkSource,
      artworkMatchConfidence: artworkMatchConfidence ?? this.artworkMatchConfidence,
      mbid: mbid ?? this.mbid,
      recordingMbid: recordingMbid ?? this.recordingMbid,
      releaseMbid: releaseMbid ?? this.releaseMbid,
      artistMbid: artistMbid ?? this.artistMbid,
    );
  }
}
