import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../core/storage/adapters/history_entry.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';
import '../../../core/sync/sync_manager.dart';
import '../../../core/sync/offline_operation.dart';

import '../../media/providers/media_providers.dart';

/// Stores and retrieves the most recently played tracks (latest 100) with cloud synchronization.
class RecentlyPlayedRepository {
  static const int _maxEntries = 100;
  final Ref _ref;

  RecentlyPlayedRepository(this._ref);

  Box<HistoryEntry> get _box =>
      Hive.box<HistoryEntry>(HiveBoxes.recentlyPlayed);

  /// Records [track] as played right now.
  ///
  /// Automatically trims the box to [_maxEntries] oldest entries and removes older duplicate
  /// instances of the same track so the latest play is always at the top.
  Future<void> recordPlay(Track track) async {
    final now = DateTime.now();
    final normId = track.id.replaceFirst('youtube_', '');

    // 1. Remove any older duplicate entry for the same track
    final duplicateKeys = <dynamic>[];
    for (final key in _box.keys) {
      final entry = _box.get(key);
      if (entry != null) {
        final entryNormId = entry.track.id.replaceFirst('youtube_', '');
        if (entry.track.id == track.id || entryNormId == normId) {
          duplicateKeys.add(key);
        }
      }
    }
    if (duplicateKeys.isNotEmpty) {
      await _box.deleteAll(duplicateKeys);
    }

    // 2. Ensure durable artwork reference
    String resolvedImageUrl = track.imageUrl;
    if (track.isYoutube && (resolvedImageUrl.isEmpty || !resolvedImageUrl.startsWith('http'))) {
      resolvedImageUrl = 'https://i.ytimg.com/vi/$normId/hqdefault.jpg';
    } else if (!track.isYoutube && resolvedImageUrl.isEmpty) {
      try {
        final localSongs = _ref.read(songsProvider);
        final match = localSongs.where((s) =>
            s.id == track.id ||
            s.id == normId ||
            (s.filePath.isNotEmpty && s.filePath == track.filePath)).firstOrNull;
        if (match != null && match.artworkPath.isNotEmpty) {
          resolvedImageUrl = match.artworkPath;
        }
      } catch (_) {}
    }

    final durableTrack = Track(
      id: track.id,
      title: track.title,
      artist: track.artist,
      imageUrl: resolvedImageUrl,
      duration: track.duration,
      filePath: track.filePath,
    );

    await _box.add(HistoryEntry(
      track: TrackHiveModel.fromTrack(durableTrack),
      playedAt: now,
    ));

    // Keep only the most recent _maxEntries entries.
    if (_box.length > _maxEntries) {
      final excess = _box.length - _maxEntries;
      final keysToDelete = _box.keys.take(excess).toList();
      await _box.deleteAll(keysToDelete);
    }

    final op = OfflineOperation(
      id: 'hist_${track.id}_${now.millisecondsSinceEpoch}',
      type: 'history_add',
      payload: {
        'id': durableTrack.id,
        'title': durableTrack.title,
        'artist': durableTrack.artist,
        'imageUrl': durableTrack.imageUrl,
        'duration': durableTrack.duration,
        'filePath': durableTrack.filePath,
        'isYoutube': durableTrack.isYoutube,
        'playedAt': now.toIso8601String(),
      },
      timestamp: now,
    );
    await _ref.read(syncManagerProvider).queueOperation(op);
  }

  /// Converts a [HistoryEntry] to a domain [Track] while ensuring valid artwork references.
  Track _resolveEntryTrack(HistoryEntry entry) {
    final rawTrack = entry.track.toTrack();
    final normId = rawTrack.id.replaceFirst('youtube_', '');

    if (rawTrack.isYoutube) {
      if (rawTrack.imageUrl.isEmpty || !rawTrack.imageUrl.startsWith('http')) {
        return Track(
          id: rawTrack.id,
          title: rawTrack.title,
          artist: rawTrack.artist,
          imageUrl: 'https://i.ytimg.com/vi/$normId/hqdefault.jpg',
          duration: rawTrack.duration,
          filePath: rawTrack.filePath,
        );
      }
      return rawTrack;
    }

    // Local track: check if songsProvider has the live artworkPath
    try {
      final localSongs = _ref.read(songsProvider);
      final match = localSongs.where((s) =>
          s.id == rawTrack.id ||
          s.id == normId ||
          (s.filePath.isNotEmpty && s.filePath == rawTrack.filePath) ||
          (s.title.trim().toLowerCase() == rawTrack.title.trim().toLowerCase() &&
              s.artist.trim().toLowerCase() == rawTrack.artist.trim().toLowerCase())).firstOrNull;
      if (match != null && match.artworkPath.isNotEmpty) {
        return Track(
          id: rawTrack.id,
          title: rawTrack.title,
          artist: rawTrack.artist,
          imageUrl: match.artworkPath,
          duration: rawTrack.duration,
          filePath: rawTrack.filePath.isNotEmpty ? rawTrack.filePath : match.filePath,
        );
      }
    } catch (_) {}

    return rawTrack;
  }

  /// Returns all recently played entries, newest first.
  List<HistoryEntry> getRecentlyPlayed() {
    final entries = _box.values.toList();
    entries.sort((a, b) => b.playedAt.compareTo(a.playedAt));
    return entries;
  }

  /// Returns the most recently played [Track] objects (newest first) with restored artwork.
  List<Track> getRecentTracks() =>
      getRecentlyPlayed().map(_resolveEntryTrack).toList(growable: false);

  /// Stream that emits whenever the history changes, starting with the current state.
  Stream<List<HistoryEntry>> watchRecentlyPlayed() async* {
    yield getRecentlyPlayed();
    yield* _box.watch().map((_) => getRecentlyPlayed());
  }

  /// Clears all recently played history.
  Future<void> clear() async => _box.clear();
}
