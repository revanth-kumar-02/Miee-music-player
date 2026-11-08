import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../media/domain/models.dart';
import '../../youtube/domain/youtube_model.dart';

/// Normalized query representation passed to the Artwork Resolution System.
class ArtworkQuery {
  /// Unique identifier of the music entity (track id, youtube id, local song id).
  final String id;

  /// Cleaned or raw title of the track.
  final String title;

  /// Primary artist name.
  final String artist;

  /// Album name if known.
  final String? album;

  /// International Standard Recording Code (ISRC) if available.
  final String? isrc;

  /// Track duration in milliseconds (for fuzzy candidate duration checks).
  final int? durationMs;

  /// Audio file path on disk (for local tracks).
  final String? localFilePath;

  /// Cached or extracted artwork file path on disk (for local tracks).
  final String? localArtworkPath;

  /// Original stream thumbnail URL (e.g. YouTube thumbnail) as last-resort fallback.
  final String? fallbackThumbnailUrl;

  const ArtworkQuery({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.isrc,
    this.durationMs,
    this.localFilePath,
    this.localArtworkPath,
    this.fallbackThumbnailUrl,
  });

  /// Factory constructor to construct an [ArtworkQuery] seamlessly from any [MusicItem].
  factory ArtworkQuery.fromMusicItem(MusicItem item, {String? album}) {
    if (item is MediaSong) {
      return ArtworkQuery(
        id: item.id,
        title: item.title,
        artist: item.artist,
        album: album ?? item.album,
        durationMs: item.durationMs,
        localFilePath: item.filePath,
        localArtworkPath: item.artworkPath,
        fallbackThumbnailUrl: null,
      );
    }

    if (item is YouTubeVideo) {
      return ArtworkQuery(
        id: item.id,
        title: item.title,
        artist: item.channelTitle,
        album: album,
        durationMs: null,
        localFilePath: null,
        localArtworkPath: null,
        fallbackThumbnailUrl: item.thumbnailUrl,
      );
    }

    if (item is Track) {
      return ArtworkQuery(
        id: item.id,
        title: item.rawTitle ?? item.title,
        artist: item.rawArtist ?? item.artist,
        album: album,
        durationMs: null,
        localFilePath: item.localFilePath,
        localArtworkPath: (item.localFilePath != null && !item.isYoutube) ? item.imageUrl : null,
        fallbackThumbnailUrl: item.imageUrl.isNotEmpty ? item.imageUrl : null,
      );
    }

    // Generic fallback for any other MusicItem implementation
    return ArtworkQuery(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: album,
      localFilePath: item.isYoutube ? null : item.filePath,
      fallbackThumbnailUrl: item.imageUrl.isNotEmpty ? item.imageUrl : null,
    );
  }

  /// Normalized deterministic key used for caching and in-flight deduplication.
  String get cacheKey {
    if (isrc != null && isrc!.trim().isNotEmpty) {
      return 'isrc_${isrc!.trim().toUpperCase()}';
    }

    final normArtist = _normalize(artist);
    final normTitle = _normalize(title);
    final normAlbum = album != null ? _normalize(album!) : '';

    if (normArtist.isNotEmpty && normTitle.isNotEmpty) {
      if (normAlbum.isNotEmpty) {
        return '${normArtist}_${normTitle}_$normAlbum';
      }
      return '${normArtist}_$normTitle';
    }

    return 'id_$id';
  }

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), '') // remove parenthesized content
        .replaceAll(RegExp(r'\[[^\]]*\]'), '') // remove bracketed content
        .replaceAll(RegExp(r'(\b[a-z])\.\s*'), r'$1') // collapse initials: 'a. r.' -> 'ar ', 'a.r.' -> 'ar'
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '') // remove remaining punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // collapse whitespace
        .trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArtworkQuery &&
          runtimeType == other.runtimeType &&
          cacheKey == other.cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'ArtworkQuery(title: "$title", artist: "$artist", album: "$album")';
}

