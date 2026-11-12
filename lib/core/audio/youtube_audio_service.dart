import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../features/youtube/domain/youtube_model.dart';
import '../../features/youtube/domain/music_result_classifier.dart';
import 'playback_diagnostics.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Client Constants
// ─────────────────────────────────────────────────────────────────────────────

/// The Apple Vision Pro client definition (based on InterTune / yt-dlp).
/// Exempt from YouTube's GVS proof-of-origin (PoToken) token requirements,
/// avoiding the ~1MB cap and HTTP 403 response on media playback.
const String kYouTubeVisionOsUserAgent =
    'com.google.ios.youtube/1.02 (RealityDevice17,1; U; visionOS 2_3)';

const YoutubeApiClient kVisionOsClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'userAgent': kYouTubeVisionOsUserAgent,
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
      'osName': 'visionOS',
      'osVersion': '2.3.21O5565d',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
    },
  },
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

/// The Android client version used for `androidSdkless` requests (fallback).
const String kYouTubeAndroidClientVersion = '20.10.38';

/// The Android user-agent header matching [kYouTubeAndroidClientVersion].
const String kYouTubeAndroidUserAgent =
    'com.google.android.youtube/$kYouTubeAndroidClientVersion (Linux; U; Android 11) gzip';

/// Based on yt-dlp's `android_sdkless` client definition.
const YoutubeApiClient kAndroidSdklessClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'ANDROID',
      'clientVersion': kYouTubeAndroidClientVersion,
      'userAgent': kYouTubeAndroidUserAgent,
      'hl': 'en',
      'timeZone': 'UTC',
      'utcOffsetMinutes': 0,
      'osName': 'Android',
      'osVersion': '11',
    },
  },
}, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

// ─────────────────────────────────────────────────────────────────────────────
// Resolved stream & cache entry
// ─────────────────────────────────────────────────────────────────────────────

/// Represents a resolved YouTube audio stream alongside the exact client identity
/// and `User-Agent` header required when fetching media bytes from `googlevideo.com`.
class ResolvedYouTubeStream {
  final String url;
  final String userAgent;
  final String clientName;

  const ResolvedYouTubeStream({
    required this.url,
    required this.userAgent,
    required this.clientName,
  });

  Map<String, String> get headers => {'User-Agent': userAgent};
}

