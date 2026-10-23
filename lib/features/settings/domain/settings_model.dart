class SettingsModel {
  final bool resumePlayback;
  final bool defaultShuffle;
  final String defaultRepeat; // 'off' | 'one' | 'all'
  final double playbackSpeed; // 0.5 to 2.0
  final bool gaplessPlayback;
  final bool crossfade;
  final String preferredSource; // 'preferLocal' | 'preferYouTube' | 'askEveryTime'
  final bool backgroundPlayback;
  final bool mediaNotification;
  final bool lockScreenControls;
  final String? lastScanTime;

  const SettingsModel({
    this.resumePlayback = true,
    this.defaultShuffle = false,
    this.defaultRepeat = 'off',
    this.playbackSpeed = 1.0,
    this.gaplessPlayback = true,
    this.crossfade = false,
    this.preferredSource = 'preferLocal',
    this.backgroundPlayback = true,
    this.mediaNotification = true,
    this.lockScreenControls = true,
    this.lastScanTime,
  });

  SettingsModel copyWith({
    bool? resumePlayback,
    bool? defaultShuffle,
    String? defaultRepeat,
    double? playbackSpeed,
    bool? gaplessPlayback,
    bool? crossfade,
    String? preferredSource,
    bool? backgroundPlayback,
    bool? mediaNotification,
    bool? lockScreenControls,
    String? lastScanTime,
  }) {
    return SettingsModel(
      resumePlayback: resumePlayback ?? this.resumePlayback,
      defaultShuffle: defaultShuffle ?? this.defaultShuffle,
      defaultRepeat: defaultRepeat ?? this.defaultRepeat,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      gaplessPlayback: gaplessPlayback ?? this.gaplessPlayback,
      crossfade: crossfade ?? this.crossfade,
      preferredSource: preferredSource ?? this.preferredSource,
      backgroundPlayback: backgroundPlayback ?? this.backgroundPlayback,
      mediaNotification: mediaNotification ?? this.mediaNotification,
      lockScreenControls: lockScreenControls ?? this.lockScreenControls,
      lastScanTime: lastScanTime ?? this.lastScanTime,
    );
  }
}
