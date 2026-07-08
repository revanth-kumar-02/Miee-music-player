import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/adapters/playlist_hive_model.dart';
import '../../../core/storage/adapters/history_entry.dart';
import '../../../shared/models/track.dart';
import '../data/favorites_repository.dart';
import '../data/most_played_repository.dart';
import '../data/playback_history_repository.dart';
import '../data/playlists_repository.dart';
import '../data/preferences_repository.dart';
import '../data/queue_state_repository.dart';
import '../data/recently_played_repository.dart';
import '../data/search_history_repository.dart';

// ── Repository providers ─────────────────────────────────────────────────────

/// Provides the [FavoritesRepository] singleton.
final favoritesRepositoryProvider = Provider<FavoritesRepository>(
  (ref) => FavoritesRepository(),
);

/// Provides the [PlaylistsRepository] singleton.
final playlistsRepositoryProvider = Provider<PlaylistsRepository>(
  (ref) => PlaylistsRepository(),
);

/// Provides the [RecentlyPlayedRepository] singleton.
final recentlyPlayedRepositoryProvider = Provider<RecentlyPlayedRepository>(
  (ref) => RecentlyPlayedRepository(),
);

/// Provides the [MostPlayedRepository] singleton.
final mostPlayedRepositoryProvider = Provider<MostPlayedRepository>(
  (ref) => MostPlayedRepository(),
);

/// Provides the [PlaybackHistoryRepository] singleton.
final playbackHistoryRepositoryProvider = Provider<PlaybackHistoryRepository>(
  (ref) => PlaybackHistoryRepository(),
);

/// Provides the [QueueStateRepository] singleton.
final queueStateRepositoryProvider = Provider<QueueStateRepository>(
  (ref) => QueueStateRepository(),
);

/// Provides the [SearchHistoryRepository] singleton.
final searchHistoryRepositoryProvider = Provider<SearchHistoryRepository>(
  (ref) => SearchHistoryRepository(),
);

/// Provides the [PreferencesRepository] singleton.
final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) => PreferencesRepository(),
);

class SettingsState {
  final String theme;
  final double playbackSpeed;
  final String repeatMode;
  final bool isShuffle;
  final String sourceSelection;
  final bool resumePlayback;
  final bool autoPlayNext;
  final bool shuffleDefault;
  final String repeatDefault;
  final bool crossfadeEnabled;
  final bool gaplessPlaybackEnabled;
  final String? lastScanTime;
  final bool mediaNotificationEnabled;
  final bool backgroundPlaybackEnabled;
  final bool lockScreenControlsEnabled;

  const SettingsState({
    required this.theme,
    required this.playbackSpeed,
    required this.repeatMode,
    required this.isShuffle,
    required this.sourceSelection,
    required this.resumePlayback,
    required this.autoPlayNext,
    required this.shuffleDefault,
    required this.repeatDefault,
    required this.crossfadeEnabled,
    required this.gaplessPlaybackEnabled,
    this.lastScanTime,
    required this.mediaNotificationEnabled,
    required this.backgroundPlaybackEnabled,
    required this.lockScreenControlsEnabled,
  });

