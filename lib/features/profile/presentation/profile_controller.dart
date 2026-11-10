import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../auth/domain/auth_user.dart';
import '../../auth/providers/auth_providers.dart';
import '../domain/profile_model.dart';
import '../domain/profile_repository.dart';
import '../domain/user_profile.dart';
import '../providers/profile_providers.dart';
import '../data/hive_profile_repository.dart';

/// Notifier that manages active profile data reactively and persists changes to Hive with background sync.
class ProfileController extends StateNotifier<ProfileModel> {
  final ProfileRepository _repository;
  final Ref _ref;

  ProfileController(this._repository, this._ref, ProfileModel initialProfile) : super(initialProfile) {
    _ref.listen<UserProfile?>(currentUserProfileProvider, (previous, next) {
      if (state.isGuest) return;
      if (next != null &&
          next.displayName.trim().isNotEmpty &&
          next.displayName != 'Miee Listener' &&
          next.displayName != 'Miee User' &&
          state.displayName != next.displayName) {
        updateProfile(
          displayName: next.displayName,
          username: next.displayName.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
          favoriteGenre: state.favoriteGenre,
          favoriteArtist: state.favoriteArtist,
        );
      }
    });

    _ref.listen<AuthUser?>(currentAuthUserProvider, (previous, next) async {
      if (next == null) {
        final isGuest = _ref.read(guestModeProvider);
        if (isGuest || !state.isGuest) {
          final guestProf = await _repository.getProfile(isGuest: true);
          state = guestProf;
        }
      } else {
        final userProf = await _repository.getProfile(userId: next.uid, isGuest: false);
        final displayName = (next.displayName != null &&
                next.displayName!.trim().isNotEmpty &&
                next.displayName != 'Miee Listener' &&
                next.displayName != 'Miee User')
            ? next.displayName!.trim()
            : userProf.displayName;
        state = userProf.copyWith(
          userId: next.uid,
          isGuest: false,
          displayName: displayName,
          username: userProf.username ?? displayName.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
          profilePicturePath: userProf.profilePicturePath ?? next.photoUrl,
        );
        await _repository.saveProfile(state);
      }
    });

    _ref.listen<bool>(guestModeProvider, (previous, next) async {
      if (next) {
        final authUser = _ref.read(currentAuthUserProvider);
        if (authUser == null) {
          final guestProf = await _repository.getProfile(isGuest: true);
          state = guestProf;
        }
      }
    });
  }

  Future<void> _queueProfileUpdate(ProfileModel profile) async {
    // Offline queue hook if cloud sync is enabled
  }

