import 'package:hive/hive.dart';
import '../domain/profile_model.dart';
import '../domain/profile_repository.dart';

class HiveProfileRepository implements ProfileRepository {
  final Box<dynamic> _box;

  HiveProfileRepository(this._box);

  static const String _keyProfile = 'active_profile';
  static const String _keyGuestProfile = 'guest_profile';

  @override
  Future<ProfileModel> getProfile({String? userId, bool isGuest = false}) async {
    if (isGuest) {
      final data = _box.get(_keyGuestProfile);
      if (data == null || data is! Map) {
        return ProfileModel.guestProfile();
      }
      return _mapToProfile(data, isGuest: true);
    }

    // Authenticated / registered profile
    dynamic data;
    if (userId != null && userId.isNotEmpty) {
      data = _box.get('profile_$userId');
    }
    data ??= _box.get(_keyProfile);

    if (data == null || data is! Map) {
      return ProfileModel.defaultProfile();
    }

    return _mapToProfile(data, isGuest: false, defaultUserId: userId);
  }

  ProfileModel _mapToProfile(Map<dynamic, dynamic> map, {required bool isGuest, String? defaultUserId}) {
    if (isGuest) {
      return ProfileModel(
        displayName: 'Guest',
        username: null,
        userId: null,
        isGuest: true,
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
        mediaNotification: map['mediaNotification'] as bool? ?? true,
        lockScreenControls: map['lockScreenControls'] as bool? ?? true,
        gaplessPlayback: map['gaplessPlayback'] as bool? ?? true,
        crossfade: map['crossfade'] as bool? ?? false,
        lastScanTime: map['lastScanTime'] as String?,
      );
    }

    return ProfileModel(
      displayName: map['displayName'] as String? ?? 'Miee User',
      username: map['username'] as String?,
      userId: map['userId'] as String? ?? defaultUserId,
      isGuest: false,
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
      mediaNotification: map['mediaNotification'] as bool? ?? true,
      lockScreenControls: map['lockScreenControls'] as bool? ?? true,
      gaplessPlayback: map['gaplessPlayback'] as bool? ?? true,
      crossfade: map['crossfade'] as bool? ?? false,
      lastScanTime: map['lastScanTime'] as String?,
    );
  }

  @override
  Future<void> saveProfile(ProfileModel profile) async {
    final Map<String, dynamic> data = {
      'displayName': profile.displayName,
      'username': profile.username,
      'userId': profile.userId,
      'isGuest': profile.isGuest,
      'profilePicturePath': profile.profilePicturePath,
      'favoriteGenre': profile.favoriteGenre,
      'favoriteArtist': profile.favoriteArtist,
      'createdDate': profile.createdDate.toIso8601String(),
      'lastOpened': profile.lastOpened.toIso8601String(),
      'playbackSpeed': profile.playbackSpeed,
      'preferredSource': profile.preferredSource,
      'defaultShuffle': profile.defaultShuffle,
      'defaultRepeat': profile.defaultRepeat,
      'resumePlayback': profile.resumePlayback,
      'backgroundPlayback': profile.backgroundPlayback,
      'mediaNotification': profile.mediaNotification,
      'lockScreenControls': profile.lockScreenControls,
      'gaplessPlayback': profile.gaplessPlayback,
      'crossfade': profile.crossfade,
      'lastScanTime': profile.lastScanTime,
    };

    if (profile.isGuest) {
      await _box.put(_keyGuestProfile, data);
    } else {
      await _box.put(_keyProfile, data);
      if (profile.userId != null && profile.userId!.isNotEmpty) {
        await _box.put('profile_${profile.userId}', data);
      }
    }
  }
}
