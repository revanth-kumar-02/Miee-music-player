import 'package:hive/hive.dart';
import '../domain/profile_model.dart';
import '../domain/profile_repository.dart';

class HiveProfileRepository implements ProfileRepository {
  final Box _box;

  HiveProfileRepository(this._box);

  static const String _keyProfile = 'active_profile';

  @override
  Future<ProfileModel> getProfile() async {
    final data = _box.get(_keyProfile);
    if (data == null || data is! Map) {
      return ProfileModel.defaultProfile();
    }
    
    final Map<dynamic, dynamic> map = data;
    return ProfileModel(
      displayName: map['displayName'] as String? ?? 'Miee User',
      username: map['username'] as String?,
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
    await _box.put(_keyProfile, data);
  }
}
