import 'package:hive/hive.dart';
import '../../../core/storage/adapters/playlist_hive_model.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';

/// Manages user-created playlists persisted in Hive.
class PlaylistsRepository {
  Box<PlaylistHiveModel> get _box =>
      Hive.box<PlaylistHiveModel>(HiveBoxes.playlists);

  /// Returns all stored playlists ordered by last modified (newest first).
  List<PlaylistHiveModel> getPlaylists() {
    final list = _box.values.toList();
    list.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return list;
  }

  /// Returns a single playlist by [id], or null if not found.
  PlaylistHiveModel? getPlaylist(String id) => _box.get(id);

  /// Stream that emits whenever any playlist changes.
  Stream<List<PlaylistHiveModel>> watchPlaylists() =>
      _box.watch().map((_) => getPlaylists());

  /// Creates a new empty playlist with [name].
  /// Returns the generated playlist id.
  Future<String> createPlaylist(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    final playlist = PlaylistHiveModel(
      id: id,
      name: name,
      tracks: [],
      createdAt: now,
      lastModified: now,
    );
    await _box.put(id, playlist);
    return id;
  }

  /// Returns true if any playlist already uses [name] (case-insensitive),
  /// excluding the playlist with [excludeId].
  bool nameExists(String name, {String? excludeId}) {
    final lower = name.trim().toLowerCase();
    return _box.values.any((p) =>
        p.name.toLowerCase() == lower && p.id != excludeId);
  }

  /// Renames the playlist with [playlistId] to [newName].
  Future<void> renamePlaylist(String playlistId, String newName) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    playlist.name = newName;
    playlist.lastModified = DateTime.now();
    await playlist.save();
  }

  /// Permanently deletes the playlist with [playlistId].
  Future<void> deletePlaylist(String playlistId) async {
    await _box.delete(playlistId);
  }

  /// Creates a deep copy of [playlistId] with " (Copy)" appended to the name.
  Future<String> duplicatePlaylist(String playlistId) async {
    final source = _box.get(playlistId);
    if (source == null) return '';
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final now = DateTime.now();
    final copy = PlaylistHiveModel(
      id: id,
      name: '${source.name} (Copy)',
      tracks: List<TrackHiveModel>.from(source.tracks),
      createdAt: now,
      lastModified: now,
    );
    await _box.put(id, copy);
    return id;
  }

  /// Appends [track] to playlist [playlistId]. No-op if already present.
  Future<void> addTrackToPlaylist(String playlistId, MusicItem track) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    final alreadyIn = playlist.tracks.any((t) => t.id == track.id);
    if (!alreadyIn) {
      playlist.tracks.add(TrackHiveModel.fromTrack(track));
      playlist.lastModified = DateTime.now();
      await playlist.save();
    }
  }


  /// Removes the track with [trackId] from playlist [playlistId].
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    playlist.tracks.removeWhere((t) => t.id == trackId);
    playlist.lastModified = DateTime.now();
    await playlist.save();
  }

  /// Reorders the track at [oldIndex] to [newIndex] within playlist [playlistId].
  Future<void> reorderTracks(
      String playlistId, int oldIndex, int newIndex) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;

    final tracks = playlist.tracks;
    if (oldIndex < 0 || oldIndex >= tracks.length) return;

    final track = tracks.removeAt(oldIndex);
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    tracks.insert(insertAt.clamp(0, tracks.length), track);
    playlist.lastModified = DateTime.now();
    await playlist.save();
  }

  /// Permanently clears all playlists from the database.
  Future<void> clearAll() async => _box.clear();

  /// Returns the tracks of playlist [playlistId] as domain [Track] objects.
  List<Track> getPlaylistTracks(String playlistId) {
    final playlist = _box.get(playlistId);
    if (playlist == null) return [];
    return playlist.tracks.map((m) => m.toTrack()).toList(growable: false);
  }
}

