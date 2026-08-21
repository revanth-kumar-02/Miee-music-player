import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/data/youtube_repository.dart';
import 'local_search_service.dart';

/// Central search repository orchestrating local fuzzy matches, YouTube API queries,
/// search suggestions, and persistent search history in Hive.
class SearchRepository {
  final LocalSearchService localSearch = LocalSearchService();
  final YouTubeRepository youtubeRepository = YouTubeRepository();

  static const String _prefKey = 'youtube_search_history';
  static const int _maxHistory = 10;

  Box<Object?> get _box => Hive.box<Object?>(HiveBoxes.preferences);

  /// Load persistent search history.
  List<String> getRecentSearches() {
    try {
      final raw = _box.get(_prefKey);
      if (raw == null) return const [];
      if (raw is List) {
        return raw.whereType<String>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
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

  /// Performs online YouTube query using official YouTube Data API v3.
  Future<List<YouTubeVideo>> searchYouTube(String query) async {
    return youtubeRepository.search(query);
  }

  /// Fetches auto-complete suggestions.
  Future<List<String>> getSuggestions(String query) async {
    // Basic offline/historical autocomplete suggestions
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];
    final history = getRecentSearches();
    return history.where((s) => s.toLowerCase().contains(trimmed)).toList();
  }

  void dispose() {
    youtubeRepository.clearCache();
  }
}
