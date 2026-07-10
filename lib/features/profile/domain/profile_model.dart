class ProfileModel {
  final String displayName;
  final String? username;
  final String? profilePicturePath;
  final String favoriteGenre;
  final String favoriteArtist;
  final DateTime createdDate;
  final DateTime lastOpened;

  // Preferences moved into Profile
  final double playbackSpeed;
  final String preferredSource; // 'preferLocal' | 'preferYouTube' | 'askEveryTime'
  final bool defaultShuffle;
  final String defaultRepeat; // 'off' | 'one' | 'all'
  final bool resumePlayback;
  final bool backgroundPlayback;
  final bool mediaNotification;
  final bool lockScreenControls;
  final bool gaplessPlayback;
  final bool crossfade;
  final String? lastScanTime;

  const ProfileModel({
    required this.displayName,
    this.username,
    this.profilePicturePath,
    required this.favoriteGenre,
    required this.favoriteArtist,
    required this.createdDate,
    required this.lastOpened,
    required this.playbackSpeed,
    required this.preferredSource,
    required this.defaultShuffle,
    required this.defaultRepeat,
    required this.resumePlayback,
    required this.backgroundPlayback,
    required this.mediaNotification,
    required this.lockScreenControls,
    required this.gaplessPlayback,
    required this.crossfade,
    this.lastScanTime,
  });

  factory ProfileModel.defaultProfile() {
    final now = DateTime.now();
    return ProfileModel(
      displayName: 'Miee User',
      favoriteGenre: 'Acoustic',
      favoriteArtist: 'Unknown Artist',
      createdDate: now,
      lastOpened: now,
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

  ProfileModel copyWith({
    String? displayName,
    String? username,
    String? profilePicturePath,
    String? favoriteGenre,
    String? favoriteArtist,
    DateTime? createdDate,
    DateTime? lastOpened,
    double? playbackSpeed,
    String? preferredSource,
    bool? defaultShuffle,
    String? defaultRepeat,
    bool? resumePlayback,
    bool? backgroundPlayback,
    bool? mediaNotification,
    bool? lockScreenControls,
    bool? gaplessPlayback,
    bool? crossfade,
    String? lastScanTime,
  }) {
    return ProfileModel(
      displayName: displayName ?? this.displayName,
      username: username ?? this.username,
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
      favoriteGenre: favoriteGenre ?? this.favoriteGenre,
      favoriteArtist: favoriteArtist ?? this.favoriteArtist,
      createdDate: createdDate ?? this.createdDate,
      lastOpened: lastOpened ?? this.lastOpened,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      preferredSource: preferredSource ?? this.preferredSource,
      defaultShuffle: defaultShuffle ?? this.defaultShuffle,
      defaultRepeat: defaultRepeat ?? this.defaultRepeat,
      resumePlayback: resumePlayback ?? this.resumePlayback,
      backgroundPlayback: backgroundPlayback ?? this.backgroundPlayback,
      mediaNotification: mediaNotification ?? this.mediaNotification,
      lockScreenControls: lockScreenControls ?? this.lockScreenControls,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      crossfade: crossfade ?? this.crossfade,
      lastScanTime: lastScanTime ?? this.lastScanTime,
    );
  }
}
