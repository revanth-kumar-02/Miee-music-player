import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../../core/storage/hive_boxes.dart';
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

    _ref.listen<AuthUser?>(currentAuthUserProvider, (previous, next) {
      if (next != null &&
          next.displayName != null &&
          next.displayName!.trim().isNotEmpty &&
          next.displayName != 'Miee Listener' &&
          next.displayName != 'Miee User' &&
          state.displayName != next.displayName) {
        updateProfile(
          displayName: next.displayName!,
          username: next.displayName!.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
          favoriteGenre: state.favoriteGenre,
          favoriteArtist: state.favoriteArtist,
        );
      }
    });
  }

  Future<void> _recordLastOpened() async {
    // final updated = state.copyWith(lastOpened: DateTime.now());
    // await _repository.saveProfile(updated);
    // state = updated;
    // await _queueProfileUpdate(updated);
  }

  Future<void> _queueProfileUpdate(ProfileModel profile) async {
    // final op = OfflineOperation(
    //   id: 'profile_upd_${DateTime.now().millisecondsSinceEpoch}',
    //   type: 'profile_update',
    //   payload: {
    //     'displayName': profile.displayName,
    //     'username': profile.username,
    //     'profilePicturePath': profile.profilePicturePath,
    //     'favoriteGenre': profile.favoriteGenre,
    //     'favoriteArtist': profile.favoriteArtist,
    //     'createdDate': profile.createdDate.toIso8601String(),
    //     'lastOpened': profile.lastOpened.toIso8601String(),
    //     'themeMode': profile.themeMode,
    //     'playbackSpeed': profile.playbackSpeed,
    //     'preferredSource': profile.preferredSource,
    //     'defaultShuffle': profile.defaultShuffle,
    //     'defaultRepeat': profile.defaultRepeat,
    //     'backgroundPlayback': profile.backgroundPlayback,
    //     'mediaNotification': profile.mediaNotification,
    //     'lockScreenControls': profile.lockScreenControls,
    //     'gaplessPlayback': profile.gaplessPlayback,
    //     'crossfade': profile.crossfade,
    //     'lastScanTime': profile.lastScanTime,
    //   },
    //   timestamp: DateTime.now(),
    // );
    // await _ref.read(syncManagerProvider).queueOperation(op);
  }

  Future<void> updateProfile({
    required String displayName,
    String? username,
    String? profilePicturePath,
    required String favoriteGenre,
    required String favoriteArtist,
  }) async {
    final updated = state.copyWith(
      displayName: displayName,
      username: username,
      profilePicturePath: profilePicturePath,
      favoriteGenre: favoriteGenre,
      favoriteArtist: favoriteArtist,
    );
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> removeProfilePicture() async {
    final updated = state.copyWith(profilePicturePath: null);
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
  final box = Hive.box(HiveBoxes.profile);
  return HiveProfileRepository(box);
});

/// Provider for the active user ProfileModel.
final profileProvider = StateNotifierProvider<ProfileController, ProfileModel>((ref) {
  debugPrint('STARTUP: profileProvider creating controller');
  final repo = ref.watch(profileRepositoryProvider);
  final box = Hive.box(HiveBoxes.profile);
  
  final data = box.get('active_profile');
  final authUser = ref.read(currentAuthUserProvider);
  final candidateAuthName = (authUser?.displayName?.trim().isNotEmpty == true &&
          authUser?.displayName != 'Miee Listener' &&
          authUser?.displayName != 'Miee User')
      ? authUser!.displayName!.trim()
      : null;

  ProfileModel initialProfile;
  if (data == null || data is! Map) {
    initialProfile = ProfileModel.defaultProfile();
    if (candidateAuthName != null) {
      initialProfile = ProfileModel(
        displayName: candidateAuthName,
        username: candidateAuthName.toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
        favoriteGenre: initialProfile.favoriteGenre,
        favoriteArtist: initialProfile.favoriteArtist,
        createdDate: initialProfile.createdDate,
        lastOpened: initialProfile.lastOpened,
        playbackSpeed: initialProfile.playbackSpeed,
        preferredSource: initialProfile.preferredSource,
        defaultShuffle: initialProfile.defaultShuffle,
        defaultRepeat: initialProfile.defaultRepeat,
        resumePlayback: initialProfile.resumePlayback,
        backgroundPlayback: initialProfile.backgroundPlayback,
        mediaNotification: initialProfile.mediaNotification,
        lockScreenControls: initialProfile.lockScreenControls,
        gaplessPlayback: initialProfile.gaplessPlayback,
        crossfade: initialProfile.crossfade,
      );
    }
  } else {
    final Map<dynamic, dynamic> map = data;
    final savedName = map['displayName'] as String?;
    final effectiveDisplayName = (savedName != null &&
            savedName.isNotEmpty &&
            savedName != 'Miee User' &&
            savedName != 'Miee Listener')
        ? savedName
        : (candidateAuthName ?? 'Miee User');

    initialProfile = ProfileModel(
      displayName: effectiveDisplayName,
      username: map['username'] as String? ??
          (candidateAuthName != null
              ? candidateAuthName.toLowerCase().replaceAll(RegExp(r'\s+'), '_')
              : null),
      profilePicturePath: map['profilePicturePath'] as String?,
      favoriteGenre: map['favoriteGenre'] as String? ?? 'Acoustic',
      favoriteArtist: map['favoriteArtist'] as String? ?? 'Unknown Artist',
      createdDate: DateTime.tryParse(map['createdDate'] as String? ?? '') ?? DateTime.now(),
      lastOpened: DateTime.tryParse(map['lastOpened'] as String? ?? '') ?? DateTime.now(),
      playbackSpeed: (map['playbackSpeed'] as num? ?? 1.0).toDouble(),
      preferredSource: map['preferredSource'] as String? ?? 'preferLocal',
      defaultShuffle: map['defaultShuffle'] as bool? ?? false,
      defaultRepeat: map['defaultRepeat'] as String? ?? 'off',
      resumePlayback: map['resumePlayback'] as bool? ?? true,
      backgroundPlayback: map['backgroundPlayback'] as bool? ?? true,
      mediaNotification: map['mediaNotification'] == 'true' || map['mediaNotification'] == true,
      lockScreenControls: map['lockScreenControls'] as bool? ?? true,
      gaplessPlayback: map['gaplessPlayback'] as bool? ?? true,
      crossfade: map['crossfade'] as bool? ?? false,
      lastScanTime: map['lastScanTime'] as String?,
    );
  }

  debugPrint('STARTUP: profileProvider initialProfile loaded (displayName: ${initialProfile.displayName})');
  return ProfileController(repo, ref, initialProfile);
});
