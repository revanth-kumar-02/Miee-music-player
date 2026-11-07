import 'package:hive/hive.dart';
import 'offline_operation.dart';

/// Manages caching of offline database modification logs to Hive and their processing order.
class OfflineOperationQueue {
  final Box<dynamic> _box;

  OfflineOperationQueue(this._box);

  /// Returns active pending operations (excluding dead-lettered ones by default), sorted chronologically.
  List<OfflineOperation> getOperations({bool includeDeadLetter = false}) {
    final values = _box.values.toList();
    final allOps = values
        .map((e) => OfflineOperation.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .toList();

    final filtered = includeDeadLetter
        ? allOps
        : allOps.where((op) => !op.isDeadLetter).toList();

    return filtered..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  /// Returns quarantined/dead-lettered operations that failed permanently or exceeded retry limits.
  List<OfflineOperation> getDeadLetterOperations() {
    final values = _box.values.toList();
    return values
        .map((e) => OfflineOperation.fromMap(Map<dynamic, dynamic>.from(e as Map)))
        .where((op) => op.isDeadLetter)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> addOperation(OfflineOperation op) async {
    await _box.put(op.id, op.toMap());
  }

  Future<void> removeOperation(String id) async {
    await _box.delete(id);
  }

  /// Updates retry count and error message for a transient failure.
  Future<void> updateRetry(String id, {required int retryCount, required String lastError}) async {
    final raw = _box.get(id);
    if (raw is Map) {
      final op = OfflineOperation.fromMap(Map<dynamic, dynamic>.from(raw));
      final updated = op.copyWith(
        retryCount: retryCount,
        lastError: lastError,
      );
      await _box.put(id, updated.toMap());
    }
  }

  /// Marks an operation as dead-lettered so it does not block the active queue.
  Future<void> markDeadLetter(String id, {String? error, int? retryCount}) async {
    final raw = _box.get(id);
    if (raw is Map) {
      final op = OfflineOperation.fromMap(Map<dynamic, dynamic>.from(raw));
      final updated = op.copyWith(
        isDeadLetter: true,
        lastError: error ?? op.lastError,
        retryCount: retryCount ?? op.retryCount,
      );
      await _box.put(id, updated.toMap());
    }
  }

  /// Quarantines an unassigned or ambiguous legacy operation.
  Future<void> quarantineOperation(String id, {required String reason}) async {
    await markDeadLetter(id, error: reason);
  }

  /// Recovers a dead-lettered operation back into active replay.
  /// If the operation is a parent (e.g. playlist_create), also recovers all dependent
  /// operations (e.g. playlist_song_add, playlist_song_remove, playlist_tracks_reorder)
  /// that were quarantined due to parent failure.
  Future<void> recoverDeadLetter(String id) async {
    final raw = _box.get(id);
    if (raw is Map) {
      final op = OfflineOperation.fromMap(Map<dynamic, dynamic>.from(raw));
      final updated = op.copyWith(
        isDeadLetter: false,
        retryCount: 0,
        clearLastError: true,
      );
      await _box.put(id, updated.toMap());

      // If recovering a parent playlist_create, also recover its quarantined dependent operations
      if (op.type == 'playlist_create') {
        final parentPlaylistId = op.payload['id']?.toString();
        if (parentPlaylistId != null && parentPlaylistId.isNotEmpty) {
          final allDeadLetters = getDeadLetterOperations();
          for (final child in allDeadLetters) {
            final childParentId = child.payload['playlistId']?.toString();
            if (childParentId == parentPlaylistId &&
                (child.lastError?.contains('Parent playlist creation failed') ?? false)) {
              final updatedChild = child.copyWith(
                isDeadLetter: false,
                retryCount: 0,
                clearLastError: true,
              );
              await _box.put(child.id, updatedChild.toMap());
            }
          }
        }
      }
    }
  }

  /// Alias for recovering an operation and all associated dependent operations.
  Future<void> recoverOperationWithDependents(String id) => recoverDeadLetter(id);

  Future<void> clearAll() async {
    await _box.clear();
  }

  bool get isEmpty => _box.isEmpty;
}
