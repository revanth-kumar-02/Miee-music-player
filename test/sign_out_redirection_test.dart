import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:Miee/app/router/app_router.dart';
import 'package:Miee/features/auth/domain/auth_repository.dart';
import 'package:Miee/features/auth/domain/auth_user.dart';
import 'package:Miee/features/auth/presentation/auth_controller.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/domain/user_profile_repository.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';

/// Fake GoRouterState implementing the matchedLocation needed by AppRouterNotifier.redirect
class FakeGoRouterState implements GoRouterState {
  @override
  final String matchedLocation;

  FakeGoRouterState(this.matchedLocation);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test implementation of AuthRepository for hermetic testing.
class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;
  bool shouldFailSignOut = false;
  int signOutCalls = 0;

  FakeAuthRepository({AuthUser? initialUser}) : _currentUser = initialUser;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  void emitUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }

  @override
  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final user = AuthUser(uid: 'test_user_id', email: email, displayName: 'Test User');
    emitUser(user);
    return user;
  }

  @override
  Future<AuthUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final user = AuthUser(uid: 'test_user_id', email: email, displayName: displayName);
    emitUser(user);
    return user;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (shouldFailSignOut) {
      throw Exception('Network error during sign out');
    }
    emitUser(null);
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  group('AppRouterNotifier Redirection Tests', () {
    test('Unauthenticated user is redirected to /login from protected routes', () {
      final fakeRepo = FakeAuthRepository(initialUser: null);
      final containerRef = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(null),
          guestModeProvider.overrideWith((ref) => false),
        ],
      );

      final routerNotifier = containerRef.read(appRouterNotifierProvider);

      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/home')), equals('/login'));
      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/settings')), equals('/login'));
      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/profile')), equals('/login'));

      containerRef.dispose();
      fakeRepo.dispose();
    });

    test('Unauthenticated user is permitted to view /login and /register', () {
      final fakeRepo = FakeAuthRepository(initialUser: null);
      final containerRef = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(null),
          guestModeProvider.overrideWith((ref) => false),
        ],
      );

      final routerNotifier = containerRef.read(appRouterNotifierProvider);

      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/login')), isNull);
      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/register')), isNull);

      containerRef.dispose();
      fakeRepo.dispose();
    });

    test('Splash screen (/) is never redirected regardless of auth state', () {
      final fakeRepo = FakeAuthRepository(initialUser: null);
      final containerRef = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(null),
          guestModeProvider.overrideWith((ref) => false),
        ],
      );

      final routerNotifier = containerRef.read(appRouterNotifierProvider);

      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/')), isNull);

      containerRef.dispose();
      fakeRepo.dispose();
    });

    test('Guest mode allows protected music routes but redirects auth pages to /home', () {
      final fakeRepo = FakeAuthRepository(initialUser: null);
      final containerRef = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(null),
          guestModeProvider.overrideWith((ref) => true),
        ],
      );

      final routerNotifier = containerRef.read(appRouterNotifierProvider);

      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/home')), isNull);
      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/login')), equals('/home'));
      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/register')), equals('/home'));

      containerRef.dispose();
      fakeRepo.dispose();
    });

    test('Authenticated user with complete onboarding is redirected from /login to /home', () {
      final fakeRepo = FakeAuthRepository(
        initialUser: const AuthUser(uid: 'user_1', email: 'test@example.com'),
      );
      final containerRef = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(
            const AuthUser(uid: 'user_1', email: 'test@example.com'),
          ),
          guestModeProvider.overrideWith((ref) => false),
          userProfileNotifierProvider.overrideWith((ref) {
            final notifier = UserProfileNotifier(ref, FakeUserProfileRepository());
            notifier.state = UserProfileState(
              profile: UserProfile.initial(
                uid: 'user_1',
                email: 'test@example.com',
                displayName: 'Test',
              ).copyWith(onboardingCompleted: true),
              isLoading: false,
            );
            return notifier;
          }),
        ],
      );

      final routerNotifier = containerRef.read(appRouterNotifierProvider);

      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/login')), equals('/home'));

      containerRef.dispose();
      fakeRepo.dispose();
    });

    test('Authenticated user with incomplete onboarding is redirected to /onboarding', () {
      final fakeRepo = FakeAuthRepository(
        initialUser: const AuthUser(uid: 'user_2', email: 'new@example.com'),
      );
      final containerRef = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
          currentAuthUserProvider.overrideWithValue(
            const AuthUser(uid: 'user_2', email: 'new@example.com'),
          ),
          guestModeProvider.overrideWith((ref) => false),
          userProfileNotifierProvider.overrideWith((ref) {
            final notifier = UserProfileNotifier(ref, FakeUserProfileRepository());
            notifier.state = UserProfileState(
              profile: UserProfile.initial(
                uid: 'user_2',
                email: 'new@example.com',
                displayName: 'New User',
              ).copyWith(onboardingCompleted: false),
              isLoading: false,
            );
            return notifier;
          }),
        ],
      );

      final routerNotifier = containerRef.read(appRouterNotifierProvider);

      expect(routerNotifier.redirect(FakeBuildContext(), FakeGoRouterState('/home')), equals('/onboarding'));

      containerRef.dispose();
      fakeRepo.dispose();
    });
  });

  group('AuthController Sign Out Tests', () {
    test('Sign out resets guestModeProvider, calls repository, and clears state', () async {
      final fakeRepo = FakeAuthRepository(
        initialUser: const AuthUser(uid: 'user_3', email: 'active@example.com'),
      );
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      // Start as guest
      container.read(guestModeProvider.notifier).state = true;
      expect(container.read(guestModeProvider), isTrue);

      final authNotifier = container.read(authControllerProvider.notifier);

      // Execute sign out
      await authNotifier.signOut();

      // Verify guest mode is cleared
      expect(container.read(guestModeProvider), isFalse);

      // Verify repository signOut was called
      expect(fakeRepo.signOutCalls, equals(1));

      // Verify AuthState is completely unauthenticated
      final authState = container.read(authControllerProvider);
      expect(authState.user, isNull);
      expect(authState.isOfflineMock, isFalse);
      expect(authState.isLoading, isFalse);
      expect(authNotifier.isAuthenticated, isFalse);

      container.dispose();
      fakeRepo.dispose();
    });

    test('Sign out rethrows exception on network or backend failure', () async {
      final fakeRepo = FakeAuthRepository(
        initialUser: const AuthUser(uid: 'user_4', email: 'error@example.com'),
      )..shouldFailSignOut = true;

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      final authNotifier = container.read(authControllerProvider.notifier);

      // Sign out must rethrow the error for UI feedback
      await expectLater(
        () => authNotifier.signOut(),
        throwsA(isA<Exception>()),
      );

      container.dispose();
      fakeRepo.dispose();
    });

    test('currentAuthUserProvider does not revive cached user after stream emits null', () async {
      final fakeRepo = FakeAuthRepository(
        initialUser: const AuthUser(uid: 'user_5', email: 'stream@example.com'),
      );

      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeRepo),
        ],
      );

      // Initial user emission
      fakeRepo.emitUser(const AuthUser(uid: 'user_5', email: 'stream@example.com'));
      await container.pump();

      // Sign out: stream emits null
      fakeRepo.emitUser(null);
      await container.pump();

      final currentUser = container.read(currentAuthUserProvider);
      expect(currentUser, isNull, reason: 'Must not resurrect user from cache after null emission');

      container.dispose();
      fakeRepo.dispose();
    });
  });
}

class FakeBuildContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeUserProfileRepository implements UserProfileRepository {
  @override
  Future<UserProfile?> getUserProfile(String uid) async => null;

  @override
  Future<void> saveUserProfile(UserProfile profile) async {}

  @override
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
    String? displayName,
    String? email,
  }) async {
    return UserProfile.initial(uid: uid, email: email ?? '', displayName: displayName ?? '');
  }

  @override
  Future<void> clearCache(String uid) async {}
}
