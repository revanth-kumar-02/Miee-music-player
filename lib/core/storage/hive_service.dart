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
      Hive.openBox<TrackHiveModel>(HiveBoxes.favorites).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.favorites}'); return box; }),
      Hive.openBox<PlaylistHiveModel>(HiveBoxes.playlists).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.playlists}'); return box; }),
      Hive.openBox<HistoryEntry>(HiveBoxes.recentlyPlayed).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.recentlyPlayed}'); return box; }),
      Hive.openBox<int>(HiveBoxes.mostPlayed).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.mostPlayed}'); return box; }),
      Hive.openBox<PlaybackHistoryEntry>(HiveBoxes.playbackHistory).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.playbackHistory}'); return box; }),
      Hive.openBox<QueueSnapshot>(HiveBoxes.queueState).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.queueState}'); return box; }),
      Hive.openBox<String>(HiveBoxes.searchHistory).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.searchHistory}'); return box; }),
      Hive.openBox<dynamic>(HiveBoxes.preferences).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.preferences}'); return box; }),
      Hive.openBox<dynamic>(HiveBoxes.profile).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.profile}'); return box; }),
      Hive.openBox<dynamic>(HiveBoxes.offlineQueue).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.offlineQueue}'); return box; }),
      Hive.openBox<dynamic>(HiveBoxes.dailyMixes).then((box) { debugPrint('STARTUP: Hive Box loaded: ${HiveBoxes.dailyMixes}'); return box; }),
    ]);
    debugPrint('STARTUP: Hive opening all boxes eagerly done');
  }

  static void _registerAdapters() {
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TrackHiveModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(PlaylistHiveModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(PlaybackHistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(QueueSnapshotAdapter());
  }
}
