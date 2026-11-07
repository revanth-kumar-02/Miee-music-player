import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../history/data/supabase_listening_history_repository.dart';
import '../domain/affinity_calculator.dart';
import '../domain/user_taste_profile.dart';

/// Repository responsible for persisting, caching, and updating deterministic
/// [UserTasteProfile] records in Hive with strict account isolation.
class TasteProfileRepository {
  final SupabaseListeningHistoryRepository _historyRepo;
  final AffinityCalculator _affinityCalculator;
  final Duration _cacheTtl;

  TasteProfileRepository({
    required SupabaseListeningHistoryRepository historyRepo,
    AffinityCalculator? affinityCalculator,
    Duration cacheTtl = const Duration(hours: 4),
  })  : _historyRepo = historyRepo,
        _affinityCalculator = affinityCalculator ?? const AffinityCalculator(),
        _cacheTtl = cacheTtl;

  String _profileStorageKey(String userId) => 'taste_profile_$userId';

  /// Invalidates the cached taste profile for [userId], forcing the next
  /// read to recompute with the latest listening events.
  void invalidateCache(String? userId) {
    if (userId == null || userId.isEmpty) return;
    try {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      box.delete(_profileStorageKey(userId));
    } catch (e) {
      debugPrint('[TasteProfileRepository] Error invalidating cache: $e');
    }
  }

  /// Retrieves the user's taste profile.
  /// If [forceRefresh] is true or the cached profile is expired/missing,
  /// recalculates it from the listening history and updates Hive.
  Future<UserTasteProfile> getProfile(
    String userId, {
    bool forceRefresh = false,
  }) async {
    if (userId.isEmpty) {
      return UserTasteProfile.empty('');
    }

    if (!forceRefresh) {
      final cached = await _getCachedProfile(userId);
      if (cached != null) {
        final age = DateTime.now().difference(cached.lastUpdated);
        if (age < _cacheTtl) {
          return cached;
        }
      }
    }

    return recalculateProfile(userId);
  }

  /// Forces a complete recomputation of the user's taste profile from their
  /// authenticated listening history, saving the result to Hive.
  Future<UserTasteProfile> recalculateProfile(String userId) async {
    if (userId.isEmpty) {
      return UserTasteProfile.empty('');
    }

    try {
      // Pull recent listening events scoped strictly to this userId (limit 200 events)
      final events = await _historyRepo.getRecentHistory(limit: 200, uid: userId);

      final profile = _affinityCalculator.computeTasteProfile(
        userId,
        events,
        referenceTime: DateTime.now(),
      );

      await _saveProfile(profile);
      return profile;
    } catch (e, st) {
      debugPrint('[TasteProfileRepository] Error calculating profile: $e\n$st');
      // If recalculation fails, attempt returning cached copy before empty fallback
      final cached = await _getCachedProfile(userId);
      return cached ?? UserTasteProfile.empty(userId);
    }
  }

  /// Removes the cached profile for the given user (e.g. on account deletion or sign-out cleanup).
  Future<void> clearProfile(String userId) async {
    if (userId.isEmpty) return;
    try {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      await box.delete(_profileStorageKey(userId));
    } catch (e) {
      debugPrint('[TasteProfileRepository] Error clearing profile for $userId: $e');
    }
  }

  Future<UserTasteProfile?> _getCachedProfile(String userId) async {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      final raw = box.get(_profileStorageKey(userId));
      if (raw != null && raw is Map) {
        return UserTasteProfile.fromMap(raw);
      }
    } catch (e) {
      debugPrint('[TasteProfileRepository] Error reading cached profile: $e');
    }
    return null;
  }

  Future<void> _saveProfile(UserTasteProfile profile) async {
    try {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      await box.put(_profileStorageKey(profile.userId), profile.toMap());
    } catch (e) {
      debugPrint('[TasteProfileRepository] Error saving profile to Hive: $e');
    }
  }
}

