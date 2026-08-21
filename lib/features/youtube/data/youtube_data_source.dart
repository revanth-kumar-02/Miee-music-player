import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../domain/youtube_failures.dart';

/// Configuration for YouTube Data API v3.
class YouTubeApiConfig {
  /// Default API Key. Can be passed via --dart-define=YOUTUBE_API_KEY=your_key
  static const String apiKey = String.fromEnvironment(
    'YOUTUBE_API_KEY',
    defaultValue: '', // Provide a fallback if configured in environment
  );

  static const String baseUrl = 'https://www.googleapis.com/youtube/v3';
}

/// Raw data source connecting to YouTube Data API v3 via HTTP/Dio.
class YouTubeDataSource {
  final Dio _dio;
  final String _apiKey;

  YouTubeDataSource({Dio? dio, String? apiKey})
      : _dio = dio ?? Dio(),
        _apiKey = (apiKey != null && apiKey.isNotEmpty)
            ? apiKey
            : YouTubeApiConfig.apiKey;

  bool get isConfigured => _apiKey.isNotEmpty;

  /// Performs a search query against YouTube Data API v3 search endpoint.
  Future<List<Map<String, dynamic>>> searchVideos(String query, {int maxResults = 25}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    if (!isConfigured) {
      debugPrint('YouTubeDataSource: API key not provided or empty.');
      // When API key is not configured, throw a clear configuration error
      throw const YouTubeApiConfigFailure(
        'YouTube API key is missing. Set YOUTUBE_API_KEY environment variable or configure API key.',
      );
    }

    try {
      final response = await _dio.get<dynamic>(
        '${YouTubeApiConfig.baseUrl}/search',
        queryParameters: {
          'part': 'snippet',
          'q': cleanQuery,
          'type': 'video',
          'maxResults': maxResults,
          'key': _apiKey,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        final items = data['items'] as List<dynamic>? ?? [];
        return items.cast<Map<String, dynamic>>();
      } else {
        throw YouTubeSearchFailure('HTTP ${response.statusCode}: Failed to fetch YouTube results.');
      }
    } on DioException catch (e) {
      debugPrint('YouTubeDataSource DioError: ${e.type} - ${e.message}');
      if (e.response?.statusCode == 403) {
        final errBody = e.response?.data.toString() ?? '';
        if (errBody.contains('quotaExceeded')) {
          throw const YouTubeApiQuotaFailure();
        }
        if (errBody.contains('keyInvalid') || errBody.contains('API key not valid')) {
          throw const YouTubeApiConfigFailure('Invalid YouTube API Key provided.');
        }
        throw const YouTubeSearchFailure('Access forbidden by YouTube API (HTTP 403).');
      } else if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        throw const NetworkPlaybackFailure();
      }
      throw YouTubeSearchFailure(e.message ?? 'Network error while querying YouTube.');
    } catch (e) {
      if (e is YouTubeFailure) rethrow;
      throw YouTubeSearchFailure('Unexpected YouTube API error: $e');
    }
  }

  /// Fetches contentDetails (duration) and statistics (view count) for a list of video IDs.
  Future<Map<String, Map<String, dynamic>>> getVideoDetails(List<String> videoIds) async {
    if (videoIds.isEmpty || !isConfigured) return {};

    try {
      final response = await _dio.get<dynamic>(
        '${YouTubeApiConfig.baseUrl}/videos',
        queryParameters: {
          'part': 'contentDetails,statistics',
          'id': videoIds.join(','),
          'key': _apiKey,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data is String
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        final items = data['items'] as List<dynamic>? ?? [];
        final Map<String, Map<String, dynamic>> resultMap = {};

        for (final item in items) {
          final id = item['id'] as String?;
          if (id != null) {
            resultMap[id] = item as Map<String, dynamic>;
          }
        }
        return resultMap;
      }
    } catch (e) {
      debugPrint('YouTubeDataSource.getVideoDetails error: $e');
    }
    return {};
  }
}