class _CachedStream {
  final String url;
  final String userAgent;
  final String clientName;
  final DateTime expiresAt;
  const _CachedStream({
    required this.url,
    required this.userAgent,
    required this.clientName,
    required this.expiresAt,
  });
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  ResolvedYouTubeStream toResolved() => ResolvedYouTubeStream(
        url: url,
        userAgent: userAgent,
        clientName: clientName,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTubeAudioService
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves direct audio-only stream URLs for YouTube video IDs using `youtube_explode_dart`
/// with the `VISIONOS` client as primary resolver.
///
/// Guarantees:
///   • Fast resolution (~1-2 seconds on cache miss, <1ms on cache hit).
///   • Audio-only streams preferred (AAC/M4A).
///   • In-memory stream URL cache bounded with safe expiration.
///   • Concurrent calls for the same video ID are deduplicated.
///   • Bounded per-attempt timeouts to prevent indefinite hanging.
class YouTubeAudioService {
  static final YouTubeAudioService _instance = YouTubeAudioService._internal();
  factory YouTubeAudioService() => _instance;
  YouTubeAudioService._internal();

  static const int _maxCacheSize = 100;
  static const Duration _cacheTtl = Duration(hours: 1);

  // ── Cache & in-flight deduplication ───────────────────────────────────────
  final Map<String, _CachedStream> _urlCache = {};
  final Map<String, Future<ResolvedYouTubeStream?>> _inFlight = {};
  final Map<String, YouTubeVideo> _queryCandidateCache = {};

  // ── youtube_explode_dart client ───────────────────────────────────────────
  YoutubeExplode _yt = YoutubeExplode();

  @visibleForTesting
  Future<StreamManifest?> Function(
    String videoId,
    List<YoutubeApiClient>? ytClients,
  )? manifestFetcherForTesting;

  @visibleForTesting
  Future<bool> Function(String url, String userAgent)?
      fallbackReadabilityValidatorForTesting;

  @visibleForTesting
  void resetTestingHooks() {
    manifestFetcherForTesting = null;
    fallbackReadabilityValidatorForTesting = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Checks if a valid, unexpired stream URL is currently cached for [videoIdOrUrl].
  bool isCached(String videoIdOrUrl) {
    final videoId = _extractVideoId(videoIdOrUrl);
    if (videoId == null) return false;
    final cached = _urlCache[videoId];
    return cached != null && !cached.isExpired && isUrlValid(cached.url);
  }

  @visibleForTesting
  void cacheUrlForTesting(
    String videoId,
    String url, {
    String userAgent = kYouTubeVisionOsUserAgent,
    String clientName = 'VISIONOS',
  }) =>
      _cacheUrl(videoId, url, userAgent: userAgent, clientName: clientName);

  /// Infers the appropriate `User-Agent` when only a raw stream URL is available.
  static String inferUserAgentForUrl(String url) {
    final uri = Uri.tryParse(url);
    final client = uri?.queryParameters['c']?.toUpperCase();
    if (client == 'ANDROID') {
      return kYouTubeAndroidUserAgent;
    }
    return kYouTubeVisionOsUserAgent;
  }

  /// Resolves an audio-only stream together with its matching `User-Agent`.
  ///
  /// Serves from cache if valid; deduplicates concurrent calls for the same ID.
  /// Pass [forceRefresh]=true to bypass cache (e.g. after a playback error).
  Future<ResolvedYouTubeStream?> getAudioStream(
    String videoIdOrUrl, {
    bool forceRefresh = false,
    String? title,
    String? artist,
  }) {
    final videoId = _extractVideoId(videoIdOrUrl);
    if (videoId == null || videoId.isEmpty) {
      debugPrint('[YouTubeAudioService] Invalid video ID: "$videoIdOrUrl"');
      return Future.value(null);
    }

    // Serve valid cache entry unless caller forces refresh
    if (!forceRefresh && _urlCache.containsKey(videoId)) {
      final cached = _urlCache[videoId]!;
      if (!cached.isExpired && isUrlValid(cached.url)) {
        debugPrint('[StreamCache] HIT for $videoId (client=${cached.clientName})');
        PlaybackDiagnostics().recordStreamResolutionEnd(
          videoId,
          fromCache: true,
          success: true,
        );
        return Future.value(cached.toResolved());
      }
      debugPrint('[StreamCache] EXPIRED for $videoId, evicting');
      _urlCache.remove(videoId);
    }

    // Deduplicate concurrent in-flight resolution calls
    if (_inFlight.containsKey(videoId)) {
      debugPrint('[YouTubeAudioService] In-flight dedup for $videoId');
      return _inFlight[videoId]!;
    }

    final future = _resolveStream(videoId, title: title, artist: artist).timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        debugPrint('[YouTubeAudioService] Overall stream resolution timed out for $videoId');
        return null;
      },
    ).then((resolved) {
      PlaybackDiagnostics().recordStreamResolutionEnd(
        videoId,
        fromCache: false,
        success: resolved != null && resolved.url.isNotEmpty,
      );
      return resolved;
    }).whenComplete(() {
      _inFlight.remove(videoId);
    });

    _inFlight[videoId] = future;
    return future;
  }

  /// Returns an audio-only stream URL for [videoIdOrUrl].
  ///
  /// Kept for backward compatibility; prefer [getAudioStream] to preserve client
  /// `User-Agent` matching on fallback streams.
  Future<String?> getAudioStreamUrl(
    String videoIdOrUrl, {
    bool forceRefresh = false,
    String? title,
    String? artist,
  }) async {
    final resolved = await getAudioStream(
      videoIdOrUrl,
      forceRefresh: forceRefresh,
      title: title,
      artist: artist,
    );
    return resolved?.url;
  }

  /// Predictively preheats and caches the stream URL for [videoIdOrUrl] in the background.
  ///
  /// Safe to call concurrently; silently catches any errors so current playback is unaffected.
  Future<void> prefetchStreamUrl(String videoIdOrUrl) async {
    final videoId = _extractVideoId(videoIdOrUrl);
    if (videoId == null || videoId.isEmpty) return;
    if (isCached(videoId) || _inFlight.containsKey(videoId)) return;

    try {
      debugPrint('[StreamCache] Predictive prefetch started for next track: $videoId');
      await getAudioStreamUrl(videoId);
    } catch (e) {
      debugPrint('[StreamCache] Predictive prefetch error for $videoId (ignored): $e');
    }
  }

  /// Returns true if [url] is non-empty, parseable, and not past its `expire` param.
  bool isUrlValid(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) return false;
      final exp = uri.queryParameters['expire'];
      if (exp != null) {
        final secs = int.tryParse(exp);
        if (secs != null) {
          return DateTime.now()
              .isBefore(DateTime.fromMillisecondsSinceEpoch(secs * 1000));
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Evicts [videoIdOrUrl] from the URL cache.
  void invalidateCache(String videoIdOrUrl) {
    final videoId = _extractVideoId(videoIdOrUrl);
    if (videoId != null && _urlCache.containsKey(videoId)) {
      _urlCache.remove(videoId);
      debugPrint('[StreamCache] INVALIDATED $videoId');
    }
  }

  void clearCache() {
    _urlCache.clear();
    _queryCandidateCache.clear();
    debugPrint('[StreamCache] Cache cleared');
  }

  void _cacheCandidate(String cacheKey, YouTubeVideo candidate) {
    if (!_queryCandidateCache.containsKey(cacheKey) &&
        _queryCandidateCache.length >= _maxCacheSize) {
      final oldestKey = _queryCandidateCache.keys.first;
      _queryCandidateCache.remove(oldestKey);
    }
    _queryCandidateCache[cacheKey] = candidate;
  }

  void dispose() {
    _yt.close();
    _yt = YoutubeExplode();
    debugPrint('[YouTubeAudioService] Disposed');
  }

  @visibleForTesting
  void injectCachedCandidate(String query, YouTubeVideo candidate) {
    final cleanQuery = query.trim().toLowerCase();
    _cacheCandidate(cleanQuery, candidate);
  }

  @visibleForTesting
  YouTubeVideo? getCachedCandidateForTesting(String query) =>
      _queryCandidateCache[query.trim().toLowerCase()];

  @visibleForTesting
  int get cachedCandidateCountForTesting => _queryCandidateCache.length;

  /// Resolves a full verified [YouTubeVideo] candidate for a track [query] (e.g. "West Coast Lana Del Rey").
  Future<YouTubeVideo?> resolveCandidateForQuery(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;
    final cacheKey = cleanQuery.toLowerCase();
    if (_queryCandidateCache.containsKey(cacheKey)) {
      debugPrint('[YouTubeAudioService] Query candidate cache HIT for "$cleanQuery" -> ${_queryCandidateCache[cacheKey]!.id}');
      return _queryCandidateCache[cacheKey];
    }

    if (kIsWeb) {
      final webProxies = [
        'http://127.0.0.1:8089',
        if (Uri.base.host.isNotEmpty && Uri.base.host != '127.0.0.1') 'http://${Uri.base.host}:8089',
        '',
      ];
      for (final baseUrl in webProxies) {
        try {
          final dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 6),
            receiveTimeout: const Duration(seconds: 6),
          ));
          final res = await dio.get<dynamic>(
            '$baseUrl/api/yt/search',
            queryParameters: {'q': cleanQuery, 'limit': 5},
          );
          if (res.statusCode == 200 && res.data != null) {
            final data = res.data is String
                ? jsonDecode(res.data as String) as Map<String, dynamic>
                : Map<String, dynamic>.from(res.data as Map);
            final list = data['results'] as List<dynamic>? ?? [];
            final candidates = <YouTubeVideo>[];
            for (final raw in list) {
              if (raw is Map) {
                final id = (raw['id'] ?? '').toString();
                final title = (raw['title'] ?? '').toString();
                final artist = (raw['artist'] ?? '').toString();
                if (id.isNotEmpty && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(id)) {
                  final candidate = YouTubeVideo(
                    id: id,
                    title: title,
                    channelTitle: artist,
                    thumbnailUrl: '',
                    duration: '3:30',
                    viewCount: '',
                    rawTitle: title,
                    rawChannelTitle: artist,
                  );
                  candidates.add(candidate);
                  if (MusicResultClassifier.isValidIndividualSong(candidate, query: cleanQuery)) {
                    debugPrint('[YouTubeAudioService] Resolved valid video ID "$id" for query "$cleanQuery" via web proxy ($baseUrl)');
                    _cacheCandidate(cacheKey, candidate);
                    return candidate;
                  }
                }
              }
            }
            debugPrint('[YouTubeAudioService] No valid music tracks found for query "$cleanQuery" among ${candidates.length} web proxy candidates');
          }
        } catch (e) {
          debugPrint('[YouTubeAudioService] Web proxy query search failed at $baseUrl for "$cleanQuery": $e');
        }
      }
    } else {
      try {
        final results = await _yt.search.search(cleanQuery);
        final candidates = <YouTubeVideo>[];
        for (final video in results) {
          final candidate = YouTubeVideo(
            id: video.id.value,
            title: video.title,
            channelTitle: video.author,
            thumbnailUrl: video.thumbnails.highResUrl,
            duration: video.duration != null
                ? '${video.duration!.inMinutes}:${(video.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
                : '3:30',
            viewCount: '',
            rawTitle: video.title,
            rawChannelTitle: video.author,
          );
          candidates.add(candidate);
          if (MusicResultClassifier.isValidIndividualSong(candidate, query: cleanQuery)) {
            final id = video.id.value;
            debugPrint('[YouTubeAudioService] Resolved valid music video ID "$id" for query "$cleanQuery" via YoutubeExplode');
            _cacheCandidate(cacheKey, candidate);
            return candidate;
          }
        }
        debugPrint('[YouTubeAudioService] No valid music tracks found for query "$cleanQuery" among ${candidates.length} candidates');
      } catch (e) {
        debugPrint('[YouTubeAudioService] Native query search failed for "$cleanQuery": $e');
      }
    }
    return null;
  }

