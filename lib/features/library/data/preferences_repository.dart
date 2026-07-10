import 'package:hive/hive.dart';

import '../../../core/storage/hive_boxes.dart';

/// Persists user-configurable preferences as strongly typed values.
///
/// Uses a plain [Box] (dynamic values) for maximum flexibility and easy
/// schema evolution — new keys can always be added without migration.
class PreferencesRepository {
  Box get _box => Hive.box(HiveBoxes.preferences);

  // ── Playback speed ──────────────────────────────────────────────────────────

  double getPlaybackSpeed() =>
      _box.get(PreferenceKeys.playbackSpeed, defaultValue: 1.0) as double;

  Future<void> setPlaybackSpeed(double speed) async =>
      _box.put(PreferenceKeys.playbackSpeed, speed);

  // ── Repeat mode ─────────────────────────────────────────────────────────────

  /// Returns repeat mode: 'off' | 'one' | 'all'.
  String getRepeatMode() =>
      _box.get(PreferenceKeys.repeatMode, defaultValue: 'off') as String;

  Future<void> setRepeatMode(String mode) async =>
      _box.put(PreferenceKeys.repeatMode, mode);

  // ── Shuffle ─────────────────────────────────────────────────────────────────

  bool getShuffle() =>
      _box.get(PreferenceKeys.shuffle, defaultValue: false) as bool;

  Future<void> setShuffle(bool value) async =>
      _box.put(PreferenceKeys.shuffle, value);

  // ── Sleep timer ─────────────────────────────────────────────────────────────

  int? getSleepTimerMinutes() =>
      _box.get(PreferenceKeys.sleepTimerMinutes) as int?;

  Future<void> setSleepTimerMinutes(int? minutes) async =>
      _box.put(PreferenceKeys.sleepTimerMinutes, minutes);

  // ── Audio quality ───────────────────────────────────────────────────────────

  /// Returns audio quality: 'low' | 'medium' | 'high'.
  String getAudioQuality() =>
      _box.get(PreferenceKeys.audioQuality, defaultValue: 'high') as String;

  Future<void> setAudioQuality(String quality) async =>
      _box.put(PreferenceKeys.audioQuality, quality);

  // ── Source Selection ─────────────────────────────────────────────────────────

  /// Returns source selection: 'smart' | 'alwaysLocal' | 'alwaysYouTube'.
  String getSourceSelectionMode() =>
      _box.get(PreferenceKeys.sourceSelection, defaultValue: 'smart') as String;

  Future<void> setSourceSelectionMode(String mode) async =>
      _box.put(PreferenceKeys.sourceSelection, mode);

  // ── Playback Settings ────────────────────────────────────────────────────────

  bool getResumePlayback() =>
      _box.get(PreferenceKeys.resumePlayback, defaultValue: false) as bool;

  Future<void> setResumePlayback(bool value) async =>
      _box.put(PreferenceKeys.resumePlayback, value);

  bool getAutoPlayNext() =>
      _box.get(PreferenceKeys.autoPlayNext, defaultValue: true) as bool;

  Future<void> setAutoPlayNext(bool value) async =>
      _box.put(PreferenceKeys.autoPlayNext, value);

  bool getShuffleDefault() =>
      _box.get(PreferenceKeys.shuffleDefault, defaultValue: false) as bool;

  Future<void> setShuffleDefault(bool value) async =>
      _box.put(PreferenceKeys.shuffleDefault, value);

  String getRepeatDefault() =>
      _box.get(PreferenceKeys.repeatDefault, defaultValue: 'off') as String;

  Future<void> setRepeatDefault(String value) async =>
      _box.put(PreferenceKeys.repeatDefault, value);

  bool getCrossfadeEnabled() =>
      _box.get(PreferenceKeys.crossfadeEnabled, defaultValue: false) as bool;

  Future<void> setCrossfadeEnabled(bool value) async =>
      _box.put(PreferenceKeys.crossfadeEnabled, value);

  bool getGaplessPlaybackEnabled() =>
      _box.get(PreferenceKeys.gaplessPlaybackEnabled, defaultValue: true) as bool;

  Future<void> setGaplessPlaybackEnabled(bool value) async =>
      _box.put(PreferenceKeys.gaplessPlaybackEnabled, value);

  // ── Library Settings ─────────────────────────────────────────────────────────

  String? getLastScanTime() =>
      _box.get(PreferenceKeys.lastScanTime) as String?;

  Future<void> setLastScanTime(String? time) async =>
      _box.put(PreferenceKeys.lastScanTime, time);

  // ── Notification Settings ───────────────────────────────────────────────────

  bool getMediaNotificationEnabled() =>
      _box.get(PreferenceKeys.mediaNotificationEnabled, defaultValue: true) as bool;

  Future<void> setMediaNotificationEnabled(bool value) async =>
      _box.put(PreferenceKeys.mediaNotificationEnabled, value);

  bool getBackgroundPlaybackEnabled() =>
      _box.get(PreferenceKeys.backgroundPlaybackEnabled, defaultValue: true) as bool;

  Future<void> setBackgroundPlaybackEnabled(bool value) async =>
      _box.put(PreferenceKeys.backgroundPlaybackEnabled, value);

  bool getLockScreenControlsEnabled() =>
      _box.get(PreferenceKeys.lockScreenControlsEnabled, defaultValue: true) as bool;

  Future<void> setLockScreenControlsEnabled(bool value) async =>
      _box.put(PreferenceKeys.lockScreenControlsEnabled, value);

  // ── Watch stream ────────────────────────────────────────────────────────────

  /// Emits a [BoxEvent] whenever any preference changes.
  Stream<BoxEvent> watchAll() => _box.watch();
}

