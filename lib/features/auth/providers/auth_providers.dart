import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository();
});

final authStateChangesProvider = StreamProvider<AuthUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return repo.authStateChanges;
});

final currentAuthUserProvider = Provider<AuthUser?>((ref) {
  final asyncUser = ref.watch(authStateChangesProvider);
  if (asyncUser.hasValue) {
    return asyncUser.value;
  }
  return ref.read(authRepositoryProvider).currentUser;
});

/// Allows users to explore and play music as a guest without signing in.
final guestModeProvider = StateProvider<bool>((ref) => false);

