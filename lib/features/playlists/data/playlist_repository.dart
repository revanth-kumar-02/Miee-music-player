import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../features/library/data/playlists_repository.dart';
import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
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

  /// Updates the custom cover image path for [playlistId].
  /// Pass null to clear the custom cover and fall back to auto-derived artwork.
  Future<void> updateCoverPath(String playlistId, String? path) =>
      _base.updateCoverPath(playlistId, path);

  Future<void> addTrack(String playlistId, MusicItem track) =>
      _base.addTrackToPlaylist(playlistId, track);

  Future<int> addTracks(String playlistId, List<MusicItem> tracks) =>
      _base.addTracksToPlaylist(playlistId, tracks);


  Future<void> removeTrack(String playlistId, String trackId) =>
      _base.removeTrackFromPlaylist(playlistId, trackId);

  Future<void> reorderTracks(String playlistId, int oldIndex, int newIndex) =>
      _base.reorderTracks(playlistId, oldIndex, newIndex);

  // ── Conversion ────────────────────────────────────────────────────────────

  PlaylistModel _toModel(dynamic raw) {
    if (raw == null) {
      return PlaylistModel(
        id: '',
        name: 'Untitled Playlist',
        tracks: const [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );
    }

    final tracksList = <Track>[];
    try {
      final rawTracks = raw.tracks;
      if (rawTracks is List) {
        for (final t in rawTracks) {
          Track? track;
          if (t is TrackHiveModel) {
            track = t.toTrack();
          } else if (t is Track) {
            track = t;
          } else if (t is MusicItem) {
            track = Track(
              id: t.id,
              title: t.title,
              artist: t.artist,
              imageUrl: t.imageUrl,
              duration: t.duration,
              filePath: t.filePath,
            );
          } else if (t is Map) {
            track = Track(
              id: (t['id'] ?? '').toString(),
              title: (t['title'] ?? 'Unknown Title').toString(),
              artist: (t['artist'] ?? 'Unknown Artist').toString(),
              imageUrl: (t['imageUrl'] ?? t['image_url'] ?? '').toString(),
              duration: (t['duration'] ?? '0:00').toString(),
              filePath: t['filePath'] as String?,
            );
          }

          if (track != null) {
            final clean = track.artist.trim().toLowerCase();
            if (!(clean.isEmpty ||
                clean == 'unknown' ||
                clean == '<unknown>' ||
                clean == 'unknown artist')) {
              tracksList.add(track);
            }
          }
        }
      }
    } catch (_) {}

    DateTime parseDate(dynamic val, DateTime fallback) {
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val) ?? fallback;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      return fallback;
    }

    final now = DateTime.now();
    final createdAt = parseDate(raw.createdAt, now);
    final lastModified = parseDate(raw.lastModified, createdAt);

    return PlaylistModel(
      id: (raw.id ?? '').toString(),
      name: (raw.name ?? 'Untitled Playlist').toString(),
      tracks: tracksList,
      createdAt: createdAt,
      lastModified: lastModified,
      customCoverPath: raw.customCoverPath as String?,
    );
  }
}
