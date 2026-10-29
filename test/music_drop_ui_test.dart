import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/music_drop/data/music_drop_native_bridge.dart';
import 'package:Miee/features/music_drop/domain/music_drop_models.dart';
import 'package:Miee/features/music_drop/presentation/music_drop_controller.dart';
import 'package:Miee/features/music_drop/presentation/widgets/incoming_drop_banner.dart';
import 'package:Miee/features/music_drop/presentation/widgets/music_drop_pill.dart';
import 'package:Miee/features/music_drop/presentation/widgets/music_drop_sheet.dart';
import 'package:Miee/features/music_drop/providers/music_drop_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class MockUiBridge implements MusicDropNativeBridge {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  bool isSupportedVal = true;
  bool permissionsGrantedVal = true;
  String? connectedEndpointId;
  String? committedTransferId;
  String? discardedTransferId;
  bool discoveryStarted = false;

  void emit(Map<String, dynamic> event) => _controller.add(event);

  @override
  Stream<Map<String, dynamic>> get eventsStream => _controller.stream;

  @override
  Future<bool> isSupported() async => isSupportedVal;

  @override
  Future<Map<String, dynamic>> checkPermissions() async => {
        'granted': permissionsGrantedVal,
        'missing': permissionsGrantedVal ? <String>[] : <String>['BLUETOOTH_SCAN'],
        'bluetoothEnabled': true,
        'locationEnabled': true,
      };

  @override
  Future<bool> requestPermissions() async {
    permissionsGrantedVal = true;
    return true;
  }

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
  Future<bool> connect(String endpointId) async {
    connectedEndpointId = endpointId;
    return true;
  }

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
  }) async => {
        'transferId': 'test_tx_001',
        'metaPayloadId': 201,
        'filePayloadId': 202,
        'sha256': 'a' * 64,
        'fileSize': 1048576,
        'fileName': 'test.mp3',
      };

  @override
  Future<bool> cancelPayload(int payloadId) async => true;

  @override
  Future<String?> commitReceivedFile({
    required String transferId,
    String? destinationDir,
    String? customName,
  }) async {
    committedTransferId = transferId;
    return '/storage/emulated/0/Music/saved_test.mp3';
  }

  @override
  Future<bool> discardReceivedFile(String transferId) async {
    discardedTransferId = transferId;
    return true;
  }

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

  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockUiBridge bridge;

  setUp(() {
    bridge = MockUiBridge();
  });

  tearDown(() {
    bridge.dispose();
  });

  Widget buildTestableWidget(
    Widget child, {
    MusicDropController? controller,
    MusicItem? activeTrack,
    WidgetTester? tester,
  }) {
    if (tester != null) {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
    }
    return ProviderScope(
      overrides: [
        musicDropNativeBridgeProvider.overrideWithValue(bridge),
        musicDropActiveTrackProvider.overrideWithValue(activeTrack),
        if (controller != null)
          musicDropControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        home: Scaffold(body: child),
      ),
    );
  }

  group('MusicDropPill Widget Tests', () {
    testWidgets('Renders default Drop pill when idle', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropPill(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Drop'), findsOneWidget);
      expect(find.byIcon(Icons.sensors_rounded), findsOneWidget);
    });

    testWidgets('Reflects discovered device count', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropPill(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      bridge.emit({
        'type': 'endpoint_found',
        'endpointId': 'dev_1',
        'endpointName': 'Pixel 8',
      });
      bridge.emit({
        'type': 'endpoint_found',
        'endpointId': 'dev_2',
        'endpointName': 'Galaxy S24',
      });
      await tester.pumpAndSettle();

      expect(find.text('Drop (2)'), findsOneWidget);
    });

    testWidgets('Reflects active transfer in-progress percentage', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropPill(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      // Simulate incoming transfer in progress
      bridge.emit({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'peer_x',
        'payloadId': 501,
        'data': '{"protocolVersion":1,"transferId":"tx_prog","payloadType":"audio_file","title":"Song","artist":"Art","sourceId":"src","fileSize":1000000,"fileName":"song.mp3","expectedSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","filePayloadId":502}',
      });
      await tester.pumpAndSettle();

      bridge.emit({
        'type': 'payload_progress',
        'endpointId': 'peer_x',
        'payloadId': 502,
        'bytesTransferred': 500000,
        'totalBytes': 1000000,
        'status': 'in_progress',
      });
      await tester.pumpAndSettle();

      expect(find.text('Receiving 50%'), findsOneWidget);
    });
  });

  group('MusicDropSheet Contextual Interface Tests', () {
    testWidgets('Renders local track badge correctly', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);
      const localTrack = Track(
        id: 'local_1',
        title: 'Local Melody',
        artist: 'Indie Artist',
        imageUrl: '',
        duration: '3:45',
        filePath: '/storage/emulated/0/Music/song.mp3',
      );

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropSheet(track: localTrack),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Music Drop'), findsOneWidget);
      expect(find.text('Local Melody'), findsOneWidget);
      expect(find.text('Indie Artist'), findsOneWidget);
      expect(find.text('Local Audio File • Full Transfer'), findsOneWidget);
    });

    testWidgets('Enforces YouTube Music restriction badge', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);
      const ytTrack = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        imageUrl: '',
        duration: '3:33',
      );

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropSheet(track: ytTrack),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Never Gonna Give You Up'), findsOneWidget);
      expect(find.text('Rick Astley'), findsOneWidget);
      expect(find.text('YouTube Music • Metadata Reference'), findsOneWidget);
    });

    testWidgets('Device selection and connect interaction', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropSheet(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      // Emit discovered endpoint
      bridge.emit({
        'type': 'endpoint_found',
        'endpointId': 'phone_42',
        'endpointName': "Alice's Phone",
      });
      await tester.pumpAndSettle();

      expect(find.text("Alice's Phone"), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);

      // Tap connect
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(bridge.connectedEndpointId, 'phone_42');
    });

    testWidgets('Authentication SAS security code confirmation', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropSheet(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      // Emit connection initiated with SAS digits
      bridge.emit({
        'type': 'connection_initiated',
        'endpointId': 'phone_42',
        'endpointName': "Alice's Phone",
        'authDigits': '7412',
        'isIncoming': true,
      });
      await tester.pumpAndSettle();

      expect(find.text('Confirm Security Code'), findsOneWidget);
      expect(find.text('7412'), findsOneWidget);
      expect(find.text('Accept & Pair'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('Receiver consent card: Accept commits file safely', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropSheet(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      // Simulate incoming completed and verified file
      bridge.emit({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'sender_1',
        'payloadId': 100,
        'data': '{"protocolVersion":1,"transferId":"tx_rcv_1","payloadType":"audio_file","title":"Shared Melody","artist":"Guest","sourceId":"src_1","fileSize":5000000,"fileName":"melody.mp3","expectedSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","filePayloadId":101}',
      });
      await tester.pumpAndSettle();

      bridge.emit({
        'type': 'transfer_completed',
        'transferId': 'tx_rcv_1',
        'payloadId': 101,
        'stagingPath': '/cache/tx_rcv_1_melody.mp3',
        'sha256': 'a' * 64,
      });
      await tester.pumpAndSettle();

      expect(find.text('Received Music Drop'), findsOneWidget);
      expect(find.text('"Shared Melody" by Guest'), findsOneWidget);
      expect(find.text('Accept & Add to Library'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      // Tap Accept
      await tester.tap(find.text('Accept & Add to Library'));
      await tester.pumpAndSettle();

      expect(bridge.committedTransferId, 'tx_rcv_1');
    });

    testWidgets('Receiver consent card: Decline discards staging file safely', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const MusicDropSheet(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      bridge.emit({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'sender_1',
        'payloadId': 200,
        'data': '{"protocolVersion":1,"transferId":"tx_discard_me","payloadType":"audio_file","title":"Unwanted Song","artist":"Spammer","sourceId":"src_sp","fileSize":1000000,"fileName":"spam.mp3","expectedSha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","filePayloadId":201}',
      });
      await tester.pumpAndSettle();

      bridge.emit({
        'type': 'transfer_completed',
        'transferId': 'tx_discard_me',
        'payloadId': 201,
        'stagingPath': '/cache/spam.mp3',
        'sha256': 'b' * 64,
      });
      await tester.pumpAndSettle();

      expect(find.text('Received Music Drop'), findsOneWidget);

      // Tap Decline
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();

      expect(bridge.discardedTransferId, 'tx_discard_me');
    });
  });

  group('IncomingDropBanner Widget Tests', () {
    testWidgets('Renders nothing when no incoming request', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const IncomingDropBanner(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingDropBanner), findsOneWidget);
      expect(find.text('Music Drop'), findsNothing);
    });

    testWidgets('Renders banner when incoming drop is ready for consent', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      final controller = MusicDropController(bridge: bridge);

      await tester.pumpWidget(buildTestableWidget(
        const IncomingDropBanner(),
        controller: controller,
        tester: tester,
      ));
      await tester.pumpAndSettle();

      bridge.emit({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'sender_1',
        'payloadId': 300,
        'data': '{"protocolVersion":1,"transferId":"tx_prompt_1","payloadType":"audio_file","title":"Incoming Hit","artist":"Star","sourceId":"src_star","fileSize":2000000,"fileName":"hit.mp3","expectedSha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","filePayloadId":301}',
      });
      await tester.pumpAndSettle();

      bridge.emit({
        'type': 'transfer_completed',
        'transferId': 'tx_prompt_1',
        'payloadId': 301,
        'stagingPath': '/cache/hit.mp3',
        'sha256': 'c' * 64,
      });
      await tester.pumpAndSettle();

      expect(find.text('Song Ready to Add'), findsOneWidget);
      expect(find.text('"Incoming Hit" by Star'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });
  });
}