  Future<void> updateProfile({
    required String displayName,
    String? username,
    String? profilePicturePath,
    required String favoriteGenre,
    required String favoriteArtist,
  }) async {
    final updated = state.copyWith(
      displayName: state.isGuest ? 'Guest' : displayName,
      username: state.isGuest ? null : username,
      clearUsername: state.isGuest,
      profilePicturePath: profilePicturePath,
      favoriteGenre: favoriteGenre,
      favoriteArtist: favoriteArtist,
    );
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> removeProfilePicture() async {
    final updated = state.copyWith(clearProfilePicture: true);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateResumePlayback(bool value) async {
    final updated = state.copyWith(resumePlayback: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateDefaultShuffle(bool value) async {
    final updated = state.copyWith(defaultShuffle: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateDefaultRepeat(String value) async {
    final updated = state.copyWith(defaultRepeat: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updatePlaybackSpeed(double value) async {
    final updated = state.copyWith(playbackSpeed: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateGaplessPlayback(bool value) async {
    final updated = state.copyWith(gaplessPlayback: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateCrossfade(bool value) async {
    final updated = state.copyWith(crossfade: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updatePreferredSource(String source) async {
    final updated = state.copyWith(preferredSource: source);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateBackgroundPlayback(bool value) async {
    final updated = state.copyWith(backgroundPlayback: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateMediaNotification(bool value) async {
    final updated = state.copyWith(mediaNotification: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateLockScreenControls(bool value) async {
    final updated = state.copyWith(lockScreenControls: value);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> updateLastScanTime(String? time) async {
    final updated = state.copyWith(lastScanTime: time);
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }
}

/// Provider for the ProfileRepository.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final box = Hive.box<dynamic>(HiveBoxes.profile);
  return HiveProfileRepository(box);
});

/// Provider for the active user ProfileModel.
final profileProvider = StateNotifierProvider<ProfileController, ProfileModel>((ref) {
  debugPrint('STARTUP: profileProvider creating controller');
  final repo = ref.watch(profileRepositoryProvider);
  final isGuest = ref.watch(guestModeProvider);
  final authUser = ref.read(currentAuthUserProvider);

  ProfileModel initialProfile;
  if (isGuest || authUser == null) {
    final box = Hive.box<dynamic>(HiveBoxes.profile);
    final data = box.get('guest_profile');
    if (data is Map) {
      initialProfile = ProfileModel(
        displayName: 'Guest',
        username: null,
        userId: null,
        isGuest: true,
        profilePicturePath: data['profilePicturePath'] as String?,
        favoriteGenre: data['favoriteGenre'] as String? ?? 'Acoustic',
        favoriteArtist: data['favoriteArtist'] as String? ?? 'Unknown Artist',
        createdDate: DateTime.tryParse(data['createdDate'] as String? ?? '') ?? DateTime.now(),
        lastOpened: DateTime.tryParse(data['lastOpened'] as String? ?? '') ?? DateTime.now(),
        playbackSpeed: (data['playbackSpeed'] as num? ?? 1.0).toDouble(),
        preferredSource: data['preferredSource'] as String? ?? 'preferLocal',
        defaultShuffle: data['defaultShuffle'] as bool? ?? false,
        defaultRepeat: data['defaultRepeat'] as String? ?? 'off',
        resumePlayback: data['resumePlayback'] as bool? ?? true,
        backgroundPlayback: data['backgroundPlayback'] as bool? ?? true,
        mediaNotification: data['mediaNotification'] == 'true' || data['mediaNotification'] == true,
        lockScreenControls: data['lockScreenControls'] as bool? ?? true,
        gaplessPlayback: data['gaplessPlayback'] as bool? ?? true,
        crossfade: data['crossfade'] as bool? ?? false,
        lastScanTime: data['lastScanTime'] as String?,
      );
    } else {
      initialProfile = ProfileModel.guestProfile();
    }
  } else {
    final box = Hive.box<dynamic>(HiveBoxes.profile);
    final data = box.get('profile_${authUser.uid}') ?? box.get('active_profile');
    final candidateAuthName = (authUser.displayName?.trim().isNotEmpty == true &&
            authUser.displayName != 'Miee Listener' &&
            authUser.displayName != 'Miee User')
        ? authUser.displayName!.trim()
        : null;

    if (data is Map) {
      final savedName = data['displayName'] as String?;
      final effectiveDisplayName = (savedName != null &&
              savedName.isNotEmpty &&
              savedName != 'Miee User' &&
              savedName != 'Miee Listener')
          ? savedName
          : (candidateAuthName ?? 'Miee User');

      initialProfile = ProfileModel(
        displayName: effectiveDisplayName,
        username: data['username'] as String? ??
            (candidateAuthName?.toLowerCase().replaceAll(RegExp(r'\s+'), '_')),
        userId: authUser.uid,
        isGuest: false,
        profilePicturePath: (data['profilePicturePath'] as String?) ?? authUser.photoUrl,
        favoriteGenre: data['favoriteGenre'] as String? ?? 'Acoustic',
        favoriteArtist: data['favoriteArtist'] as String? ?? 'Unknown Artist',
        createdDate: DateTime.tryParse(data['createdDate'] as String? ?? '') ?? DateTime.now(),
        lastOpened: DateTime.tryParse(data['lastOpened'] as String? ?? '') ?? DateTime.now(),
        playbackSpeed: (data['playbackSpeed'] as num? ?? 1.0).toDouble(),
        preferredSource: data['preferredSource'] as String? ?? 'preferLocal',
        defaultShuffle: data['defaultShuffle'] as bool? ?? false,
        defaultRepeat: data['defaultRepeat'] as String? ?? 'off',
        resumePlayback: data['resumePlayback'] as bool? ?? true,
        backgroundPlayback: data['backgroundPlayback'] as bool? ?? true,
        mediaNotification: data['mediaNotification'] == 'true' || data['mediaNotification'] == true,
        lockScreenControls: data['lockScreenControls'] as bool? ?? true,
        gaplessPlayback: data['gaplessPlayback'] as bool? ?? true,
        crossfade: data['crossfade'] as bool? ?? false,
        lastScanTime: data['lastScanTime'] as String?,
      );
    } else {
      initialProfile = ProfileModel(
        displayName: candidateAuthName ?? 'Miee User',
        username: candidateAuthName?.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
        userId: authUser.uid,
        isGuest: false,
        profilePicturePath: authUser.photoUrl,
        favoriteGenre: 'Acoustic',
        favoriteArtist: 'Unknown Artist',
        createdDate: DateTime.now(),
        lastOpened: DateTime.now(),
        playbackSpeed: 1.0,
        preferredSource: 'preferLocal',
        defaultShuffle: false,
        defaultRepeat: 'off',
        resumePlayback: true,
        backgroundPlayback: true,
        mediaNotification: true,
        lockScreenControls: true,
        gaplessPlayback: true,
        crossfade: false,
      );
    }
  }

  debugPrint('STARTUP: profileProvider initialProfile loaded (displayName: ${initialProfile.displayName}, isGuest: ${initialProfile.isGuest})');
  return ProfileController(repo, ref, initialProfile);
});
