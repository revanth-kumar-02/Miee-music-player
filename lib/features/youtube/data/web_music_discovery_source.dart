import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../domain/youtube_model.dart';
import '../domain/youtube_metadata_cleaner.dart';

/// Supported, policy-compliant music discovery source for web and fallback environments.
///
/// Direct client-side HTML scraping of YouTube search results is blocked in web browsers
/// due to Same-Origin Policy (CORS) enforcement. This source provides verified, individual
/// songs with accurate metadata (title, artist, album, duration), high-resolution CDN artwork,
/// and playable preview streams with official `Access-Control-Allow-Origin: *` support.
class WebMusicDiscoverySource {
  static final WebMusicDiscoverySource _instance = WebMusicDiscoverySource._internal();
  factory WebMusicDiscoverySource() => _instance;
  WebMusicDiscoverySource._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Accept': 'application/json',
      },
    ),
  );

  /// In-memory cache for discovery searches (bounded to 50 entries)
  final Map<String, List<YouTubeVideo>> _cache = {};
  static const int _maxCacheSize = 50;

  /// Cache for resolved audio preview stream URLs (title+artist -> url)
  final Map<String, String> _streamCache = {};

  /// Searches for verified individual songs matching [query].
  Future<List<YouTubeVideo>> searchVideos(String query, {int limit = 25}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final cacheKey = cleanQuery.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      debugPrint('[WebMusicDiscovery] Cache hit for "$cleanQuery"');
      return _cache[cacheKey]!;
    }

    try {
      debugPrint('[WebMusicDiscovery] Querying supported discovery provider for "$cleanQuery"');
      final response = await _dio.get<dynamic>(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': cleanQuery,
          'entity': 'song',
          'limit': limit,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        throw Exception('Discovery provider returned status ${response.statusCode}');
      }

      final Map<String, dynamic> data;
      if (response.data is String) {
        data = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else {
        data = Map<String, dynamic>.from(response.data as Map);
      }

      final results = data['results'] as List<dynamic>? ?? [];
      final candidateVideos = <YouTubeVideo>[];
      final seenTrackIds = <String>{};

      for (final raw in results) {
        if (raw is! Map) continue;
        final item = Map<String, dynamic>.from(raw);

        // Ensure this is an individual song
        final kind = item['kind'] as String? ?? '';
        if (kind != 'song') continue;

        final trackId = (item['trackId'] ?? '').toString();
        if (trackId.isEmpty || !seenTrackIds.add(trackId)) continue;

        final trackName = item['trackName'] as String? ?? '';
        final artistName = item['artistName'] as String? ?? '';
        if (trackName.isEmpty) continue;

        // Duration formatting from trackTimeMillis
        final millis = item['trackTimeMillis'] as int? ?? 0;
        final totalSeconds = millis ~/ 1000;
        final minutes = totalSeconds ~/ 60;
        final seconds = totalSeconds % 60;
        final durationStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

        // High-resolution artwork: upgrade 100x100 to 600x600
        final art100 = item['artworkUrl100'] as String? ??
            item['artworkUrl60'] as String? ??
            '';
        final highResArt = art100.isNotEmpty
            ? art100.replaceAll('100x100bb', '600x600bb')
            : 'https://i.ytimg.com/vi/placeholder/hqdefault.jpg';

        final previewUrl = item['previewUrl'] as String? ?? '';

        final cleaned = YouTubeMetadataCleaner.clean(
          rawTitle: trackName,
          rawChannel: artistName,
        );

        candidateVideos.add(
          YouTubeVideo(
            id: 'wm_$trackId',
            title: cleaned.title,
            channelTitle: cleaned.artist,
            thumbnailUrl: highResArt,
            duration: durationStr,
            viewCount: 'Verified Song',
            rawTitle: trackName,
            rawChannelTitle: artistName,
            audioStreamUrl: previewUrl.isNotEmpty ? previewUrl : null,
          ),
        );

        // Cache stream URL for title+artist lookup
        if (previewUrl.isNotEmpty) {
          final streamKey = _streamKey(cleaned.title, cleaned.artist);
          _streamCache[streamKey] = previewUrl;
        }
      }

      if (candidateVideos.isNotEmpty) {
        if (_cache.length >= _maxCacheSize) {
          _cache.remove(_cache.keys.first);
        }
        _cache[cacheKey] = candidateVideos;
      }

      debugPrint('[WebMusicDiscovery] Discovered ${candidateVideos.length} genuine songs for "$cleanQuery"');
      return candidateVideos;
    } catch (e) {
      debugPrint('[WebMusicDiscovery] Error querying provider: $e');
      rethrow;
    }
  }

  /// Resolves an audio stream URL for a song by [title] and [artist].
  Future<String?> resolveStreamForTrack(String title, String artist) async {
    final streamKey = _streamKey(title, artist);
    if (_streamCache.containsKey(streamKey)) {
      return _streamCache[streamKey];
    }

    try {
      final query = '$title $artist'.trim();
      final videos = await searchVideos(query, limit: 5);
      if (videos.isNotEmpty) {
        for (final v in videos) {
          if (v.audioStreamUrl != null && v.audioStreamUrl!.isNotEmpty) {
            _streamCache[streamKey] = v.audioStreamUrl!;
            return v.audioStreamUrl;
          }
        }
      }
    } catch (e) {
      debugPrint('[WebMusicDiscovery] Stream resolution fallback failed for "$title": $e');
    }
    return null;
  }

  String _streamKey(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
}
