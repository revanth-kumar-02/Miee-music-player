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

  final testSpeakerDevice = ConnectDevice(
    id: 'remote_speaker_2',
    name: 'Living Room Speaker',
    type: DeviceType.speaker,
    protocol: DeviceProtocol.googleCast,
    lastSeen: DateTime.now(),
  );

  final testTvDevice = ConnectDevice(
    id: 'remote_tv_3',
    name: 'Samsung OLED TV',
    type: DeviceType.tv,
    protocol: DeviceProtocol.dlna,
    lastSeen: DateTime.now(),
  );

  group('NotificationSheet & Devices View Tests', () {
    testWidgets('1. NotificationSheet displays header, devices count, and lists available devices', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectControllerProvider.overrideWith((ref) => FakeConnectController(
              ConnectState(
                currentDevice: testCurrentDevice,
                activeDevice: testCurrentDevice,
                availableDevices: [testCurrentDevice, testSpeakerDevice, testTvDevice],
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
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Connected devices & activity'), findsOneWidget);

      // Devices section header
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('3 devices to connect with'), findsOneWidget);
      expect(find.text('3 Available'), findsOneWidget);

      // Verify each individual device is displayed
      expect(find.text('Android Phone (Miee)'), findsOneWidget);
      expect(find.text('Living Room Speaker'), findsOneWidget);
      expect(find.text('Samsung OLED TV'), findsOneWidget);

      // Current active device shows Active badge
      expect(find.text('Active'), findsOneWidget);

      // Non-active devices show Connect action
      expect(find.text('Connect'), findsNWidgets(2));

      // Device & Volume Controls action
      expect(find.text('Volume & Device Controls'), findsOneWidget);

      // Scroll to reveal System Activity section
      await tester.scrollUntilVisible(find.text('System Activity'), 200);
      expect(find.text('System Activity'), findsOneWidget);
      expect(find.text('Miee Connect Active'), findsOneWidget);
      expect(find.text('Direct Master Audio'), findsOneWidget);
    });

    testWidgets('2. Tapping a non-active device in NotificationSheet invokes selectDevice', (tester) async {
      ConnectDevice? selectedDevice;

      final controller = FakeConnectController(
        ConnectState(
          currentDevice: testCurrentDevice,
          activeDevice: testCurrentDevice,
          availableDevices: [testCurrentDevice, testSpeakerDevice],
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

      // Tap on the Living Room Speaker
      await tester.tap(find.text('Living Room Speaker'));
      await tester.pumpAndSettle();

      expect(selectedDevice, isNotNull);
      expect(selectedDevice!.id, equals('remote_speaker_2'));
      expect(selectedDevice!.name, equals('Living Room Speaker'));
    });

    testWidgets('3. NotificationSheet updates status when connected to a remote speaker', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            connectControllerProvider.overrideWith((ref) => FakeConnectController(
              ConnectState(
                currentDevice: testCurrentDevice,
                activeDevice: testSpeakerDevice,
                availableDevices: [testCurrentDevice, testSpeakerDevice],
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

      // Reflects playing on the remote speaker
      expect(find.text('Playing on Living Room Speaker'), findsOneWidget);
      expect(find.text('Streaming to Living Room Speaker'), findsOneWidget);
    });
  });
}

class FakeConnectController extends StateNotifier<ConnectState>
    implements ConnectNotifier {
  final void Function(ConnectDevice)? onSelectDevice;

  FakeConnectController(
    super.state, {
    this.onSelectDevice,
  });

  @override
  Future<void> selectDevice(ConnectDevice device) async {
    onSelectDevice?.call(device);
    state = state.copyWith(activeDevice: device);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
