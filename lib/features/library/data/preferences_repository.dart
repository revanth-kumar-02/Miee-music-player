import 'package:hive/hive.dart';

import '../../../core/storage/hive_boxes.dart';

/// Persists user-configurable preferences as strongly typed values.
///
/// Uses a plain [Box] (dynamic values) for maximum flexibility and easy
/// schema evolution — new keys can always be added without migration.
class PreferencesRepository {
  Box get _box => Hive.box(HiveBoxes.preferences);

  // ── Theme ───────────────────────────────────────────────────────────────────

  /// Returns the stored theme. Defaults to 'dark'.
  String getTheme() => _box.get(PreferenceKeys.theme, defaultValue: 'dark') as String;

  Future<void> setTheme(String theme) async =>
      _box.put(PreferenceKeys.theme, theme);

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

  // ── Watch stream ────────────────────────────────────────────────────────────

  /// Emits a [BoxEvent] whenever any preference changes.
  Stream<BoxEvent> watchAll() => _box.watch();
}
