import 'package:hive/hive.dart';

import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';

/// Manages persisted favorite tracks.
///
/// All writes are synchronous and immediately durable.
/// Hive boxes must be opened by [HiveService.init] before use.
class FavoritesRepository {
  Box<TrackHiveModel> get _box =>
      Hive.box<TrackHiveModel>(HiveBoxes.favorites);

  /// Adds [track] to favorites. No-op if already favorited.
  Future<void> addFavorite(Track track) async {
    if (!_box.containsKey(track.id)) {
      await _box.put(track.id, TrackHiveModel.fromTrack(track));
    }
  }

  /// Removes the track with [trackId] from favorites. No-op if not present.
  Future<void> removeFavorite(String trackId) async {
    await _box.delete(trackId);
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
