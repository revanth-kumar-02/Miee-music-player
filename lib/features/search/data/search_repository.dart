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
  Future<List<YouTubeVideo>> searchYouTube(String query, {SearchRankingConfig? config}) async {
    final rawVideos = await youtubeRepository.search(query);
    return SearchDeduplicator.deduplicateAndRank(
      rawVideos,
      query: query,
      config: config ?? const SearchRankingConfig(filterDerivativeEdits: true),
    );
  }

  /// Searches verified online artists via Curated catalog, Deezer, and YouTube Music channels.
  Future<List<ArtistModel>> searchArtists(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final results = await Future.wait([
      artistRepository.searchArtists(cleanQuery).catchError((_) => <ArtistModel>[]),
      youtubeRepository.searchArtists(cleanQuery).catchError((_) => <ArtistModel>[]),
    ]);

    final deezerCurated = results[0];
    final ytArtists = results[1];

    return mergeAndDeduplicateArtists(
      curatedAndDeezer: deezerCurated,
      youtubeArtists: ytArtists,
      query: cleanQuery,
    );
  }

  /// Merges and deduplicates artist results across providers:
  /// - Preserves stable identities (Deezer ID, YouTube Channel ID).
  /// - Enriches portrait URLs when verified curated images exist.
  /// - Deduplicates identical canonical entities without merging distinct artists.
  static List<ArtistModel> mergeAndDeduplicateArtists({
    required List<ArtistModel> curatedAndDeezer,
    required List<ArtistModel> youtubeArtists,
    required String query,
  }) {
    final seenIds = <String>{};
    final seenCanonicalNames = <String>{};
    final merged = <ArtistModel>[];

    String canonical(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanQuery = query.trim().toLowerCase();
    final queryCanonical = canonical(cleanQuery);

    // 1. Process Curated / Deezer artists first (they have verified discography metadata)
    for (final artist in curatedAndDeezer) {
      if (artist.id.isEmpty) continue;
      final cName = canonical(artist.name);

      var effectiveArtist = artist;
      if (!artist.hasValidImage) {
        final curated = DeezerArtistRepository.findCuratedByName(artist.name);
        if (curated != null && curated.hasValidImage) {
          effectiveArtist = artist.copyWith(imageUrl: curated.imageUrl);
        }
      }

      if (seenIds.add(effectiveArtist.id)) {
        if (cName.isNotEmpty) seenCanonicalNames.add(cName);
        merged.add(effectiveArtist);
      }
    }

    // 2. Process YouTube artist channels
    for (final ytArtist in youtubeArtists) {
      if (ytArtist.id.isEmpty) continue;
      final cName = canonical(ytArtist.name);

      // If an artist with the exact same canonical name is already present from Deezer/curated
      if (cName.isNotEmpty && seenCanonicalNames.contains(cName)) {
        final index = merged.indexWhere((a) => canonical(a.name) == cName);
        if (index >= 0 && !merged[index].hasValidImage && ytArtist.hasValidImage) {
          merged[index] = merged[index].copyWith(imageUrl: ytArtist.imageUrl);
        }
        continue;
      }

      // Check if matches curated list by name to inherit verified high-res portrait
      var effectiveArtist = ytArtist;
      final curated = DeezerArtistRepository.findCuratedByName(ytArtist.name);
      if (curated != null) {
        effectiveArtist = ytArtist.copyWith(
          imageUrl: curated.hasValidImage ? curated.imageUrl : ytArtist.imageUrl,
          languages: curated.languages.isNotEmpty ? curated.languages : ytArtist.languages,
        );
      }

      if (seenIds.add(effectiveArtist.id)) {
        if (cName.isNotEmpty) seenCanonicalNames.add(cName);
        merged.add(effectiveArtist);
      }
    }

    // Prioritize exact or prefix matches to query
    merged.sort((a, b) {
      final aName = a.name.toLowerCase();
      final bName = b.name.toLowerCase();
      final aExact = aName == cleanQuery || canonical(aName) == queryCanonical;
      final bExact = bName == cleanQuery || canonical(bName) == queryCanonical;
      if (aExact && !bExact) return -1;
      if (!aExact && bExact) return 1;

      final aStarts = aName.startsWith(cleanQuery);
      final bStarts = bName.startsWith(cleanQuery);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;

      return b.fanCount.compareTo(a.fanCount);
    });

    return merged;
  }

  /// Searches verified online albums for matching artist entities.
  Future<List<ArtistAlbum>> searchAlbums(String query, {List<ArtistModel>? matchedArtists}) async {
    final cleanQuery = query.trim().toLowerCase();
    final artists = (matchedArtists != null && matchedArtists.isNotEmpty)
        ? matchedArtists
        : await searchArtists(cleanQuery);

    final resultAlbums = <ArtistAlbum>[];
    final seenAlbumTitles = <String>{};

    for (final artist in artists.take(2)) {
      try {
        final deezerId = (int.tryParse(artist.id) != null)
            ? artist.id
            : (DeezerArtistRepository.findCuratedByName(artist.name)?.id ?? '');
        if (deezerId.isNotEmpty) {
          final albums = await artistRepository.getArtistAlbums(deezerId);
          for (final alb in albums) {
            if (seenAlbumTitles.add(alb.title.toLowerCase())) {
              resultAlbums.add(alb);
            }
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
