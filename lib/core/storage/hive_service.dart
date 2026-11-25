import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'adapters/history_entry.dart';
import 'adapters/playback_history_entry.dart';
import 'adapters/playlist_hive_model.dart';
import 'adapters/queue_snapshot.dart';
import 'adapters/track_hive_model.dart';
import 'hive_boxes.dart';

/// Responsible for initialising Hive, registering all [TypeAdapter]s,
/// and opening every box before the app renders its first frame.
///
/// Call [HiveService.init] once in [main] before [AudioService.init].
class HiveService {
  HiveService._();

  /// Initialises Hive and opens all application boxes.
  ///
  /// Must be awaited before creating any Riverpod providers that depend
  /// on Hive boxes.
  static Future<void> init() async {
    // Initialise Hive with the default Flutter path (app documents directory).
    debugPrint('STARTUP: Hive.initFlutter() starting');
    await Hive.initFlutter();
    debugPrint('STARTUP: Hive.initFlutter() done');

    // Register type adapters — order does not matter.
    debugPrint('STARTUP: Hive registering adapters starting');
    _registerAdapters();
    debugPrint('STARTUP: Hive registering adapters done');

    // Open all boxes eagerly so repositories never need to await box opening.
    debugPrint('STARTUP: Hive opening all boxes eagerly starting');
    await Future.wait([
      _openBoxSafely<TrackHiveModel>(HiveBoxes.favorites),
      _openBoxSafely<PlaylistHiveModel>(HiveBoxes.playlists),
      _openBoxSafely<HistoryEntry>(HiveBoxes.recentlyPlayed),
      _openBoxSafely<int>(HiveBoxes.mostPlayed),
      _openBoxSafely<PlaybackHistoryEntry>(HiveBoxes.playbackHistory),
      _openBoxSafely<QueueSnapshot>(HiveBoxes.queueState),
      _openBoxSafely<String>(HiveBoxes.searchHistory),
      _openBoxSafely<dynamic>(HiveBoxes.preferences),
      _openBoxSafely<dynamic>(HiveBoxes.profile),
      _openBoxSafely<dynamic>(HiveBoxes.offlineQueue),
      _openBoxSafely<dynamic>(HiveBoxes.dailyMixes),
      _openBoxSafely<dynamic>(HiveBoxes.artworkCache),
    ]);
    debugPrint('STARTUP: Hive opening all boxes eagerly done');
  }

  static Future<Box<T>> _openBoxSafely<T>(String boxName) async {
    try {
      final box = await Hive.openBox<T>(boxName);
      debugPrint('STARTUP: Hive Box loaded: $boxName');
      return box;
    } catch (e) {
      debugPrint('STARTUP: Corrupted Hive box "$boxName" ($e); resetting box.');
      try {
        await Hive.deleteBoxFromDisk(boxName);
      } catch (_) {}
      return Hive.openBox<T>(boxName);
    }
  }

  static void _registerAdapters() {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TrackHiveModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(PlaylistHiveModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(PlaybackHistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(QueueSnapshotAdapter());
  }

  /// Clears user-scoped Hive boxes on sign-out or account switch while
  /// preserving device-level preferences and artwork cache.
  static Future<void> clearUserDataBoxes() async {
    Future<void> clearIfOpen<T>(String boxName) async {
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box<T>(boxName).clear();
      }
    }

    await Future.wait([
      clearIfOpen<TrackHiveModel>(HiveBoxes.favorites),
      clearIfOpen<PlaylistHiveModel>(HiveBoxes.playlists),
      clearIfOpen<HistoryEntry>(HiveBoxes.recentlyPlayed),
      clearIfOpen<int>(HiveBoxes.mostPlayed),
      clearIfOpen<PlaybackHistoryEntry>(HiveBoxes.playbackHistory),
      clearIfOpen<QueueSnapshot>(HiveBoxes.queueState),
      clearIfOpen<String>(HiveBoxes.searchHistory),
      clearIfOpen<dynamic>(HiveBoxes.profile),
      clearIfOpen<dynamic>(HiveBoxes.offlineQueue),
      clearIfOpen<dynamic>(HiveBoxes.dailyMixes),
    ]);
  }
}
