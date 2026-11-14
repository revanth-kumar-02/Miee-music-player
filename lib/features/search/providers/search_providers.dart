import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../media/providers/media_providers.dart';
import '../data/search_repository.dart';
import '../domain/search_state.dart';
import '../domain/search_diagnostics.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../youtube/domain/youtube_model.dart';

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
        liveSuggestions: const [],
        localSongs: const [],
        localAlbums: const [],
        localArtists: const [],
        localPlaylists: const [],
        youtubeResults: const [],
        onlineArtists: const [],
        onlineAlbums: const [],
        onlinePlaylists: const [],
        isLocalLoading: false,
        isYouTubeLoading: false,
        isArtistsLoading: false,
        isPlaylistsLoading: false,
        isSuggestionsLoading: false,
        errorMessage: null,
      );
      return;
    }

    final currentReqId = ++_searchRequestId;
    SearchDiagnostics().recordInput(query: query, reqId: currentReqId);

    // Fast local scan for instant feedback while typing
    final library = _ref.read(mediaLibraryServiceProvider);
    final instantLocalSongs = _repo.localSearch.searchSongs(library.songs, trimmed);
    final instantLocalArtists = _repo.localSearch.searchArtists(library.artists, trimmed);
    final instantLocalAlbums = _repo.localSearch.searchAlbums(library.albums, trimmed);
    final instantLocalPlaylists = _repo.localSearch.searchPlaylists(library.playlists, trimmed);

    final initialSuggestions = <MusicSuggestion>[];
    for (final a in instantLocalArtists.take(2)) {
      initialSuggestions.add(MusicSuggestion(
        id: a.id,
        title: a.name,
        imageUrl: a.artworkPath,
        type: SuggestionType.artist,
        isOnline: false,
        source: 'Local',
        entity: a,
      ));
    }
    for (final s in instantLocalSongs.take(3)) {
      initialSuggestions.add(MusicSuggestion(
        id: s.id,
        title: s.title,
        subtitle: s.artist,
        imageUrl: s.artworkPath,
        type: SuggestionType.song,
        isOnline: false,
        source: 'Local',
        entity: s,
      ));
    }
    for (final alb in instantLocalAlbums.take(1)) {
      initialSuggestions.add(MusicSuggestion(
        id: alb.id,
        title: alb.title,
        subtitle: alb.artist,
        imageUrl: alb.artworkPath,
        type: SuggestionType.album,
        isOnline: false,
        source: 'Local',
        entity: alb,
      ));
    }
    initialSuggestions.add(MusicSuggestion(
      id: 'search_query_$trimmed',
      title: 'Search for "$trimmed"',
      type: SuggestionType.searchQuery,
      entity: trimmed,
    ));

    state = state.copyWith(
      query: query,
      localSongs: instantLocalSongs,
      localAlbums: instantLocalAlbums,
      localArtists: instantLocalArtists,
      localPlaylists: instantLocalPlaylists,
      liveSuggestions: initialSuggestions,
      youtubeResults: const [],
      onlineArtists: const [],
      onlineAlbums: const [],
      onlinePlaylists: const [],
      isLocalLoading: false,
      isYouTubeLoading: true,
      isArtistsLoading: true,
      isPlaylistsLoading: true,
      isSuggestionsLoading: true,
      errorMessage: null,
    );

    // Live music-first suggestions (debounced 120ms)
    _suggestionDebounceTimer = Timer(const Duration(milliseconds: 120), () async {
      if (currentReqId != _searchRequestId) return;
      try {
        final liveMusic = await _repo.getLiveMusicSuggestions(
          query: trimmed,
          localSongs: instantLocalSongs,
          localArtists: instantLocalArtists,
          localAlbums: instantLocalAlbums,
          localPlaylists: instantLocalPlaylists,
        );
        if (currentReqId == _searchRequestId) {
          state = state.copyWith(
            liveSuggestions: liveMusic,
            isSuggestionsLoading: false,
          );
        }
      } catch (_) {
        if (currentReqId == _searchRequestId) {
          state = state.copyWith(isSuggestionsLoading: false);
        }
      }
    });

    // Main search debounce (250ms for snappy response)
    _debounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (currentReqId != _searchRequestId) return;
      SearchDiagnostics().recordDebounceComplete(currentReqId);
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
    SearchDiagnostics().recordInput(query: query, reqId: currentReqId);
    SearchDiagnostics().recordDebounceComplete(currentReqId);

    state = state.copyWith(
      query: query,
      liveSuggestions: const [],
      localSongs: const [],
      localAlbums: const [],
      localArtists: const [],
      localPlaylists: const [],
      youtubeResults: const [],
      onlineArtists: const [],
      onlineAlbums: const [],
      onlinePlaylists: const [],
      isLocalLoading: true,
      isYouTubeLoading: true,
      isArtistsLoading: true,
      isPlaylistsLoading: true,
      isSuggestionsLoading: false,
      errorMessage: null,
    );

    _runSearch(trimmed, currentReqId);
    addHistory(trimmed);
  }

  Future<void> _runSearch(String query, int reqId) async {
    // 1. Run Local Database Search (In-memory, instant <10ms)
    SearchDiagnostics().recordLocalQueryStart(reqId);
    final library = _ref.read(mediaLibraryServiceProvider);
    final songs = _repo.localSearch.searchSongs(library.songs, query);
    final albums = _repo.localSearch.searchAlbums(library.albums, query);
    final artists = _repo.localSearch.searchArtists(library.artists, query);
    final playlists = _repo.localSearch.searchPlaylists(library.playlists, query);

    if (reqId == _searchRequestId) {
      SearchDiagnostics().recordLocalQueryEnd(reqId, resultCount: songs.length);
      state = state.copyWith(
        localSongs: songs,
        localAlbums: albums,
        localArtists: artists,
        localPlaylists: playlists,
        isLocalLoading: false,
      );
    }

    // 2. Concurrently run independent online tasks without blocking YouTube song results
    final ytTask = () async {
      SearchDiagnostics().recordYouTubeRequestStart(reqId);
      final fromCache = _repo.isCached(query);
      try {
        final youtube = await _repo.searchYouTube(query);
        if (reqId == _searchRequestId) {
          SearchDiagnostics().recordYouTubeRequestEnd(
            reqId,
            resultCount: youtube.length,
            fromCache: fromCache,
            success: true,
          );
          SearchDiagnostics().recordFirstResultRendered(reqId);
          SearchDiagnostics().recordResultsDelivered(
            reqId,
            totalResults: youtube.length,
          );
          state = state.copyWith(
            youtubeResults: youtube,
            isYouTubeLoading: false,
            errorMessage: null,
          );
          _enrichArtistsFromSongs(query, youtube, reqId);
          _enrichYouTubeMetadataProgressively(query, youtube, reqId);
        }
      } catch (e) {
        if (reqId == _searchRequestId) {
          SearchDiagnostics().recordYouTubeRequestEnd(
            reqId,
            resultCount: 0,
            fromCache: false,
            success: false,
          );
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
    }();

    final artistsTask = () async {
      try {
        final onlineArtists = await _repo.searchArtists(query);
        if (reqId == _searchRequestId) {
          state = state.copyWith(
            onlineArtists: onlineArtists,
            isArtistsLoading: false,
          );
        }

        final onlineAlbums = await _repo.searchAlbums(query, matchedArtists: onlineArtists);
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
    }();

    final playlistsTask = () async {
      try {
        final playlists = await _repo.searchPlaylists(query);
        if (reqId == _searchRequestId) {
          state = state.copyWith(
            onlinePlaylists: playlists,
            isPlaylistsLoading: false,
          );
        }
      } catch (_) {
        if (reqId == _searchRequestId) {
          state = state.copyWith(isPlaylistsLoading: false);
        }
      }
    }();

    await Future.wait([ytTask, artistsTask, playlistsTask]);
  }

  /// Progressively enriches displayed YouTube results with iTunes artwork & album
  /// in the background without blocking the user interface.
  void _enrichYouTubeMetadataProgressively(
    String query,
    List<YouTubeVideo> rawResults,
    int reqId,
  ) async {
    if (reqId != _searchRequestId || rawResults.isEmpty) return;
    final stopwatch = Stopwatch()..start();
    try {
      final enriched = await _repo.enrichYouTubeResults(rawResults);
      stopwatch.stop();
      if (reqId == _searchRequestId) {
        final enrichedCount =
            enriched.where((v) => v.albumName != null && v.albumName!.isNotEmpty).length;
        SearchDiagnostics().recordEnrichmentEnd(
          reqId,
          durationMs: stopwatch.elapsedMilliseconds,
          enrichedCount: enrichedCount,
        );
        _repo.updateCachedResults(query, enriched);
        state = state.copyWith(youtubeResults: enriched);
      }
    } catch (_) {}
  }

  /// Automatically resolves and displays verified artists from top song results
  /// when a user searches for a song title (e.g. "Brooklyn Baby" -> Lana Del Rey).
  void _enrichArtistsFromSongs(
    String query,
    List<YouTubeVideo> youtube,
    int reqId,
  ) async {
    if (reqId != _searchRequestId || youtube.isEmpty) return;

    final existingArtists = List<ArtistModel>.from(state.onlineArtists);

    // Extract potential artist tokens from top songs
    final candidateNames = <String>[];
    for (final video in youtube.take(5)) {
      final artistName = (video.canonicalArtist ?? video.channelTitle).trim();
      if (artistName.isEmpty) continue;

      final parts = artistName.split(
        RegExp(r'\s*(&|,|\bft\.?\b|\bfeat\.?\b)\s*', caseSensitive: false),
      );
      for (final part in parts) {
        final p = part.trim();
        if (p.isNotEmpty && !candidateNames.contains(p)) {
          candidateNames.add(p);
        }
      }
    }

    final resolvedArtists = <ArtistModel>[];
    for (final name in candidateNames) {
      final curated = DeezerArtistRepository.findCuratedByName(name);
      if (curated != null && !resolvedArtists.any((a) => a.id == curated.id)) {
        resolvedArtists.add(curated);
      } else {
        // Also check if existing online artists already have this artist
        final match = existingArtists.cast<ArtistModel?>().firstWhere(
          (a) => a != null && a.name.toLowerCase() == name.toLowerCase(),
          orElse: () => null,
        );
        if (match != null && !resolvedArtists.any((a) => a.id == match.id)) {
          resolvedArtists.add(match);
        }
      }
    }

    // If candidate artist is not yet in resolvedArtists, query online artist repo
    for (final name in candidateNames.take(2)) {
      if (!resolvedArtists.any((a) => a.name.toLowerCase() == name.toLowerCase())) {
        try {
          final online = await _repo.artistRepository.searchArtists(name);
          if (online.isNotEmpty) {
            final top = online.first;
            if (top.fanCount > 100 || DeezerArtistRepository.findCuratedByName(top.name) != null) {
              if (!resolvedArtists.any((a) => a.id == top.id)) {
                resolvedArtists.add(top);
              }
            }
          }
        } catch (_) {}
      }
    }

    if (resolvedArtists.isNotEmpty && reqId == _searchRequestId) {
      final merged = SearchRepository.mergeAndDeduplicateArtists(
        curatedAndDeezer: [...resolvedArtists, ...existingArtists],
        youtubeArtists: const [],
        query: query,
      );
      state = state.copyWith(onlineArtists: merged);
    }
  }

  @visibleForTesting
  void enrichArtistsFromSongsForTesting(String query, List<YouTubeVideo> youtube) {
    _enrichArtistsFromSongs(query, youtube, _searchRequestId);
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
