/// Central registry of all Hive box names used in Miee.
///
/// Using constants prevents typos and makes renaming boxes a single-line change.
abstract class HiveBoxes {
  /// Stores favorited [TrackHiveModel] entries keyed by track id.
  static const String favorites = 'miee_favorites';

  /// Stores user-created [PlaylistHiveModel] entries keyed by playlist id.
  static const String playlists = 'miee_playlists';

  /// Stores [HistoryEntry] objects representing the last 100 played songs.
  static const String recentlyPlayed = 'miee_recently_played';

  /// Stores raw play-count integers keyed by track id.
  static const String mostPlayed = 'miee_most_played';

  /// Stores [PlaybackHistoryEntry] objects for session-level history.
  static const String playbackHistory = 'miee_playback_history';

  /// Stores a single [QueueSnapshot] under the key [queueSnapshotKey].
  static const String queueState = 'miee_queue_state';

  /// Key used inside [queueState] box for the current snapshot.
  static const String queueSnapshotKey = 'current';

  /// Stores recent search query strings (max 20).
  static const String searchHistory = 'miee_search_history';

  /// Stores user preference values keyed by [PreferenceKeys] constants.
  static const String preferences = 'miee_preferences';

  /// Stores local profile details and personal configuration settings.
  static const String profile = 'miee_profile';

  /// Stores pending offline operations to replay on connection return.
  static const String offlineQueue = 'miee_offline_queue';
}

/// Typed keys for the [HiveBoxes.preferences] box.
abstract class PreferenceKeys {
  static const String playbackSpeed = 'playback_speed';
  static const String repeatMode = 'repeat_mode';
  static const String shuffle = 'shuffle';
  static const String sleepTimerMinutes = 'sleep_timer_minutes';
  static const String audioQuality = 'audio_quality';
  static const String sourceSelection = 'source_selection';
  static const String resumePlayback = 'resume_playback';
  static const String autoPlayNext = 'auto_play_next';
  static const String shuffleDefault = 'shuffle_default';
  static const String repeatDefault = 'repeat_default';
  static const String crossfadeEnabled = 'crossfade_enabled';
  static const String gaplessPlaybackEnabled = 'gapless_playback';
  static const String lastScanTime = 'last_scan_time';
  static const String mediaNotificationEnabled = 'media_notification_enabled';
  static const String backgroundPlaybackEnabled = 'background_playback_enabled';
  static const String lockScreenControlsEnabled = 'lock_screen_controls_enabled';
}
