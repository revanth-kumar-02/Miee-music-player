import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/music_drop_native_bridge.dart';
import '../domain/music_drop_models.dart';
import '../presentation/music_drop_controller.dart';

/// Provides the singleton instance of the low-level native bridge.
final musicDropNativeBridgeProvider = Provider<MusicDropNativeBridge>((ref) {
  return MusicDropNativeBridge();
});

/// Primary state notifier provider for Miee Music Drop proximity discovery and connections.
final musicDropControllerProvider =
    StateNotifierProvider<MusicDropController, MusicDropState>((ref) {
  final bridge = ref.watch(musicDropNativeBridgeProvider);
  return MusicDropController(bridge: bridge);
});

/// Convenience provider for the active list of discovered nearby Miee endpoints.
final musicDropDiscoveredEndpointsProvider = Provider<List<MusicDropEndpoint>>((ref) {
  return ref.watch(musicDropControllerProvider).discoveredEndpoints;
});

/// Convenience provider for the current active or pending P2P connection.
final musicDropActiveConnectionProvider = Provider<MusicDropConnection?>((ref) {
  return ref.watch(musicDropControllerProvider).activeConnection;
});

/// Convenience provider indicating whether discovery scanning is active.
final musicDropIsDiscoveringProvider = Provider<bool>((ref) {
  return ref.watch(musicDropControllerProvider).isDiscovering;
});

/// Convenience provider indicating whether advertising is active.
final musicDropIsAdvertisingProvider = Provider<bool>((ref) {
  return ref.watch(musicDropControllerProvider).isAdvertising;
});
