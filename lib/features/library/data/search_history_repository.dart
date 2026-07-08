import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/hive_boxes.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/offline_operation.dart';

/// Manages persisted recent search queries (latest 20, deduplicated) with cloud synchronization.
class SearchHistoryRepository {
  static const int _maxEntries = 20;
  final Ref _ref;

  SearchHistoryRepository(this._ref);

  Box<String> get _box => Hive.box<String>(HiveBoxes.searchHistory);

  /// Adds [query] to search history. Moves it to top if already present.
  /// Trims to [_maxEntries] if necessary.
  Future<void> addSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Remove existing duplicate.
    final existingKey = _box.keys.cast<dynamic>().firstWhere(
      (k) => _box.get(k) == trimmed,
      orElse: () => null,
    );
    if (existingKey != null) await _box.delete(existingKey);

    // Append as newest entry.
    await _box.add(trimmed);

    // Trim oldest entries beyond limit.
    if (_box.length > _maxEntries) {
      final excess = _box.length - _maxEntries;
      final keysToDelete = _box.keys.take(excess).toList();
      await _box.deleteAll(keysToDelete);
    }

    final op = OfflineOperation(
      id: 'search_add_${trimmed}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'search_add',
      payload: {
        'query': trimmed,
        'timestamp': DateTime.now().toIso8601String(),
      },
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
  }

  /// Returns the last [_maxEntries] queries, newest first.
  List<String> getSearchHistory() {
    return _box.values.toList().reversed.toList(growable: false);
  }

  /// Removes a specific [query] from history.
  Future<void> removeEntry(String query) async {
    final key = _box.keys.cast<dynamic>().firstWhere(
      (k) => _box.get(k) == query,
      orElse: () => null,
    );
    if (key != null) {
      await _box.delete(key);
      
      final op = OfflineOperation(
        id: 'search_rem_${query}_${DateTime.now().millisecondsSinceEpoch}',
        type: 'search_remove',
        payload: {'query': query},
        timestamp: DateTime.now(),
      );
      await _ref.read(syncManagerProvider).queueOperation(op);
    }
  }

  /// Clears all search history.
  Future<void> clearAll() async => _box.clear();
}
