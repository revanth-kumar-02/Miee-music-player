import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/firestore_user_profile_repository.dart';
import '../domain/user_profile.dart';

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return FirestoreUserProfileRepository();
});

class UserProfileState {
  final UserProfile? profile;
  final bool isLoading;
  final String? errorMessage;

  const UserProfileState({
    this.profile,
    this.isLoading = false,
    this.errorMessage,
  });

  UserProfileState copyWith({
    UserProfile? profile,
    bool? isLoading,
    String? errorMessage,
  }) {
    return UserProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class UserProfileNotifier extends StateNotifier<UserProfileState> {
  final Ref _ref;
  final UserProfileRepository _repository;

  UserProfileNotifier(this._ref, this._repository)
      : super(const UserProfileState(isLoading: true)) {
    _listenToAuth();
  }

  void _listenToAuth() {
    _ref.listen(currentAuthUserProvider, (previous, next) {
      if (next == null) {
        state = const UserProfileState(profile: null, isLoading: false);
      } else if (previous?.uid != next.uid) {
        loadProfile(next.uid);
      }
    });

    final currentUser = _ref.read(currentAuthUserProvider);
    if (currentUser != null) {
      loadProfile(currentUser.uid);
    } else {
      state = const UserProfileState(profile: null, isLoading: false);
    }
  }

  Future<void> loadProfile(String uid) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final profile = await _repository.getUserProfile(uid);
      state = UserProfileState(profile: profile, isLoading: false);
    } catch (e) {
      state = UserProfileState(
        profile: null,
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repository.saveUserProfile(profile);
      state = UserProfileState(profile: profile, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  void updateProfileLocally(UserProfile profile) {
    state = UserProfileState(profile: profile, isLoading: false);
  }

  Future<void> clearCache(String uid) async {
    await _repository.clearCache(uid);
    state = const UserProfileState(profile: null, isLoading: false);
  }
}

final userProfileNotifierProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfileState>((ref) {
  final repo = ref.watch(userProfileRepositoryProvider);
  return UserProfileNotifier(ref, repo);
});

final currentUserProfileProvider = Provider<UserProfile?>((ref) {
  return ref.watch(userProfileNotifierProvider).profile;
});
