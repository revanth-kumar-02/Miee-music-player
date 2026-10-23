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

/// Manages the debounced local and unified online search logic.
class SearchNotifier extends StateNotifier<SearchState> {
  final SearchRepository _repo;
  final Ref _ref;
  Timer? _debounceTimer;
  Timer? _suggestionDebounceTimer;
  int _searchRequestId = 0;

  SearchNotifier(this._repo, this._ref) : super(const SearchState()) {
    _loadRecentSearches();
  }

  void _loadRecentSearches() {
    state = state.copyWith(recentSearches: _repo.getRecentSearches());
  }

  /// Sets the active category filter ('All', 'Songs', 'Artists', 'Albums').
  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  /// Updates search text query, running debounced suggestions (150ms) and searches (300ms).
  void updateQuery(String query) {
    _debounceTimer?.cancel();
    _suggestionDebounceTimer?.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchRequestId++;
      state = state.copyWith(
        query: '',
        suggestions: const [],
        localSongs: const [],
        localAlbums: const [],
        localArtists: const [],
        localPlaylists: const [],
        youtubeResults: const [],
        onlineArtists: const [],
        onlineAlbums: const [],
        isLocalLoading: false,
        isYouTubeLoading: false,
        isArtistsLoading: false,
        errorMessage: null,
      );
      return;
    }

    final currentReqId = ++_searchRequestId;

    state = state.copyWith(
      query: query,
      isLocalLoading: true,
      isYouTubeLoading: true,
      isArtistsLoading: true,
      errorMessage: null,
    );

    // Suggestions autocomplete updates (150ms)
    _suggestionDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
      if (currentReqId != _searchRequestId) return;
      final suggestions = await _repo.getSuggestions(trimmed);
      if (currentReqId == _searchRequestId) {
        state = state.copyWith(suggestions: suggestions);
      }
    });

    // Main search debounce (300ms)
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _runSearch(trimmed, currentReqId);
    });
  }

  /// Forces an immediate search, bypassing debounce.
  void searchNow(String query) {
    _debounceTimer?.cancel();
    _suggestionDebounceTimer?.cancel();

    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchRequestId++;
      state = const SearchState();
      return;
    }

    final currentReqId = ++_searchRequestId;

    state = state.copyWith(
      query: query,
      isLocalLoading: true,
      isYouTubeLoading: true,
      isArtistsLoading: true,
      errorMessage: null,
    );

    _runSearch(trimmed, currentReqId);
    addHistory(trimmed);
  }

  Future<void> _runSearch(String query, int reqId) async {
    // 1. Run Local Database Search (In-memory, instant)
    final library = _ref.read(mediaLibraryServiceProvider);
    final songs = _repo.localSearch.searchSongs(library.songs, query);
    final albums = _repo.localSearch.searchAlbums(library.albums, query);
    final artists = _repo.localSearch.searchArtists(library.artists, query);
    final playlists = _repo.localSearch.searchPlaylists(library.playlists, query);

    if (reqId == _searchRequestId) {
      state = state.copyWith(
        localSongs: songs,
        localAlbums: albums,
        localArtists: artists,
        localPlaylists: playlists,
        isLocalLoading: false,
      );
    }

    // 2. Concurrently run Online Artists + Albums search
    try {
      final artists = await _repo.searchArtists(query);
      if (reqId == _searchRequestId) {
        state = state.copyWith(
          onlineArtists: artists,
          isArtistsLoading: false,
        );
      }

      // If artist matches exist, fetch albums
      final onlineAlbums = await _repo.searchAlbums(query, matchedArtists: artists);
      if (reqId == _searchRequestId) {
        state = state.copyWith(
          onlineAlbums: onlineAlbums,
        );
      }
    } catch (_) {
      if (reqId == _searchRequestId) {
        state = state.copyWith(isArtistsLoading: false);
      }
    }

    // 3. Run YouTube Song Search (Network API)
    try {
      final youtube = await _repo.searchYouTube(query);
      if (reqId == _searchRequestId) {
        state = state.copyWith(
          youtubeResults: youtube,
          isYouTubeLoading: false,
          errorMessage: null,
        );
      }
    } catch (e) {
      if (reqId == _searchRequestId) {
        final errStr = e.toString().toLowerCase();
        final message = (errStr.contains('socketexception') ||
                errStr.contains('failed host lookup') ||
                errStr.contains('network') ||
                errStr.contains('connection refused') ||
                errStr.contains('connection timed out') ||
                errStr.contains('clientexception'))
            ? 'No internet connection. Please check your network and try again.'
            : e.toString().replaceFirst('Exception: ', '');
        state = state.copyWith(
          youtubeResults: const [],
          isYouTubeLoading: false,
          errorMessage: message,
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

/// Riverpod state provider for unified search handling.
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.watch(searchRepositoryProvider);
  return SearchNotifier(repo, ref);
});
