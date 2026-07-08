import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/sync/supabase_config.dart';

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
      final client = Supabase.instance.client;
      state = AuthState(user: client.auth.currentUser);
      
      client.auth.onAuthStateChange.listen((data) {
        state = state.copyWith(user: data.session?.user);
      });
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
    state = state.copyWith(isLoading: true);
    try {
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
        state = AuthState(
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
    state = state.copyWith(isLoading: true);
    try {
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
        state = AuthState(
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
    state = state.copyWith(isLoading: true);
    try {
      if (SupabaseConfig.hasActiveSupabase) {
        await Supabase.instance.client.auth.signOut();
      }
      state = const AuthState(isOfflineMock: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(ref);
});
