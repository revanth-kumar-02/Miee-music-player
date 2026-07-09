import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../../../../core/sync/sync_manager.dart';
import '../../../../core/sync/offline_operation.dart';
import '../domain/profile_model.dart';
import '../domain/profile_repository.dart';
import '../data/hive_profile_repository.dart';

/// Notifier that manages active profile data reactively and persists changes to Hive with background sync.
class ProfileController extends StateNotifier<ProfileModel> {
  final ProfileRepository _repository;
  final Ref _ref;

  ProfileController(this._repository, this._ref, ProfileModel initialProfile) : super(initialProfile) {
    _recordLastOpened();
  }

  Future<void> _recordLastOpened() async {
    final updated = state.copyWith(lastOpened: DateTime.now());
    await _repository.saveProfile(updated);
    state = updated;
    await _queueProfileUpdate(updated);
  }

  Future<void> _queueProfileUpdate(ProfileModel profile) async {
    final op = OfflineOperation(
      id: 'profile_upd_${DateTime.now().millisecondsSinceEpoch}',
      type: 'profile_update',
      payload: {
        'displayName': profile.displayName,
        'username': profile.username,
        'profilePicturePath': profile.profilePicturePath,
        'favoriteGenre': profile.favoriteGenre,
        'favoriteArtist': profile.favoriteArtist,
        'createdDate': profile.createdDate.toIso8601String(),
        'lastOpened': profile.lastOpened.toIso8601String(),
        'themeMode': profile.themeMode,
        'playbackSpeed': profile.playbackSpeed,
        'preferredSource': profile.preferredSource,
        'defaultShuffle': profile.defaultShuffle,
        'defaultRepeat': profile.defaultRepeat,
        'backgroundPlayback': profile.backgroundPlayback,
        'mediaNotification': profile.mediaNotification,
        'lockScreenControls': profile.lockScreenControls,
        'gaplessPlayback': profile.gaplessPlayback,
        'crossfade': profile.crossfade,
        'lastScanTime': profile.lastScanTime,
      },
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
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

  Future<void> updateThemeMode(String mode) async {
    final updated = state.copyWith(themeMode: mode);
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
  final repo = ref.watch(profileRepositoryProvider);
  final box = Hive.box(HiveBoxes.profile);
  
  final data = box.get('active_profile');
  ProfileModel initialProfile;
  if (data == null || data is! Map) {
    initialProfile = ProfileModel.defaultProfile();
  } else {
    final Map<dynamic, dynamic> map = data;
    initialProfile = ProfileModel(
      displayName: map['displayName'] as String? ?? 'Miee User',
      username: map['username'] as String?,
      profilePicturePath: map['profilePicturePath'] as String?,
      favoriteGenre: map['favoriteGenre'] as String? ?? 'Acoustic',
      favoriteArtist: map['favoriteArtist'] as String? ?? 'Unknown Artist',
      createdDate: DateTime.tryParse(map['createdDate'] as String? ?? '') ?? DateTime.now(),
      lastOpened: DateTime.tryParse(map['lastOpened'] as String? ?? '') ?? DateTime.now(),
      themeMode: map['themeMode'] as String? ?? 'system',
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

  return ProfileController(repo, ref, initialProfile);
});
