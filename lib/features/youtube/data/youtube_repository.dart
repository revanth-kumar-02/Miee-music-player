import 'dart:convert';
import 'package:dio/dio.dart';
import '../domain/youtube_model.dart';

/// Repository responsible for querying YouTube search results.
///
/// Implements a no-API-key scraper by requesting the HTML results page and
/// parsing the embedded `ytInitialData` JSON structure.
class YouTubeRepository {
  final Dio _dio;

  // Simple in-memory cache to prevent redundant search requests.
  final Map<String, List<YouTubeVideo>> _searchCache = {};

  YouTubeRepository({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                  'Accept-Language': 'en-US,en;q=0.9',
                },
              ),
            );

  /// Searches YouTube for the given [query].
  ///
  /// Caches the results in memory. Handles empty results, network timeouts,
  /// and missing connection errors gracefully.
  Future<List<YouTubeVideo>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    // Return cached results if available
    if (_searchCache.containsKey(cleanQuery)) {
      return _searchCache[cleanQuery]!;
    }

    try {
      // sp=EgIQAQ%253D%253D is the video-only filter
      final response = await _dio.get<String>(
        'https://www.youtube.com/results',
        queryParameters: {
          'search_query': cleanQuery,
          'sp': 'EgIQAQ==',
        },
      );

      final html = response.data as String?;
      if (html == null || html.isEmpty) return [];

      final videos = _parseInitialData(html);
      if (videos.isEmpty && !html.contains('ytInitialData')) {
        throw Exception('YouTube integration is temporarily unavailable. YouTube layout may have changed.');
      }

      if (videos.isNotEmpty) {
        _searchCache[cleanQuery] = videos;
        // Keep cache size bounded to 50 queries
        if (_searchCache.length > 50) {
          _searchCache.remove(_searchCache.keys.first);
        }
      }
      return videos;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('Connection timed out. Please check your internet connection.');
      }
      if (e.type == DioExceptionType.connectionError) {
        throw Exception('No internet connection. Please go online to search YouTube.');
      }
      throw Exception('Failed to search YouTube: ${e.message}');
    } catch (e) {
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Extracts and parses [ytInitialData] from YouTube's HTML response.
  List<YouTubeVideo> _parseInitialData(String html) {
    final List<YouTubeVideo> results = [];

    // Matches the ytInitialData JSON object inside script tags.
    final regex = RegExp(r'ytInitialData\s*=\s*({.*?});\s*</script>');
    final match = regex.firstMatch(html);
    if (match == null) return [];

    final jsonStr = match.group(1);
    if (jsonStr == null) return [];

    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      final contents = data['contents']
          ?['twoColumnSearchResultRenderer']
          ?['primaryContents']
          ?['sectionListRenderer']
          ?['contents'];

      if (contents is List) {
        for (final section in contents) {
          final itemSection = section['itemSectionRenderer'];
          if (itemSection != null) {
            final items = itemSection['contents'];
            if (items is List) {
              for (final item in items) {
                final video = item['videoRenderer'];
                if (video != null) {
                  final videoId = video['videoId'] as String?;
                  final title = _extractText(video['title'] as Map<String, dynamic>?);
                  final channel = _extractText((video['longBylineText'] ?? video['shortBylineText']) as Map<String, dynamic>?);
                  final duration = video['lengthText']?['simpleText'] as String? ?? '0:00';
                  final viewCount = video['viewCountText']?['simpleText'] as String? ?? '';

                  final thumbnails = video['thumbnail']?['thumbnails'];
                  final thumbnailUrl = (thumbnails is List && thumbnails.isNotEmpty)
                      ? thumbnails.last['url'] as String? ?? ''
                      : '';

                  if (videoId != null && title.isNotEmpty) {
                    results.add(
                      YouTubeVideo(
                        id: videoId,
                        title: title,
                        channelTitle: channel.isNotEmpty ? channel : 'Unknown Channel',
                        thumbnailUrl: thumbnailUrl,
                        duration: duration,
                        viewCount: viewCount,
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }
    } catch (_) {
      // If parsing fails, return empty list instead of crashing
    }

    return results;
  }

  /// Extracts text from standard YouTube rendering structures (runs vs simpleText).
  String _extractText(Map<String, dynamic>? data) {
    if (data == null) return '';
    final simpleText = data['simpleText'];
    if (simpleText is String) return simpleText;

    final runs = data['runs'];
    if (runs is List && runs.isNotEmpty) {
      return runs.map((run) => run['text'] as String? ?? '').join();
    }
    return '';
  }
}
