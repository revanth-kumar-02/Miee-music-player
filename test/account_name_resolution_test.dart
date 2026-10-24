import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'dart:io';

import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/features/auth/domain/auth_user.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile_repository.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';

class FakeUserProfileRepository implements UserProfileRepository {
  UserProfile? _storedProfile;

  @override
  Future<void> clearCache(String uid) async {
    _storedProfile = null;
  }

  @override
  Future<UserProfile?> getUserProfile(String uid) async {
    return _storedProfile;
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    _storedProfile = profile;
  }

  @override
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
    String? displayName,
    String? email,
  }) async {
    final existing = await getUserProfile(uid);
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

    final base = existing ??
        UserProfile.initial(
          uid: uid,
          email: email ?? '',
          displayName: effectiveName,
        );

    final updated = base.copyWith(
      displayName: effectiveName,
      email: email ?? existing?.email ?? '',
      onboardingCompleted: true,
      selectedArtistIds: artists.map((a) => a.id).toList(),
      selectedArtists: artists,
      updatedAt: DateTime.now(),
    );
    _storedProfile = updated;
    return updated;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_profile_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveBoxes.profile);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Account Name Preservation & Onboarding Resolution', () {
    test('1. completeOnboarding preserves provided user name "rev" when profile was null', () async {
      final repo = FakeUserProfileRepository();
      const artists = [
        ArtistSummary(id: '1', name: 'Coldplay', imageUrl: ''),
        ArtistSummary(id: '2', name: 'Imagine Dragons', imageUrl: ''),
        ArtistSummary(id: '3', name: 'Lana Del Rey', imageUrl: ''),
      ];

      final profile = await repo.completeOnboarding(
        uid: 'user_rev_123',
        artists: artists,
        displayName: 'rev',
        email: 'rev@example.com',
      );

      expect(profile.displayName, equals('rev'));
      expect(profile.email, equals('rev@example.com'));
      expect(profile.onboardingCompleted, isTrue);
      expect(profile.selectedArtists.length, equals(3));
    });

    test('2. completeOnboarding does not overwrite existing "rev" with placeholder', () async {
      final repo = FakeUserProfileRepository();
      await repo.saveUserProfile(
        UserProfile.initial(
          uid: 'user_rev_123',
          email: 'rev@example.com',
          displayName: 'rev',
        ),
      );

      const artists = [
        ArtistSummary(id: '1', name: 'Coldplay', imageUrl: ''),
        ArtistSummary(id: '2', name: 'Imagine Dragons', imageUrl: ''),
        ArtistSummary(id: '3', name: 'Lana Del Rey', imageUrl: ''),
      ];

      final profile = await repo.completeOnboarding(
        uid: 'user_rev_123',
        artists: artists,
        displayName: null, // No override passed
        email: null,
      );

      expect(profile.displayName, equals('rev'));
      expect(profile.onboardingCompleted, isTrue);
    });

    test('3. ProfileController hydrates "rev" when initialized with authUser present', () async {
      final fakeRepo = FakeUserProfileRepository();
      final container = ProviderContainer(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(
            const AuthUser(
              uid: 'user_rev_123',
              email: 'rev@example.com',
              displayName: 'rev',
            ),
          ),
        ],
      );

      final profile = container.read(profileProvider);
      expect(profile.displayName, equals('rev'));
      expect(profile.username, equals('rev'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      container.dispose();
    });

    test('4. UserProfileNotifier.loadProfile heals placeholder name with authUser displayName', () async {
      final fakeRepo = FakeUserProfileRepository();
      // Suppose Firestore had a profile with placeholder 'Miee Listener'
      await fakeRepo.saveUserProfile(
        UserProfile.initial(
          uid: 'user_rev_123',
          email: 'rev@example.com',
          displayName: 'Miee Listener',
        ),
      );

      final container = ProviderContainer(
        overrides: [
          userProfileRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(
            const AuthUser(
              uid: 'user_rev_123',
              email: 'rev@example.com',
              displayName: 'rev',
            ),
          ),
        ],
      );

      // Trigger loadProfile
      await container.read(userProfileNotifierProvider.notifier).loadProfile('user_rev_123');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final loadedProfile = container.read(currentUserProfileProvider);
      expect(loadedProfile, isNotNull);
      expect(loadedProfile!.displayName, equals('rev'));

      // Also verify local profileProvider synced
      final localProfile = container.read(profileProvider);
      expect(localProfile.displayName, equals('rev'));

      container.dispose();
    });
  });
}
