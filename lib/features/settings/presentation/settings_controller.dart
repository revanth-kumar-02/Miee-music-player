import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../domain/settings_model.dart';
import '../domain/settings_repository.dart';
import '../data/hive_settings_repository.dart';

/// Notifier that manages UI settings state reactively and persists changes to Hive.
class SettingsController extends StateNotifier<SettingsModel> {
  final SettingsRepository _repository;

  SettingsController(this._repository, SettingsModel initialSettings) : super(initialSettings);

  Future<void> updateThemeMode(String mode) async {
    final updated = state.copyWith(themeMode: mode);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateResumePlayback(bool value) async {
    final updated = state.copyWith(resumePlayback: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateDefaultShuffle(bool value) async {
    final updated = state.copyWith(defaultShuffle: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateDefaultRepeat(String value) async {
    final updated = state.copyWith(defaultRepeat: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updatePlaybackSpeed(double value) async {
    final updated = state.copyWith(playbackSpeed: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateGaplessPlayback(bool value) async {
    final updated = state.copyWith(gaplessPlayback: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateCrossfade(bool value) async {
    final updated = state.copyWith(crossfade: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updatePreferredSource(String source) async {
    final updated = state.copyWith(preferredSource: source);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateBackgroundPlayback(bool value) async {
    final updated = state.copyWith(backgroundPlayback: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateMediaNotification(bool value) async {
    final updated = state.copyWith(mediaNotification: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateLockScreenControls(bool value) async {
    final updated = state.copyWith(lockScreenControls: value);
    await _repository.saveSettings(updated);
    state = updated;
  }

  Future<void> updateLastScanTime(String? time) async {
    final updated = state.copyWith(lastScanTime: time);
    await _repository.saveSettings(updated);
    state = updated;
  }
}

/// Provider for the SettingsRepository dependency.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final box = Hive.box(HiveBoxes.preferences);
  return HiveSettingsRepository(box);
});

/// Provider for the SettingsController state.
/// Retrieves stored parameters synchronously from Hive.
final settingsControllerProvider = StateNotifierProvider<SettingsController, SettingsModel>((ref) {
  final repository = ref.watch(settingsRepositoryProvider);
  
  // Create an initial model based on Hive storage values synchronously.
  // Because Hive.box is opened synchronously on startup, this does not block.
  final box = Hive.box(HiveBoxes.preferences);
  
  final initialSettings = SettingsModel(
    themeMode: box.get('settings_theme_mode', defaultValue: 'system') as String,
    resumePlayback: box.get('settings_resume_playback', defaultValue: false) as bool,
    defaultShuffle: box.get('settings_default_shuffle', defaultValue: false) as bool,
    defaultRepeat: box.get('settings_default_repeat', defaultValue: 'off') as String,
    playbackSpeed: box.get('settings_playback_speed', defaultValue: 1.0) as double,
    gaplessPlayback: box.get('settings_gapless_playback', defaultValue: true) as bool,
    crossfade: box.get('settings_crossfade', defaultValue: false) as bool,
    preferredSource: box.get('settings_preferred_source', defaultValue: 'preferLocal') as String,
    backgroundPlayback: box.get('settings_background_playback', defaultValue: true) as bool,
    mediaNotification: box.get('settings_media_notification', defaultValue: true) as bool,
    lockScreenControls: box.get('settings_lock_screen_controls', defaultValue: true) as bool,
    lastScanTime: box.get('settings_last_scan_time') as String?,
  );

  return SettingsController(repository, initialSettings);
});
