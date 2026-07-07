import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/adapters/playlist_hive_model.dart';
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
