import '../../../features/library/data/playlists_repository.dart';
import '../../../shared/models/track.dart';
import '../domain/playlist_model.dart';

/// Extended repository that converts [PlaylistHiveModel] to [PlaylistModel]
/// and adds business-level validation.
///
/// All Hive access is delegated to the underlying [PlaylistsRepository].
/// This class never touches Hive directly.
class PlaylistRepository {
  final PlaylistsRepository _base;

  PlaylistRepository(this._base);

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns all playlists as [PlaylistModel], newest-modified first.
  List<PlaylistModel> getAllPlaylists() =>
      _base.getPlaylists().map(_toModel).toList(growable: false);

  /// Returns a single playlist by [id], or null if not found.
  PlaylistModel? getPlaylist(String id) {
    final raw = _base.getPlaylist(id);
    return raw == null ? null : _toModel(raw);
  }

  /// Returns the track list for [playlistId] as domain [Track]s.
  List<Track> getPlaylistTracks(String playlistId) =>
      _base.getPlaylistTracks(playlistId);

  // ── Validation ────────────────────────────────────────────────────────────

  /// Returns true if [name] is already used by another playlist.
  bool nameExists(String name, {String? excludeId}) =>
      _base.nameExists(name, excludeId: excludeId);

  /// Validates [name]: non-empty, unique (excluding [excludeId]).
  /// Returns null on success, or an error string on failure.
  String? validateName(String name, {String? excludeId}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Name cannot be empty.';
    if (trimmed.length > 100) return 'Name is too long (max 100 characters).';
    if (nameExists(trimmed, excludeId: excludeId)) {
      return 'A playlist named "$trimmed" already exists.';
    }
    return null;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Creates a new playlist. Returns the id, or throws if name is invalid.
  Future<String> createPlaylist(String name) async {
    final error = validateName(name);
    if (error != null) throw ArgumentError(error);
    return _base.createPlaylist(name.trim());
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final error = validateName(newName, excludeId: id);
    if (error != null) throw ArgumentError(error);
    return _base.renamePlaylist(id, newName.trim());
  }

  Future<void> deletePlaylist(String id) => _base.deletePlaylist(id);

  Future<String> duplicatePlaylist(String id) => _base.duplicatePlaylist(id);

  Future<void> addTrack(String playlistId, Track track) =>
      _base.addTrackToPlaylist(playlistId, track);

  Future<void> removeTrack(String playlistId, String trackId) =>
      _base.removeTrackFromPlaylist(playlistId, trackId);

  Future<void> reorderTracks(String playlistId, int oldIndex, int newIndex) =>
      _base.reorderTracks(playlistId, oldIndex, newIndex);

  // ── Conversion ────────────────────────────────────────────────────────────

  PlaylistModel _toModel(dynamic raw) => PlaylistModel(
        id: raw.id as String,
        name: raw.name as String,
        tracks: (raw.tracks as List).map((t) => t.toTrack() as Track).toList(),
        createdAt: raw.createdAt as DateTime,
        lastModified: raw.lastModified as DateTime,
      );
}
