import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../onboarding/domain/artist_model.dart';
import '../domain/user_profile.dart';

abstract class UserProfileRepository {
  Future<UserProfile?> getUserProfile(String uid);
  Future<void> saveUserProfile(UserProfile profile);
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
  });
  Future<void> clearCache(String uid);
}

class FirestoreUserProfileRepository implements UserProfileRepository {
  FirebaseFirestore? get _firestore {
    if (!FirebaseService.isConfigured) return null;
    try {
      return FirebaseFirestore.instance;
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
      debugPrint('[UserProfileRepository] Cache read error: $e');
    }

    // 2. Fetch from Firestore if available
    final db = _firestore;
    if (db == null) {
      return cachedProfile;
    }

    try {
      final doc = await db.collection('users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final profile = UserProfile.fromMap(uid, doc.data()!);
        // Update local cache
        await _box.put(_cacheKey(uid), profile.toMap());
        return profile;
      }
    } catch (e) {
      debugPrint('[UserProfileRepository] Firestore read error ($e). Using cached profile.');
    }

    return cachedProfile;
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    // Save to local cache
    await _box.put(_cacheKey(profile.uid), profile.toMap());

    final db = _firestore;
    if (db == null) return;

    try {
      await db.collection('users').doc(profile.uid).set(
            profile.toMap(),
            SetOptions(merge: true),
          );
    } catch (e) {
      debugPrint('[UserProfileRepository] Firestore save error: $e');
      rethrow;
    }
  }

  @override
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
  }) async {
    if (artists.length < 3 || artists.length > 5) {
      throw ArgumentError('You must select between 3 and 5 favorite artists.');
    }

    // Fetch existing profile or create base
    final existing = await getUserProfile(uid);
    final artistIds = artists.map((a) => a.id).toList();

    final updated = (existing ?? UserProfile.initial(uid: uid, email: '', displayName: ''))
        .copyWith(
      onboardingCompleted: true,
      selectedArtistIds: artistIds,
      selectedArtists: artists,
      updatedAt: DateTime.now(),
    );

    // Save to local cache
    await _box.put(_cacheKey(uid), updated.toMap());

    // Save to Firestore
    final db = _firestore;
    if (db != null) {
      try {
        await db.collection('users').doc(uid).set({
          'displayName': updated.displayName,
          'email': updated.email,
          'avatarUrl': updated.avatarUrl,
          'onboardingCompleted': true,
          'selectedArtistIds': artistIds,
          'selectedArtists': artists.map((a) => a.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
          'schemaVersion': updated.schemaVersion,
        }, SetOptions(merge: true));
        debugPrint('[UserProfileRepository] Onboarding saved successfully to Firestore for $uid');
      } catch (e) {
        debugPrint('[UserProfileRepository] Failed to save onboarding to Firestore: $e');
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
