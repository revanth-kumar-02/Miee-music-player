import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Resolves a YouTube video ID to a direct playable audio-stream URL.
///
/// Uses [YoutubeExplode] to fetch the stream manifest and select the
/// highest-quality audio-only stream. Results are cached in memory so
/// re-queuing the same video does not incur another network round-trip.
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

  /// Resolves [videoId] to a playable audio-only stream URL.
  ///
  /// Full stack traces are printed in debug mode.
  /// Throws a descriptive [Exception] on every failure path.
  Future<String> resolve(String videoId) async {
    if (_cache.containsKey(videoId)) {
      debugPrint('YouTubeAudioResolver: cache hit for $videoId');
      return _cache[videoId]!;
    }

    debugPrint('YouTubeAudioResolver: resolving stream for $videoId');

    try {
      final manifest = await _yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [
          YoutubeApiClient.ios,
          YoutubeApiClient.androidMusic,
          YoutubeApiClient.androidSdkless,
        ],
      );

      debugPrint(
        'YouTubeAudioResolver: manifest fetched for $videoId — '
        '${manifest.audioOnly.length} audio-only, '
        '${manifest.muxed.length} muxed streams',
      );

      String? url;

      // Prefer audio-only (AAC/WebM) — no video data, smallest payload.
      final audioStreams = manifest.audioOnly;
      if (audioStreams.isNotEmpty) {
        // sortByBitrate() returns ascending order; .last = highest bitrate.
        final sorted = audioStreams.sortByBitrate();
        final best = sorted.last;
        url = best.url.toString();
        debugPrint(
          'YouTubeAudioResolver: SELECTED STREAM IS AUDIO-ONLY: true. '
          'Codec: ${best.codec}, Container: ${best.container}, '
          'Bitrate: ${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps',
        );
      } else {
        // Muxed fallback (rare — live streams, some age-restricted videos).
        final muxedStreams = manifest.muxed;
        if (muxedStreams.isNotEmpty) {
          final best = muxedStreams.withHighestBitrate();
          url = best.url.toString();
          debugPrint(
            'YouTubeAudioResolver: SELECTED STREAM IS AUDIO-ONLY: false. '
            'Falling back to muxed stream: ${best.qualityLabel}',
          );
        }
      }

      if (url == null || url.isEmpty) {
        throw Exception(
          'No playable stream found for video $videoId. '
          'The video may be age-restricted, private, or region-locked.',
        );
      }

      // Evict oldest entry if cache is full.
      if (_cache.length >= _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }
      _cache[videoId] = url;

      final preview = url.length > 80 ? '${url.substring(0, 80)}…' : url;
      debugPrint('YouTubeAudioResolver: resolved $videoId → $preview');
      return url;
    } on YoutubeExplodeException catch (e, stack) {
      debugPrint('YouTubeAudioResolver: YoutubeExplodeException for $videoId: ${e.message}');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      throw Exception('YouTube stream error for $videoId: ${e.message}');
    } catch (e, stack) {
      debugPrint('YouTubeAudioResolver: unexpected error resolving $videoId: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      throw Exception('Could not resolve audio for $videoId: $e');
    }
  }

  /// Clears the cached stream URL for a specific video ID.
  void clearVideoCache(String videoId) => _cache.remove(videoId);

  /// Clears the in-memory URL cache.
  void clearCache() => _cache.clear();

  /// Closes the underlying [YoutubeExplode] HTTP client.
  /// Call only when the app is shutting down.
  void dispose() => _yt.close();
}
