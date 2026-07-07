import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio_player_service.dart';
import 'playback_state.dart';
import 'player_controller.dart';
import 'queue_manager.dart';

/// Provider for the single wrapped [AudioPlayerService] instance.
final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the single [QueueManager] instance.
final queueManagerProvider = Provider<QueueManager>((ref) {
  return QueueManager();
});

/// StateNotifierProvider exposing the active playback state orchestrations.
final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlaybackState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  final queue = ref.watch(queueManagerProvider);
  return PlayerController(service, queue);
});
