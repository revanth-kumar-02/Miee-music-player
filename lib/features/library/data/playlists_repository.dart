import 'package:hive/hive.dart';

import '../../../core/storage/adapters/playlist_hive_model.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';

/// Manages user-created playlists persisted in Hive.
class PlaylistsRepository {
  Box<PlaylistHiveModel> get _box =>
      Hive.box<PlaylistHiveModel>(HiveBoxes.playlists);

  /// Returns all stored playlists ordered by creation date.
  List<PlaylistHiveModel> getPlaylists() {
    final list = _box.values.toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// Stream that emits whenever any playlist changes.
  Stream<List<PlaylistHiveModel>> watchPlaylists() =>
      _box.watch().map((_) => getPlaylists());

  /// Creates a new empty playlist with [name].
  /// Returns the generated playlist id.
  Future<String> createPlaylist(String name) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final playlist = PlaylistHiveModel(
      id: id,
      name: name,
      tracks: [],
      createdAt: DateTime.now(),
    );
    await _box.put(id, playlist);
    return id;
  }

  /// Renames the playlist with [playlistId] to [newName].
  Future<void> renamePlaylist(String playlistId, String newName) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    playlist.name = newName;
    await playlist.save();
  }

  /// Permanently deletes the playlist with [playlistId].
  Future<void> deletePlaylist(String playlistId) async {
    await _box.delete(playlistId);
  }

  /// Appends [track] to playlist [playlistId]. No-op if already present.
  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    final alreadyIn = playlist.tracks.any((t) => t.id == track.id);
    if (!alreadyIn) {
      playlist.tracks.add(TrackHiveModel.fromTrack(track));
      await playlist.save();
    }
  }

  /// Removes the track with [trackId] from playlist [playlistId].
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    playlist.tracks.removeWhere((t) => t.id == trackId);
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
    await playlist.save();
  }

  /// Returns the tracks of playlist [playlistId] as domain [Track] objects.
  List<Track> getPlaylistTracks(String playlistId) {
    final playlist = _box.get(playlistId);
    if (playlist == null) return [];
    return playlist.tracks.map((m) => m.toTrack()).toList(growable: false);
  }
}
