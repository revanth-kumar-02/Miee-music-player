import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/audio/audio_handler.dart';
import 'core/audio/providers.dart';
import 'core/storage/hive_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await HiveService.init();

  // AudioService.init() starts the Android foreground service and returns the
  // fully registered handler. The handler constructor is intentionally kept
  // minimal (no AudioSession calls) to avoid the circular deadlock where
  // AudioSession.instance waits for audio focus from the same service that
  // AudioService.init() is still in the process of starting.
  final MieeAudioHandler audioHandler;
  try {
    audioHandler = await AudioService.init<MieeAudioHandler>(
      builder: () => MieeAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.miee.music.channel.audio',
        androidNotificationChannelName: 'Miee Music',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
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