  SettingsState copyWith({
    String? theme,
    double? playbackSpeed,
    String? repeatMode,
    bool? isShuffle,
    String? sourceSelection,
    bool? resumePlayback,
    bool? autoPlayNext,
    bool? shuffleDefault,
    String? repeatDefault,
    bool? crossfadeEnabled,
    bool? gaplessPlaybackEnabled,
    String? lastScanTime,
    bool? mediaNotificationEnabled,
    bool? backgroundPlaybackEnabled,
    bool? lockScreenControlsEnabled,
  }) {
    return SettingsState(
      theme: theme ?? this.theme,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      repeatMode: repeatMode ?? this.repeatMode,
      isShuffle: isShuffle ?? this.isShuffle,
      sourceSelection: sourceSelection ?? this.sourceSelection,
      resumePlayback: resumePlayback ?? this.resumePlayback,
      autoPlayNext: autoPlayNext ?? this.autoPlayNext,
      shuffleDefault: shuffleDefault ?? this.shuffleDefault,
      repeatDefault: repeatDefault ?? this.repeatDefault,
      crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
      gaplessPlaybackEnabled: gaplessPlaybackEnabled ?? this.gaplessPlaybackEnabled,
      lastScanTime: lastScanTime ?? this.lastScanTime,
      mediaNotificationEnabled: mediaNotificationEnabled ?? this.mediaNotificationEnabled,
      backgroundPlaybackEnabled: backgroundPlaybackEnabled ?? this.backgroundPlaybackEnabled,
      lockScreenControlsEnabled: lockScreenControlsEnabled ?? this.lockScreenControlsEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  final PreferencesRepository _repo;

  SettingsNotifier(this._repo)
      : super(SettingsState(
          theme: _repo.getTheme(),
          playbackSpeed: _repo.getPlaybackSpeed(),
          repeatMode: _repo.getRepeatMode(),
          isShuffle: _repo.getShuffle(),
          sourceSelection: _repo.getSourceSelectionMode(),
          resumePlayback: _repo.getResumePlayback(),
          autoPlayNext: _repo.getAutoPlayNext(),
          shuffleDefault: _repo.getShuffleDefault(),
          repeatDefault: _repo.getRepeatDefault(),
          crossfadeEnabled: _repo.getCrossfadeEnabled(),
          gaplessPlaybackEnabled: _repo.getGaplessPlaybackEnabled(),
          lastScanTime: _repo.getLastScanTime(),
          mediaNotificationEnabled: _repo.getMediaNotificationEnabled(),
          backgroundPlaybackEnabled: _repo.getBackgroundPlaybackEnabled(),
          lockScreenControlsEnabled: _repo.getLockScreenControlsEnabled(),
        ));

  Future<void> setTheme(String theme) async {
    await _repo.setTheme(theme);
    state = state.copyWith(theme: theme);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _repo.setPlaybackSpeed(speed);
    state = state.copyWith(playbackSpeed: speed);
  }

  Future<void> setRepeatMode(String mode) async {
    await _repo.setRepeatMode(mode);
    state = state.copyWith(repeatMode: mode);
  }

  Future<void> setShuffle(bool value) async {
    await _repo.setShuffle(value);
    state = state.copyWith(isShuffle: value);
  }

  Future<void> setSourceSelectionMode(String mode) async {
    await _repo.setSourceSelectionMode(mode);
    state = state.copyWith(sourceSelection: mode);
  }

  Future<void> setResumePlayback(bool value) async {
    await _repo.setResumePlayback(value);
    state = state.copyWith(resumePlayback: value);
  }

  Future<void> setAutoPlayNext(bool value) async {
    await _repo.setAutoPlayNext(value);
    state = state.copyWith(autoPlayNext: value);
  }

  Future<void> setShuffleDefault(bool value) async {
    await _repo.setShuffleDefault(value);
    state = state.copyWith(shuffleDefault: value);
  }

  Future<void> setRepeatDefault(String value) async {
    await _repo.setRepeatDefault(value);
    state = state.copyWith(repeatDefault: value);
  }

  Future<void> setCrossfadeEnabled(bool value) async {
    await _repo.setCrossfadeEnabled(value);
    state = state.copyWith(crossfadeEnabled: value);
  }

  Future<void> setGaplessPlaybackEnabled(bool value) async {
    await _repo.setGaplessPlaybackEnabled(value);
    state = state.copyWith(gaplessPlaybackEnabled: value);
  }

  Future<void> setLastScanTime(String? time) async {
    await _repo.setLastScanTime(time);
    state = state.copyWith(lastScanTime: time);
  }

  Future<void> setMediaNotificationEnabled(bool value) async {
    await _repo.setMediaNotificationEnabled(value);
    state = state.copyWith(mediaNotificationEnabled: value);
  }

  Future<void> setBackgroundPlaybackEnabled(bool value) async {
    await _repo.setBackgroundPlaybackEnabled(value);
    state = state.copyWith(backgroundPlaybackEnabled: value);
  }

  Future<void> setLockScreenControlsEnabled(bool value) async {
    await _repo.setLockScreenControlsEnabled(value);
    state = state.copyWith(lockScreenControlsEnabled: value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final repo = ref.watch(preferencesRepositoryProvider);
  return SettingsNotifier(repo);
});

/// Reactive source selection preference proxy.
final sourceSelectionProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider.select((s) => s.sourceSelection));
});


