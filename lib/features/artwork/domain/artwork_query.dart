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

  /// Source of the music track ('youtube', 'local', etc.).
  final String? source;

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
    this.source,
  });

  /// Whether this query is for an online YouTube / streaming track.
  bool get isYoutube {
    if (source == 'youtube') return true;
    if (id.startsWith('youtube_') || id.startsWith('wm_')) return true;
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) return true;
    if (fallbackThumbnailUrl != null) {
      final u = fallbackThumbnailUrl!.toLowerCase();
      if (u.contains('ytimg.com') || u.contains('youtube.com')) return true;
    }
    return false;
  }

  /// Extracts the 11-character YouTube video ID if available.
  String? get youtubeVideoId {
    if (id.startsWith('youtube_')) {
      final clean = id.replaceFirst('youtube_', '').trim();
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) return clean;
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
      return id;
    }
    if (fallbackThumbnailUrl != null) {
      final match = RegExp(r'\/vi\/([a-zA-Z0-9_-]{11})\/').firstMatch(fallbackThumbnailUrl!);
      if (match != null) return match.group(1);
    }
    return null;
  }

  /// Sanitizes a candidate fallback thumbnail URL, rejecting bogus placeholders.
  static String? _sanitizeFallbackUrl(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    if (lower.contains('/vi/placeholder/')) return null;
    if (lower.startsWith('http://img.youtube.com/') ||
        lower.startsWith('https://img.youtube.com/')) {
      return trimmed
          .replaceFirst(RegExp(r'^http://img\.youtube\.com/', caseSensitive: false), 'https://i.ytimg.com/')
          .replaceFirst(RegExp(r'^https://img\.youtube\.com/', caseSensitive: false), 'https://i.ytimg.com/');
    }
    if (lower.startsWith('http://i.ytimg.com/')) {
      return trimmed.replaceFirst(RegExp(r'^http://', caseSensitive: false), 'https://');
    }
    return trimmed;
  }

  /// Factory constructor to construct an [ArtworkQuery] seamlessly from any [MusicItem].
  factory ArtworkQuery.fromMusicItem(MusicItem item, {String? album, String? explicitUrl}) {
    final cleanExplicit = _sanitizeFallbackUrl(explicitUrl);
    if (item is MediaSong) {
      return ArtworkQuery(
        id: item.id,
        title: item.title,
        artist: item.artist,
        album: album ?? item.album,
        durationMs: item.durationMs,
        localFilePath: item.filePath,
        localArtworkPath: item.artworkPath,
        fallbackThumbnailUrl: cleanExplicit,
        source: 'local',
      );
    }

    if (item is YouTubeVideo) {
      String? fallback = cleanExplicit ??
          _sanitizeFallbackUrl(item.highResArtworkUrl) ??
          _sanitizeFallbackUrl(item.thumbnailUrl);
      if (fallback == null || fallback.isEmpty) {
        fallback = 'https://i.ytimg.com/vi/${item.id}/hqdefault.jpg';
      }
      return ArtworkQuery(
        id: item.id,
        title: item.canonicalTitle ?? item.title,
        artist: item.canonicalArtist ?? item.channelTitle,
        album: album ?? item.albumName,
        durationMs: _parseDurationString(item.duration),
        localFilePath: null,
        localArtworkPath: null,
        fallbackThumbnailUrl: fallback,
        source: 'youtube',
      );
    }

    if (item is Track) {
      final isYt = item.isYoutube;
      String? fallback = cleanExplicit ?? _sanitizeFallbackUrl(item.imageUrl);

      if (isYt && (fallback == null || fallback.isEmpty || !fallback.startsWith('http'))) {
        final vid = (item.sourceId ?? item.id).replaceFirst('youtube_', '').trim();
        if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(vid)) {
          fallback = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
        }
      }

      return ArtworkQuery(
        id: item.id,
        title: item.title,
        artist: item.artist,
        album: album ?? item.albumName,
        durationMs: _parseDurationString(item.duration),
        localFilePath: item.localFilePath,
        localArtworkPath: (item.localFilePath != null && !isYt) ? item.imageUrl : null,
        fallbackThumbnailUrl: fallback,
        source: isYt ? 'youtube' : 'local',
      );
    }

    // Generic fallback for any other MusicItem implementation
    final isYt = item.isYoutube;
    String? fallback = cleanExplicit ?? _sanitizeFallbackUrl(item.imageUrl);
    if (isYt && (fallback == null || fallback.isEmpty)) {
      final vid = item.id.replaceFirst('youtube_', '').trim();
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(vid)) {
        fallback = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
      }
    }

    return ArtworkQuery(
      id: item.id,
      title: item.title,
      artist: item.artist,
      album: album,
      localFilePath: isYt ? null : item.filePath,
      fallbackThumbnailUrl: fallback,
      source: isYt ? 'youtube' : 'local',
    );
  }

  /// Normalized deterministic key used for caching and in-flight deduplication.
  /// Uses stable, source-specific identifiers to prevent cross-source or cross-track pollution.
  String get cacheKey {
    if (isrc != null && isrc!.trim().isNotEmpty) {
      return 'isrc_${isrc!.trim().toUpperCase()}';
    }

    final normArtist = _normalize(artist);
    final normTitle = _normalize(title);
    final normAlbum = album != null ? _normalize(album!) : '';

    if (isYoutube) {
      final vid = youtubeVideoId ?? id.replaceFirst('youtube_', '').trim();
      if (vid.isNotEmpty) {
        return 'yt_${vid}_${normArtist}_$normTitle';
      }
      return 'yt_${normArtist}_$normTitle';
    }

    if (localArtworkPath != null && localArtworkPath!.isNotEmpty) {
      return 'loc_${id}_${normArtist}_$normTitle';
    }

    if (localFilePath != null && localFilePath!.isNotEmpty) {
      return 'loc_${id}_${normArtist}_$normTitle';
    }

    if (normArtist.isNotEmpty && normTitle.isNotEmpty) {
      if (normAlbum.isNotEmpty) {
        return 'track_${normArtist}_${normTitle}_$normAlbum';
      }
      return 'track_${normArtist}_$normTitle';
    }

    return 'id_$id';
  }

  static String _normalize(String input) {
    return input
        .toLowerCase()
        .replaceAll(RegExp(r'\([^)]*\)'), '') // remove parenthesized content
        .replaceAll(RegExp(r'\[[^\]]*\]'), '') // remove bracketed content
        .replaceAllMapped(
          RegExp(r'\b([a-z])\.\s*([a-z])\.\s*'),
          (m) => '${m[1]}${m[2]} ',
        ) // collapse paired initials: 'a. r.' -> 'ar '
        .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), '') // preserve Unicode letters, marks & digits
        .replaceAll(RegExp(r'\s+'), ' ') // collapse whitespace
        .trim();
  }

  static int? _parseDurationString(String? duration) {
    if (duration == null || duration.trim().isEmpty) return null;
    final parts = duration.trim().split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return ((mins * 60) + secs) * 1000;
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]) ?? 0;
      final mins = int.tryParse(parts[1]) ?? 0;
      final secs = int.tryParse(parts[2]) ?? 0;
      return ((hrs * 3600) + (mins * 60) + secs) * 1000;
    }
    return null;
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
  String toString() => 'ArtworkQuery(id: "$id", title: "$title", artist: "$artist", isYoutube: $isYoutube)';
}
