import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import '../../../core/sync/supabase_config.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseClient? get _client {
    if (!SupabaseConfig.hasActiveSupabase) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<AuthUser?> get authStateChanges {
    final client = _client;
    if (client == null) {
      return Stream.value(null);
    }
    return client.auth.onAuthStateChange.map((data) {
      final user = data.session?.user ?? client.auth.currentUser;
      return user != null ? AuthUser.fromSupabase(user) : null;
    });
  }

  @override
  AuthUser? get currentUser {
    final client = _client;
    if (client == null) return null;
    final user = client.auth.currentUser;
    return user != null ? AuthUser.fromSupabase(user) : null;
  }

  @override
  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception('Supabase is not configured. Please verify your Supabase credentials.');
    }

    try {
      final res = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      if (user == null) {
        throw Exception('Sign in failed. Please verify your credentials.');
      }
      return AuthUser.fromSupabase(user);
    } on AuthException catch (e) {
      throw Exception(_mapSupabaseAuthError(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Future<AuthUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final client = _client;
    if (client == null) {
      throw Exception('Supabase is not configured. Please verify your Supabase credentials.');
    }

    try {
      final trimmedName = displayName.trim();
      final res = await client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {
          if (trimmedName.isNotEmpty) 'display_name': trimmedName,
          if (trimmedName.isNotEmpty) 'full_name': trimmedName,
        },
      );
      final user = res.user;
      if (user == null) {
        throw Exception('Account creation failed. Please try again.');
      }
      return AuthUser.fromSupabase(user);
    } on AuthException catch (e) {
      throw Exception(_mapSupabaseAuthError(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    final client = _client;
    if (client == null) {
      throw Exception('Supabase is not configured. Please verify your Supabase credentials.');
    }

    try {
      await client.auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      throw Exception(_mapSupabaseAuthError(e));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client?.auth.signOut();
    } catch (e) {
      debugPrint('[SupabaseAuthRepository] Error during signOut: $e');
    }
  }

  String _mapSupabaseAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid credentials') ||
        msg.contains('wrong password')) {
      return 'Incorrect email or password. Please try again.';
    }
    if (msg.contains('user already registered') || msg.contains('already exists')) {
      return 'An account already exists with this email address.';
    }
    if (msg.contains('weak password') || msg.contains('password should be at least')) {
      return 'Password must be at least 6 characters long.';
    }
    if (msg.contains('invalid email') || msg.contains('unable to validate email')) {
      return 'The provided email address is invalid.';
    }
    if (msg.contains('rate limit') || msg.contains('over_email_send_rate_limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return e.message;
  }
}
