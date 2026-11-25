import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../core/storage/hive_service.dart';
import '../../../core/sync/supabase_config.dart';
import '../../../core/sync/sync_manager.dart';
import '../../library/providers/library_providers.dart';
import '../../profile/presentation/profile_controller.dart';
import '../../profile/providers/profile_providers.dart';
import '../../rooms/providers/room_providers.dart';
import '../providers/auth_providers.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? errorMessage;
  final bool isOfflineMock;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
    this.isOfflineMock = false,
  });

  AuthState copyWith({
    User? user,
    bool? isLoading,
    String? errorMessage,
    bool? isOfflineMock,
  }) {
    return AuthState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      isOfflineMock: isOfflineMock ?? this.isOfflineMock,
    );
  }
}

class AuthController extends StateNotifier<AuthState> {
  final Ref _ref;
  StreamSubscription<dynamic>? _authStateSub;

  AuthController(this._ref) : super(const AuthState()) {
    _init();
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }

  Future<void> _handleAuthenticatedUser(String userId) async {
    try {
      String? previousUserId;
      Box<dynamic>? prefsBox;
      if (Hive.isBoxOpen(HiveBoxes.preferences)) {
        prefsBox = Hive.box<dynamic>(HiveBoxes.preferences);
        previousUserId = prefsBox.get(PreferenceKeys.lastSignedInUserId) as String?;
      }

      if (previousUserId != null && previousUserId != userId) {
        await HiveService.clearUserDataBoxes();
        _invalidateUserProviders();
      } else if (previousUserId == null) {
        await _ref.read(syncManagerProvider).migrateGuestPlaylists(userId);
      }

      if (prefsBox != null) {
        await prefsBox.put(PreferenceKeys.lastSignedInUserId, userId);
      }
    } catch (e) {
      debugPrint('[AuthController] Account transition handling error: $e');
    }
  }

  void _invalidateUserProviders() {
    _ref.invalidate(userPlaylistsProvider);
    _ref.invalidate(favoritesProvider);
    _ref.invalidate(recentlyPlayedProvider);
    _ref.invalidate(searchHistoryProvider);
    _ref.invalidate(userProfileNotifierProvider);
    _ref.invalidate(currentUserProfileProvider);
    _ref.invalidate(profileProvider);
  }

  void _init() {
    if (SupabaseConfig.hasActiveSupabase) {
      try {
        final client = Supabase.instance.client;
        state = AuthState(user: client.auth.currentUser);

        _authStateSub = client.auth.onAuthStateChange.listen((data) {
          if (!mounted) return;
          if (data.event == AuthChangeEvent.signedOut) {
            state = const AuthState(user: null, isLoading: false, isOfflineMock: false);
          } else {
            final u = data.session?.user;
            state = state.copyWith(user: u, isLoading: false);
            if (u != null) {
              unawaited(_handleAuthenticatedUser(u.id));
            }
          }
        });
      } catch (_) {
        // Uninitialized client in test environments
        state = const AuthState();
      }
    } else {
      // Local Guest Auth Mode
      state = const AuthState(isOfflineMock: true);
    }
  }

  bool get isAuthenticated => state.user != null || state.isOfflineMock;

  String? get currentUserId {
    if (state.user != null) return state.user!.id;
    if (state.isOfflineMock) return 'offline_guest_user';
    return null;
  }

  Future<bool> signIn(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _ref.read(guestModeProvider.notifier).state = false;
      if (SupabaseConfig.hasActiveSupabase) {
        final client = Supabase.instance.client;
        final response = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        state = AuthState(user: response.user);
        if (response.user != null) {
          unawaited(_handleAuthenticatedUser(response.user!.id));
        }
        return true;
      } else {
        // Mock offline sign in
        state = const AuthState(
          isOfflineMock: true,
          user: null,
        );
        return true;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _cleanErrorMessage(e));
      return false;
    }
  }

  Future<bool> signUp(String email, String password, String displayName) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      _ref.read(guestModeProvider.notifier).state = false;
      if (SupabaseConfig.hasActiveSupabase) {
        final client = Supabase.instance.client;
        final response = await client.auth.signUp(
          email: email,
          password: password,
          data: {'display_name': displayName},
        );
        state = AuthState(user: response.user);
        if (response.user != null) {
          unawaited(_handleAuthenticatedUser(response.user!.id));
        }
        return true;
      } else {
        state = const AuthState(
          isOfflineMock: true,
          user: null,
        );
        return true;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _cleanErrorMessage(e));
      return false;
    }
  }

  String _cleanErrorMessage(dynamic e) {
    final str = e.toString().toLowerCase();
    if (str.contains('socketexception') ||
        str.contains('failed host lookup') ||
        str.contains('no address associated') ||
        str.contains('network is unreachable') ||
        str.contains('connection refused') ||
        str.contains('connection timed out') ||
        str.contains('clientexception')) {
      return 'Unable to reach the server. Please check your internet connection or Private DNS settings, or tap "Continue as Guest".';
    }
    if (str.contains('invalid login credentials') || str.contains('invalid credentials')) {
      return 'Incorrect email or password. Please try again.';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }

  Future<void> signOut() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      // 1. Leave any active collaborative listening room
      try {
        await _ref.read(roomControllerProvider.notifier).leaveRoom();
      } catch (e) {
        debugPrint('[AuthController] Note: Room leave during signOut: $e');
      }

      // 2. Reset guest mode
      _ref.read(guestModeProvider.notifier).state = false;

      // 3. Best-effort flush of pending offline sync operations before clearing local user data
      if (SupabaseConfig.hasActiveSupabase) {
        try {
          await _ref.read(syncManagerProvider).triggerSync(force: true);
        } catch (e) {
          debugPrint('[AuthController] Best-effort pre-signOut sync note: $e');
        }
        await _ref.read(authRepositoryProvider).signOut();
      }

      // 4. Clear user-scoped local Hive caches to prevent cross-account data leakage
      try {
        await HiveService.clearUserDataBoxes();
        if (Hive.isBoxOpen(HiveBoxes.preferences)) {
          await Hive.box<dynamic>(HiveBoxes.preferences)
              .delete(PreferenceKeys.lastSignedInUserId);
        }
      } catch (e) {
        debugPrint('[AuthController] Note: Hive cleanup during signOut: $e');
      }

      // 5. Update auth state to fully signed out
      state = const AuthState(user: null, isLoading: false, isOfflineMock: false);

      // 6. Invalidate user-scoped providers so stale caches do not linger
      _invalidateUserProviders();
    } catch (e) {
      if (!mounted) rethrow;
      final errorMsg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(isLoading: false, errorMessage: errorMsg);
      rethrow;
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});
