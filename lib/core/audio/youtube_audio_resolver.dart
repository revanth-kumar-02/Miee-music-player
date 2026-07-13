import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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
      final cachedUrl = _cache[videoId]!;
      // Verify cached URL is still valid and reachable before returning it.
      final isReachable = await _validateAudioUrl(videoId, cachedUrl);
      if (isReachable) {
        return cachedUrl;
      } else {
        debugPrint('YouTubeAudioResolver: cached URL is no longer reachable. Evicting and re-resolving.');
        _cache.remove(videoId);
      }
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

      final audioStreams = manifest.audioOnly;
      debugPrint(
        'YouTubeAudioResolver: manifest fetched for $videoId — '
        '${audioStreams.length} audio-only, '
        '${manifest.muxed.length} muxed streams',
      );

      if (audioStreams.isEmpty) {
        throw Exception('Strict Audio-Only Mode: No audio-only streams found for video $videoId.');
      }

      // Sort by bitrate descending; pick the highest quality audio-only stream.
      final sorted = audioStreams.sortByBitrate();
      final best = sorted.last;
      final url = best.url.toString();

      debugPrint('YouTubeAudioResolver Details:');
      debugPrint('- Video ID: $videoId');
      debugPrint('- Number of audio streams found: ${audioStreams.length}');
      debugPrint('- Selected audio bitrate: ${best.bitrate.kiloBitsPerSecond.toStringAsFixed(0)} kbps');
      debugPrint('- Audio codec: ${best.audioCodec}');
      debugPrint('- MIME type: ${best.codec.toString()}');
      debugPrint('- Selected stream URL: $url');
      debugPrint('- SELECTED STREAM IS AUDIO-ONLY: true');

      // Before calling just_audio, validate:
      // - URL is HTTPS
      // - URL is non-empty
      // - URL is reachable
      // - URL is an audio stream
      final isValid = await _validateAudioUrl(videoId, url);
      if (!isValid) {
        throw Exception('Resolved stream URL for video $videoId failed HTTPS, reachability, or audio stream validations.');
      }

      // Evict oldest entry if cache is full.
      if (_cache.length >= _maxCacheSize) {
        _cache.remove(_cache.keys.first);
      }
      _cache[videoId] = url;

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

  /// Validates the stream URL before playing it.
  Future<bool> _validateAudioUrl(String videoId, String urlString) async {
    if (urlString.isEmpty) {
      debugPrint('YouTubeAudioResolver VALIDATION FAILED: URL is empty.');
      return false;
    }
    if (!urlString.startsWith('https://')) {
      debugPrint('YouTubeAudioResolver VALIDATION FAILED: URL is not HTTPS: $urlString');
      return false;
    }

    try {
      final uri = Uri.parse(urlString);
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 5);
      
      // Perform a HEAD request to check connection status and content headers
      final request = await client.headUrl(uri);
      
      // Pass typical browser headers so YouTube doesn't block the verification request
      request.headers.set('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1');
      request.headers.set('Accept', '*/*');
      
      final response = await request.close();
      final statusCode = response.statusCode;
      final contentType = response.headers.value(HttpHeaders.contentTypeHeader) ?? '';

      debugPrint('YouTubeAudioResolver VALIDATION RESULT: HTTP Status = $statusCode, Content-Type = $contentType');

      if (statusCode != 200 && statusCode != 206) {
        debugPrint('YouTubeAudioResolver VALIDATION FAILED: URL returned HTTP status $statusCode');
        return false;
      }

      if (!contentType.toLowerCase().contains('audio/')) {
        debugPrint('YouTubeAudioResolver VALIDATION FAILED: Content-Type is not an audio stream: $contentType');
        return false;
      }

      debugPrint('YouTubeAudioResolver VALIDATION PASSED successfully.');
      return true;
    } catch (e) {
      debugPrint('YouTubeAudioResolver VALIDATION FAILED: Connection error: $e');
      return false;
    }
  }

  /// Returns the File object representing the cached audio file if it exists and is valid.
  /// Otherwise, returns null.
  Future<File?> getCachedFile(String videoId) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final targetFile = File('${cacheDir.path}/yt_cache_$videoId.m4a');
      if (await targetFile.exists() && await targetFile.length() > 0) {
        return targetFile;
      }
    } catch (e) {
      debugPrint('YouTubeAudioResolver: error getting cached file for $videoId: $e');
    }
    return null;
  }

  /// Downloads the resolved YouTube stream URL in the background.
  void startBackgroundDownload(String videoId, String streamUrl) {
    // Spin up background downloader task without blocking caller thread
    Future.microtask(() async {
      try {
        final cacheDir = await getTemporaryDirectory();
        final tempFile = File('${cacheDir.path}/yt_cache_$videoId.tmp');
        final targetFile = File('${cacheDir.path}/yt_cache_$videoId.m4a');
        
        if (await targetFile.exists() && await targetFile.length() > 0) {
          debugPrint('YouTubeAudioResolver Cache Downloader: cache already exists for $videoId');
          return;
        }
        
        debugPrint('YouTubeAudioResolver Cache Downloader: starting download for $videoId');
        
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 10);
        final request = await client.getUrl(Uri.parse(streamUrl));
        request.headers.set('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1');
        final response = await request.close();
        
        if (response.statusCode != 200) {
          debugPrint('YouTubeAudioResolver Cache Downloader: download failed with status ${response.statusCode}');
          return;
        }
        
        final fileSink = tempFile.openWrite();
        await response.pipe(fileSink);
        await fileSink.close();
        
        if (await tempFile.length() > 0) {
          await tempFile.rename(targetFile.path);
          debugPrint('YouTubeAudioResolver Cache Downloader: download complete and saved to ${targetFile.path}');
        } else {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      } catch (e) {
        debugPrint('YouTubeAudioResolver Cache Downloader: error downloading $videoId: $e');
      }
    });
  }

  /// Clears the cached stream URL for a specific video ID.
  void clearVideoCache(String videoId) => _cache.remove(videoId);

  /// Clears the in-memory URL cache.
  void clearCache() => _cache.clear();

  /// Closes the underlying [YoutubeExplode] HTTP client.
  /// Call only when the app is shutting down.
  void dispose() => _yt.close();
}
