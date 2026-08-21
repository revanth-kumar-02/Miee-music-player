import 'package:flutter/foundation.dart';
import '../domain/youtube_model.dart';
import 'youtube_data_source.dart';

/// Repository responsible for searching YouTube via YouTube Data API v3,
/// applying smart music video heuristics, and mapping responses to [YouTubeVideo].
class YouTubeRepository {
  final YouTubeDataSource _dataSource;

  /// In-memory search cache (bounded to 50 queries)
  final Map<String, List<YouTubeVideo>> _searchCache = {};
  static const int _maxCacheSize = 50;

  YouTubeRepository({YouTubeDataSource? dataSource})
      : _dataSource = dataSource ?? YouTubeDataSource();

  /// Searches YouTube for [query] using official YouTube Data API v3.
  Future<List<YouTubeVideo>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    if (_searchCache.containsKey(cleanQuery)) {
      debugPrint('YouTubeRepository: Cache hit for "$cleanQuery"');
      return _searchCache[cleanQuery]!;
    }

    debugPrint('YouTubeRepository: Searching YouTube Data API v3 for "$cleanQuery"');

    final rawItems = await _dataSource.searchVideos(cleanQuery, maxResults: 25);
    if (rawItems.isEmpty) return [];

    // Extract video IDs to fetch duration & statistics
    final videoIds = <String>[];
    for (final item in rawItems) {
      final idObj = item['id'];
      if (idObj is Map && idObj['kind'] == 'youtube#video') {
        final videoId = idObj['videoId'] as String?;
        if (videoId != null && videoId.isNotEmpty) {
          videoIds.add(videoId);
        }
      }
    }

    // Fetch details (duration & stats)
    final detailsMap = await _dataSource.getVideoDetails(videoIds);

    final excludedKeywords = [
      'live',
      'livestream',
      'podcast',
      'interview',
      'full movie',
      'documentary',
      'compilation',
      'reaction',
      'karaoke',
      '8d',
      'lyrics',
    ];

    final candidateVideos = <YouTubeVideo>[];

    for (final item in rawItems) {
      final idObj = item['id'];
      if (idObj is! Map || idObj['kind'] != 'youtube#video') continue;
      final videoId = idObj['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) continue;

      final snippet = item['snippet'] as Map<String, dynamic>? ?? {};
      final title = snippet['title'] as String? ?? '';
      final channelTitle = snippet['channelTitle'] as String? ?? '';
      final description = snippet['description'] as String? ?? '';
      final liveBroadcast = snippet['liveBroadcastContent'] as String? ?? 'none';

      // 1. Exclude live streams
      if (liveBroadcast != 'none') continue;

      // 2. Exclude non-music keyword matches
      final titleLower = title.toLowerCase();
      final channelLower = channelTitle.toLowerCase();
      final descLower = description.toLowerCase();

      final hasExcluded = excludedKeywords.any((kw) =>
          titleLower.contains(kw) ||
          channelLower.contains(kw) ||
          descLower.contains(kw));

      if (hasExcluded) continue;

      // Extract thumbnails
      final thumbnails = snippet['thumbnails'] as Map<String, dynamic>? ?? {};
      String thumbnailUrl = '';
      if (thumbnails['high'] != null) {
        thumbnailUrl = thumbnails['high']['url'] as String? ?? '';
      } else if (thumbnails['medium'] != null) {
        thumbnailUrl = thumbnails['medium']['url'] as String? ?? '';
      } else if (thumbnails['default'] != null) {
        thumbnailUrl = thumbnails['default']['url'] as String? ?? '';
      }
      if (thumbnailUrl.isEmpty) {
        thumbnailUrl = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      }

      // Details metadata
      final detail = detailsMap[videoId];
      String durationStr = '3:30';
      String viewCountStr = '';

      if (detail != null) {
        final contentDetails = detail['contentDetails'] as Map<String, dynamic>?;
        final statistics = detail['statistics'] as Map<String, dynamic>?;

        if (contentDetails != null) {
          final isoDuration = contentDetails['duration'] as String?;
          durationStr = _parseIso8601Duration(isoDuration);
        }

        if (statistics != null) {
          final viewsRaw = int.tryParse(statistics['viewCount'] as String? ?? '');
          if (viewsRaw != null) {
            viewCountStr = _formatViewCount(viewsRaw);
          }
        }
      }

      candidateVideos.add(
        YouTubeVideo(
          id: videoId,
          title: _unescapeHtml(title),
          channelTitle: _unescapeHtml(channelTitle),
          thumbnailUrl: thumbnailUrl,
          duration: durationStr,
          viewCount: viewCountStr,
        ),
      );
    }

    // Heuristic scoring to prioritize official audio / releases
    int calculateScore(YouTubeVideo video) {
      int score = 0;
      final titleLower = video.title.toLowerCase();
      final channelLower = video.channelTitle.toLowerCase();

      if (channelLower.contains('- topic')) score += 100;
      if (channelLower.contains('vevo')) score += 90;
      if (channelLower.contains('official')) score += 50;

      if (titleLower.contains('official audio')) score += 80;
      if (titleLower.contains('official music video') || titleLower.contains('official video')) score += 75;
      if (titleLower.contains('music video') || titleLower.contains('mv')) score += 40;
      if (titleLower.contains('audio')) score += 30;

      return score;
    }

    candidateVideos.sort((a, b) => calculateScore(b).compareTo(calculateScore(a)));

    if (candidateVideos.isNotEmpty) {
      if (_searchCache.length >= _maxCacheSize) {
        _searchCache.remove(_searchCache.keys.first);
      }
      _searchCache[cleanQuery] = candidateVideos;
    }

    return candidateVideos;
  }

  String _parseIso8601Duration(String? isoDuration) {
    if (isoDuration == null || isoDuration.isEmpty) return '0:00';
    final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
    final match = regex.firstMatch(isoDuration);
    if (match == null) return '0:00';

    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

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

  String _unescapeHtml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }

  void clearCache() => _searchCache.clear();
}
