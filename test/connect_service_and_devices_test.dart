import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/connect/domain/connect_device.dart';
import 'package:Miee/features/connect/providers/connect_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Connect & Smart Speaker Device Casting Tests', () {
    test('ConnectDevice serialization & model integrity across device types', () {
      final now = DateTime.now();
      final phone = ConnectDevice(
        id: 'phone_1',
        name: 'Pixel 8 Pro',
        type: DeviceType.phone,
        protocol: DeviceProtocol.thisDevice,
        isCurrent: true,
        lastSeen: now,
      );

      final map = phone.toMap();
      expect(map['id'], equals('phone_1'));
      expect(map['type'], equals('phone'));
      expect(map['protocol'], equals('thisDevice'));

      final fromMap = ConnectDevice.fromMap(map, isCurrent: true);
      expect(fromMap.id, equals('phone_1'));
      expect(fromMap.name, equals('Pixel 8 Pro'));
      expect(fromMap.type, equals(DeviceType.phone));
      expect(fromMap.isCurrent, isTrue);

      // Smart Speaker & Cast devices
      final speaker = ConnectDevice(
        id: 'nest_1',
        name: 'Living Room Nest Audio',
        type: DeviceType.speaker,
        protocol: DeviceProtocol.googleCast,
        lastSeen: now,
      );
      final speakerMap = speaker.toMap();
      final fromSpeakerMap = ConnectDevice.fromMap(speakerMap);
      expect(fromSpeakerMap.type, equals(DeviceType.speaker));
      expect(fromSpeakerMap.protocol, equals(DeviceProtocol.googleCast));

      // Smart TV & AirPlay/DLNA
      final tv = ConnectDevice(
        id: 'tv_1',
        name: 'Samsung Smart TV',
        type: DeviceType.tv,
        protocol: DeviceProtocol.dlna,
        lastSeen: now,
      );
      final tvMap = tv.toMap();
      final fromTvMap = ConnectDevice.fromMap(tvMap);
      expect(fromTvMap.type, equals(DeviceType.tv));
      expect(fromTvMap.protocol, equals(DeviceProtocol.dlna));
    });

    test('ConnectCommand payload serialization for remote playback commands', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final playCmd = ConnectCommand(
        action: 'play',
        targetDeviceId: 'desktop_123',
        senderDeviceId: 'phone_456',
        trackData: {
          'id': 'youtube_song_1',
          'title': 'Believer',
          'artist': 'Imagine Dragons',
        },
        positionMs: 45000,
        volume: 0.8,
        timestamp: now,
      );

      final map = playCmd.toMap();
      expect(map['action'], equals('play'));
      expect(map['target_device_id'], equals('desktop_123'));
      expect(map['position_ms'], equals(45000));
      expect(map['volume'], equals(0.8));

      final restored = ConnectCommand.fromMap(map);
      expect(restored.action, equals('play'));
      expect(restored.targetDeviceId, equals('desktop_123'));
      expect(restored.trackData?['title'], equals('Believer'));
    });

    test('ConnectState correctly computes isRemote flag based on activeDevice', () {
      final now = DateTime.now();
      final thisPhone = ConnectDevice(
        id: 'device_phone_1',
        name: 'This Phone',
        type: DeviceType.phone,
        protocol: DeviceProtocol.thisDevice,
        isCurrent: true,
        lastSeen: now,
      );

      final remoteSpeaker = ConnectDevice(
        id: 'device_speaker_2',
        name: 'Google Nest Speaker',
        type: DeviceType.speaker,
        protocol: DeviceProtocol.googleCast,
        isCurrent: false,
        lastSeen: now,
      );

      final localState = ConnectState(
        currentDevice: thisPhone,
        activeDevice: thisPhone,
        availableDevices: [thisPhone, remoteSpeaker],
      );

      expect(localState.isRemote, isFalse);

      final remoteState = localState.copyWith(activeDevice: remoteSpeaker);
      expect(remoteState.isRemote, isTrue);
      expect(remoteState.activeDevice.name, equals('Google Nest Speaker'));
    });
  });
}
