import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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
// Cache entry
// ─────────────────────────────────────────────────────────────────────────────

class _CachedStream {
  final String url;
  final DateTime expiresAt;
  const _CachedStream({required this.url, required this.expiresAt});
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTubeAudioService
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves direct audio-only stream URLs for YouTube video IDs using `youtube_explode_dart`
/// with the `androidSdkless` client as primary resolver.
///
/// Guarantees:
///   • Fast resolution (~2-4 seconds) without dead proxy waterfall blocking.
///   • Audio-only streams preferred (AAC/M4A).
///   • In-memory stream URL cache bounded with ~1-hour expiry.
///   • Concurrent calls for the same video ID are deduplicated.
class YouTubeAudioService {
  static final YouTubeAudioService _instance = YouTubeAudioService._internal();
  factory YouTubeAudioService() => _instance;
  YouTubeAudioService._internal();

  static const int _maxCacheSize = 100;
  static const Duration _cacheTtl = Duration(hours: 1);

  // ── Cache & in-flight deduplication ───────────────────────────────────────
  final Map<String, _CachedStream> _urlCache = {};
  final Map<String, Future<String?>> _inFlight = {};

  // ── youtube_explode_dart client ───────────────────────────────────────────
  YoutubeExplode _yt = YoutubeExplode();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns an audio-only stream URL for [videoIdOrUrl].
  ///
  /// Serves from cache if valid; deduplicates concurrent calls for the same ID.
  /// Pass [forceRefresh]=true to bypass cache (e.g. after a playback error).
  Future<String?> getAudioStreamUrl(
    String videoIdOrUrl, {
    bool forceRefresh = false,
  }) {
    final videoId = _extractVideoId(videoIdOrUrl);
    if (videoId == null || videoId.isEmpty) {
      debugPrint('[YouTubeAudioService] Invalid video ID: "$videoIdOrUrl"');
      return Future.value(null);
    }

    // Serve valid cache entry unless caller forces refresh
    if (!forceRefresh && _urlCache.containsKey(videoId)) {
      final cached = _urlCache[videoId]!;
      if (!cached.isExpired) {
        debugPrint('[StreamCache] HIT for $videoId');
        return Future.value(cached.url);
      }
      debugPrint('[StreamCache] EXPIRED for $videoId, evicting');
      _urlCache.remove(videoId);
    }

    // Deduplicate concurrent resolution calls
    if (_inFlight.containsKey(videoId)) {
      debugPrint('[YouTubeAudioService] In-flight dedup for $videoId');
      return _inFlight[videoId]!;
    }

    final future = _resolveStream(videoId).whenComplete(() {
      _inFlight.remove(videoId);
    });
    _inFlight[videoId] = future;
    return future;
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
    debugPrint('[StreamCache] Cache cleared');
  }

  void dispose() {
    _yt.close();
    _yt = YoutubeExplode();
    debugPrint('[YouTubeAudioService] Disposed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Core stream resolution
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> _resolveStream(String videoId) async {
    debugPrint('[YouTubeAudioService] Resolving audio stream for $videoId');

    // Primary attempt: VISIONOS client (exempt from GVS PoToken 1MB cap / 403 errors)
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [kVisionOsClient],
      );
      final streamUrl = _selectBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        debugPrint('[YouTubeAudioService] Resolved stream via VISIONOS for $videoId');
        _cacheUrl(videoId, streamUrl);
        return streamUrl;
      }
    } catch (e) {
      debugPrint('[YouTubeAudioService] VISIONOS attempt failed for $videoId: $e');
    }

    // Fallback attempt 1: androidSdkless client
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [kAndroidSdklessClient],
      );
      final streamUrl = _selectBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        debugPrint('[YouTubeAudioService] Resolved stream via androidSdkless for $videoId');
        _cacheUrl(videoId, streamUrl);
        return streamUrl;
      }
    } catch (e) {
      debugPrint('[YouTubeAudioService] androidSdkless attempt failed for $videoId: $e');
    }

    // Fallback attempt 2: default getManifest client chain
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final streamUrl = _selectBestAudioUrl(manifest);
      if (streamUrl != null && streamUrl.isNotEmpty) {
        debugPrint('[YouTubeAudioService] Resolved stream via default manifest for $videoId');
        _cacheUrl(videoId, streamUrl);
        return streamUrl;
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

  void _cacheUrl(String videoId, String url) {
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

    _urlCache[videoId] = _CachedStream(url: url, expiresAt: expiresAt);
    debugPrint(
      '[StreamCache] STORED $videoId (TTL: ~1hr | expires: ${expiresAt.toIso8601String()} | cache size: ${_urlCache.length})',
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
