import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/settings_model.dart';
import '../../profile/domain/profile_model.dart';
import '../../profile/presentation/profile_controller.dart';

/// Notifier that proxies setting updates directly to the active Profile database.
class SettingsController extends StateNotifier<SettingsModel> {
  final Ref _ref;

  SettingsController(this._ref) : super(_mapSettings(_ref.read(profileProvider))) {
    debugPrint('STARTUP: SettingsController() created');
    _ref.listen<ProfileModel>(profileProvider, (previous, next) {
      debugPrint('STARTUP: SettingsController heard profileProvider change');
      state = _mapSettings(next);
    });
  }

  static SettingsModel _mapSettings(ProfileModel profile) {
    return SettingsModel(
      themeMode: profile.themeMode,
      resumePlayback: profile.resumePlayback,
      defaultShuffle: profile.defaultShuffle,
      defaultRepeat: profile.defaultRepeat,
      playbackSpeed: profile.playbackSpeed,
      gaplessPlayback: profile.gaplessPlayback,
      crossfade: profile.crossfade,
      preferredSource: profile.preferredSource,
      backgroundPlayback: profile.backgroundPlayback,
      mediaNotification: profile.mediaNotification,
      lockScreenControls: profile.lockScreenControls,
      lastScanTime: profile.lastScanTime,
    );
  }

  Future<void> updateThemeMode(String mode) async {
    await _ref.read(profileProvider.notifier).updateThemeMode(mode);
  }

  Future<void> updateResumePlayback(bool value) async {
    await _ref.read(profileProvider.notifier).updateResumePlayback(value);
  }

  Future<void> updateDefaultShuffle(bool value) async {
    await _ref.read(profileProvider.notifier).updateDefaultShuffle(value);
  }

  Future<void> updateDefaultRepeat(String value) async {
    await _ref.read(profileProvider.notifier).updateDefaultRepeat(value);
  }

  Future<void> updatePlaybackSpeed(double value) async {
    await _ref.read(profileProvider.notifier).updatePlaybackSpeed(value);
  }

  Future<void> updateGaplessPlayback(bool value) async {
    await _ref.read(profileProvider.notifier).updateGaplessPlayback(value);
  }

  Future<void> updateCrossfade(bool value) async {
    await _ref.read(profileProvider.notifier).updateCrossfade(value);
  }

  Future<void> updatePreferredSource(String source) async {
    await _ref.read(profileProvider.notifier).updatePreferredSource(source);
  }

  Future<void> updateBackgroundPlayback(bool value) async {
    await _ref.read(profileProvider.notifier).updateBackgroundPlayback(value);
  }

  Future<void> updateMediaNotification(bool value) async {
    await _ref.read(profileProvider.notifier).updateMediaNotification(value);
  }

  Future<void> updateLockScreenControls(bool value) async {
    await _ref.read(profileProvider.notifier).updateLockScreenControls(value);
  }

  Future<void> updateLastScanTime(String? time) async {
    await _ref.read(profileProvider.notifier).updateLastScanTime(time);
  }
}

/// Provider for the SettingsController state, proxying to the profile provider.
final settingsControllerProvider = StateNotifierProvider<SettingsController, SettingsModel>((ref) {
  return SettingsController(ref);
});