// ── State providers ───────────────────────────────────────────────────────────

/// Reactive list of favorited [Track] objects.
///
/// Notifier delegates all writes to [FavoritesRepository].
class FavoritesNotifier extends StateNotifier<List<Track>> {
  final FavoritesRepository _repo;

  FavoritesNotifier(this._repo) : super(_repo.getFavorites());

  Future<void> addFavorite(Track track) async {
    await _repo.addFavorite(track);
    state = _repo.getFavorites();
  }

  Future<void> removeFavorite(String trackId) async {
    await _repo.removeFavorite(trackId);
    state = _repo.getFavorites();
  }

  bool isFavorite(String trackId) => _repo.isFavorite(trackId);

  Future<void> clearAll() async {
    await _repo.clearAll();
    state = [];
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<Track>>((ref) {
  final repo = ref.watch(favoritesRepositoryProvider);
  return FavoritesNotifier(repo);
});

// ── Playlists notifier ───────────────────────────────────────────────────────

/// Reactive list of user playlists.
class PlaylistsNotifier extends StateNotifier<List<PlaylistHiveModel>> {
  final PlaylistsRepository _repo;

  PlaylistsNotifier(this._repo) : super(_repo.getPlaylists());

  Future<String> createPlaylist(String name) async {
    final id = await _repo.createPlaylist(name);
    state = _repo.getPlaylists();
    return id;
  }

  Future<void> renamePlaylist(String id, String newName) async {
    await _repo.renamePlaylist(id, newName);
    state = _repo.getPlaylists();
  }

  Future<void> deletePlaylist(String id) async {
    await _repo.deletePlaylist(id);
    state = _repo.getPlaylists();
  }

  Future<void> addTrack(String playlistId, Track track) async {
    await _repo.addTrackToPlaylist(playlistId, track);
    state = _repo.getPlaylists();
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    await _repo.removeTrackFromPlaylist(playlistId, trackId);
    state = _repo.getPlaylists();
  }

  Future<void> reorderTracks(
      String playlistId, int oldIndex, int newIndex) async {
    await _repo.reorderTracks(playlistId, oldIndex, newIndex);
    state = _repo.getPlaylists();
  }

  Future<void> clearAll() async {
    await _repo.clearAll();
    state = [];
  }
}

final userPlaylistsProvider =
    StateNotifierProvider<PlaylistsNotifier, List<PlaylistHiveModel>>((ref) {
  final repo = ref.watch(playlistsRepositoryProvider);
  return PlaylistsNotifier(repo);
});

// ── Search history notifier ──────────────────────────────────────────────────

/// Reactive search history list (newest first).
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  final SearchHistoryRepository _repo;

  SearchHistoryNotifier(this._repo) : super(_repo.getSearchHistory());

  Future<void> addSearch(String query) async {
    await _repo.addSearch(query);
    state = _repo.getSearchHistory();
  }

  Future<void> removeEntry(String query) async {
    await _repo.removeEntry(query);
    state = _repo.getSearchHistory();
  }

  Future<void> clearAll() async {
    await _repo.clearAll();
    state = [];
  }
}

final searchHistoryProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>((ref) {
  final repo = ref.watch(searchHistoryRepositoryProvider);
  return SearchHistoryNotifier(repo);
});

// ── Preferences notifier ─────────────────────────────────────────────────────

/// Exposes current user preferences as a typed snapshot.
class PreferencesState {
  final String theme;
  final double playbackSpeed;
  final String repeatMode;
  final bool isShuffle;
  final int? sleepTimerMinutes;
  final String audioQuality;

