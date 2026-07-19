import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../media/providers/media_providers.dart';
import '../data/search_repository.dart';
import '../domain/search_state.dart';

/// Singleton [SearchRepository] provider.
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  final repo = SearchRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

/// Manages the debounced local and online search logic.
class SearchNotifier extends StateNotifier<SearchState> {
  final SearchRepository _repo;
  final Ref _ref;
  Timer? _debounceTimer;
  Timer? _suggestionDebounceTimer;

  SearchNotifier(this._repo, this._ref) : super(const SearchState()) {
    _loadRecentSearches();
  }

  void _loadRecentSearches() {
    state = state.copyWith(recentSearches: _repo.getRecentSearches());
  }

  /// Updates search text query, running debounced suggestions (150ms) and searches (300ms).
  void updateQuery(String query) {
    _debounceTimer?.cancel();
    _suggestionDebounceTimer?.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        query: '',
        suggestions: const [],
        localSongs: const [],
        localAlbums: const [],
        localArtists: const [],
        localPlaylists: const [],
        youtubeResults: const [],
        isLocalLoading: false,
        isYouTubeLoading: false,
        errorMessage: null,
      );
      return;
    }

    state = state.copyWith(
      query: query,
      isLocalLoading: true,
      isYouTubeLoading: true,
      errorMessage: null,
    );

    // Suggestions autocomplete updates (150ms)
    _suggestionDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
      if (state.query != query) return;
      final suggestions = await _repo.getSuggestions(trimmed);
      if (state.query == query) {
        state = state.copyWith(suggestions: suggestions);
      }
    });

    // Main search debounce (300ms)
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _runSearch(trimmed);
    });
  }

  /// Forces an immediate search, bypassing debounce.
  void searchNow(String query) {
    _debounceTimer?.cancel();
    _suggestionDebounceTimer?.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(
      query: query,
      isLocalLoading: true,
      isYouTubeLoading: true,
      errorMessage: null,
    );

    _runSearch(trimmed);
    addHistory(trimmed);
  }

  Future<void> _runSearch(String query) async {
    // 1. Run Local Database Search (In-memory, synchronous feel)
    final library = _ref.read(mediaLibraryServiceProvider);
    final songs = _repo.localSearch.searchSongs(library.songs, query);
    final albums = _repo.localSearch.searchAlbums(library.albums, query);
    final artists = _repo.localSearch.searchArtists(library.artists, query);
    final playlists = _repo.localSearch.searchPlaylists(library.playlists, query);

    if (state.query.trim().toLowerCase() == query.toLowerCase()) {
      state = state.copyWith(
        localSongs: songs,
        localAlbums: albums,
        localArtists: artists,
        localPlaylists: playlists,
        isLocalLoading: false,
      );
    }

    // 2. Run YouTube Search (Network API)
    try {
      final youtube = await _repo.searchYouTube(query);
      if (state.query.trim().toLowerCase() == query.toLowerCase()) {
        state = state.copyWith(
          youtubeResults: youtube,
          isYouTubeLoading: false,
        );
      }
    } catch (e) {
      if (state.query.trim().toLowerCase() == query.toLowerCase()) {
        state = state.copyWith(
          isYouTubeLoading: false,
          errorMessage: e.toString(),
        );
      }
    }
  }

  /// Stores query in recent searches.
  Future<void> addHistory(String query) async {
    await _repo.addRecentSearch(query);
    _loadRecentSearches();
  }

  /// Removes single search history entry.
  Future<void> removeHistory(String query) async {
    await _repo.removeRecentSearch(query);
    _loadRecentSearches();
  }

  /// Wipes entire search history box.
  Future<void> clearHistory() async {
    await _repo.clearRecentSearches();
    _loadRecentSearches();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _suggestionDebounceTimer?.cancel();
    super.dispose();
  }
}

/// riverpod state provider for unified search handling.
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.watch(searchRepositoryProvider);
  return SearchNotifier(repo, ref);
});
