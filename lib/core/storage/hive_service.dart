import 'package:hive_flutter/hive_flutter.dart';

import 'adapters/history_entry.dart';
import 'adapters/playback_history_entry.dart';
import 'adapters/playlist_hive_model.dart';
import 'adapters/queue_snapshot.dart';
import 'adapters/track_hive_model.dart';
import 'adapters/user_preferences.dart';
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
    await Hive.initFlutter();

    // Register type adapters — order does not matter.
    _registerAdapters();

    // Open all boxes eagerly so repositories never need to await box opening.
    await Future.wait([
      Hive.openBox<TrackHiveModel>(HiveBoxes.favorites),
      Hive.openBox<PlaylistHiveModel>(HiveBoxes.playlists),
      Hive.openBox<HistoryEntry>(HiveBoxes.recentlyPlayed),
      Hive.openBox<int>(HiveBoxes.mostPlayed),
      Hive.openBox<PlaybackHistoryEntry>(HiveBoxes.playbackHistory),
      Hive.openBox<QueueSnapshot>(HiveBoxes.queueState),
      Hive.openBox<String>(HiveBoxes.searchHistory),
      Hive.openBox(HiveBoxes.preferences),
      Hive.openBox(HiveBoxes.profile),
    ]);
  }

  static void _registerAdapters() {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TrackHiveModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(PlaylistHiveModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(PlaybackHistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(QueueSnapshotAdapter());
    if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(UserPreferencesAdapter());
  }
}
