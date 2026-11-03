import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ConnectedAudioDevice {
  final String id;
  final String name;
  final String type;
  final int typeId;
  final bool isSink;

  const ConnectedAudioDevice({
    required this.id,
    required this.name,
    required this.type,
    required this.typeId,
    required this.isSink,
  });

  bool get isBluetooth =>
      type.toLowerCase().contains('bluetooth') || typeId == 7 || typeId == 8;

  bool get isHeadphones =>
      type.toLowerCase().contains('headphone') ||
      type.toLowerCase().contains('headset') ||
      typeId == 3 ||
      typeId == 4;

  bool get isSpeaker =>
      type.toLowerCase().contains('speaker') || typeId == 2;

  factory ConnectedAudioDevice.fromMap(Map<dynamic, dynamic> map) {
    return ConnectedAudioDevice(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? 'Audio Device',
      type: map['type']?.toString() ?? 'Audio Output',
      typeId: (map['type_id'] as num?)?.toInt() ?? 0,
      isSink: map['is_sink'] as bool? ?? true,
    );
  }
}

class AudioOutputBridge {
  static const MethodChannel _channel = MethodChannel('com.example.miee/audio_output');

  /// Fetches physically and wirelessly connected audio devices from Android's AudioManager.
  static Future<List<ConnectedAudioDevice>> getConnectedAudioDevices() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const [];
    }

    try {
      final List<dynamic>? res =
          await _channel.invokeMethod<List<dynamic>>('getConnectedAudioDevices');
      if (res == null) return const [];
      return res
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => ConnectedAudioDevice.fromMap(m))
          .toList();
    } catch (e) {
      debugPrint('[AudioOutputBridge] Error fetching audio devices: $e');
      return const [];
    }
  }

  /// Opens Android 11+ Media Output Switcher panel, or falls back to Bluetooth settings.
  static Future<bool> openMediaOutputSwitcher() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('openMediaOutputSwitcher');
      return success ?? false;
    } catch (e) {
      debugPrint('[AudioOutputBridge] Error opening Media Output Switcher: $e');
      return false;
    }
  }

  /// Opens the native Android Bluetooth settings.
  static Future<bool> openBluetoothSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('openBluetoothSettings');
      return success ?? false;
    } catch (e) {
      debugPrint('[AudioOutputBridge] Error opening Bluetooth settings: $e');
      return false;
    }
  }

  /// Opens the native Android Cast settings.
  static Future<bool> openCastSettings() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final bool? success = await _channel.invokeMethod<bool>('openCastSettings');
      return success ?? false;
    } catch (e) {
      debugPrint('[AudioOutputBridge] Error opening Cast settings: $e');
      return false;
    }
  }
}

