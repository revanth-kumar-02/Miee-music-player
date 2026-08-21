import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/providers.dart';
import '../../../features/library/data/playlists_repository.dart';
import '../../../features/library/providers/library_providers.dart';
import '../../../shared/models/track.dart';
import '../data/playlist_repository.dart';
import '../domain/playlist_model.dart';

import '../../../shared/models/music_item.dart';

// ── Repository providers ──────────────────────────────────────────────────────

/// Provides the low-level [PlaylistsRepository] (Hive-backed).
/// Reuses the instance already registered in [library_providers.dart].
final _basePlaylistsRepoProvider = Provider<PlaylistsRepository>(
  (ref) => ref.watch(playlistsRepositoryProvider),
);

/// Provides the extended [PlaylistRepository] (domain model, validation).
final playlistRepositoryProvider = Provider<PlaylistRepository>((ref) {
  return PlaylistRepository(ref.watch(_basePlaylistsRepoProvider));
});

// ── Playlists state ───────────────────────────────────────────────────────────

class PlaylistsState {
  final List<PlaylistModel> playlists;
  final bool isLoading;
  final String? error;

  const PlaylistsState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
  });

  PlaylistsState copyWith({
    List<PlaylistModel>? playlists,
    bool? isLoading,
    String? error,
  }) =>
      PlaylistsState(
        playlists: playlists ?? this.playlists,
        isLoading: isLoading ?? this.isLoading,
        error: error,
      );
}

// ── PlaylistController ────────────────────────────────────────────────────────

/// Manages all playlist operations and keeps the UI in sync.
class PlaylistController extends StateNotifier<PlaylistsState> {
  final PlaylistRepository _repo;
  final Ref _ref;

  PlaylistController(this._repo, this._ref)
      : super(PlaylistsState(playlists: _repo.getAllPlaylists()));

  void _refresh() => state = state.copyWith(playlists: _repo.getAllPlaylists(), error: null);

  // ── CRUD ───────────────────────────────────────────────────────────────────

  /// Creates a playlist. Returns the new id, or null on validation error.
  Future<String?> createPlaylist(String name) async {
    try {
      final id = await _repo.createPlaylist(name);
      _refresh();
      return id;
    } on ArgumentError catch (e) {
      state = state.copyWith(error: e.message as String?);
      return null;
    }
  }

  /// Renames [id]. Returns the error string if validation fails, null on success.
  Future<String?> renamePlaylist(String id, String newName) async {
    try {
      await _repo.renamePlaylist(id, newName);
      _refresh();
      return null;
    } on ArgumentError catch (e) {
      return e.message as String?;
    }
  }

  Future<void> deletePlaylist(String id) async {
    await _repo.deletePlaylist(id);
    _refresh();
  }

  Future<void> duplicatePlaylist(String id) async {
    await _repo.duplicatePlaylist(id);
    _refresh();
  }

  /// Sets or clears the custom cover image for [playlistId].
  /// Pass null [path] to remove the custom cover and fall back to auto-derived artwork.
  Future<void> updateCoverPath(String playlistId, String? path) async {
    await _repo.updateCoverPath(playlistId, path);
    _refresh();
  }

  // ── Track operations ───────────────────────────────────────────────────────

  Future<void> addTrack(String playlistId, MusicItem track) async {
    await _repo.addTrack(playlistId, track);
    _refresh();
  }

  Future<void> removeTrack(String playlistId, String trackId) async {
    await _repo.removeTrack(playlistId, trackId);
    _refresh();
  }

  Future<void> reorderTracks(String playlistId, int oldIndex, int newIndex) async {
    await _repo.reorderTracks(playlistId, oldIndex, newIndex);
    _refresh();
  }

  // ── Playback ───────────────────────────────────────────────────────────────

  /// Loads all playlist tracks into [PlayerController] and starts playing.
  void playPlaylist(String playlistId) {
    final tracks = _repo.getPlaylistTracks(playlistId);
    if (tracks.isEmpty) return;
    _ref.read(playerControllerProvider.notifier).selectTrack(tracks.first, tracks);
  }

  /// Loads playlist tracks shuffled into [PlayerController].
  void shufflePlaylist(String playlistId) {
    final tracks = List<MusicItem>.from(_repo.getPlaylistTracks(playlistId))..shuffle();
    if (tracks.isEmpty) return;
    _ref.read(playerControllerProvider.notifier).selectTrack(tracks.first, tracks);
  }


  // ── Validation helper ──────────────────────────────────────────────────────

  String? validateName(String name, {String? excludeId}) =>
      _repo.validateName(name, excludeId: excludeId);
}

/// Primary provider for playlist management.
final playlistControllerProvider =
    StateNotifierProvider<PlaylistController, PlaylistsState>((ref) {
  final repo = ref.watch(playlistRepositoryProvider);
  return PlaylistController(repo, ref);
});

// ── Convenience derived providers ─────────────────────────────────────────────

/// All playlists as a flat list (newest-modified first).
final allPlaylistsProvider = Provider<List<PlaylistModel>>((ref) {
  return ref.watch(playlistControllerProvider).playlists;
});

/// Number of user playlists.
final playlistCountProvider = Provider<int>((ref) {
  return ref.watch(allPlaylistsProvider).length;
});

/// The currently selected playlist id (for the detail screen).
final selectedPlaylistIdProvider = StateProvider<String?>((ref) => null);

/// The currently selected [PlaylistModel] (null when none selected).
final selectedPlaylistProvider = Provider<PlaylistModel?>((ref) {
  final id = ref.watch(selectedPlaylistIdProvider);
  if (id == null) return null;
  return ref.watch(playlistControllerProvider).playlists
      .where((p) => p.id == id)
      .firstOrNull;
});

/// Whether any playlist operation is in progress.
final playlistLoadingProvider = Provider<bool>((ref) {
  return ref.watch(playlistControllerProvider).isLoading;
});

/// Last playlist error message, null when no error.
final playlistErrorProvider = Provider<String?>((ref) {
  return ref.watch(playlistControllerProvider).error;
});
