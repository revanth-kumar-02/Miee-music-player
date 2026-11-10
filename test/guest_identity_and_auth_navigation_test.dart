import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive/hive.dart';
import 'package:Miee/app/router/app_router.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/features/auth/domain/auth_user.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/profile/data/hive_profile_repository.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_guest_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>(HiveBoxes.profile);
    await Hive.openBox<dynamic>(HiveBoxes.preferences);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Guest Profile Identity & Persistence Tests', () {
    test('1. ProfileModel.guestProfile creates profile with Guest name and null username', () {
      final guest = ProfileModel.guestProfile();
      expect(guest.displayName, equals('Guest'));
      expect(guest.username, isNull);
      expect(guest.isGuest, isTrue);
      expect(guest.userId, isNull);
    });

    test('2. HiveProfileRepository returns Guest profile when isGuest is true even if rev was stored in active_profile', () async {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      // Simulate previously logged in user "rev" stored in active_profile
      await box.put('active_profile', {
        'displayName': 'rev',
        'username': 'rev',
        'favoriteGenre': 'Rock',
        'favoriteArtist': 'Lana Del Rey',
        'createdDate': DateTime.now().toIso8601String(),
        'lastOpened': DateTime.now().toIso8601String(),
      });

      final repo = HiveProfileRepository(box);

      // In guest mode, it must return Guest without leaking "rev" or "@rev"
      final guestProfile = await repo.getProfile(isGuest: true);
      expect(guestProfile.displayName, equals('Guest'));
      expect(guestProfile.username, isNull);
      expect(guestProfile.isGuest, isTrue);

      // The registered user profile in active_profile remains untouched
      final userProfile = await repo.getProfile(isGuest: false);
      expect(userProfile.displayName, equals('rev'));
      expect(userProfile.username, equals('rev'));
    });

    test('3. Saving guest preferences persists to guest_profile without corrupting active_profile', () async {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      await box.put('active_profile', {
        'displayName': 'rev',
        'username': 'rev',
        'userId': 'rev_user_id',
        'preferredSource': 'preferLocal',
      });

      final repo = HiveProfileRepository(box);
      final guest = ProfileModel.guestProfile().copyWith(
        preferredSource: 'preferYouTube',
      );

      await repo.saveProfile(guest);

      // Guest profile updated
      final loadedGuest = await repo.getProfile(isGuest: true);
      expect(loadedGuest.displayName, equals('Guest'));
      expect(loadedGuest.username, isNull);
      expect(loadedGuest.preferredSource, equals('preferYouTube'));

      // Active profile preserved
      final loadedUser = await repo.getProfile(userId: 'rev_user_id', isGuest: false);
      expect(loadedUser.displayName, equals('rev'));
      expect(loadedUser.preferredSource, equals('preferLocal'));
    });

    test('4. guestModeProvider persists to Hive and survives state changes', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(guestModeProvider), isFalse);

      container.read(guestModeProvider.notifier).state = true;
      expect(container.read(guestModeProvider), isTrue);

      final prefBox = Hive.box<dynamic>(HiveBoxes.preferences);
      expect(prefBox.get('is_guest_mode'), isTrue);

      container.read(guestModeProvider.notifier).state = false;
      expect(prefBox.get('is_guest_mode'), isFalse);
    });

    test('5. profileProvider initializes with Guest profile when in guest mode', () async {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      await box.put('active_profile', {
        'displayName': 'rev',
        'username': 'rev',
      });

      final container = ProviderContainer(
        overrides: [
          guestModeProvider.overrideWith((ref) => true),
          currentAuthUserProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      final profile = container.read(profileProvider);
      expect(profile.displayName, equals('Guest'));
      expect(profile.username, isNull);
      expect(profile.isGuest, isTrue);
    });
  });

  group('Authentication Navigation & GoRouter Tests', () {
    test('6. AppRouterNotifier allows guest user to navigate to /login and /register', () {
      final container = ProviderContainer(
        overrides: [
          guestModeProvider.overrideWith((ref) => true),
          currentAuthUserProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      final routerNotifier = container.read(appRouterNotifierProvider);

      // Guest going to login screen
      final loginRedirect = routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/login'));
      expect(loginRedirect, isNull, reason: 'Guest should be allowed to open /login');

      // Guest going to register screen
      final registerRedirect = routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/register'));
      expect(registerRedirect, isNull, reason: 'Guest should be allowed to open /register');

      // Guest going to home screen
      final homeRedirect = routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/home'));
      expect(homeRedirect, isNull, reason: 'Guest should be allowed to open /home');
    });

    test('7. AppRouterNotifier prevents authenticated user from re-entering /login', () {
      final container = ProviderContainer(
        overrides: [
          guestModeProvider.overrideWith((ref) => false),
          currentAuthUserProvider.overrideWith((ref) => const AuthUser(
            uid: '123',
            email: 'user@test.com',
            displayName: 'Real User',
          )),
          userProfileNotifierProvider.overrideWith((ref) => FakeUserProfileNotifier(
            UserProfileState(
              profile: UserProfile.initial(
                uid: '123',
                email: 'user@test.com',
                displayName: 'Real User',
              ).copyWith(onboardingCompleted: true),
              isLoading: false,
            ),
          )),
        ],
      );
      addTearDown(container.dispose);

      final routerNotifier = container.read(appRouterNotifierProvider);

      final redirect = routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/login'));
      expect(redirect, equals('/home'), reason: 'Authenticated user with onboarding done should redirect to /home');
    });

    test('8. Transition from guest session to authenticated user loads real identity', () async {
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      await box.put('profile_auth_user_999', {
        'displayName': 'Rev Developer',
        'username': 'rev_dev',
        'userId': 'auth_user_999',
      });

      final container = ProviderContainer(
        overrides: [
          guestModeProvider.overrideWith((ref) => true),
          currentAuthUserProvider.overrideWith((ref) => null),
        ],
      );
      addTearDown(container.dispose);

      // Initially guest
      expect(container.read(profileProvider).displayName, equals('Guest'));
      expect(container.read(profileProvider).username, isNull);

      // Switch to authenticated user
      container.read(guestModeProvider.notifier).state = false;
      final controller = container.read(profileProvider.notifier);

      final realProfile = await container.read(profileRepositoryProvider).getProfile(
        userId: 'auth_user_999',
        isGuest: false,
      );
      controller.state = realProfile;

      expect(container.read(profileProvider).displayName, equals('Rev Developer'));
      expect(container.read(profileProvider).username, equals('rev_dev'));
      expect(container.read(profileProvider).isGuest, isFalse);
    });
  });
}

class FakeGoRouterState implements GoRouterState {
  @override
  final String matchedLocation;

  FakeGoRouterState(this.matchedLocation);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBuildContext extends BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class FakeUserProfileNotifier extends StateNotifier<UserProfileState> implements UserProfileNotifier {
  FakeUserProfileNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
