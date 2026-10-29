import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/music_drop/data/music_drop_native_bridge.dart';
import 'package:Miee/features/music_drop/domain/music_drop_models.dart';
import 'package:Miee/features/music_drop/presentation/music_drop_controller.dart';
import 'package:Miee/features/music_drop/presentation/widgets/music_drop_sheet.dart';
import 'package:Miee/features/music_drop/providers/music_drop_providers.dart';

class MockBackgroundBridge implements MusicDropNativeBridge {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  bool serviceRunning = false;
  bool notificationsEnabled = true;
  List<Map<String, dynamic>> mockRecoveredTransfers = [];

  String? lastCommittedTransferId;
  String? lastDiscardedTransferId;

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
  Future<bool> startDiscovery() async => true;
  @override
  Future<bool> stopDiscovery() async => true;
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
  }) async {
    lastCommittedTransferId = transferId;
    return '/storage/emulated/0/Music/${customName ?? 'song.mp3'}';
  }

  @override
  Future<bool> discardReceivedFile(String transferId) async {
    lastDiscardedTransferId = transferId;
    return true;
  }

  @override
  Future<bool> startBackgroundService({String? customName}) async {
    serviceRunning = true;
    emit({'type': 'background_service_state', 'isRunning': true});
    return true;
  }

  @override
  Future<bool> stopBackgroundService() async {
    serviceRunning = false;
    emit({'type': 'background_service_state', 'isRunning': false});
    return true;
  }

  @override
  Future<bool> isBackgroundServiceRunning() async => serviceRunning;

  @override
  Future<List<Map<String, dynamic>>> getRecoveredTransfers() async => mockRecoveredTransfers;

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<String> checkNfcStatus() async => 'unsupported';

  @override
  Future<bool> openNfcSettings() async => true;

  void dispose() {
    _events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Music Drop Phase 4: Background Receiving & Recovery Tests', () {
    late MockBackgroundBridge mockBridge;

    setUp(() {
      mockBridge = MockBackgroundBridge();
    });

    tearDown(() {
      mockBridge.dispose();
    });

    test('1. Starts and stops background receiving service via controller', () async {
      final controller = MusicDropController(bridge: mockBridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.isBackgroundReceivingEnabled, isFalse);

      final started = await controller.enableBackgroundReceiving();
      expect(started, isTrue);
      expect(controller.state.isBackgroundReceivingEnabled, isTrue);

      final stopped = await controller.disableBackgroundReceiving();
      expect(stopped, isTrue);
      expect(controller.state.isBackgroundReceivingEnabled, isFalse);

      controller.dispose();
    });

    test('2. Reacts to native background_service_state events', () async {
      final controller = MusicDropController(bridge: mockBridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      mockBridge.emit({'type': 'background_service_state', 'isRunning': true});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.isBackgroundReceivingEnabled, isTrue);

      mockBridge.emit({'type': 'background_service_state', 'isRunning': false});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.state.isBackgroundReceivingEnabled, isFalse);

      controller.dispose();
    });

    test('3. Handles notification decline action without committing files', () async {
      final controller = MusicDropController(bridge: mockBridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const metaJson = '{"protocolVersion":1,"transferId":"notif_tx_1","payloadType":"audio_file","title":"After Hours","artist":"The Weeknd","sourceId":"local_1","fileName":"song.mp3","fileSize":5000000,"expectedSha256":"abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"}';

      mockBridge.emit({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'ep_1',
        'payloadId': 501,
        'data': metaJson,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.activeTransfers.containsKey('notif_tx_1'), isTrue);
      expect(controller.state.activeTransfers['notif_tx_1']!.status, MusicDropTransferStatus.waiting);

      // User declines from system notification
      mockBridge.emit({
        'type': 'notification_action',
        'action': 'decline',
        'transferId': 'notif_tx_1',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.activeTransfers['notif_tx_1']!.status, MusicDropTransferStatus.cancelled);
      expect(controller.state.activeTransfers['notif_tx_1']!.isCommitted, isFalse);

      controller.dispose();
    });

    test('4. Recovers pending staged transfers after process death and requires consent', () async {
      mockBridge.mockRecoveredTransfers = [
        {
          'transferId': 'recovered_tx_101',
          'title': 'Midnight City',
          'artist': 'M83',
          'album': 'Hurry Up, We\'re Dreaming',
          'expectedSha256': '9876543210abcdef9876543210abcdef9876543210abcdef9876543210abcdef',
          'fileSize': 8400000,
          'stagingPath': '/data/user/0/com.example.miee/cache/music_drop_staging/recovered_tx_101_midnight.mp3',
          'timestamp': 1700000000000,
          'isVerified': true,
        }
      ];

      final controller = MusicDropController(bridge: mockBridge);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(controller.state.recoveredTransfers.length, 1);
      final recovered = controller.state.activeTransfers['recovered_tx_101'];
      expect(recovered, isNotNull);
      expect(recovered!.metadata.title, 'Midnight City');
      expect(recovered.metadata.artist, 'M83');
      expect(recovered.status, MusicDropTransferStatus.completed);
      expect(recovered.isIntegrityVerified, isTrue);
      expect(recovered.isCommitted, isFalse);
      expect(controller.state.lastCompletedTransfer?.transferId, 'recovered_tx_101');

      // User provides explicit consent to add to library
      final finalPath = await controller.commitTransfer('recovered_tx_101');
      expect(finalPath, isNotNull);
      expect(mockBridge.lastCommittedTransferId, 'recovered_tx_101');
      expect(controller.state.activeTransfers['recovered_tx_101']!.isCommitted, isTrue);

      controller.dispose();
    });

    test('5. Handles tapping notification to open specific drop', () async {
      final controller = MusicDropController(bridge: mockBridge);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      const metaJson = '{"protocolVersion":1,"transferId":"open_tx_99","payloadType":"metadata_only","title":"Blinding Lights","artist":"The Weeknd","sourceId":"yt_1"}';

      mockBridge.emit({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'ep_2',
        'payloadId': 801,
        'data': metaJson,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.activeTransfers.containsKey('open_tx_99'), isTrue);

      // System notification tapped
      mockBridge.emit({
        'type': 'open_drop_requested',
        'transferId': 'open_tx_99',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.state.lastCompletedTransfer?.transferId, 'open_tx_99');

      controller.dispose();
    });

    testWidgets('6. MusicDropSheet renders Background Receiving switch and toggles state', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;

      final controller = MusicDropController(bridge: mockBridge);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            musicDropNativeBridgeProvider.overrideWithValue(mockBridge),
            musicDropControllerProvider.overrideWith((ref) => controller),
            musicDropActiveTrackProvider.overrideWithValue(null),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MusicDropSheet(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Background Receiving'), findsOneWidget);
      expect(find.text('Allow receiving songs while Miee is closed'), findsOneWidget);

      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);

      await tester.tap(switchFinder);
      await tester.pump(const Duration(milliseconds: 50));

      expect(controller.state.isBackgroundReceivingEnabled, isTrue);
    });
  });
}
