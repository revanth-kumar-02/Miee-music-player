import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/music_drop/data/music_drop_native_bridge.dart';
import 'package:Miee/features/music_drop/domain/music_drop_models.dart';
import 'package:Miee/features/music_drop/presentation/music_drop_controller.dart';
import 'package:Miee/features/music_drop/presentation/widgets/music_drop_sheet.dart';
import 'package:Miee/features/music_drop/providers/music_drop_providers.dart';

class MockNfcBridge implements MusicDropNativeBridge {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  String nfcStatus = 'unsupported';
  bool openNfcSettingsCalled = false;
  bool discoveryStarted = false;

  void emit(Map<String, dynamic> event) => _events.add(event);

  @override
  Stream<Map<String, dynamic>> get eventsStream => _events.stream;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<Map<String, dynamic>> checkPermissions() async => {
        'granted': true,
        'missing': <String>[],
        'bluetoothEnabled': true,
        'locationEnabled': true,
      };

  @override
  Future<bool> requestPermissions() async => true;
  @override
  Future<bool> startAdvertising({String? customName}) async => true;
  @override
  Future<bool> stopAdvertising() async => true;

  @override
  Future<bool> startDiscovery() async {
    discoveryStarted = true;
    emit({'type': 'discovery_state', 'isDiscovering': true});
    return true;
  }

  @override
  Future<bool> stopDiscovery() async {
    discoveryStarted = false;
    emit({'type': 'discovery_state', 'isDiscovering': false});
    return true;
  }

  @override
  Future<bool> connect(String endpointId) async => true;
  @override
  Future<bool> acceptConnection(String endpointId) async => true;
  @override
  Future<bool> rejectConnection(String endpointId) async => true;
  @override
  Future<bool> disconnect(String endpointId) async => true;
  @override
  Future<void> stopAll() async {}

  @override
  Future<int?> sendMetadata({
    required String endpointId,
    required String metadataJson,
  }) async => 101;

  @override
  Future<Map<String, dynamic>?> sendAudioFile({
    required String endpointId,
    required String filePath,
    required String metadataJson,
  }) async => null;

  @override
  Future<bool> cancelPayload(int payloadId) async => true;

  @override
  Future<String?> commitReceivedFile({
    required String transferId,
    String? destinationDir,
    String? customName,
  }) async => '/storage/emulated/0/Music/track.mp3';

  @override
  Future<bool> discardReceivedFile(String transferId) async => true;

  @override
  Future<bool> startBackgroundService({String? customName}) async => true;

  @override
  Future<bool> stopBackgroundService() async => true;

  @override
  Future<bool> isBackgroundServiceRunning() async => false;

  @override
  Future<List<Map<String, dynamic>>> getRecoveredTransfers() async => const [];

  @override
  Future<bool> areNotificationsEnabled() async => true;

  @override
  Future<String> checkNfcStatus() async => nfcStatus;

  @override
  Future<bool> openNfcSettings() async {
    openNfcSettingsCalled = true;
    return true;
  }

  void dispose() {
    _events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Music Drop Optional NFC Flow Tests', () {
    late MockNfcBridge bridge;

    setUp(() {
      bridge = MockNfcBridge();
    });

    tearDown(() {
      bridge.dispose();
    });

    test('1. Capability detection: unsupported device never crashes and defaults safely', () async {
      bridge.nfcStatus = 'unsupported';
      final controller = MusicDropController(bridge: bridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.nfcStatus, MusicDropNfcStatus.unsupported);
      controller.dispose();
    });

    test('2. Capability detection: supported but disabled detects status correctly', () async {
      bridge.nfcStatus = 'disabled';
      final controller = MusicDropController(bridge: bridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.nfcStatus, MusicDropNfcStatus.disabled);
      controller.dispose();
    });

    test('3. Capability detection: enabled device reflects active NFC status', () async {
      bridge.nfcStatus = 'enabled';
      final controller = MusicDropController(bridge: bridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.nfcStatus, MusicDropNfcStatus.enabled);
      controller.dispose();
    });

    test('4. NFC trigger event initiates discovery without bypassing security gates', () async {
      bridge.nfcStatus = 'enabled';
      final controller = MusicDropController(bridge: bridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.isDiscovering, isFalse);

      bridge.emit({'type': 'nfc_trigger', 'data': 'miee://drop?peer=pixel7'});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Auto-starts Nearby discovery as a fast pairing trigger
      expect(controller.state.isDiscovering, isTrue);
      // Security: no connection is accepted automatically without authentication & consent
      expect(controller.state.activeConnection, isNull);
      expect(controller.state.activeTransfers.isEmpty, isTrue);

      controller.dispose();
    });

    testWidgets('5. Sheet UI: hides NFC badge completely when NFC is unsupported', (tester) async {
      bridge.nfcStatus = 'unsupported';
      final controller = MusicDropController(bridge: bridge);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicDropNativeBridgeProvider.overrideWithValue(bridge),
            musicDropControllerProvider.overrideWith((ref) => controller),
            musicDropActiveTrackProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MusicDropSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Nearby Devices'), findsOneWidget);
      expect(find.text('NFC Ready'), findsNothing);
      expect(find.text('Enable NFC'), findsNothing);
    });

    testWidgets('6. Sheet UI: shows "Enable NFC" chip and opens settings when disabled', (tester) async {
      bridge.nfcStatus = 'disabled';
      final controller = MusicDropController(bridge: bridge);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicDropNativeBridgeProvider.overrideWithValue(bridge),
            musicDropControllerProvider.overrideWith((ref) => controller),
            musicDropActiveTrackProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MusicDropSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Enable NFC'), findsOneWidget);

      await tester.tap(find.text('Enable NFC'));
      await tester.pump(const Duration(milliseconds: 50));

      expect(bridge.openNfcSettingsCalled, isTrue);
    });

    testWidgets('7. Sheet UI: shows "NFC Ready" badge when NFC is enabled', (tester) async {
      bridge.nfcStatus = 'enabled';
      final controller = MusicDropController(bridge: bridge);

      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicDropNativeBridgeProvider.overrideWithValue(bridge),
            musicDropControllerProvider.overrideWith((ref) => controller),
            musicDropActiveTrackProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: Scaffold(body: MusicDropSheet()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('NFC Ready'), findsOneWidget);
    });
  });
}
