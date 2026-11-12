import 'package:dio/dio.dart';

import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';

/// Online artwork provider for YouTube Music content.
///
/// Selects the highest-quality valid YouTube thumbnail variant
/// (`maxresdefault` -> `sddefault` -> `hqdefault` -> `mqdefault`) and rejects
/// known broken/placeholder URLs.
class YouTubeFallbackProvider implements ArtworkProvider {
  final Dio? dio;

  const YouTubeFallbackProvider({this.dio});

  @override
  String get id => 'youtube';

  @override
  ArtworkSource get source => ArtworkSource.youtube;

  @override
  bool get isEnabled => true;

  @override
  int get priority => 2;

  /// Builds ranked candidate thumbnail URLs for [query], highest quality first.
  List<String> buildCandidateUrls(ArtworkQuery query) {
    final candidates = <String>[];
    final vid = query.youtubeVideoId ??
        (query.isYoutube ? query.id.replaceFirst('youtube_', '').trim() : null);
    final hasValidVid = vid != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(vid);

    final sanitizedFallback = _sanitizeUrl(query.fallbackThumbnailUrl);
    if (hasValidVid) {
      candidates.add('https://i.ytimg.com/vi/$vid/maxresdefault.jpg');
      candidates.add('https://i.ytimg.com/vi/$vid/sddefault.jpg');
      if (sanitizedFallback != null && !candidates.contains(sanitizedFallback)) {
        candidates.add(sanitizedFallback);
      }
      candidates.add('https://i.ytimg.com/vi/$vid/hqdefault.jpg');
      candidates.add('https://i.ytimg.com/vi/$vid/mqdefault.jpg');
    } else if (sanitizedFallback != null) {
      candidates.add(sanitizedFallback);
    }

    return candidates.toSet().toList();
  }

  static String? _sanitizeUrl(String? raw) {
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

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    final candidates = buildCandidateUrls(query);
    if (candidates.isEmpty) return null;

    if (dio != null) {
      for (final url in candidates) {
        if (await _isUrlReachableImage(url)) {
          return ResolvedArtwork(
            imageUrl: url,
            source: ArtworkSource.youtube,
            confidence: 0.5,
            attribution: 'YouTube Music',
            resolvedAt: DateTime.now(),
          );
        }
      }
      return null;
    }

    // Without an injected Dio client, prefer the sanitized fallback URL (if not low-res default.jpg)
    // or deterministic hqdefault.jpg for the video ID.
    final fallback = _sanitizeUrl(query.fallbackThumbnailUrl);
    final chosen = (fallback != null && !fallback.endsWith('/default.jpg'))
        ? fallback
        : candidates.firstWhere(
            (u) => u.endsWith('/hqdefault.jpg'),
            orElse: () => candidates.first,
          );

    return ResolvedArtwork(
      imageUrl: chosen,
      source: ArtworkSource.youtube,
      confidence: 0.5,
      attribution: 'YouTube Music',
      resolvedAt: DateTime.now(),
    );
  }

  Future<bool> _isUrlReachableImage(String url) async {
    try {
      final resp = await dio!.head<dynamic>(
        url,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (resp.statusCode != 200) return false;
      final contentType = resp.headers.value('content-type')?.toLowerCase() ?? '';
      if (contentType.isNotEmpty && !contentType.startsWith('image/')) {
        return false;
      }
      final lenHeader = resp.headers.value('content-length');
      final len = lenHeader != null ? int.tryParse(lenHeader) : null;
      // YouTube placeholder 404/grey thumbs on maxres/sd are often tiny or 404
      if (len != null && len < 1500 && url.contains('i.ytimg.com/vi/')) {
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
