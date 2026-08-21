import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_handler.dart';
import 'playback_state.dart';
import 'player_controller.dart';
import 'queue_manager.dart';

/// Provider that holds the single [MieeAudioHandler] instance.
///
/// This is initialized via [AudioService.init] in main.dart and passed in
/// as an override so the same instance is shared across the app.
final audioHandlerProvider = Provider<MieeAudioHandler>((ref) {
  throw UnimplementedError(
    'audioHandlerProvider must be overridden in main.dart via AudioService.init()',
  );
});

/// Provider for the single [QueueManager] instance.
final queueManagerProvider = Provider<QueueManager>((ref) {
  return QueueManager();
});

/// StateNotifierProvider exposing the active playback state orchestrations.
final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final queue = ref.watch(queueManagerProvider);
  return PlayerController(handler, queue, ref);
});
