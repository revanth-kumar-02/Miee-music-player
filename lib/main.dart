import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app/app.dart';
import 'core/audio/audio_handler.dart';
import 'core/audio/providers.dart';
import 'core/storage/hive_service.dart';
import 'core/sync/supabase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await HiveService.init();
  await SupabaseConfig.initialize();

  // On Android 13+ (API 33+), request POST_NOTIFICATIONS runtime permission
  // so the OS system media player card and foreground service notification are visible.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        debugPrint('[Startup] Requesting notification permission for system media controls');
        await Permission.notification.request();
      }
    } catch (e) {
      debugPrint('[Startup] Notification permission request error: $e');
    }
  }

  // On Web, native AudioService foreground services and Android notification
  // configurations are not applicable; use direct MieeAudioHandler.
  if (kIsWeb) {
    debugPrint('Running on Web platform: using direct MieeAudioHandler');
    final webHandler = MieeAudioHandler();
    await webHandler.initialize();

    runApp(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(webHandler)],
        child: const MieeApp(),
      ),
    );
    return;
  }

  // AudioService.init() starts the Android foreground service and returns the
  // fully registered handler.
  final MieeAudioHandler audioHandler;
  try {
    audioHandler = await AudioService.init<MieeAudioHandler>(
      builder: () => MieeAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.miee.music.channel.audio',
        androidNotificationChannelName: 'Miee Music',
        androidNotificationChannelDescription: 'Miee playback controls and system media player',
        androidNotificationIcon: 'drawable/ic_notification',
        // androidNotificationOngoing: false allows user to swipe away notification
        // when paused or finished, and allows androidStopForegroundOnPause: false.
        androidNotificationOngoing: false,
        // androidStopForegroundOnPause: false keeps the foreground service alive
        // during pauses, track transitions, and background execution so Android OS
        // does not kill the process or freeze playback when switching to other apps.
        androidStopForegroundOnPause: false,
        androidNotificationClickStartsActivity: true,
        notificationColor: Color(0xFF244A91), // Nordic Cobalt
        preloadArtwork: true,
      ),
    );

    // Configure AudioSession AFTER the foreground service is fully started.
    // Doing this inside the constructor (while AudioService.init is in progress)
    // causes a deadlock — hence the separate initialize() call here.
    await audioHandler.initialize();
  } catch (e, stack) {
    // If AudioService fails for any reason, fall back to a plain handler so
    // the app can still start and play audio (foreground only, no notification).
    debugPrint('AudioService.init failed, using direct handler: $e\n$stack');
    final fallback = MieeAudioHandler();
    await fallback.initialize();

    runApp(
      ProviderScope(
        overrides: [audioHandlerProvider.overrideWithValue(fallback)],
        child: const MieeApp(),
      ),
    );
    return;
  }

  runApp(
    ProviderScope(
      overrides: [audioHandlerProvider.overrideWithValue(audioHandler)],
      child: const MieeApp(),
    ),
  );
}