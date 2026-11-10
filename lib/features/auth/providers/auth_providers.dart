import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
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
/// Backed by Hive to persist guest session state across app restarts.
final guestModeProvider = StateProvider<bool>((ref) {
  bool initial = false;
  try {
    if (Hive.isBoxOpen(HiveBoxes.preferences)) {
      initial = Hive.box<dynamic>(HiveBoxes.preferences).get('is_guest_mode', defaultValue: false) as bool? ?? false;
    }
  } catch (_) {}

  // ignore: deprecated_member_use
  ref.listenSelf((previous, next) {
    try {
      if (Hive.isBoxOpen(HiveBoxes.preferences)) {
        Hive.box<dynamic>(HiveBoxes.preferences).put('is_guest_mode', next);
      }
    } catch (_) {}
  });

  return initial;
});
