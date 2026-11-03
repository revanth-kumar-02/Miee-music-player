import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/connect/domain/connect_device.dart';
import 'package:Miee/features/connect/providers/connect_providers.dart';
import 'package:Miee/features/notifications/presentation/widgets/notification_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testCurrentDevice = ConnectDevice(
    id: 'local_phone_1',
    name: 'Android Phone (Miee)',
    type: DeviceType.phone,
    protocol: DeviceProtocol.thisDevice,
    lastSeen: DateTime.now(),
  );

  final testRemotePeerDevice = ConnectDevice(
    id: 'remote_peer_2',
    name: 'Living Room PC (Miee)',
    type: DeviceType.desktop,
    protocol: DeviceProtocol.mieeConnect,
    lastSeen: DateTime.now(),
  );

  group('Playback Output & Device View Tests', () {
    testWidgets('1. NotificationSheet displays honest header, active device, volume slider, and verified status', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectControllerProvider.overrideWith((ref) => FakeConnectController(
              ConnectState(
                currentDevice: testCurrentDevice,
                activeDevice: testCurrentDevice,
                availableDevices: [testCurrentDevice, testRemotePeerDevice],
              ),
            )),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top title and subtitle
      expect(find.text('Playback Output & Device'), findsOneWidget);
      expect(find.text('Active audio destination & system status'), findsOneWidget);

      // Playback Destination section header
      expect(find.text('Playback Destination'), findsOneWidget);
      expect(find.text('Outputting locally on this device'), findsOneWidget);

      // Active device details
      expect(find.text('Android Phone (Miee)'), findsOneWidget);
      expect(find.text('Active Output'), findsOneWidget);

      // Volume slider
      expect(find.text('Playback Volume'), findsOneWidget);

      // Verified peer Miee sessions
      expect(find.text('OTHER MIEE SESSIONS'), findsOneWidget);
      expect(find.text('Living Room PC (Miee)'), findsOneWidget);
      expect(find.text('Transfer'), findsOneWidget);

      // Scroll to reveal System & Audio Status section
      await tester.scrollUntilVisible(find.text('System & Audio Status'), 200);
      expect(find.text('System & Audio Status'), findsOneWidget);
      expect(find.text('Audio Engine'), findsOneWidget);
      expect(find.text('just_audio (ExoPlayer) • Standard 16-bit PCM output'), findsOneWidget);

      // Verified: Fake marketing claims are NOT present
      expect(find.text('Direct Master Audio'), findsNothing);
      expect(find.text('Pure 32-bit floating-point audio engine operational'), findsNothing);
      expect(find.text('Google Nest Audio'), findsNothing);
      expect(find.text('Samsung Smart TV'), findsNothing);
    });

    testWidgets('2. Tapping a non-active peer device invokes selectDevice transfer', (tester) async {
      ConnectDevice? selectedDevice;

      final controller = FakeConnectController(
        ConnectState(
          currentDevice: testCurrentDevice,
          activeDevice: testCurrentDevice,
          availableDevices: [testCurrentDevice, testRemotePeerDevice],
        ),
        onSelectDevice: (device) {
          selectedDevice = device;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on Transfer for the Living Room PC
      await tester.tap(find.text('Transfer'));
      await tester.pumpAndSettle();

      expect(selectedDevice, isNotNull);
      expect(selectedDevice!.id, equals('remote_peer_2'));
      expect(selectedDevice!.name, equals('Living Room PC (Miee)'));
    });

    testWidgets('3. NotificationSheet displays remote streaming destination and return button when active on peer', (tester) async {
      bool disconnected = false;

      final controller = FakeConnectController(
        ConnectState(
          currentDevice: testCurrentDevice,
          activeDevice: testRemotePeerDevice,
          availableDevices: [testCurrentDevice, testRemotePeerDevice],
        ),
        onDisconnectToThisDevice: () {
          disconnected = true;
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: NotificationSheet(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Reflects playing on the remote peer device
      expect(find.text('Playing through Living Room PC (Miee)'), findsOneWidget);
      expect(find.text('Living Room PC (Miee)'), findsOneWidget);
      expect(find.text('Switch Back to This Device'), findsOneWidget);

      // Ensure button is visible and tap
      await tester.ensureVisible(find.text('Switch Back to This Device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch Back to This Device'));
      await tester.pumpAndSettle();
      expect(disconnected, isTrue);
    });
  });
}

class FakeConnectController extends StateNotifier<ConnectState>
    implements ConnectNotifier {
  final void Function(ConnectDevice)? onSelectDevice;
  final void Function()? onDisconnectToThisDevice;

  FakeConnectController(
    super.state, {
    this.onSelectDevice,
    this.onDisconnectToThisDevice,
  });

  @override
  Future<void> selectDevice(ConnectDevice device) async {
    onSelectDevice?.call(device);
  }

  @override
  Future<void> disconnectToThisDevice() async {
    onDisconnectToThisDevice?.call();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
