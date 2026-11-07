import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../domain/daily_mix.dart';

/// Repository managing local persistence and retrieval of [DailyMixSnapshot]
/// records in Hive with strict account isolation.
class DailyMixRepository {
  final Box<dynamic>? _injectedBox;
  final Map<String, Future<void>> _writeLocks = {};

  DailyMixRepository({Box<dynamic>? box}) : _injectedBox = box;

  Box<dynamic> get _box {
    if (_injectedBox != null) return _injectedBox!;
    if (Hive.isBoxOpen(HiveBoxes.dailyMixes)) {
      return Hive.box<dynamic>(HiveBoxes.dailyMixes);
    }
    if (Hive.isBoxOpen(HiveBoxes.profile)) {
      return Hive.box<dynamic>(HiveBoxes.profile);
    }
    throw StateError('Neither ${HiveBoxes.dailyMixes} nor ${HiveBoxes.profile} is open');
  }

  static String storageKey(String userId) {
    final cleanUid = userId.trim().isEmpty ? 'guest' : userId.trim();
    return 'daily_mix_snapshot_$cleanUid';
  }

  Future<T> _withLock<T>(String key, Future<T> Function() action) async {
    final previous = _writeLocks[key] ?? Future.value();
    final completer = Completer<void>();
    _writeLocks[key] = completer.future;

    try {
      await previous;
    } catch (_) {
      // Ignore previous errors in write chain
    }

    try {
      return await action();
    } finally {
      completer.complete();
      if (identical(_writeLocks[key], completer.future)) {
        unawaited(_writeLocks.remove(key));
      }
    }
  }

  /// Retrieves the saved snapshot for [userId].
  Future<DailyMixSnapshot?> getSnapshot(String userId) async {
    try {
      final key = storageKey(userId);
      final raw = _box.get(key);
      if (raw != null && raw is Map) {
        return DailyMixSnapshot.fromMap(raw);
      }
    } catch (e) {
      debugPrint('[DailyMixRepository] Error reading snapshot for $userId: $e');
    }
    return null;
  }

  /// Saves [snapshot] strictly under the snapshot owner's user key with monotonic
  /// overwrite protection and serialized write execution.
  Future<bool> saveSnapshot(DailyMixSnapshot snapshot) async {
    final key = storageKey(snapshot.userId);
    return _withLock<bool>(key, () async {
      try {
        final existing = await getSnapshot(snapshot.userId);
        if (existing != null && existing.isNotEmpty) {
          // Reject older or identical-timestamp incoming generations
          if (existing.generatedAt.isAfter(snapshot.generatedAt)) {
            debugPrint('[DailyMixRepository] Monotonic guard: Rejecting snapshot write for ${snapshot.userId}. Existing (${existing.generatedAt}) is newer than incoming (${snapshot.generatedAt}).');
            return false;
          }
          if (existing.generatedAt.isAtSameMomentAs(snapshot.generatedAt)) {
            debugPrint('[DailyMixRepository] Monotonic guard: Rejecting snapshot write for ${snapshot.userId}. Identical generatedAt timestamp.');
            return false;
          }
        }

        // Test serialization before touching persistence
        final map = snapshot.toMap();
        await _box.put(key, map);
        return true;
      } catch (e) {
        debugPrint('[DailyMixRepository] Error saving snapshot for ${snapshot.userId}: $e');
        rethrow;
      }
    });
  }

  /// Clears the saved snapshot for [userId] (e.g. on account sign-out or account wipe).
  Future<void> clearSnapshot(String userId) async {
    try {
      final key = storageKey(userId);
      await _box.delete(key);
    } catch (e) {
      debugPrint('[DailyMixRepository] Error clearing snapshot for $userId: $e');
    }
  }

  /// Evaluates whether [snapshot] exists, is non-empty, and belongs to [targetLocalDate] ('YYYY-MM-DD').
  bool isSnapshotValidForDate(DailyMixSnapshot? snapshot, String targetLocalDate) {
    if (snapshot == null || snapshot.isEmpty) return false;
    return snapshot.localDate == targetLocalDate;
  }
}

