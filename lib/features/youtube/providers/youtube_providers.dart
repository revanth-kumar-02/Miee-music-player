import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../data/youtube_repository.dart';
import '../domain/youtube_model.dart';

// ── Repository Provider ──────────────────────────────────────────────────────

final youtubeRepositoryProvider = Provider<YouTubeRepository>((ref) {
  return YouTubeRepository();
});

// ── Search History State & Notifier ──────────────────────────────────────────

class YouTubeSearchHistoryNotifier extends StateNotifier<List<String>> {
  static const String _prefKey = 'youtube_search_history';
  static const int _maxEntries = 20;

  Box get _box => Hive.box(HiveBoxes.preferences);

  YouTubeSearchHistoryNotifier() : super([]) {
    _load();
  }

  void _load() {
    final list = _box.get(_prefKey);
    if (list is List) {
      state = list.cast<String>();
    }
  }

  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final updated = List<String>.from(state)
      ..removeWhere((q) => q.toLowerCase() == trimmed.toLowerCase())
      ..insert(0, trimmed);

    if (updated.length > _maxEntries) {
      updated.removeRange(_maxEntries, updated.length);
    }

    state = updated;
    await _box.put(_prefKey, updated);
  }

  Future<void> removeEntry(String query) async {
    final updated = List<String>.from(state)
      ..removeWhere((q) => q == query);
    state = updated;
    await _box.put(_prefKey, updated);
  }

  Future<void> clearAll() async {
    state = [];
    await _box.delete(_prefKey);
  }
}

final youtubeSearchHistoryProvider =
    StateNotifierProvider<YouTubeSearchHistoryNotifier, List<String>>((ref) {
  return YouTubeSearchHistoryNotifier();
});

// ── Search State Wrapper ─────────────────────────────────────────────────────

class YouTubeSearchState {
  final List<YouTubeVideo> results;
  final bool isLoading;
  final String? error;

  const YouTubeSearchState({
    this.results = const [],
    this.isLoading = false,
    this.error,
  });

  YouTubeSearchState copyWith({
    List<YouTubeVideo>? results,
    bool? isLoading,
    String? error,
  }) {
    return YouTubeSearchState(
      results: results ?? this.results,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  bool get isEmpty => !isLoading && error == null && results.isEmpty;
}

// ── Search Controller & Notifier ─────────────────────────────────────────────

class YouTubeSearchNotifier extends StateNotifier<YouTubeSearchState> {
  final YouTubeRepository _repository;
  Timer? _debounceTimer;

  YouTubeSearchNotifier(this._repository) : super(const YouTubeSearchState());

  /// Sets the query and performs a debounced search (300ms).
  void searchDebounced(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();

    if (trimmed.isEmpty) {
      state = const YouTubeSearchState();
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _runSearch(trimmed);
    });
  }

  /// Forces an immediate search, ignoring the debounce.
  void searchNow(String query) {
    _debounceTimer?.cancel();
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = const YouTubeSearchState();
      return;
    }
    state = state.copyWith(isLoading: true, error: null);
    _runSearch(trimmed);
  }

  Future<void> _runSearch(String query) async {
    try {
      final results = await _repository.search(query);
      state = YouTubeSearchState(results: results, isLoading: false);
    } catch (e) {
      state = YouTubeSearchState(
        results: const [],
        isLoading: false,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  void clear() {
    _debounceTimer?.cancel();
    state = const YouTubeSearchState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

final youtubeSearchProvider =
    StateNotifierProvider.autoDispose<YouTubeSearchNotifier, YouTubeSearchState>((ref) {
  final repo = ref.watch(youtubeRepositoryProvider);
  return YouTubeSearchNotifier(repo);
});

final youtubeSearchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
