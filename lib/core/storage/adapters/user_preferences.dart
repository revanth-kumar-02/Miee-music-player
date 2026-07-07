import 'package:hive/hive.dart';

/// Hive model storing all user-configurable preferences.
///
/// TypeId 6 is permanently reserved for this model.
class UserPreferences extends HiveObject {
  /// Theme identifier: 'dark' | 'light' | 'system'.
  String theme;

  /// Playback speed multiplier (default 1.0).
  double playbackSpeed;

  /// Repeat mode string: 'off' | 'one' | 'all'.
  String repeatMode;

  /// Whether shuffle is enabled.
  bool isShuffle;

  /// Sleep timer in minutes, null if not set.
  int? sleepTimerMinutes;

  /// Audio quality preference: 'low' | 'medium' | 'high'.
  String audioQuality;

  UserPreferences({
    this.theme = 'dark',
    this.playbackSpeed = 1.0,
    this.repeatMode = 'off',
    this.isShuffle = false,
    this.sleepTimerMinutes,
    this.audioQuality = 'high',
  });
}

/// Manual [TypeAdapter] for [UserPreferences].
class UserPreferencesAdapter extends TypeAdapter<UserPreferences> {
  @override
  final int typeId = 6;

  @override
  UserPreferences read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserPreferences(
      theme: fields[0] as String? ?? 'dark',
      playbackSpeed: fields[1] as double? ?? 1.0,
      repeatMode: fields[2] as String? ?? 'off',
      isShuffle: fields[3] as bool? ?? false,
      sleepTimerMinutes: fields[4] as int?,
      audioQuality: fields[5] as String? ?? 'high',
    );
  }

  @override
  void write(BinaryWriter writer, UserPreferences obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.theme)
      ..writeByte(1)
      ..write(obj.playbackSpeed)
      ..writeByte(2)
      ..write(obj.repeatMode)
      ..writeByte(3)
      ..write(obj.isShuffle)
      ..writeByte(4)
      ..write(obj.sleepTimerMinutes)
      ..writeByte(5)
      ..write(obj.audioQuality);
  }
}
