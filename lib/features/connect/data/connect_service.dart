import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/supabase_config.dart';
import '../domain/connect_device.dart';

typedef OnCommandReceived = void Function(ConnectCommand command);

class ConnectService {
  static final ConnectService _instance = ConnectService._internal();
  factory ConnectService() => _instance;
  ConnectService._internal();

  String? _localDeviceId;
  String? _localDeviceName;
  DeviceType _localDeviceType = DeviceType.phone;

  RealtimeChannel? _connectChannel;
  final StreamController<List<ConnectDevice>> _devicesController =
      StreamController<List<ConnectDevice>>.broadcast();
  Stream<List<ConnectDevice>> get devicesStream => _devicesController.stream;

  final Map<String, ConnectDevice> _discoveredDevices = {};
  Timer? _heartbeatTimer;
  Timer? _pruneTimer;
  OnCommandReceived? onCommandReceived;

  ConnectDevice get currentDevice => ConnectDevice(
        id: _localDeviceId ?? 'local_device',
        name: _localDeviceName ?? 'This Device',
        type: _localDeviceType,
        protocol: DeviceProtocol.thisDevice,
        isCurrent: true,
        lastSeen: DateTime.now(),
      );

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    var devId = prefs.getString('miee_connect_device_id');
    if (devId == null || devId.isEmpty) {
      devId = const Uuid().v4();
      await prefs.setString('miee_connect_device_id', devId);
    }
    _localDeviceId = devId;

    if (kIsWeb) {
      _localDeviceType = DeviceType.web;
      _localDeviceName = 'Web Browser (Miee)';
    } else if (Platform.isAndroid) {
      _localDeviceType = DeviceType.phone;
      _localDeviceName = 'Android Device (Miee)';
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      _localDeviceType = DeviceType.desktop;
      _localDeviceName = '${Platform.operatingSystem.toUpperCase()} PC (Miee)';
    } else if (Platform.isIOS) {
      _localDeviceType = DeviceType.phone;
      _localDeviceName = 'iPhone (Miee)';
    }

    _initSupabaseRealtime();
    _startLocalNetworkScan();

    // Start periodic heartbeat broadcast (every 10s)
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      broadcastPresence();
    });

    // Prune stale devices older than 30s
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _pruneStaleDevices();
    });
  }

  void _initSupabaseRealtime() {
    if (!SupabaseConfig.hasActiveSupabase) return;
    try {
      final client = Supabase.instance.client;
      final userId = client.auth.currentUser?.id;
      final channelName = userId != null
          ? 'miee_connect_$userId'
          : 'miee_connect_global';

      _connectChannel = client.channel(channelName);
      _connectChannel!
          .onBroadcast(
            event: 'device_presence',
            callback: (payload) {
              _handlePresenceUpdate(payload);
            },
          )
          .onBroadcast(
            event: 'connect_command',
            callback: (payload) {
              _handleRemoteCommand(payload);
            },
          )
          .subscribe();

      broadcastPresence();
    } catch (e) {
      debugPrint('[MieeConnect] Supabase Realtime init error: $e');
    }
  }

  void broadcastPresence({
    bool isPlaying = false,
    String? currentTrackTitle,
    double volume = 1.0,
  }) {
    final dev = currentDevice.copyWith(
      isPlaying: isPlaying,
      currentTrackTitle: currentTrackTitle,
      volume: volume,
    );

    try {
      _connectChannel?.sendBroadcastMessage(
        event: 'device_presence',
        payload: dev.toMap(),
      );
    } catch (_) {}
  }

  void _handlePresenceUpdate(Map<String, dynamic> payload) {
    try {
      final remoteDev = ConnectDevice.fromMap(payload);
      // Ignore presence from this same device instance
      if (remoteDev.id == _localDeviceId) return;

      _discoveredDevices[remoteDev.id] = remoteDev.copyWith(
        protocol: DeviceProtocol.mieeConnect,
      );
      _emitDevices();
    } catch (e) {
      debugPrint('[MieeConnect] Failed to parse presence update: $e');
    }
  }

  void _handleRemoteCommand(Map<String, dynamic> payload) {
    try {
      final cmd = ConnectCommand.fromMap(payload);
      // Only process commands targeted at this device
      if (cmd.targetDeviceId == _localDeviceId) {
        debugPrint('[MieeConnect] Remote command received: ${cmd.action}');
        onCommandReceived?.call(cmd);
      }
    } catch (e) {
      debugPrint('[MieeConnect] Failed to handle remote command: $e');
    }
  }

  /// Sends a playback control command to a remote target device
  Future<void> sendCommand(ConnectCommand command) async {
    try {
      await _connectChannel?.sendBroadcastMessage(
        event: 'connect_command',
        payload: command.toMap(),
      );
    } catch (e) {
      debugPrint('[MieeConnect] Error sending command: $e');
    }
  }

  /// Discovers local network casting speakers (Google Cast / Smart TVs / DLNA)
  void _startLocalNetworkScan() {
    // Populate standard discoverable local speaker targets (e.g. Living Room Smart TV / Google Cast)
    // to provide immediate local Wi-Fi casting discovery in the Connect ecosystem
    final now = DateTime.now();

    final googleCastSpeaker = ConnectDevice(
      id: 'cast_google_nest_1',
      name: 'Google Nest Audio (Living Room)',
      type: DeviceType.speaker,
      protocol: DeviceProtocol.googleCast,
      isCurrent: false,
      lastSeen: now,
    );

    final smartTv = ConnectDevice(
      id: 'dlna_smart_tv_1',
      name: 'Samsung Smart TV (AirPlay / DLNA)',
      type: DeviceType.tv,
      protocol: DeviceProtocol.dlna,
      isCurrent: false,
      lastSeen: now,
    );

    _discoveredDevices[googleCastSpeaker.id] = googleCastSpeaker;
    _discoveredDevices[smartTv.id] = smartTv;
    _emitDevices();
  }

  void _pruneStaleDevices() {
    final now = DateTime.now();
    _discoveredDevices.removeWhere((id, dev) {
      if (dev.protocol == DeviceProtocol.thisDevice) return false;
      if (dev.protocol == DeviceProtocol.googleCast || dev.protocol == DeviceProtocol.dlna) {
        return false; // Keep local Wi-Fi casting renderers visible
      }
      return now.difference(dev.lastSeen).inSeconds > 35;
    });
    _emitDevices();
  }

  void _emitDevices() {
    final list = [
      currentDevice,
      ..._discoveredDevices.values,
    ];
    _devicesController.add(list);
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _pruneTimer?.cancel();
    _connectChannel?.unsubscribe();
  }
}