  /// Resolves a YouTube video ID for a track [query] (e.g. "West Coast Lana Del Rey").
  Future<String?> resolveVideoIdForQuery(String query) async {
    final candidate = await resolveCandidateForQuery(query);
    return candidate?.id;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core stream resolution
  // ─────────────────────────────────────────────────────────────────────────

  Future<StreamManifest?> _fetchManifest(
    String videoId,
    List<YoutubeApiClient>? ytClients,
    Duration timeout,
  ) async {
    if (manifestFetcherForTesting != null) {
      return manifestFetcherForTesting!(videoId, ytClients).timeout(timeout);
    }
    return _yt.videos.streamsClient
        .getManifest(videoId, ytClients: ytClients)
        .timeout(timeout);
  }

  Future<bool> _validateFallbackStreamUrl(
    String url, {
    required String userAgent,
    required String clientName,
  }) async {
    if (!isUrlValid(url)) return false;
    if (fallbackReadabilityValidatorForTesting != null) {
      return fallbackReadabilityValidatorForTesting!(url, userAgent);
    }
    if (kIsWeb) return true;
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
        followRedirects: false,
        validateStatus: (_) => true,
      ));
      var currentUrl = url;
      for (var hop = 0; hop < 5; hop++) {
        final res = await dio.get<ResponseBody>(
          currentUrl,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'User-Agent': userAgent,
              'Range': 'bytes=0-1023',
            },
          ),
        );
        final status = res.statusCode ?? 0;
        final location = res.headers.value('location');
        await res.data?.stream
            .listen((_) {}, onError: (_) {}, cancelOnError: true)
            .cancel();
        if ((status == 301 ||
                status == 302 ||
                status == 303 ||
                status == 307 ||
                status == 308) &&
            location != null &&
            location.isNotEmpty) {
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
          continue;
        }
        if (status == 403 || status == 410 || status < 200 || status >= 400) {
          debugPrint(
            '[YouTubeAudioService] Rejected $clientName fallback stream: HTTP $status',
          );
          return false;
        }
        return status == 200 || status == 206;
      }
      debugPrint(
        '[YouTubeAudioService] Rejected $clientName fallback stream: too many redirects',
      );
      return false;
    } catch (e) {
      debugPrint(
        '[YouTubeAudioService] $clientName fallback readability check failed: $e',
      );
      return false;
    }
  }

  Future<ResolvedYouTubeStream?> _resolveStream(
    String videoId, {
    String? title,
    String? artist,
  }) async {
    debugPrint('[YouTubeAudioService] Resolving audio stream for $videoId (title: $title)');

    // Web environment: resolve via dedicated backend proxy to bypass browser CORS restrictions
    if (kIsWeb) {
      final webProxies = [
        'http://127.0.0.1:8089',
        if (Uri.base.host.isNotEmpty && Uri.base.host != '127.0.0.1') 'http://${Uri.base.host}:8089',
        '',
      ];
      for (final baseUrl in webProxies) {
        try {
          final dio = Dio(BaseOptions(
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
          ));
          final res = await dio.get<dynamic>(
            '$baseUrl/api/yt/resolve',
            queryParameters: {
              'id': videoId,
              if (title != null && title.isNotEmpty) 'title': title,
              if (artist != null && artist.isNotEmpty) 'artist': artist,
            },
          );
          if (res.statusCode == 200 && res.data != null) {
            final data = res.data is String
                ? jsonDecode(res.data as String) as Map<String, dynamic>
                : Map<String, dynamic>.from(res.data as Map);
            final streamUrl = data['streamUrl'] as String?;
            if (streamUrl != null && streamUrl.isNotEmpty) {
              final ua = inferUserAgentForUrl(streamUrl);
              debugPrint('[YouTubeAudioService] Resolved stream via web proxy ($baseUrl) for $videoId');
              _cacheUrl(videoId, streamUrl, userAgent: ua, clientName: 'WEB_PROXY');
              return ResolvedYouTubeStream(
                url: streamUrl,
                userAgent: ua,
                clientName: 'WEB_PROXY',
              );
            }
          }
        } catch (e) {
          debugPrint('[YouTubeAudioService] Web stream proxy resolution failed at $baseUrl for $videoId: $e');
        }
      }
    }

    // Primary attempt: VISIONOS client (exempt from GVS PoToken 1MB cap / 403 errors)
    try {
      final manifest = await _fetchManifest(
        videoId,
        [kVisionOsClient],
        const Duration(seconds: 12),
      );
      final streamUrl = manifest != null ? _selectBestAudioUrl(manifest) : null;
      if (streamUrl != null && streamUrl.isNotEmpty) {
        debugPrint('[YouTubeAudioService] Resolved stream via VISIONOS for $videoId');
        _cacheUrl(
          videoId,
          streamUrl,
          userAgent: kYouTubeVisionOsUserAgent,
          clientName: 'VISIONOS',
        );
        return ResolvedYouTubeStream(
          url: streamUrl,
          userAgent: kYouTubeVisionOsUserAgent,
          clientName: 'VISIONOS',
        );
      }
    } catch (e) {
      debugPrint('[YouTubeAudioService] VISIONOS attempt failed for $videoId: $e');
    }

    // Fallback attempt 1: androidSdkless client (must pass byte-range readability check)
    try {
      final manifest = await _fetchManifest(
        videoId,
        [kAndroidSdklessClient],
        const Duration(seconds: 7),
      );
      final streamUrl = manifest != null ? _selectBestAudioUrl(manifest) : null;
      if (streamUrl != null && streamUrl.isNotEmpty) {
        final readable = await _validateFallbackStreamUrl(
          streamUrl,
          userAgent: kYouTubeAndroidUserAgent,
          clientName: 'ANDROID_SDKLESS',
        );
        if (readable) {
          debugPrint('[YouTubeAudioService] Resolved readable stream via androidSdkless for $videoId');
          _cacheUrl(
            videoId,
            streamUrl,
            userAgent: kYouTubeAndroidUserAgent,
            clientName: 'ANDROID_SDKLESS',
          );
          return ResolvedYouTubeStream(
            url: streamUrl,
            userAgent: kYouTubeAndroidUserAgent,
            clientName: 'ANDROID_SDKLESS',
          );
        }
      }
    } catch (e) {
      debugPrint('[YouTubeAudioService] androidSdkless attempt failed for $videoId: $e');
    }

    // Fallback attempt 2: default getManifest client chain (must pass byte-range readability check)
    try {
      final manifest = await _fetchManifest(
        videoId,
        null,
        const Duration(seconds: 7),
      );
      final streamUrl = manifest != null ? _selectBestAudioUrl(manifest) : null;
      if (streamUrl != null && streamUrl.isNotEmpty) {
        const fallbackUa = kYouTubeAndroidUserAgent;
        final readable = await _validateFallbackStreamUrl(
          streamUrl,
          userAgent: fallbackUa,
          clientName: 'DEFAULT_MANIFEST',
        );
        if (readable) {
          debugPrint('[YouTubeAudioService] Resolved readable stream via default manifest for $videoId');
          _cacheUrl(
            videoId,
            streamUrl,
            userAgent: fallbackUa,
            clientName: 'DEFAULT_MANIFEST',
          );
          return ResolvedYouTubeStream(
            url: streamUrl,
            userAgent: fallbackUa,
            clientName: 'DEFAULT_MANIFEST',
          );
        }
      }
    } catch (e) {
      debugPrint('[YouTubeAudioService] Default getManifest failed for $videoId: $e');
    }

    debugPrint('[YouTubeAudioService] Stream resolution failed for $videoId');
    return null;
  }

  String? _selectBestAudioUrl(StreamManifest manifest) {
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) return null;

    final aacStreams = audioStreams.where((s) =>
        s.container.name.toLowerCase() == 'm4a' ||
        s.container.name.toLowerCase() == 'mp4' ||
        s.audioCodec.toLowerCase().contains('mp4a') ||
        s.audioCodec.toLowerCase().contains('aac'));

    final selected = aacStreams.isNotEmpty
        ? aacStreams.withHighestBitrate()
        : audioStreams.withHighestBitrate();

    final url = selected.url.toString();
    return url.isNotEmpty ? url : null;
  }

  void _cacheUrl(
    String videoId,
    String url, {
    String userAgent = kYouTubeVisionOsUserAgent,
    String clientName = 'VISIONOS',
  }) {
    if (_urlCache.length >= _maxCacheSize) {
      final oldest = _urlCache.keys.first;
      _urlCache.remove(oldest);
    }

    // Cache with ~1-hour expiry, respecting URL expire param if earlier
    DateTime expiresAt = DateTime.now().add(_cacheTtl);
    try {
      final uri = Uri.parse(url);
      final exp = uri.queryParameters['expire'];
      if (exp != null) {
        final secs = int.tryParse(exp);
        if (secs != null) {
          final urlExpiry = DateTime.fromMillisecondsSinceEpoch(secs * 1000)
              .subtract(const Duration(minutes: 3));
          if (urlExpiry.isBefore(expiresAt)) {
            expiresAt = urlExpiry;
          }
        }
      }
    } catch (_) {}

    _urlCache[videoId] = _CachedStream(
      url: url,
      userAgent: userAgent,
      clientName: clientName,
      expiresAt: expiresAt,
    );
    debugPrint(
      '[StreamCache] STORED $videoId (client=$clientName | TTL: ~1hr | expires: ${expiresAt.toIso8601String()} | cache size: ${_urlCache.length})',
    );
  }

  String? _extractVideoId(String input) {
    var clean = input.trim();
    if (clean.startsWith('youtube_')) clean = clean.replaceFirst('youtube_', '');
    if (clean.contains('watch?v=')) {
      return Uri.tryParse(clean)?.queryParameters['v'] ?? clean;
    }
    if (clean.contains('youtu.be/')) {
      final segs = Uri.tryParse(clean)?.pathSegments ?? [];
      return segs.isNotEmpty ? segs.last : clean;
    }
    return clean.isNotEmpty ? clean : null;
  }
}
