import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../domain/search_deduplicator.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/data/youtube_repository.dart';
import 'local_search_service.dart';

/// Central search repository orchestrating local fuzzy matches, YouTube API queries,
/// online artist discovery, suggestions, and persistent search history in Hive.
class SearchRepository {
  final LocalSearchService localSearch;
  final YouTubeRepository youtubeRepository;
  final ArtistRepository artistRepository;

  SearchRepository({
    LocalSearchService? localSearch,
    YouTubeRepository? youtubeRepository,
    ArtistRepository? artistRepository,
  })  : localSearch = localSearch ?? LocalSearchService(),
        youtubeRepository = youtubeRepository ?? YouTubeRepository(),
        artistRepository = artistRepository ?? DeezerArtistRepository();

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

  /// Performs online YouTube query and applies canonical-song deduplication and ranking.
  Future<List<YouTubeVideo>> searchYouTube(String query) async {
    final rawVideos = await youtubeRepository.search(query);
    return SearchDeduplicator.deduplicateAndRank(rawVideos, query: query);
  }

  /// Searches verified online artists via Deezer / curated catalog.
  Future<List<ArtistModel>> searchArtists(String query) async {
    return artistRepository.searchArtists(query);
  }

  /// Searches verified online albums for matching artist entities.
  Future<List<ArtistAlbum>> searchAlbums(String query, {List<ArtistModel>? matchedArtists}) async {
    final cleanQuery = query.trim().toLowerCase();
    final artists = (matchedArtists != null && matchedArtists.isNotEmpty)
        ? matchedArtists
        : await artistRepository.searchArtists(cleanQuery);

    final resultAlbums = <ArtistAlbum>[];
    final seenAlbumTitles = <String>{};

    for (final artist in artists.take(2)) {
      try {
        final albums = await artistRepository.getArtistAlbums(artist.id);
        for (final alb in albums) {
          if (seenAlbumTitles.add(alb.title.toLowerCase())) {
            resultAlbums.add(alb);
          }
        }
      } catch (_) {}
    }

    return resultAlbums;
  }

  /// Fetches auto-complete suggestions from history and online provider.
  Future<List<String>> getSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final lower = trimmed.toLowerCase();
    final history = getRecentSearches()
        .where((s) => s.toLowerCase().contains(lower))
        .toList();
    if (history.length >= 5) return history.take(5).toList();

    try {
      final online = await youtubeRepository.getSuggestions(trimmed);
      final combined = <String>{...history, ...online}.toList();
      return combined.take(6).toList();
    } catch (_) {
      return history;
    }
  }

  void dispose() {
    youtubeRepository.clearCache();
  }
}
