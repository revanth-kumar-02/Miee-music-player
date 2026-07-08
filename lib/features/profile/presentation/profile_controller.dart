import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../../core/storage/hive_boxes.dart';
import '../domain/profile_model.dart';
import '../domain/profile_repository.dart';
import '../data/hive_profile_repository.dart';

/// Notifier that manages active profile data reactively and persists changes to Hive.
class ProfileController extends StateNotifier<ProfileModel> {
  final ProfileRepository _repository;

  ProfileController(this._repository, ProfileModel initialProfile) : super(initialProfile) {
    _recordLastOpened();
  }

  Future<void> _recordLastOpened() async {
    final updated = state.copyWith(lastOpened: DateTime.now());
    await _repository.saveProfile(updated);
    state = updated;
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
  }

  Future<void> removeProfilePicture() async {
    final updated = state.copyWith(profilePicturePath: null);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateThemeMode(String mode) async {
    final updated = state.copyWith(themeMode: mode);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateResumePlayback(bool value) async {
    final updated = state.copyWith(resumePlayback: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateDefaultShuffle(bool value) async {
    final updated = state.copyWith(defaultShuffle: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateDefaultRepeat(String value) async {
    final updated = state.copyWith(defaultRepeat: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updatePlaybackSpeed(double value) async {
    final updated = state.copyWith(playbackSpeed: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateGaplessPlayback(bool value) async {
    final updated = state.copyWith(gaplessPlayback: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateCrossfade(bool value) async {
    final updated = state.copyWith(crossfade: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updatePreferredSource(String source) async {
    final updated = state.copyWith(preferredSource: source);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateBackgroundPlayback(bool value) async {
    final updated = state.copyWith(backgroundPlayback: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateMediaNotification(bool value) async {
    final updated = state.copyWith(mediaNotification: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateLockScreenControls(bool value) async {
    final updated = state.copyWith(lockScreenControls: value);
    await _repository.saveProfile(updated);
    state = updated;
  }

  Future<void> updateLastScanTime(String? time) async {
    final updated = state.copyWith(lastScanTime: time);
    await _repository.saveProfile(updated);
    state = updated;
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
      backgroundPlayback: map['backgroundPlayback'] as bool? ?? true,
      mediaNotification: map['mediaNotification'] as String? == 'true' || map['mediaNotification'] as bool? ?? true,
      lockScreenControls: map['lockScreenControls'] as bool? ?? true,
      gaplessPlayback: map['gaplessPlayback'] as bool? ?? true,
      crossfade: map['crossfade'] as bool? ?? false,
      lastScanTime: map['lastScanTime'] as String?,
    );
  }

  return ProfileController(repo, initialProfile);
});
