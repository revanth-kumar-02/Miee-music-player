import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/music_drop/data/music_drop_native_bridge.dart';
import 'package:Miee/features/music_drop/domain/music_drop_models.dart';
import 'package:Miee/features/music_drop/providers/music_drop_providers.dart';

class MockSecurityAuditBridge implements MusicDropNativeBridge {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();

  String? lastCommittedTransferId;
  String? lastDiscardedTransferId;
  String? lastAcceptedEndpointId;
  String? lastRejectedEndpointId;

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
        'transferId': 'test_tx',
        'filePayloadId': 202,
        'sha256': 'abc',
      };

  @override
  Future<bool> cancelPayload(int payloadId) async => true;

  @override
  Future<String?> commitReceivedFile({
    required String transferId,
    String? destinationDir,
    String? customName,
  }) async {
    lastCommittedTransferId = transferId;
    return '/storage/emulated/0/Music/${customName ?? "song.mp3"}';
  }

  @override
  Future<bool> discardReceivedFile(String transferId) async {
    lastDiscardedTransferId = transferId;
    return true;
  }

  @override
  Future<bool> isBackgroundServiceRunning() async => false;
  @override
  Future<bool> startBackgroundService({String? customName}) async => true;
  @override
  Future<bool> stopBackgroundService() async => true;
  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<List<Map<String, dynamic>>> getRecoveredTransfers() async => [];
  @override
  Future<String> checkNfcStatus() async => 'unsupported';
  @override
  Future<bool> openNfcSettings() async => true;
}

