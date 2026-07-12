import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../domain/youtube_model.dart';

/// Repository responsible for querying YouTube search results.
///
/// Uses [YoutubeExplode]'s search API — no web scraping, no custom regex,
/// no Dio. Works reliably with the current YouTube backend.
class YouTubeRepository {
  /// Shared [YoutubeExplode] instance — keep alive for the app's lifetime
  /// so the underlying HTTP client is reused across searches.
  final YoutubeExplode _yt;

  /// In-memory query → results cache (bounded to 50 entries).
  final Map<String, List<YouTubeVideo>> _searchCache = {};
  static const int _maxCacheSize = 50;

  YouTubeRepository({YoutubeExplode? yt}) : _yt = yt ?? YoutubeExplode();

  /// Searches YouTube for [query] and returns up to 20 video results.
  ///
  /// Throws a descriptive exception on network failure, rate limiting, or
  /// empty results caused by a bad response. Never silently swallows errors.
  Future<List<YouTubeVideo>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Return cached results if available.
    if (_searchCache.containsKey(cleanQuery)) {
      debugPrint('YouTubeRepository: cache hit for "$cleanQuery"');
      return _searchCache[cleanQuery]!;
    }

    debugPrint('YouTubeRepository: searching for "$cleanQuery"');

    try {
      // Use youtube_explode_dart's official search API.
      // TypeFilters.video restricts results to videos only.
      final searchResults = await _yt.search.search(
        cleanQuery,
        filter: TypeFilters.video,
      );

      debugPrint(
        'YouTubeRepository: raw results count = ${searchResults.length}',
      );

      if (searchResults.isEmpty) {
        debugPrint('YouTubeRepository: search returned 0 results for "$cleanQuery"');
        return [];
      }

      final videos = searchResults
          .map((video) => _videoToModel(video))
          .where((v) => v != null)
          .cast<YouTubeVideo>()
          .toList();

      debugPrint(
        'YouTubeRepository: mapped ${videos.length} valid videos for "$cleanQuery"',
      );

      // Cache and return.
      if (videos.isNotEmpty) {
        if (_searchCache.length >= _maxCacheSize) {
          _searchCache.remove(_searchCache.keys.first);
        }
        _searchCache[cleanQuery] = videos;
      }

      return videos;
    } on YoutubeExplodeException catch (e, stack) {
      debugPrint('YouTubeRepository: YoutubeExplodeException: ${e.message}');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      throw Exception('YouTube search failed: ${e.message}');
    } catch (e, stack) {
      debugPrint('YouTubeRepository: unexpected error during search: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);

      // Distinguish network errors from other failures.
      final msg = e.toString();
      if (msg.contains('SocketException') ||
          msg.contains('NetworkException') ||
          msg.contains('Failed host lookup')) {
        throw Exception('No internet connection. Please go online to search YouTube.');
      }
      if (msg.contains('429') || msg.contains('rate limit')) {
        throw Exception('YouTube rate limit reached. Please wait a moment and try again.');
      }
      throw Exception('YouTube search error: $e');
    }
  }

  /// Converts a [Video] from youtube_explode_dart to our [YouTubeVideo] model.
  YouTubeVideo? _videoToModel(Video video) {
    try {
      final id = video.id.value;
      final title = video.title;

      if (id.isEmpty || title.isEmpty) {
        debugPrint('YouTubeRepository: skipping video with empty id/title');
        return null;
      }

      // Duration: format as M:SS or H:MM:SS.
      final duration = _formatDuration(video.duration);

      // Thumbnail: highResUrl (hqdefault.jpg) is always available.
      // maxResUrl may return a 404 for some videos, so prefer highRes.
      final thumbnailUrl = video.thumbnails.highResUrl;

      // View count — non-nullable int.
      final viewCount = _formatViewCount(video.engagement.viewCount);

      debugPrint(
        'YouTubeRepository: [$id] title="$title" duration="$duration" '
        'views="$viewCount" thumb="${thumbnailUrl.substring(0, 40)}…"',
      );

      return YouTubeVideo(
        id: id,
        title: title,
        channelTitle: video.author,
        thumbnailUrl: thumbnailUrl,
        duration: duration,
        viewCount: viewCount,
      );
    } catch (e, stack) {
      debugPrint('YouTubeRepository: error mapping video: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      return null;
    }
  }

  /// Formats a [Duration] as "M:SS" or "H:MM:SS".
  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final h = duration.inHours;
    final m = duration.inMinutes.remainder(60);
    final s = duration.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Formats a raw view count integer to a human-readable string.
  String _formatViewCount(int views) {
    if (views >= 1000000000) {
      return '${(views / 1000000000).toStringAsFixed(1)}B views';
    } else if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M views';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(0)}K views';
    }
    return '$views views';
  }

  /// Clears the in-memory search cache.
  void clearCache() => _searchCache.clear();

  /// Closes the underlying HTTP client. Call only on app shutdown.
  void dispose() => _yt.close();
}
