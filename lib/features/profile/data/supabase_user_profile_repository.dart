import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../core/sync/supabase_config.dart';
import '../../onboarding/domain/artist_model.dart';
import '../domain/user_profile.dart';
import '../domain/user_profile_repository.dart';

class SupabaseUserProfileRepository implements UserProfileRepository {
  SupabaseClient? get _client {
    if (!SupabaseConfig.hasActiveSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  Box<dynamic> get _box => Hive.box<dynamic>(HiveBoxes.profile);

  String _cacheKey(String uid) => 'user_profile_$uid';

  @override
  Future<UserProfile?> getUserProfile(String uid) async {
    // 1. Try local cache first for instant UI response
    UserProfile? cachedProfile;
    try {
      final cachedMap = _box.get(_cacheKey(uid));
      if (cachedMap is Map) {
        cachedProfile = UserProfile.fromMap(
          uid,
          Map<String, dynamic>.from(cachedMap),
        );
      }
    } catch (e) {
      debugPrint('[SupabaseUserProfileRepository] Cache read error: $e');
    }

    // 2. Fetch from Supabase if available
    final client = _client;
    if (client == null) {
      return cachedProfile;
    }

    try {
      final res = await client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      if (res != null) {
        final profile = UserProfile(
          uid: uid,
          displayName: res['display_name'] as String? ?? 'Miee Listener',
          email: res['email'] as String? ?? '',
          avatarUrl: res['avatar_url'] as String?,
          onboardingCompleted: res['onboarding_completed'] as bool? ?? false,
          selectedArtistIds: (res['selected_artist_ids'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          selectedArtists: (res['selected_artists'] as List<dynamic>?)
                  ?.map((a) =>
                      ArtistSummary.fromMap(Map<String, dynamic>.from(a as Map)))
                  .toList() ??
              const [],
          createdAt: res['created_at'] != null
              ? DateTime.parse(res['created_at'] as String)
              : DateTime.now(),
          updatedAt: res['updated_at'] != null
              ? DateTime.parse(res['updated_at'] as String)
              : DateTime.now(),
        );

        // Update local cache
        await _box.put(_cacheKey(uid), profile.toMap());
        return profile;
      }
    } catch (e) {
      debugPrint('[SupabaseUserProfileRepository] Supabase read error ($e). Using cached profile.');
    }

    return cachedProfile;
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    // Save to local cache
    await _box.put(_cacheKey(profile.uid), profile.toMap());

    final client = _client;
    if (client == null) return;

    try {
      await client.from('profiles').upsert({
        'id': profile.uid,
        'display_name': profile.displayName,
        'email': profile.email,
        'avatar_url': profile.avatarUrl,
        'onboarding_completed': profile.onboardingCompleted,
        'selected_artist_ids': profile.selectedArtistIds,
        'selected_artists':
            profile.selectedArtists.map((a) => a.toMap()).toList(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('[SupabaseUserProfileRepository] Supabase save error: $e');
      rethrow;
    }
  }

  @override
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
    String? displayName,
    String? email,
  }) async {
    if (artists.length < 3 || artists.length > 5) {
      throw ArgumentError('You must select between 3 and 5 favorite artists.');
    }

    // Fetch existing profile or create base
    final existing = await getUserProfile(uid);
    final artistIds = artists.map((a) => a.id).toList();

    final cleanDisplayName = (displayName != null &&
            displayName.trim().isNotEmpty &&
            displayName.trim() != 'Miee Listener' &&
            displayName.trim() != 'Miee User')
        ? displayName.trim()
        : null;
    final cleanExistingName = (existing != null &&
            existing.displayName.trim().isNotEmpty &&
            existing.displayName.trim() != 'Miee Listener' &&
            existing.displayName.trim() != 'Miee User')
        ? existing.displayName.trim()
        : null;

    final effectiveName = cleanDisplayName ??
        cleanExistingName ??
        (existing?.displayName.isNotEmpty == true
            ? existing!.displayName
            : 'Miee Listener');

    final cleanEmail = (email != null && email.trim().isNotEmpty)
        ? email.trim()
        : (existing?.email ?? '');

    final base = existing ??
        UserProfile.initial(
          uid: uid,
          email: cleanEmail,
          displayName: effectiveName,
        );

    final updated = base.copyWith(
      displayName: effectiveName,
      email: cleanEmail,
      onboardingCompleted: true,
      selectedArtistIds: artistIds,
      selectedArtists: artists,
      updatedAt: DateTime.now(),
    );

    // Save to local cache
    await _box.put(_cacheKey(uid), updated.toMap());

    // Save to Supabase
    final client = _client;
    if (client != null) {
      try {
        await client.from('profiles').upsert({
          'id': uid,
          'display_name': updated.displayName,
          'email': updated.email,
          'avatar_url': updated.avatarUrl,
          'onboarding_completed': true,
          'selected_artist_ids': artistIds,
          'selected_artists': artists.map((a) => a.toMap()).toList(),
          'updated_at': DateTime.now().toIso8601String(),
        });
        debugPrint('[SupabaseUserProfileRepository] Onboarding saved successfully to Supabase for $uid');
      } catch (e) {
        debugPrint('[SupabaseUserProfileRepository] Failed to save onboarding to Supabase: $e');
        rethrow;
      }
    }

    return updated;
  }

  @override
  Future<void> clearCache(String uid) async {
    try {
      await _box.delete(_cacheKey(uid));
    } catch (_) {}
  }
}