void main() {
  group('Security Audit: Domain Metadata Validation & Bounds', () {
    test('Rejects malformed JSON syntax and non-JSON objects', () {
      String? reason;
      final result1 = MusicDropMetadata.tryParse('{ invalid_json ', onError: (r) => reason = r);
      expect(result1, isNull);
      expect(reason, contains('Malformed JSON'));

      final result2 = MusicDropMetadata.tryParse('"just a string"', onError: (r) => reason = r);
      expect(result2, isNull);
      expect(reason, contains('Invalid JSON format'));
    });

    test('Rejects unsupported protocol version', () {
      String? reason;
      final payload = '''
      {
        "protocolVersion": 999,
        "transferId": "tx_sec_1",
        "payloadType": "metadata_only",
        "title": "Song",
        "artist": "Artist",
        "sourceId": "local_1"
      }
      ''';
      final result = MusicDropMetadata.tryParse(payload, onError: (r) => reason = r);
      expect(result, isNull);
      expect(reason, contains('Unsupported protocol version: 999'));
    });

    test('Rejects path traversal attacks in fileName', () {
      String? reason;
      final traversalPayloads = [
        '../../../../etc/passwd.mp3',
        r'..\..\Windows\System32\cmd.exe.mp3',
        '/data/data/com.example.miee/lib/exploit.mp3',
        r'C:\Users\admin\exploit.mp3',
      ];

      for (final maliciousName in traversalPayloads) {
        final payload = jsonEncode({
          'protocolVersion': 1,
          'transferId': 'tx_sec_2',
          'payloadType': 'audio_file',
          'title': 'Exploit Song',
          'artist': 'Hacker',
          'sourceId': 'local_1',
          'fileSize': 1024,
          'fileName': maliciousName,
          'expectedSha256': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        });
        final result = MusicDropMetadata.tryParse(payload, onError: (r) => reason = r);
        expect(result, isNull, reason: 'Failed to block traversal payload: $maliciousName');
        expect(reason, contains('illegal path traversal'));
      }
    });

    test('Rejects unauthorized executable or script extensions', () {
      String? reason;
      final badExtensions = ['sh', 'exe', 'dex', 'apk', 'bat', 'vbs', 'py', 'jar'];

      for (final ext in badExtensions) {
        final payload = '''
        {
          "protocolVersion": 1,
          "transferId": "tx_sec_ext",
          "payloadType": "audio_file",
          "title": "Trojan Track",
          "artist": "Malicious",
          "sourceId": "local_1",
          "fileSize": 5000,
          "fileName": "track.$ext",
          "expectedSha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
        ''';
        final result = MusicDropMetadata.tryParse(payload, onError: (r) => reason = r);
        expect(result, isNull);
        expect(reason, contains('Unsupported audio extension'));
      }
    });

    test('Rejects missing or invalid SHA-256 hash in audio file payload', () {
      String? reason;
      final invalidHashes = [
        '',
        'not_a_hash',
        '123456', // Too short
        'zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz', // Non-hex
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', // 65 chars
      ];

      for (final badHash in invalidHashes) {
        final payload = '''
        {
          "protocolVersion": 1,
          "transferId": "tx_sec_hash",
          "payloadType": "audio_file",
          "title": "Song",
          "artist": "Artist",
          "sourceId": "local_1",
          "fileSize": 2048,
          "fileName": "valid_song.flac",
          "expectedSha256": "$badHash"
        }
        ''';
        final result = MusicDropMetadata.tryParse(payload, onError: (r) => reason = r);
        expect(result, isNull);
        expect(reason, contains('Invalid or missing expected SHA-256'));
      }
    });

    test('Rejects zero-byte or oversized declared file payloads', () {
      String? reason;
      // Zero-byte test
      final zeroPayload = '''
      {
        "protocolVersion": 1,
        "transferId": "tx_sec_zero",
        "payloadType": "audio_file",
        "title": "Zero Song",
        "artist": "Artist",
        "sourceId": "local_1",
        "fileSize": 0,
        "fileName": "zero.mp3",
        "expectedSha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
      }
      ''';
      expect(MusicDropMetadata.tryParse(zeroPayload, onError: (r) => reason = r), isNull);
      expect(reason, contains('out of allowed bounds'));

      // Negative size test
      final negPayload = '''
      {
        "protocolVersion": 1,
        "transferId": "tx_sec_neg",
        "payloadType": "audio_file",
        "title": "Neg Song",
        "artist": "Artist",
        "sourceId": "local_1",
        "fileSize": -50,
        "fileName": "neg.mp3",
        "expectedSha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
      }
      ''';
      expect(MusicDropMetadata.tryParse(negPayload, onError: (r) => reason = r), isNull);
      expect(reason, contains('out of allowed bounds'));

      // Oversized (>150MB) test
      final overPayload = '''
      {
        "protocolVersion": 1,
        "transferId": "tx_sec_over",
        "payloadType": "audio_file",
        "title": "Big Song",
        "artist": "Artist",
        "sourceId": "local_1",
        "fileSize": 160000000,
        "fileName": "big.mp3",
        "expectedSha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
      }
      ''';
      expect(MusicDropMetadata.tryParse(overPayload, onError: (r) => reason = r), isNull);
      expect(reason, contains('out of allowed bounds'));
    });

    test('Sanitizes illegal filesystem characters without directory breakout', () {
      final sanitized = MusicDropMetadata.sanitizeFileName(
        '../../evil\x00track:?*<>"|name.m4a',
      );
      expect(sanitized, isNot(contains('/')));
      expect(sanitized, isNot(contains('\\')));
      expect(sanitized, isNot(contains(':')));
      expect(sanitized, isNot(contains('?')));
      expect(sanitized, isNot(contains('*')));
      expect(sanitized, isNot(contains('<')));
      expect(sanitized, isNot(contains('>')));
      expect(sanitized, isNot(contains('|')));
      expect(sanitized, isNot(contains('\x00')));
      expect(sanitized.endsWith('.m4a'), isTrue);
    });
  });

  group('Security Audit: Native Pipeline Failure Handling in Controller', () {
    late MockSecurityAuditBridge bridge;
    late ProviderContainer container;

    setUp(() {
      bridge = MockSecurityAuditBridge();
      container = ProviderContainer(
        overrides: [
          musicDropNativeBridgeProvider.overrideWithValue(bridge),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('Captures INSUFFICIENT_STORAGE failure event and reports error', () async {
      container.read(musicDropControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Simulate native INSUFFICIENT_STORAGE error event
      bridge.emit({
        'type': 'transfer_failed',
        'transferId': 'tx_storage_err',
        'payloadId': 901,
        'reason': 'INSUFFICIENT_STORAGE',
        'message': 'Device storage critically low. Required: 52428800 bytes, available: 10485760 bytes.',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(musicDropControllerProvider);
      expect(state.errorMessage, contains('Device storage critically low'));
    });

    test('Captures CHECKSUM_MISSING and CHECKSUM_MISMATCH security failure events', () async {
      container.read(musicDropControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Emit checksum missing rejection
      bridge.emit({
        'type': 'transfer_failed',
        'transferId': 'tx_chk_missing',
        'payloadId': 902,
        'reason': 'CHECKSUM_MISSING',
        'message': 'Expected SHA-256 checksum was missing or malformed.',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      var state = container.read(musicDropControllerProvider);
      expect(state.errorMessage, contains('checksum was missing or malformed'));

      // Emit checksum mismatch rejection
      bridge.emit({
        'type': 'transfer_failed',
        'transferId': 'tx_chk_mismatch',
        'payloadId': 903,
        'reason': 'CHECKSUM_MISMATCH',
        'message': 'SHA-256 checksum mismatch: expected abc, got def',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      state = container.read(musicDropControllerProvider);
      expect(state.errorMessage, contains('checksum mismatch'));
    });

    test('Captures EMPTY_FILE and SIZE_MISMATCH failure events', () async {
      container.read(musicDropControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bridge.emit({
        'type': 'transfer_failed',
        'transferId': 'tx_empty',
        'payloadId': 904,
        'reason': 'EMPTY_FILE',
        'message': 'Received file is empty (0 bytes).',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      var state = container.read(musicDropControllerProvider);
      expect(state.errorMessage, contains('Received file is empty'));

      bridge.emit({
        'type': 'transfer_failed',
        'transferId': 'tx_size_mismatch',
        'payloadId': 905,
        'reason': 'SIZE_MISMATCH',
        'message': 'Declared size (5000000 bytes) does not match received size (250000 bytes).',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      state = container.read(musicDropControllerProvider);
      expect(state.errorMessage, contains('does not match received size'));
    });

    test('Enforces user consent gate: Staged files remain uncommitted without explicit consent', () async {
      final controller = container.read(musicDropControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // Send metadata
      final meta = MusicDropMetadata(
        transferId: 'tx_consent_audit',
        payloadType: MusicDropPayloadType.audioFile,
        title: 'Consent Song',
        artist: 'Safe Artist',
        sourceId: 'local_1',
        fileSize: 4096,
        fileName: 'consent_song.mp3',
        expectedSha256: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
        filePayloadId: 888,
      );

      bridge.emit({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'peer_1',
        'payloadId': 777,
        'data': meta.toJsonString(),
      });

      // Complete transfer
      bridge.emit({
        'type': 'transfer_completed',
        'transferId': 'tx_consent_audit',
        'payloadId': 888,
        'stagingPath': '/data/user/0/com.example.miee/cache/music_drop_staging/tx_consent_audit.mp3',
        'sha256': 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(musicDropControllerProvider);
      final transfer = state.activeTransfers['tx_consent_audit'];
      expect(transfer, isNotNull);
      expect(transfer!.status, MusicDropTransferStatus.completed);
      // Consent gate assertion: isCommitted must remain FALSE until commit action
      expect(transfer.isCommitted, isFalse);
      expect(bridge.lastCommittedTransferId, isNull);

      // Now perform explicit user consent
      await controller.commitTransfer('tx_consent_audit');
      expect(bridge.lastCommittedTransferId, equals('tx_consent_audit'));
      expect(
        container.read(musicDropControllerProvider).activeTransfers['tx_consent_audit']?.isCommitted,
        isTrue,
      );
    });

    test('Preserves peer authentication SAS digits for verification', () async {
      container.read(musicDropControllerProvider.notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bridge.emit({
        'type': 'connection_initiated',
        'endpointId': 'endpoint_sas_1',
        'endpointName': 'Pixel 9',
        'authDigits': '7392',
        'isIncoming': true,
      });

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(musicDropControllerProvider);
      expect(state.activeConnection, isNotNull);
      expect(state.activeConnection!.endpointId, 'endpoint_sas_1');
      expect(state.activeConnection!.authDigits, '7392');
      expect(state.activeConnection!.isIncoming, isTrue);
    });
  });
}
