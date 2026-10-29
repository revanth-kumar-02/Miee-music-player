/// Connection status during Nearby Connections negotiation.
enum MusicDropConnectionStatus {
  idle,
  initiating,
  connected,
  rejected,
  disconnected,
}

/// Represents a discovered nearby Miee endpoint advertising on the local network.
class MusicDropEndpoint {
  final String endpointId;
  final String endpointName;
  final String? serviceId;
  final DateTime discoveredAt;

  const MusicDropEndpoint({
    required this.endpointId,
    required this.endpointName,
    this.serviceId,
    required this.discoveredAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicDropEndpoint &&
          runtimeType == other.runtimeType &&
          endpointId == other.endpointId;

  @override
  int get hashCode => endpointId.hashCode;

  @override
  String toString() => 'MusicDropEndpoint(id: $endpointId, name: $endpointName)';
}

/// Represents an active or pending P2P connection session.
class MusicDropConnection {
  final String endpointId;
  final String endpointName;
  final String? authDigits;
  final bool isIncoming;
  final MusicDropConnectionStatus status;

  const MusicDropConnection({
    required this.endpointId,
    required this.endpointName,
    this.authDigits,
    required this.isIncoming,
    required this.status,
  });

  MusicDropConnection copyWith({
    String? endpointId,
    String? endpointName,
    String? authDigits,
    bool? isIncoming,
    MusicDropConnectionStatus? status,
  }) {
    return MusicDropConnection(
      endpointId: endpointId ?? this.endpointId,
      endpointName: endpointName ?? this.endpointName,
      authDigits: authDigits ?? this.authDigits,
      isIncoming: isIncoming ?? this.isIncoming,
      status: status ?? this.status,
    );
  }

  @override
  String toString() =>
      'MusicDropConnection(id: $endpointId, name: $endpointName, status: $status, isIncoming: $isIncoming)';
}

/// Overall reactive state of the Miee Music Drop proximity foundation.
class MusicDropState {
  final bool isSupported;
  final bool isPermissionsGranted;
  final List<String> missingPermissions;
  final bool isBluetoothEnabled;
  final bool isLocationEnabled;
  final bool isAdvertising;
  final bool isDiscovering;
  final List<MusicDropEndpoint> discoveredEndpoints;
  final MusicDropConnection? activeConnection;
  final String? errorMessage;

  const MusicDropState({
    this.isSupported = true,
    this.isPermissionsGranted = false,
    this.missingPermissions = const [],
    this.isBluetoothEnabled = true,
    this.isLocationEnabled = true,
    this.isAdvertising = false,
    this.isDiscovering = false,
    this.discoveredEndpoints = const [],
    this.activeConnection,
    this.errorMessage,
  });

  MusicDropState copyWith({
    bool? isSupported,
    bool? isPermissionsGranted,
    List<String>? missingPermissions,
    bool? isBluetoothEnabled,
    bool? isLocationEnabled,
    bool? isAdvertising,
    bool? isDiscovering,
    List<MusicDropEndpoint>? discoveredEndpoints,
    MusicDropConnection? Function()? activeConnection,
    String? Function()? errorMessage,
  }) {
    return MusicDropState(
      isSupported: isSupported ?? this.isSupported,
      isPermissionsGranted: isPermissionsGranted ?? this.isPermissionsGranted,
      missingPermissions: missingPermissions ?? this.missingPermissions,
      isBluetoothEnabled: isBluetoothEnabled ?? this.isBluetoothEnabled,
      isLocationEnabled: isLocationEnabled ?? this.isLocationEnabled,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      discoveredEndpoints: discoveredEndpoints ?? this.discoveredEndpoints,
      activeConnection:
          activeConnection != null ? activeConnection() : this.activeConnection,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}
