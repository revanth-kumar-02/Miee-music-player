import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../youtube/domain/youtube_model.dart';

/// Service responsible for communicating with YouTube Explode API and filtering music videos.
class YouTubeSearchService {
  final YoutubeExplode _yt;

  YouTubeSearchService({YoutubeExplode? yt}) : _yt = yt ?? YoutubeExplode();

  /// Queries YouTube, excluding live streams, podcasts, mixes, compilations, and videos >10 minutes.
  Future<List<YouTubeVideo>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    try {
      final searchResults = await _yt.search.search(
        cleanQuery,
        filter: TypeFilters.video,
      );

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
        'mix',
        'livestreaming',
        'podcast episode',
        'non-stop',
      ];

      final filteredResults = searchResults.where((video) {
        // Duration check: 30s < duration <= 10m
        final duration = video.duration;
        if (duration == null ||
            duration <= const Duration(seconds: 30) ||
            duration > const Duration(minutes: 10)) {
          return false;
        }

        // Live stream check
        if (video.isLive) return false;

        final titleLower = video.title.toLowerCase();
        final authorLower = video.author.toLowerCase();
        final descLower = video.description.toLowerCase();

        final hasExcluded = excludedKeywords.any((kw) =>
            titleLower.contains(kw) ||
            authorLower.contains(kw) ||
            descLower.contains(kw));

        return !hasExcluded;
      }).toList();

      // Heuristic scoring to prioritize official audio and music videos first
      int calculateScore(Video video) {
        int score = 0;
        final titleLower = video.title.toLowerCase();
        final authorLower = video.author.toLowerCase();

        if (authorLower.contains('- topic')) score += 100;
        if (authorLower.contains('vevo')) score += 90;
        if (authorLower.contains('official')) score += 50;

        if (titleLower.contains('official audio')) score += 80;
        if (titleLower.contains('official music video') || titleLower.contains('official video')) score += 75;
        if (titleLower.contains('music video') || titleLower.contains('mv')) score += 40;
        if (titleLower.contains('audio')) score += 30;

        return score;
      }

      filteredResults.sort((a, b) => calculateScore(b).compareTo(calculateScore(a)));

      return filteredResults.map((video) {
        return YouTubeVideo(
          id: video.id.value,
          title: video.title,
          channelTitle: video.author,
          thumbnailUrl: video.thumbnails.highResUrl,
          duration: _formatDuration(video.duration),
          viewCount: _formatViewCount(video.engagement.viewCount),
        );
      }).toList();
    } catch (e) {
      debugPrint('YouTubeSearchService error: $e');
      throw Exception('YouTube search failed: $e');
    }
  }

  /// Fetches search query recommendations/auto-completions.
  Future<List<String>> getSuggestions(String query) async {
    if (query.trim().isEmpty) return const [];
    try {
      return await _yt.search.getQuerySuggestions(query);
    } catch (_) {
      return const [];
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    final m = duration.inMinutes;
    final s = duration.inSeconds.remainder(60);
    return '$m:${s.toString().padLeft(2, '0')}';
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

  void dispose() {
    _yt.close();
  }
}
