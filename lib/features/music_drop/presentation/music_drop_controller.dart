import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/music_drop_native_bridge.dart';
import '../domain/music_drop_models.dart';

/// StateNotifier managing peer-to-peer discovery and connection lifecycle for Miee Music Drop.
class MusicDropController extends StateNotifier<MusicDropState> {
  final MusicDropNativeBridge _bridge;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  MusicDropController({MusicDropNativeBridge? bridge})
      : _bridge = bridge ?? MusicDropNativeBridge(),
        super(const MusicDropState()) {
    _init();
  }

  Future<void> _init() async {
    final supported = await _bridge.isSupported();
    final permStatus = await _bridge.checkPermissions();

    state = state.copyWith(
      isSupported: supported,
      isPermissionsGranted: permStatus['granted'] as bool? ?? false,
      missingPermissions: List<String>.from(permStatus['missing'] as List? ?? []),
      isBluetoothEnabled: permStatus['bluetoothEnabled'] as bool? ?? false,
      isLocationEnabled: permStatus['locationEnabled'] as bool? ?? false,
    );

    _subscription = _bridge.eventsStream.listen(_handleNativeEvent);
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'discovery_state':
        state = state.copyWith(
          isDiscovering: event['isDiscovering'] as bool? ?? false,
        );
        break;

      case 'advertising_state':
        state = state.copyWith(
          isAdvertising: event['isAdvertising'] as bool? ?? false,
        );
        break;

      case 'endpoint_found':
        final endpointId = event['endpointId'] as String?;
        final endpointName = event['endpointName'] as String?;
        final serviceId = event['serviceId'] as String?;
        if (endpointId != null && endpointName != null) {
          final newEndpoint = MusicDropEndpoint(
            endpointId: endpointId,
            endpointName: endpointName,
            serviceId: serviceId,
            discoveredAt: DateTime.now(),
          );
          final updated = List<MusicDropEndpoint>.from(state.discoveredEndpoints);
          updated.removeWhere((e) => e.endpointId == endpointId);
          updated.add(newEndpoint);
          state = state.copyWith(discoveredEndpoints: updated);
        }
        break;

      case 'endpoint_lost':
        final endpointId = event['endpointId'] as String?;
        if (endpointId != null) {
          final updated = List<MusicDropEndpoint>.from(state.discoveredEndpoints);
          updated.removeWhere((e) => e.endpointId == endpointId);
          state = state.copyWith(discoveredEndpoints: updated);
        }
        break;

      case 'connection_initiated':
        final endpointId = event['endpointId'] as String?;
        final endpointName = event['endpointName'] as String? ?? 'Nearby Miee Device';
        final authDigits = event['authDigits'] as String?;
        final isIncoming = event['isIncoming'] as bool? ?? false;
        if (endpointId != null) {
          state = state.copyWith(
            activeConnection: () => MusicDropConnection(
              endpointId: endpointId,
              endpointName: endpointName,
              authDigits: authDigits,
              isIncoming: isIncoming,
              status: MusicDropConnectionStatus.initiating,
            ),
          );
        }
        break;

      case 'connection_result':
        final isSuccess = event['isSuccess'] as bool? ?? false;
        final endpointId = event['endpointId'] as String?;
        if (endpointId != null && state.activeConnection?.endpointId == endpointId) {
          if (isSuccess) {
            state = state.copyWith(
              activeConnection: () => state.activeConnection?.copyWith(
                status: MusicDropConnectionStatus.connected,
              ),
            );
          } else {
            state = state.copyWith(
              activeConnection: () => state.activeConnection?.copyWith(
                status: MusicDropConnectionStatus.rejected,
              ),
              errorMessage: () => 'Connection failed (${event['statusMessage'] ?? 'Rejected'})',
            );
          }
        }
        break;

      case 'disconnected':
        final endpointId = event['endpointId'] as String?;
        if (endpointId != null && state.activeConnection?.endpointId == endpointId) {
          state = state.copyWith(
            activeConnection: () => state.activeConnection?.copyWith(
              status: MusicDropConnectionStatus.disconnected,
            ),
          );
        }
        break;

      case 'error':
        final msg = event['message'] as String? ?? 'Proximity connection error';
        state = state.copyWith(errorMessage: () => msg);
        break;
    }
  }

  /// Refreshes permission and connectivity status.
  Future<void> refreshPermissions() async {
    final permStatus = await _bridge.checkPermissions();
    state = state.copyWith(
      isPermissionsGranted: permStatus['granted'] as bool? ?? false,
      missingPermissions: List<String>.from(permStatus['missing'] as List? ?? []),
      isBluetoothEnabled: permStatus['bluetoothEnabled'] as bool? ?? false,
      isLocationEnabled: permStatus['locationEnabled'] as bool? ?? false,
    );
  }

  /// Prompts the user for missing Nearby Connections permissions.
  Future<bool> requestPermissions() async {
    final granted = await _bridge.requestPermissions();
    await refreshPermissions();
    return granted;
  }

  /// Starts Nearby advertising as a Miee peer.
  Future<bool> startAdvertising({String? customName}) async {
    state = state.copyWith(errorMessage: () => null);
    final ok = await _bridge.startAdvertising(customName: customName);
    return ok;
  }

  /// Stops Nearby advertising.
  Future<bool> stopAdvertising() async {
    final ok = await _bridge.stopAdvertising();
    state = state.copyWith(isAdvertising: false);
    return ok;
  }

  /// Starts scanning for nearby Miee instances.
  Future<bool> startDiscovery() async {
    state = state.copyWith(errorMessage: () => null);
    final ok = await _bridge.startDiscovery();
    return ok;
  }

  /// Stops scanning for nearby instances.
  Future<bool> stopDiscovery() async {
    final ok = await _bridge.stopDiscovery();
    state = state.copyWith(
      isDiscovering: false,
      discoveredEndpoints: const [],
    );
    return ok;
  }

  /// Requests a connection to a discovered endpoint.
  Future<bool> connect(String endpointId) async {
    state = state.copyWith(errorMessage: () => null);
    return _bridge.connect(endpointId);
  }

  /// Accepts an incoming connection request.
  Future<bool> acceptConnection(String endpointId) async {
    return _bridge.acceptConnection(endpointId);
  }

  /// Rejects an incoming connection request.
  Future<bool> rejectConnection(String endpointId) async {
    final ok = await _bridge.rejectConnection(endpointId);
    if (state.activeConnection?.endpointId == endpointId) {
      state = state.copyWith(activeConnection: () => null);
    }
    return ok;
  }

  /// Disconnects from an active connection.
  Future<bool> disconnect(String endpointId) async {
    final ok = await _bridge.disconnect(endpointId);
    if (state.activeConnection?.endpointId == endpointId) {
      state = state.copyWith(activeConnection: () => null);
    }
    return ok;
  }

  /// Closes all sessions and resets state.
  Future<void> stopAll() async {
    await _bridge.stopAll();
    state = state.copyWith(
      isAdvertising: false,
      isDiscovering: false,
      discoveredEndpoints: const [],
      activeConnection: () => null,
      errorMessage: () => null,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.stopAll();
    super.dispose();
  }
}
