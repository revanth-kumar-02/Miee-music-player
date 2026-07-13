import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/adapters/playlist_hive_model.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/offline_operation.dart';

/// Manages user-created playlists persisted in Hive with background cloud synchronization.
class PlaylistsRepository {
  final Ref _ref;

  PlaylistsRepository(this._ref);

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

    final op = OfflineOperation(
      id: 'pl_create_${id}_${now.millisecondsSinceEpoch}',
      type: 'playlist_create',
      payload: {
        'id': id,
        'name': name,
        'createdAt': now.toIso8601String(),
        'lastModified': now.toIso8601String(),
      },
      timestamp: now,
    );
    await _ref.read(syncManagerProvider).queueOperation(op);

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

    final op = OfflineOperation(
      id: 'pl_rename_${playlistId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'playlist_rename',
      payload: {
        'id': playlistId,
        'name': newName,
        'lastModified': playlist.lastModified.toIso8601String(),
      },
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
  }

  /// Updates the custom cover image path for [playlistId].
  /// Pass null to clear the custom cover and fall back to auto-derived artwork.
  Future<void> updateCoverPath(String playlistId, String? path) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    playlist.customCoverPath = path;
    playlist.lastModified = DateTime.now();
    await playlist.save();
  }

  /// Permanently deletes the playlist with [playlistId].
  Future<void> deletePlaylist(String playlistId) async {
    await _box.delete(playlistId);

    final op = OfflineOperation(
      id: 'pl_delete_${playlistId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'playlist_delete',
      payload: {'id': playlistId},
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
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

    // Sync metadata
    final op = OfflineOperation(
      id: 'pl_create_${id}_${now.millisecondsSinceEpoch}',
      type: 'playlist_create',
      payload: {
        'id': id,
        'name': copy.name,
        'createdAt': now.toIso8601String(),
        'lastModified': now.toIso8601String(),
      },
      timestamp: now,
    );
    await _ref.read(syncManagerProvider).queueOperation(op);

    // Sync all copied songs
    for (final track in copy.tracks) {
      final songOp = OfflineOperation(
        id: 'pl_song_add_${id}_${track.id}_${DateTime.now().millisecondsSinceEpoch}',
        type: 'playlist_song_add',
        payload: {
          'playlistId': id,
          'track': {
            'id': track.id,
            'title': track.title,
            'artist': track.artist,
            'imageUrl': track.imageUrl,
            'duration': track.duration,
            'filePath': track.filePath,
            'isYoutube': track.filePath == null || track.filePath!.startsWith('http'),
          }
        },
        timestamp: DateTime.now(),
      );
      await _ref.read(syncManagerProvider).queueOperation(songOp);
    }

    return id;
  }

  /// Appends [track] to playlist [playlistId]. No-op if already present.
  Future<void> addTrackToPlaylist(String playlistId, MusicItem track) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    
    String trackId = track.id;
    if (track.isYoutube && !trackId.startsWith('youtube_')) {
      trackId = 'youtube_${track.id}';
    }

    final alreadyIn = playlist.tracks.any((t) {
      final tid = t.id.startsWith('youtube_')
          ? t.id
          : (t.filePath?.contains('youtube.com') == true ? 'youtube_${t.id}' : t.id);
      return tid == trackId;
    });

    if (!alreadyIn) {
      final hiveTrack = TrackHiveModel.fromTrack(track);
      playlist.tracks.add(hiveTrack);
      playlist.lastModified = DateTime.now();
      await playlist.save();

      final op = OfflineOperation(
        id: 'pl_song_add_${playlistId}_${hiveTrack.id}_${DateTime.now().millisecondsSinceEpoch}',
        type: 'playlist_song_add',
        payload: {
          'playlistId': playlistId,
          'track': {
            'id': hiveTrack.id,
            'title': hiveTrack.title,
            'artist': hiveTrack.artist,
            'imageUrl': hiveTrack.imageUrl,
            'duration': hiveTrack.duration,
            'filePath': hiveTrack.filePath,
            'isYoutube': hiveTrack.filePath?.contains('youtube.com') == true || hiveTrack.id.startsWith('youtube_'),
          }
        },
        timestamp: DateTime.now(),
      );
      await _ref.read(syncManagerProvider).queueOperation(op);
    }
  }

  /// Removes the track with [trackId] from playlist [playlistId].
  Future<void> removeTrackFromPlaylist(String playlistId, String trackId) async {
    final playlist = _box.get(playlistId);
    if (playlist == null) return;
    playlist.tracks.removeWhere((t) => t.id == trackId);
    playlist.lastModified = DateTime.now();
    await playlist.save();

    final op = OfflineOperation(
      id: 'pl_song_rem_${playlistId}_${trackId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'playlist_song_remove',
      payload: {
        'playlistId': playlistId,
        'trackId': trackId,
      },
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
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
    
    // Push the full updated order on re-sync since position order resolves on sync
    final op = OfflineOperation(
      id: 'pl_rename_${playlistId}_${DateTime.now().millisecondsSinceEpoch}',
      type: 'playlist_rename',
      payload: {
        'id': playlistId,
        'name': playlist.name,
        'lastModified': playlist.lastModified.toIso8601String(),
      },
      timestamp: DateTime.now(),
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
  }

  /// Permanently clears all playlists from the database.
  Future<void> clearAll() async => _box.clear();

  /// Returns the tracks of playlist [playlistId] as domain [Track] objects.
  List<Track> getPlaylistTracks(String playlistId) {
    final playlist = _box.get(playlistId);
    if (playlist == null) return [];
    return playlist.tracks
        .map((m) => m.toTrack())
        .where((t) {
          final clean = t.artist.trim().toLowerCase();
          return !(clean.isEmpty ||
              clean == 'unknown' ||
              clean == '<unknown>' ||
              clean == 'unknown artist');
        })
        .toList(growable: false);
  }
}
