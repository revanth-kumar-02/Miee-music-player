import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../domain/youtube_model.dart';
import '../domain/youtube_metadata_cleaner.dart';
import '../domain/music_result_classifier.dart';
import '../../../core/audio/youtube_audio_service.dart';

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
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
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
      return await _fetchFromProvider(cleanQuery, limit: limit, cacheKey: cacheKey);
    } catch (e) {
      debugPrint('[WebMusicDiscovery] First attempt failed ($e), retrying once...');
      try {
        return await _fetchFromProvider(cleanQuery, limit: limit, cacheKey: cacheKey);
      } catch (e2) {
        debugPrint('[WebMusicDiscovery] Retry also failed: $e2');
        rethrow;
      }
    }
  }

  Future<List<YouTubeVideo>> _fetchFromProvider(
    String cleanQuery, {
    required int limit,
    required String cacheKey,
  }) async {
    try {
      Response<dynamic>? response;
      // 1. Direct verified discovery catalog (iTunes) - pristine studio artists, tracks, and 600x600 covers
      try {
        debugPrint('[WebMusicDiscovery] Querying direct discovery provider for "$cleanQuery"');
        response = await _dio.get<dynamic>(
          'https://itunes.apple.com/search',
          queryParameters: {
            'term': cleanQuery,
            'entity': 'song',
            'limit': limit,
          },
        );
      } catch (e) {
        debugPrint('[WebMusicDiscovery] Direct discovery provider failed ($e), checking local proxy');
      }

      // Check if direct catalog returned valid song results
      bool hasValidResults = false;
      if (response != null && response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> checkData;
        if (response.data is String) {
          checkData = jsonDecode(response.data as String) as Map<String, dynamic>;
        } else {
          checkData = Map<String, dynamic>.from(response.data as Map);
        }
        final list = checkData['results'] as List<dynamic>? ?? [];
        if (list.isNotEmpty) {
          hasValidResults = true;
        }
      }

      // 2. If direct catalog has no results or failed, query local/proxy backend
      if (!hasValidResults && kIsWeb) {
        try {
          debugPrint('[WebMusicDiscovery] Querying local/proxy API for "$cleanQuery"');
          final proxyResp = await _dio.get<dynamic>(
            '/api/search',
            queryParameters: {'q': cleanQuery},
          );
          if (proxyResp.statusCode == 200 && proxyResp.data != null) {
            response = proxyResp;
          }
        } catch (e) {
          debugPrint('[WebMusicDiscovery] Proxy request failed: $e');
        }
      }

      if (response == null || response.statusCode != 200 || response.data == null) {
        throw Exception('Discovery provider returned status ${response?.statusCode}');
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

        // 1. YouTube format (from local proxy/backend)
        if (item.containsKey('id') && item.containsKey('title') && item['kind'] != 'song') {
          final videoId = (item['id'] ?? '').toString();
          if (videoId.isEmpty || !seenTrackIds.add(videoId)) continue;

          final title = item['title'] as String? ?? '';
          final artist = item['artist'] as String? ?? '';
          final durationStr = item['duration'] as String? ?? '3:30';
          final thumb = item['thumbnailUrl'] as String? ??
              'https://img.youtube.com/vi/$videoId/hqdefault.jpg';

          final cleaned = YouTubeMetadataCleaner.clean(
            rawTitle: title,
            rawChannel: artist,
          );

          final candidate = YouTubeVideo(
            id: videoId,
            title: cleaned.title,
            channelTitle: cleaned.artist,
            thumbnailUrl: thumb,
            duration: durationStr,
            viewCount: 'Verified Song',
            rawTitle: title,
            rawChannelTitle: artist,
            audioStreamUrl: null, // Full audio stream resolved on demand
          );

          if (MusicResultClassifier.isValidMusicTrack(candidate, query: cleanQuery)) {
            candidateVideos.add(candidate);
          }
          continue;
        }

        // 2. iTunes catalog fallback (metadata only - DO NOT use 30s previewUrl as audioStreamUrl)
        final kind = item['kind'] as String? ?? '';
        if (kind != 'song') continue;

        final trackId = (item['trackId'] ?? '').toString();
        if (trackId.isEmpty || !seenTrackIds.add(trackId)) continue;

        final trackName = item['trackName'] as String? ?? '';
        final artistName = item['artistName'] as String? ?? '';
        if (trackName.isEmpty) continue;

        final millis = item['trackTimeMillis'] as int? ?? 0;
        final totalSeconds = millis ~/ 1000;
        final minutes = totalSeconds ~/ 60;
        final seconds = totalSeconds % 60;
        final durationStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

        final art100 = item['artworkUrl100'] as String? ??
            item['artworkUrl60'] as String? ??
            '';
        final highResArt = art100.isNotEmpty
            ? art100.replaceAll('100x100bb', '600x600bb')
            : 'https://i.ytimg.com/vi/placeholder/hqdefault.jpg';

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
            audioStreamUrl: null, // Never assign 30s previewUrl as audioStreamUrl
          ),
        );
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

  /// Resolves a full audio stream URL for a song by [title] and [artist].
  /// Never returns a 30-second preview clip for full song playback.
  Future<String?> resolveStreamForTrack(String title, String artist) async {
    final streamKey = _streamKey(title, artist);
    if (_streamCache.containsKey(streamKey)) {
      return _streamCache[streamKey];
    }

    try {
      final query = '$title $artist'.trim();
      final videoId = await YouTubeAudioService().resolveVideoIdForQuery(query);
      if (videoId != null && videoId.isNotEmpty) {
        final fullStreamUrl = await YouTubeAudioService().getAudioStreamUrl(videoId);
        if (fullStreamUrl != null && fullStreamUrl.isNotEmpty) {
          _streamCache[streamKey] = fullStreamUrl;
          return fullStreamUrl;
        }
      }
    } catch (e) {
      debugPrint('[WebMusicDiscovery] Full stream resolution failed for "$title": $e');
    }
    return null;
  }

  String _streamKey(String title, String artist) =>
      '${title.trim().toLowerCase()}|${artist.trim().toLowerCase()}';
}
