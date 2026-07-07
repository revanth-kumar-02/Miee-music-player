import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/audio/audio_handler.dart';
import 'core/audio/providers.dart';
import 'core/storage/hive_service.dart';

/// App entry point.
///
/// Initialises [AudioService] so [MieeAudioHandler] runs in a persistent
/// foreground service that enables background playback, OS notifications,
/// lock-screen controls, and Bluetooth media button routing.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Hive and open all boxes before anything else runs.
  await HiveService.init();

  // Register MieeAudioHandler with audio_service.
  // The returned instance is the same object used throughout the app lifetime.
  final audioHandler = await AudioService.init(
    builder: () => MieeAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.miee.audio',
      androidNotificationChannelName: 'Miee Music',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: false,
      notificationColor: Color(0xFF1A1A2E),
    ),
  );

  runApp(
    ProviderScope(
      // Override the lazy placeholder so every provider that reads
      // audioHandlerProvider gets the concrete handler initialized above.
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const MieeApp(),
    ),
  );
}