  const PreferencesState({
    required this.theme,
    required this.playbackSpeed,
    required this.repeatMode,
    required this.isShuffle,
    this.sleepTimerMinutes,
    required this.audioQuality,
  });
}

class PreferencesNotifier extends StateNotifier<PreferencesState> {
  final PreferencesRepository _repo;

  PreferencesNotifier(this._repo)
      : super(PreferencesState(
          theme: _repo.getTheme(),
          playbackSpeed: _repo.getPlaybackSpeed(),
          repeatMode: _repo.getRepeatMode(),
          isShuffle: _repo.getShuffle(),
          sleepTimerMinutes: _repo.getSleepTimerMinutes(),
          audioQuality: _repo.getAudioQuality(),
        ));

  Future<void> setTheme(String theme) async {
    await _repo.setTheme(theme);
    state = PreferencesState(
      theme: theme,
      playbackSpeed: state.playbackSpeed,
      repeatMode: state.repeatMode,
      isShuffle: state.isShuffle,
      sleepTimerMinutes: state.sleepTimerMinutes,
      audioQuality: state.audioQuality,
    );
  }

  Future<void> setPlaybackSpeed(double speed) async {
    await _repo.setPlaybackSpeed(speed);
    state = PreferencesState(
      theme: state.theme,
      playbackSpeed: speed,
      repeatMode: state.repeatMode,
      isShuffle: state.isShuffle,
      sleepTimerMinutes: state.sleepTimerMinutes,
      audioQuality: state.audioQuality,
    );
  }

  Future<void> setRepeatMode(String mode) async {
    await _repo.setRepeatMode(mode);
    state = PreferencesState(
      theme: state.theme,
      playbackSpeed: state.playbackSpeed,
      repeatMode: mode,
      isShuffle: state.isShuffle,
      sleepTimerMinutes: state.sleepTimerMinutes,
      audioQuality: state.audioQuality,
    );
  }

  Future<void> setShuffle(bool value) async {
    await _repo.setShuffle(value);
    state = PreferencesState(
      theme: state.theme,
      playbackSpeed: state.playbackSpeed,
      repeatMode: state.repeatMode,
      isShuffle: value,
      sleepTimerMinutes: state.sleepTimerMinutes,
      audioQuality: state.audioQuality,
    );
  }

  Future<void> setSleepTimer(int? minutes) async {
    await _repo.setSleepTimerMinutes(minutes);
    state = PreferencesState(
      theme: state.theme,
      playbackSpeed: state.playbackSpeed,
      repeatMode: state.repeatMode,
      isShuffle: state.isShuffle,
      sleepTimerMinutes: minutes,
      audioQuality: state.audioQuality,
    );
  }

  Future<void> setAudioQuality(String quality) async {
    await _repo.setAudioQuality(quality);
    state = PreferencesState(
      theme: state.theme,
      playbackSpeed: state.playbackSpeed,
      repeatMode: state.repeatMode,
      isShuffle: state.isShuffle,
      sleepTimerMinutes: state.sleepTimerMinutes,
      audioQuality: quality,
    );
  }
}

final preferencesProvider =
    StateNotifierProvider<PreferencesNotifier, PreferencesState>((ref) {
  final repo = ref.watch(preferencesRepositoryProvider);
  return PreferencesNotifier(repo);
});

final recentlyPlayedProvider = StreamProvider<List<HistoryEntry>>((ref) {
  final repo = ref.watch(recentlyPlayedRepositoryProvider);
  return repo.watchRecentlyPlayed();
});
