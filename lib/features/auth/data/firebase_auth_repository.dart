import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart';
import '../../../core/services/firebase_service.dart';
import '../domain/auth_user.dart';

abstract class AuthRepository {
  Stream<AuthUser?> get authStateChanges;
  AuthUser? get currentUser;
  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  });
  Future<AuthUser> signUpWithEmailAndPassword({
    required String email,
    required String password,
    required String displayName,
  });
  Future<void> sendPasswordResetEmail(String email);
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  fb.FirebaseAuth? get _auth {
    if (!FirebaseService.isConfigured) return null;
    try {
      return fb.FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<AuthUser?> get authStateChanges {
    final auth = _auth;
    if (auth == null) {
      return Stream.value(null);
    }
    return auth.authStateChanges().map((user) {
      return user != null ? AuthUser.fromFirebase(user) : null;
    });
  }

  @override
  AuthUser? get currentUser {
    final user = _auth?.currentUser;
    return user != null ? AuthUser.fromFirebase(user) : null;
  }

  @override
  Future<AuthUser> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final auth = _auth;
    if (auth == null) {
      throw Exception(
        FirebaseService.errorMessage ??
            'Firebase is not configured. Please ensure google-services.json is present.',
      );
    }

    try {
      final cred = await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (cred.user == null) {
        throw Exception('Sign in failed. Please verify your credentials.');
      }
      return AuthUser.fromFirebase(cred.user!);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseAuthError(e));
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
    final auth = _auth;
    if (auth == null) {
      throw Exception(
        FirebaseService.errorMessage ??
            'Firebase is not configured. Please ensure google-services.json is present.',
      );
    }

    try {
      final cred = await auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (cred.user == null) {
        throw Exception('Account creation failed. Please try again.');
      }

      final trimmedName = displayName.trim();
      if (trimmedName.isNotEmpty) {
        await cred.user!.updateDisplayName(trimmedName);
        await cred.user!.reload();
      }

      final updatedUser = auth.currentUser ?? cred.user!;
      return AuthUser.fromFirebase(updatedUser);
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseAuthError(e));
    } catch (e) {
      throw Exception(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    final auth = _auth;
    if (auth == null) {
      throw Exception(
        FirebaseService.errorMessage ??
            'Firebase is not configured. Please ensure google-services.json is present.',
      );
    }

    try {
      await auth.sendPasswordResetEmail(email: email.trim());
    } on fb.FirebaseAuthException catch (e) {
      throw Exception(_mapFirebaseAuthError(e));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _auth?.signOut();
    } catch (e) {
      debugPrint('[FirebaseAuthRepository] Error during signOut: $e');
    }
  }

  String _mapFirebaseAuthError(fb.FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'email-already-in-use':
        return 'An account already exists with this email address.';
      case 'invalid-email':
        return 'The provided email address is invalid.';
      case 'weak-password':
        return 'Password must be at least 6 characters long.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network connection issue. Please check your internet connection.';
      default:
        return e.message ??
            'An authentication error occurred (Code: ${e.code}).';
    }
  }
}
