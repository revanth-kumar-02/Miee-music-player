enum DeviceType {
  phone,
  desktop,
  web,
  speaker,
  tv,
}

enum DeviceProtocol {
  thisDevice,
  mieeConnect,
  googleCast,
  dlna,
}

class ConnectDevice {
  final String id;
  final String name;
  final DeviceType type;
  final DeviceProtocol protocol;
  final bool isCurrent;
  final double volume;
  final bool isPlaying;
  final String? currentTrackTitle;
  final String? ipAddress;
  final DateTime lastSeen;

  const ConnectDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.protocol,
    this.isCurrent = false,
    this.volume = 1.0,
    this.isPlaying = false,
    this.currentTrackTitle,
    this.ipAddress,
    required this.lastSeen,
  });

  ConnectDevice copyWith({
    String? id,
    String? name,
    DeviceType? type,
    DeviceProtocol? protocol,
    bool? isCurrent,
    double? volume,
    bool? isPlaying,
    String? currentTrackTitle,
    String? ipAddress,
    DateTime? lastSeen,
  }) {
    return ConnectDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      protocol: protocol ?? this.protocol,
      isCurrent: isCurrent ?? this.isCurrent,
      volume: volume ?? this.volume,
      isPlaying: isPlaying ?? this.isPlaying,
      currentTrackTitle: currentTrackTitle ?? this.currentTrackTitle,
      ipAddress: ipAddress ?? this.ipAddress,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'protocol': protocol.name,
      'volume': volume,
      'is_playing': isPlaying,
      'current_track_title': currentTrackTitle,
      'ip_address': ipAddress,
      'last_seen': lastSeen.toIso8601String(),
    };
  }

  factory ConnectDevice.fromMap(Map<String, dynamic> map, {bool isCurrent = false}) {
    return ConnectDevice(
      id: map['id'] as String? ?? 'unknown_device',
      name: map['name'] as String? ?? 'Unknown Speaker',
      type: _parseDeviceType(map['type'] as String?),
      protocol: _parseProtocol(map['protocol'] as String?),
      isCurrent: isCurrent,
      volume: (map['volume'] as num?)?.toDouble() ?? 1.0,
      isPlaying: map['is_playing'] as bool? ?? false,
      currentTrackTitle: map['current_track_title'] as String?,
      ipAddress: map['ip_address'] as String?,
      lastSeen: map['last_seen'] != null
          ? DateTime.tryParse(map['last_seen'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  static DeviceType _parseDeviceType(String? val) {
    switch (val) {
      case 'desktop':
        return DeviceType.desktop;
      case 'web':
        return DeviceType.web;
      case 'speaker':
        return DeviceType.speaker;
      case 'tv':
        return DeviceType.tv;
      case 'phone':
      default:
        return DeviceType.phone;
    }
  }

  static DeviceProtocol _parseProtocol(String? val) {
    switch (val) {
      case 'mieeConnect':
        return DeviceProtocol.mieeConnect;
      case 'googleCast':
        return DeviceProtocol.googleCast;
      case 'dlna':
        return DeviceProtocol.dlna;
      case 'thisDevice':
      default:
        return DeviceProtocol.thisDevice;
    }
  }
}

class ConnectCommand {
  final String action; // 'play', 'pause', 'seek', 'volume', 'next', 'previous'
  final String targetDeviceId;
  final String senderDeviceId;
  final Map<String, dynamic>? trackData;
  final int? positionMs;
  final double? volume;
  final int timestamp;

  const ConnectCommand({
    required this.action,
    required this.targetDeviceId,
    required this.senderDeviceId,
    this.trackData,
    this.positionMs,
    this.volume,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'action': action,
      'target_device_id': targetDeviceId,
      'sender_device_id': senderDeviceId,
      'track_data': trackData,
      'position_ms': positionMs,
      'volume': volume,
      'timestamp': timestamp,
    };
  }

  factory ConnectCommand.fromMap(Map<String, dynamic> map) {
    return ConnectCommand(
      action: map['action'] as String? ?? 'pause',
      targetDeviceId: map['target_device_id'] as String? ?? '',
      senderDeviceId: map['sender_device_id'] as String? ?? '',
      trackData: map['track_data'] as Map<String, dynamic>?,
      positionMs: (map['position_ms'] as num?)?.toInt(),
      volume: (map['volume'] as num?)?.toDouble(),
      timestamp: (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
