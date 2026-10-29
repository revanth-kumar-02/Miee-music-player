import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/music_drop/data/music_drop_native_bridge.dart';
import 'package:Miee/features/music_drop/domain/music_drop_models.dart';
import 'package:Miee/features/music_drop/presentation/music_drop_controller.dart';

class MockMusicDropBridge implements MusicDropNativeBridge {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  bool supported = true;
  bool permissionsGranted = true;
  bool advertising = false;
  bool discovering = false;

  String? lastConnectedEndpointId;
  String? lastAcceptedEndpointId;
  String? lastRejectedEndpointId;
  String? lastDisconnectedEndpointId;
  bool stopAllCalled = false;

  void emitEvent(Map<String, dynamic> event) {
    _controller.add(event);
  }

  @override
  Stream<Map<String, dynamic>> get eventsStream => _controller.stream;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<Map<String, dynamic>> checkPermissions() async {
    return {
      'granted': permissionsGranted,
      'missing': permissionsGranted ? <String>[] : <String>['BLUETOOTH_SCAN'],
      'bluetoothEnabled': true,
      'locationEnabled': true,
    };
  }

  @override
  Future<bool> requestPermissions() async {
    permissionsGranted = true;
    return true;
  }

  @override
  Future<bool> startAdvertising({String? customName}) async {
    advertising = true;
    emitEvent({'type': 'advertising_state', 'isAdvertising': true});
    return true;
  }

  @override
  Future<bool> stopAdvertising() async {
    advertising = false;
    emitEvent({'type': 'advertising_state', 'isAdvertising': false});
    return true;
  }

  @override
  Future<bool> startDiscovery() async {
    discovering = true;
    emitEvent({'type': 'discovery_state', 'isDiscovering': true});
    return true;
  }

  @override
  Future<bool> stopDiscovery() async {
    discovering = false;
    emitEvent({'type': 'discovery_state', 'isDiscovering': false});
    return true;
  }

  @override
  Future<bool> connect(String endpointId) async {
    lastConnectedEndpointId = endpointId;
    return true;
  }

  @override
  Future<bool> acceptConnection(String endpointId) async {
    lastAcceptedEndpointId = endpointId;
    return true;
  }

  @override
  Future<bool> rejectConnection(String endpointId) async {
    lastRejectedEndpointId = endpointId;
    return true;
  }

  @override
  Future<bool> disconnect(String endpointId) async {
    lastDisconnectedEndpointId = endpointId;
    return true;
  }

  @override
  Future<void> stopAll() async {
    stopAllCalled = true;
    advertising = false;
    discovering = false;
  }

  @override
  Future<int?> sendMetadata({
    required String endpointId,
    required String metadataJson,
  }) async => 1001;

  @override
  Future<Map<String, dynamic>?> sendAudioFile({
    required String endpointId,
    required String filePath,
    required String metadataJson,
  }) async => {
        'metaPayloadId': 1001,
        'filePayloadId': 2002,
        'sha256': 'a' * 64,
        'fileSize': 1024,
        'fileName': 'test.mp3',
      };

  @override
  Future<bool> cancelPayload(int payloadId) async => true;

  @override
  Future<String?> commitReceivedFile({
    required String transferId,
    String? destinationDir,
    String? customName,
  }) async => '/storage/emulated/0/Music/test.mp3';

  @override
  Future<bool> discardReceivedFile(String transferId) async => true;

  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Music Drop Native Foundation Unit Tests', () {
    late MockMusicDropBridge bridge;
    late MusicDropController controller;

    setUp(() {
      bridge = MockMusicDropBridge();
      controller = MusicDropController(bridge: bridge);
    });

    tearDown(() {
      controller.dispose();
      bridge.dispose();
    });

