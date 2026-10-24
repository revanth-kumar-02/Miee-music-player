import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync/supabase_config.dart';
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

  AuthController(this._ref) : super(const AuthState()) {
    _init();
  }

  void _init() {
    if (SupabaseConfig.hasActiveSupabase) {
      try {
        final client = Supabase.instance.client;
        state = AuthState(user: client.auth.currentUser);

        client.auth.onAuthStateChange.listen((data) {
          if (!mounted) return;
          if (data.event == AuthChangeEvent.signedOut) {
            state = const AuthState(user: null, isLoading: false, isOfflineMock: false);
          } else {
            state = state.copyWith(user: data.session?.user, isLoading: false);
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
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
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
        return true;
      } else {
        state = const AuthState(
          isOfflineMock: true,
          user: null,
        );
        return true;
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
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

      // 3. Perform real sign out via Supabase
      if (SupabaseConfig.hasActiveSupabase) {
        await _ref.read(authRepositoryProvider).signOut();
      }

      // 4. Update auth state to fully signed out
      state = const AuthState(user: null, isLoading: false, isOfflineMock: false);

      // 5. Invalidate profile state so user-specific caches do not linger
      _ref.invalidate(userProfileNotifierProvider);
      _ref.invalidate(currentUserProfileProvider);
      _ref.invalidate(profileProvider);
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
