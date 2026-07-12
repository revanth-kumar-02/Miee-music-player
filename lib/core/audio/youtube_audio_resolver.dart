import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves a YouTube video ID to a direct playable audio-stream URL.
///
/// Uses [YoutubeExplode] to fetch the stream manifest and select the
/// highest-quality audio-only stream (AAC/WebM). Resolved URLs are
/// cached in memory so re-queuing the same video does not incur another
/// network round-trip.
///
/// Usage:
/// ```dart
/// final url = await YouTubeAudioResolver.instance.resolve('dQw4w9WgXcQ');
/// await player.setUrl(url);
/// ```
class YouTubeAudioResolver {
  YouTubeAudioResolver._();
  static final YouTubeAudioResolver instance = YouTubeAudioResolver._();

  final YoutubeExplode _yt = YoutubeExplode();

  /// In-memory cache: videoId → direct audio URL.
  /// Bounded to 100 entries to limit memory usage.
  final Map<String, String> _cache = {};
  static const int _maxCacheSize = 100;

  /// Resolves [videoId] to a playable audio URL.
  ///
  /// Throws a descriptive [Exception] if the stream cannot be resolved
  /// (private video, region-locked, network error, etc.).
  Future<String> resolve(String videoId) async {
    if (_cache.containsKey(videoId)) {
      debugPrint('YouTubeAudioResolver: cache hit for $videoId');
      return _cache[videoId]!;
    }

    debugPrint('YouTubeAudioResolver: resolving stream for $videoId');
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

      // Prefer audio-only streams (smallest data, no video payload).
      // Fallback to muxed if no audio-only is available.
      String? url;

      final audioOnly = manifest.audioOnly;
      if (audioOnly.isNotEmpty) {
        // Sort by bitrate descending; pick the best quality.
        final sorted = audioOnly.sortByBitrate();
        url = sorted.last.url.toString();
      } else {
        // Muxed fallback (rare).
        final muxed = manifest.muxed;
        if (muxed.isNotEmpty) {
          url = muxed.withHighestBitrate().url.toString();
        }
      }

      if (url == null || url.isEmpty) {
        throw Exception('No playable stream found for video $videoId.');
      }

      // Evict oldest entry if cache is full.
      if (_cache.length >= _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }
      _cache[videoId] = url;
      debugPrint('YouTubeAudioResolver: resolved $videoId → ${url.substring(0, 60)}…');
      return url;
    } on YoutubeExplodeException catch (e) {
      throw Exception('YouTube stream error: ${e.message}');
    } catch (e) {
      throw Exception('Could not resolve audio for video $videoId: $e');
    }
  }

  /// Clears the in-memory URL cache (e.g., when the user signs out or
  /// on low-memory pressure).
  void clearCache() => _cache.clear();

  /// Disposes the underlying [YoutubeExplode] HTTP client.
  /// Call this only when the app is shutting down.
  void dispose() => _yt.close();
}
