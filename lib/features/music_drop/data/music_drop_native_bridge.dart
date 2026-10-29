import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Low-level Flutter-to-Android bridge communicating with MusicDropManager via MethodChannel and EventChannel.
class MusicDropNativeBridge {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.miee/music_drop');
  static const EventChannel _eventChannel =
      EventChannel('com.example.miee/music_drop_events');

  Stream<Map<String, dynamic>>? _eventsStream;

  /// Stream of native proximity, connection lifecycle, and payload transfer events.
  Stream<Map<String, dynamic>> get eventsStream {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const Stream.empty();
    }
    _eventsStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _eventsStream!;
  }

  /// Checks if Google Play Services and Bluetooth hardware are supported.
  Future<bool> isSupported() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final supported = await _methodChannel.invokeMethod<bool>('isSupported');
      return supported ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] isSupported error: $e');
      return false;
    }
  }

  /// Checks whether all required Nearby Connections permissions are granted.
  Future<Map<String, dynamic>> checkPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return {
        'granted': false,
        'missing': <String>['unsupported_platform'],
        'bluetoothEnabled': false,
        'locationEnabled': false,
      };
    }
    try {
      final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('checkPermissions');
      if (res != null) {
        return {
          'granted': res['granted'] as bool? ?? false,
          'missing': List<String>.from(res['missing'] as List? ?? []),
          'bluetoothEnabled': res['bluetoothEnabled'] as bool? ?? false,
          'locationEnabled': res['locationEnabled'] as bool? ?? false,
        };
      }
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] checkPermissions error: $e');
    }
    return {
      'granted': false,
      'missing': <String>['error'],
      'bluetoothEnabled': false,
      'locationEnabled': false,
    };
  }

  /// Requests missing permissions using the Android runtime permission dialog.
  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('requestPermissions');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] requestPermissions error: $e');
      return false;
    }
  }

  /// Begins Nearby advertising as a discoverable Miee peer.
  Future<bool> startAdvertising({String? customName}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'startAdvertising',
        {'customName': customName},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] startAdvertising error: $e');
      return false;
    }
  }

  /// Stops advertising.
  Future<bool> stopAdvertising() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopAdvertising');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] stopAdvertising error: $e');
      return false;
    }
  }

  /// Begins scanning for nearby advertising Miee instances.
  Future<bool> startDiscovery() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('startDiscovery');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] startDiscovery error: $e');
      return false;
    }
  }

  /// Stops scanning for nearby devices.
  Future<bool> stopDiscovery() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopDiscovery');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] stopDiscovery error: $e');
      return false;
    }
  }

  /// Requests a connection to a discovered endpoint.
  Future<bool> connect(String endpointId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'connect',
        {'endpointId': endpointId},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] connect error: $e');
      return false;
    }
  }

  /// Accepts an incoming connection request.
  Future<bool> acceptConnection(String endpointId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'acceptConnection',
        {'endpointId': endpointId},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] acceptConnection error: $e');
      return false;
    }
  }

  /// Rejects an incoming connection request.
  Future<bool> rejectConnection(String endpointId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'rejectConnection',
        {'endpointId': endpointId},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] rejectConnection error: $e');
      return false;
    }
  }

  /// Disconnects from an active endpoint.
  Future<bool> disconnect(String endpointId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'disconnect',
        {'endpointId': endpointId},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] disconnect error: $e');
      return false;
    }
  }

  /// Terminates all active connections, discovery, and advertising sessions.
  Future<void> stopAll() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _methodChannel.invokeMethod<void>('stopAll');
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] stopAll error: $e');
    }
  }

  // ==========================================
  // Phase 2: Payload Engine Bridge Methods
  // ==========================================

  /// Sends a metadata-only bytes payload to the connected endpoint.
  Future<int?> sendMetadata({
    required String endpointId,
    required String metadataJson,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final payloadId = await _methodChannel.invokeMethod<int>(
        'sendMetadata',
        {
          'endpointId': endpointId,
          'metadataJson': metadataJson,
        },
      );
      return payloadId;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] sendMetadata error: $e');
      return null;
    }
  }

  /// Initiates transfer of a local audio file and accompanying metadata to the connected endpoint.
  Future<Map<String, dynamic>?> sendAudioFile({
    required String endpointId,
    required String filePath,
    required String metadataJson,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final res = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'sendAudioFile',
        {
          'endpointId': endpointId,
          'filePath': filePath,
          'metadataJson': metadataJson,
        },
      );
      if (res != null) {
        return Map<String, dynamic>.from(res);
      }
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] sendAudioFile error: $e');
    }
    return null;
  }

  /// Cancels an in-progress payload by its 64-bit payload ID.
  Future<bool> cancelPayload(int payloadId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'cancelPayload',
        {'payloadId': payloadId},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] cancelPayload error: $e');
      return false;
    }
  }

  /// Commits a verified staging file into the final destination directory with collision avoidance.
  Future<String?> commitReceivedFile({
    required String transferId,
    String? destinationDir,
    String? customName,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final path = await _methodChannel.invokeMethod<String>(
        'commitReceivedFile',
        {
          'transferId': transferId,
          'destinationDir': destinationDir,
          'customName': customName,
        },
      );
      return path;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] commitReceivedFile error: $e');
      return null;
    }
  }

  /// Discards and removes a received staging file without committing it.
  Future<bool> discardReceivedFile(String transferId) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'discardReceivedFile',
        {'transferId': transferId},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] discardReceivedFile error: $e');
      return false;
    }
  }

  // ==========================================
  // Phase 4: Background Service & Recovery APIs
  // ==========================================

  /// Starts the Android foreground service with connectedDevice type for background receiving.
  Future<bool> startBackgroundService({String? customName}) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>(
        'startBackgroundService',
        {'customName': customName},
      );
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] startBackgroundService error: $e');
      return false;
    }
  }

  /// Stops the background receiving service and clears persistent foreground notification.
  Future<bool> stopBackgroundService() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('stopBackgroundService');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] stopBackgroundService error: $e');
      return false;
    }
  }

  /// Checks if the native background service is currently active.
  Future<bool> isBackgroundServiceRunning() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('isBackgroundServiceRunning');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] isBackgroundServiceRunning error: $e');
      return false;
    }
  }

  /// Retrieves any verified pending staging transfers recovered after process death.
  Future<List<Map<String, dynamic>>> getRecoveredTransfers() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const [];
    try {
      final res = await _methodChannel.invokeMethod<List<dynamic>>('getRecoveredTransfers');
      if (res != null) {
        return res
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] getRecoveredTransfers error: $e');
    }
    return const [];
  }

  /// Checks if system notifications are enabled for the app.
  Future<bool> areNotificationsEnabled() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      final res = await _methodChannel.invokeMethod<bool>('areNotificationsEnabled');
      return res ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MusicDrop] areNotificationsEnabled error: $e');
      return false;
    }
  }
}
