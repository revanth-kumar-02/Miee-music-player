import 'dart:math';

/// Domain helper that implements non-destructive merge resolution strategies for offline-first sync.
class ConflictResolver {
  /// Merges two list of items based on a unique identifier key.
  /// If item exists in both lists, the mergeFn resolves them.
  static List<T> mergeLists<T, K>({
    required List<T> local,
    required List<T> remote,
    required K Function(T) idSelector,
    required T Function(T, T) mergeFn,
  }) {
    final Map<K, T> merged = {};

    for (final item in local) {
      final key = idSelector(item);
      merged[key] = item;
    }

    for (final item in remote) {
      final key = idSelector(item);
      if (merged.containsKey(key)) {
        merged[key] = mergeFn(merged[key]!, item);
      } else {
        merged[key] = item;
      }
    }

    return merged.values.toList();
  }

  /// Resolve conflict between two timestamps (favoring the newest change).
  static T resolveLatest<T>({
    required T local,
    required DateTime localTime,
    required T remote,
    required DateTime remoteTime,
  }) {
    return localTime.isAfter(remoteTime) ? local : remote;
  }
}
