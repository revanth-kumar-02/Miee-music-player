import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/offline_operation.dart';

/// Manages persisted favorite tracks with background cloud synchronization.
class FavoritesRepository {
  final Ref _ref;

  FavoritesRepository(this._ref);

  Box<TrackHiveModel> get _box =>
      Hive.box<TrackHiveModel>(HiveBoxes.favorites);

  /// Adds [track] to favorites. No-op if already favorited.
  Future<void> addFavorite(Track track) async {
    if (!_box.containsKey(track.id)) {
      await _box.put(track.id, TrackHiveModel.fromTrack(track));

      final op = OfflineOperation(
        id: 'fav_add_${track.id}_${DateTime.now().millisecondsSinceEpoch}',
        type: 'favorite_add',
        payload: {
          'id': track.id,
          'title': track.title,
          'artist': track.artist,
          'imageUrl': track.imageUrl,
          'duration': track.duration,
          'filePath': track.filePath,
          'isYoutube': track.isYoutube,
        },
        timestamp: DateTime.now(),
      );
      await _ref.read(syncManagerProvider).queueOperation(op);
    }
  }

  /// Removes the track with [trackId] from favorites. No-op if not present.
  Future<void> removeFavorite(String trackId) async {
    if (_box.containsKey(trackId)) {
      await _box.delete(trackId);

      final op = OfflineOperation(
        id: 'fav_rem_${trackId}_${DateTime.now().millisecondsSinceEpoch}',
        type: 'favorite_remove',
        payload: {'id': trackId},
        timestamp: DateTime.now(),
      );
      await _ref.read(syncManagerProvider).queueOperation(op);
    }
  }

  /// Returns true if the track with [trackId] is currently favorited.
  bool isFavorite(String trackId) => _box.containsKey(trackId);

  /// Returns the current list of favorited tracks.
  List<Track> getFavorites() =>
      _box.values.map((m) => m.toTrack()).toList(growable: false);

  /// Stream that emits a new list whenever favorites change.
  Stream<List<Track>> watchFavorites() => _box.watch().map((_) => getFavorites());

  /// Clears all favorites.
  Future<void> clearAll() async => _box.clear();
}