    test('Initial initialization loads support and permissions correctly', () async {
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.isSupported, isTrue);
      expect(controller.state.isPermissionsGranted, isTrue);
      expect(controller.state.missingPermissions, isEmpty);
      expect(controller.state.isAdvertising, isFalse);
      expect(controller.state.isDiscovering, isFalse);
      expect(controller.state.discoveredEndpoints, isEmpty);
      expect(controller.state.activeConnection, isNull);
    });

    test('Discovery lifecycle: start, endpoint found, endpoint lost, stop', () async {
      await Future<void>.delayed(Duration.zero);

      await controller.startDiscovery();
      expect(controller.state.isDiscovering, isTrue);

      // Simulate native Nearby endpoint found
      bridge.emitEvent({
        'type': 'endpoint_found',
        'endpointId': 'MIEE_DEV_1',
        'endpointName': 'Rahul Pixel 8',
        'serviceId': 'com.example.miee.music_drop',
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.discoveredEndpoints.length, equals(1));
      expect(controller.state.discoveredEndpoints.first.endpointId, equals('MIEE_DEV_1'));
      expect(controller.state.discoveredEndpoints.first.endpointName, equals('Rahul Pixel 8'));

      // Duplicate endpoint_found updates rather than duplicates
      bridge.emitEvent({
        'type': 'endpoint_found',
        'endpointId': 'MIEE_DEV_1',
        'endpointName': 'Rahul Pixel 8 (Renamed)',
        'serviceId': 'com.example.miee.music_drop',
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.discoveredEndpoints.length, equals(1));
      expect(controller.state.discoveredEndpoints.first.endpointName, equals('Rahul Pixel 8 (Renamed)'));

      // Simulate native endpoint lost
      bridge.emitEvent({
        'type': 'endpoint_lost',
        'endpointId': 'MIEE_DEV_1',
      });
      await Future<void>.delayed(Duration.zero);
      expect(controller.state.discoveredEndpoints, isEmpty);

      await controller.stopDiscovery();
      expect(controller.state.isDiscovering, isFalse);
    });

    test('Connection negotiation lifecycle: initiate, accept, and result', () async {
      await Future<void>.delayed(Duration.zero);

      // Simulate incoming connection request
      bridge.emitEvent({
        'type': 'connection_initiated',
        'endpointId': 'EP_99',
        'endpointName': 'Ananya Galaxy S24',
        'authDigits': '7241',
        'isIncoming': true,
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.activeConnection, isNotNull);
      expect(controller.state.activeConnection?.endpointId, equals('EP_99'));
      expect(controller.state.activeConnection?.authDigits, equals('7241'));
      expect(controller.state.activeConnection?.isIncoming, isTrue);
      expect(controller.state.activeConnection?.status, equals(MusicDropConnectionStatus.initiating));

      // Accept connection
      await controller.acceptConnection('EP_99');
      expect(bridge.lastAcceptedEndpointId, equals('EP_99'));

      // Simulate successful resolution
      bridge.emitEvent({
        'type': 'connection_result',
        'endpointId': 'EP_99',
        'isSuccess': true,
        'statusCode': 0,
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.activeConnection?.status, equals(MusicDropConnectionStatus.connected));

      // Disconnect
      await controller.disconnect('EP_99');
      expect(bridge.lastDisconnectedEndpointId, equals('EP_99'));
      expect(controller.state.activeConnection, isNull);
    });

    test('Connection rejection clears active connection and sets status', () async {
      await Future<void>.delayed(Duration.zero);

      bridge.emitEvent({
        'type': 'connection_initiated',
        'endpointId': 'EP_REJECT',
        'endpointName': 'Unknown Peer',
        'authDigits': '1111',
        'isIncoming': true,
      });
      await Future<void>.delayed(Duration.zero);

      await controller.rejectConnection('EP_REJECT');
      expect(bridge.lastRejectedEndpointId, equals('EP_REJECT'));
      expect(controller.state.activeConnection, isNull);
    });

    test('Native error events update errorMessage in state without crashing', () async {
      await Future<void>.delayed(Duration.zero);

      bridge.emitEvent({
        'type': 'error',
        'code': 'DISCOVERY_FAILED',
        'message': 'Bluetooth adapter is disabled',
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.errorMessage, equals('Bluetooth adapter is disabled'));
    });

    test('StopAll resets advertising, discovery, and connections cleanly', () async {
      await Future<void>.delayed(Duration.zero);

      await controller.startAdvertising();
      await controller.startDiscovery();
      expect(controller.state.isAdvertising, isTrue);
      expect(controller.state.isDiscovering, isTrue);

      await controller.stopAll();
      expect(bridge.stopAllCalled, isTrue);
      expect(controller.state.isAdvertising, isFalse);
      expect(controller.state.isDiscovering, isFalse);
      expect(controller.state.discoveredEndpoints, isEmpty);
      expect(controller.state.activeConnection, isNull);
    });
  });
}

