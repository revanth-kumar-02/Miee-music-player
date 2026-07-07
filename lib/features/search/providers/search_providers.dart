import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../media/providers/media_providers.dart';
import '../data/search_repository.dart';
import '../domain/search_results.dart';

/// Debounce duration — short enough to feel instant, long enough to avoid
/// excessive re-computation while the user is still typing.
const _kDebounceDuration = Duration(milliseconds: 280);

// ── Repository provider ───────────────────────────────────────────────────────

/// Singleton [SearchRepository] provider.
final searchRepositoryProvider = Provider<SearchRepository>((ref) {
  return SearchRepository();
});

// ── Search state ──────────────────────────────────────────────────────────────

/// Snapshot of the search feature state.
class SearchState {
  /// The current raw query string.
  final String query;

  /// Grouped results for the current query.
  final SearchResults results;

  /// True while the 280ms debounce timer is running.
  final bool isLoading;

  const SearchState({
    this.query = '',
    this.results = const SearchResults(),
    this.isLoading = false,
  });

  SearchState copyWith({
    String? query,
    SearchResults? results,
    bool? isLoading,
  }) =>
      SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
        isLoading: isLoading ?? this.isLoading,
      );

  bool get hasQuery => query.trim().isNotEmpty;
}

// ── Search notifier ───────────────────────────────────────────────────────────

/// Manages search query lifecycle with debounce and synchronous in-memory search.
class SearchNotifier extends StateNotifier<SearchState> {
  final SearchRepository _repo;
  final Ref _ref;
  Timer? _debounceTimer;

  SearchNotifier(this._repo, this._ref) : super(const SearchState());

  /// Called every time the search bar text changes.
  ///
  /// Sets loading immediately, then debounces the actual search.
  void updateQuery(String query) {
    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }

    state = state.copyWith(query: query, isLoading: true);

    _debounceTimer = Timer(_kDebounceDuration, () {
      _runSearch(query);
    });
  }

  /// Forces an immediate search without waiting for the debounce.
  ///
  /// Use this on search bar submit / keyboard done action.
  void searchNow(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      state = const SearchState();
      return;
    }
    state = state.copyWith(query: query, isLoading: true);
    _runSearch(query);
  }

  void _runSearch(String query) {
    final library = _ref.read(mediaLibraryServiceProvider);
    final results = _repo.search(query, library);
    state = state.copyWith(results: results, isLoading: false);
  }

  /// Clears the current query and results.
  void clear() {
    _debounceTimer?.cancel();
    state = const SearchState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// Primary search provider — UI widgets read this for query, results, loading.
final searchNotifierProvider =
    StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  final repo = ref.watch(searchRepositoryProvider);
  return SearchNotifier(repo, ref);
});

// ── Convenience derived providers ─────────────────────────────────────────────

/// True while the debounce timer is running.
final searchLoadingProvider = Provider<bool>((ref) {
  return ref.watch(searchNotifierProvider).isLoading;
});

/// The current [SearchResults] (empty when no query is active).
final searchResultsProvider = Provider<SearchResults>((ref) {
  return ref.watch(searchNotifierProvider).results;
});

/// The raw query string currently in the search bar.
final searchQueryProvider = Provider<String>((ref) {
  return ref.watch(searchNotifierProvider).query;
});
