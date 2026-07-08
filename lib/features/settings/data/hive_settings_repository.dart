import 'package:hive/hive.dart';
import '../domain/settings_model.dart';
import '../domain/settings_repository.dart';

class HiveSettingsRepository implements SettingsRepository {
  final Box _box;

  HiveSettingsRepository(this._box);

  static const _keyThemeMode = 'settings_theme_mode';
  static const _keyResumePlayback = 'settings_resume_playback';
  static const _keyDefaultShuffle = 'settings_default_shuffle';
  static const _keyDefaultRepeat = 'settings_default_repeat';
  static const _keyPlaybackSpeed = 'settings_playback_speed';
  static const _keyGaplessPlayback = 'settings_gapless_playback';
  static const _keyCrossfade = 'settings_crossfade';
  static const _keyPreferredSource = 'settings_preferred_source';
  static const _keyBackgroundPlayback = 'settings_background_playback';
  static const _keyMediaNotification = 'settings_media_notification';
  static const _keyLockScreenControls = 'settings_lock_screen_controls';
  static const _keyLastScanTime = 'settings_last_scan_time';

  @override
  Future<SettingsModel> getSettings() async {
    return SettingsModel(
      themeMode: _box.get(_keyThemeMode, defaultValue: 'system') as String,
      resumePlayback: _box.get(_keyResumePlayback, defaultValue: false) as bool,
      defaultShuffle: _box.get(_keyDefaultShuffle, defaultValue: false) as bool,
      defaultRepeat: _box.get(_keyDefaultRepeat, defaultValue: 'off') as String,
      playbackSpeed: _box.get(_keyPlaybackSpeed, defaultValue: 1.0) as double,
      gaplessPlayback: _box.get(_keyGaplessPlayback, defaultValue: true) as bool,
      crossfade: _box.get(_keyCrossfade, defaultValue: false) as bool,
      preferredSource: _box.get(_keyPreferredSource, defaultValue: 'preferLocal') as String,
      backgroundPlayback: _box.get(_keyBackgroundPlayback, defaultValue: true) as bool,
      mediaNotification: _box.get(_keyMediaNotification, defaultValue: true) as bool,
      lockScreenControls: _box.get(_keyLockScreenControls, defaultValue: true) as bool,
      lastScanTime: _box.get(_keyLastScanTime) as String?,
    );
  }

  @override
  Future<void> saveSettings(SettingsModel settings) async {
    await _box.put(_keyThemeMode, settings.themeMode);
    await _box.put(_keyResumePlayback, settings.resumePlayback);
    await _box.put(_keyDefaultShuffle, settings.defaultShuffle);
    await _box.put(_keyDefaultRepeat, settings.defaultRepeat);
    await _box.put(_keyPlaybackSpeed, settings.playbackSpeed);
    await _box.put(_keyGaplessPlayback, settings.gaplessPlayback);
    await _box.put(_keyCrossfade, settings.crossfade);
    await _box.put(_keyPreferredSource, settings.preferredSource);
    await _box.put(_keyBackgroundPlayback, settings.backgroundPlayback);
    await _box.put(_keyMediaNotification, settings.mediaNotification);
    await _box.put(_keyLockScreenControls, settings.lockScreenControls);
    await _box.put(_keyLastScanTime, settings.lastScanTime);
  }
}
