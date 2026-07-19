import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../youtube/domain/youtube_model.dart';
import 'local_search_service.dart';
import 'youtube_search_service.dart';

/// Central search repository orchestrating local fuzzy matches, YouTube results caching,
/// search suggestions, and persistent search history in Hive.
class SearchRepository {
  final LocalSearchService localSearch = LocalSearchService();
  final YouTubeSearchService youtubeSearch = YouTubeSearchService();

  static const String _prefKey = 'youtube_search_history';
  static const int _maxHistory = 10;

  /// Bounded query cache preventing duplicate YouTube Explode network queries.
  final Map<String, List<YouTubeVideo>> _youtubeCache = {};
  static const int _maxCacheSize = 50;

  Box<Object?> get _box => Hive.box<Object?>(HiveBoxes.preferences);

  /// Load persistent search history.
  List<String> getRecentSearches() {
    final list = _box.get(_prefKey);
    if (list is List) {
      return list.cast<String>();
    }
    return const [];
  }

  /// Add query to history, maintaining a limit of 10 searches.
  Future<void> addRecentSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final list = List<String>.from(getRecentSearches())
      ..removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);

    if (list.length > _maxHistory) {
      list.removeRange(_maxHistory, list.length);
    }

    await _box.put(_prefKey, list);
  }

  /// Remove single query entry.
  Future<void> removeRecentSearch(String query) async {
    final list = List<String>.from(getRecentSearches())
      ..removeWhere((q) => q == query);
    await _box.put(_prefKey, list);
  }

  /// Destructively clear entire history database.
  Future<void> clearRecentSearches() async {
    await _box.delete(_prefKey);
  }

  /// Performs online YouTube query checking cache first.
  Future<List<YouTubeVideo>> searchYouTube(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    if (_youtubeCache.containsKey(trimmed)) {
      debugPrint('SearchRepository: YouTube cache hit for "$trimmed"');
      return _youtubeCache[trimmed]!;
    }

    final results = await youtubeSearch.search(trimmed);
    if (results.isNotEmpty) {
      if (_youtubeCache.length >= _maxCacheSize) {
        _youtubeCache.remove(_youtubeCache.keys.first);
      }
      _youtubeCache[trimmed] = results;
    }
    return results;
  }

  /// Fetches auto-complete suggestions.
  Future<List<String>> getSuggestions(String query) async {
    return youtubeSearch.getSuggestions(query);
  }

  /// Disposes open connections.
  void dispose() {
    youtubeSearch.dispose();
  }
}
