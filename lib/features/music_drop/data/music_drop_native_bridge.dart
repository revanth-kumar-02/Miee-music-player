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

  /// Stream of native proximity and connection lifecycle events.
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
}
