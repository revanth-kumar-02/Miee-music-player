import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/music_drop/data/music_drop_native_bridge.dart';
import 'package:Miee/features/music_drop/domain/music_drop_models.dart';
import 'package:Miee/features/music_drop/presentation/music_drop_controller.dart';

class MockMusicDropTransferBridge implements MusicDropNativeBridge {
  final StreamController<Map<String, dynamic>> _controller =
      StreamController<Map<String, dynamic>>.broadcast();

  bool supported = true;
  bool permissionsGranted = true;

  int? lastCancelledPayloadId;
  String? lastCommittedTransferId;
  String? lastDiscardedTransferId;
  String? sendMetadataCalledWithJson;
  String? sendAudioFileCalledWithPath;

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
      'missing': <String>[],
      'bluetoothEnabled': true,
      'locationEnabled': true,
    };
  }

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
  }) async {
    sendMetadataCalledWithJson = metadataJson;
    return 8888;
  }

  @override
  Future<Map<String, dynamic>?> sendAudioFile({
    required String endpointId,
    required String filePath,
    required String metadataJson,
  }) async {
    sendAudioFileCalledWithPath = filePath;
    return {
      'transferId': 'test_tx_001',
      'metaPayloadId': 9001,
      'filePayloadId': 9002,
      'fileSize': 1048576,
      'fileName': 'starboy.mp3',
      'sha256': 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    };
  }

  @override
  Future<bool> cancelPayload(int payloadId) async {
    lastCancelledPayloadId = payloadId;
    return true;
  }

  @override
  Future<String?> commitReceivedFile({
    required String transferId,
    String? destinationDir,
    String? customName,
  }) async {
    lastCommittedTransferId = transferId;
    return '/storage/emulated/0/Music/${customName ?? 'starboy.mp3'}';
  }

  @override
  Future<bool> discardReceivedFile(String transferId) async {
    lastDiscardedTransferId = transferId;
    return true;
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MusicDropMetadata Parsing, Validation, and Security Tests', () {
    test('Valid metadata-only JSON parses correctly', () {
      final jsonStr = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'tx_12345',
        'payloadType': 'metadata_only',
        'title': 'Blinding Lights',
        'artist': 'The Weeknd',
        'album': 'After Hours',
        'artworkUrl': 'https://example.com/art.jpg',
        'sourceId': 'yt_track_abc',
      });

      final meta = MusicDropMetadata.tryParse(jsonStr);
      expect(meta, isNotNull);
      expect(meta!.protocolVersion, 1);
      expect(meta.transferId, 'tx_12345');
      expect(meta.payloadType, MusicDropPayloadType.metadataOnly);
      expect(meta.title, 'Blinding Lights');
      expect(meta.artist, 'The Weeknd');
      expect(meta.album, 'After Hours');
      expect(meta.sourceId, 'yt_track_abc');
    });

    test('Valid audio-file metadata parses and sanitizes filename', () {
      final sha256 = 'a' * 64;
      final jsonStr = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'tx_audio_99',
        'payloadType': 'audio_file',
        'title': 'Midnight City',
        'artist': 'M83',
        'sourceId': 'local_99',
        'fileSize': 12582912, // 12 MB
        'fileName': 'Midnight City (Remastered).flac',
        'expectedSha256': sha256,
        'filePayloadId': 5001,
      });

      final meta = MusicDropMetadata.tryParse(jsonStr);
      expect(meta, isNotNull);
      expect(meta!.payloadType, MusicDropPayloadType.audioFile);
      expect(meta.fileSize, 12582912);
      expect(meta.audioFormat, 'flac');
      expect(meta.expectedSha256, sha256);
      expect(meta.filePayloadId, 5001);
    });

    test('Rejects malformed JSON syntax gracefully', () {
      String? error;
      final meta = MusicDropMetadata.tryParse(
        '{ not valid json at all',
        onError: (err) => error = err,
      );
      expect(meta, isNull);
      expect(error, contains('Malformed JSON syntax'));
    });

    test('Rejects unsupported protocol version', () {
      String? error;
      final jsonStr = jsonEncode({
        'protocolVersion': 99,
        'transferId': 'tx_1',
        'payloadType': 'metadata_only',
        'title': 'Test',
        'artist': 'Artist',
        'sourceId': 'src',
      });

      final meta = MusicDropMetadata.tryParse(jsonStr, onError: (e) => error = e);
      expect(meta, isNull);
      expect(error, contains('Unsupported protocol version: 99'));
    });

    test('Rejects missing or invalid mandatory fields', () {
      String? error;
      // Missing title
      final noTitle = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'tx_1',
        'payloadType': 'metadata_only',
        'artist': 'Artist',
        'sourceId': 'src',
      });
      expect(MusicDropMetadata.tryParse(noTitle, onError: (e) => error = e), isNull);
      expect(error, contains('Invalid title'));

      // Empty artist
      final emptyArtist = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'tx_1',
        'payloadType': 'metadata_only',
        'title': 'Title',
        'artist': '   ',
        'sourceId': 'src',
      });
      expect(MusicDropMetadata.tryParse(emptyArtist, onError: (e) => error = e), isNull);
      expect(error, contains('Invalid artist'));
    });

    test('Rejects illegal path traversal characters in filename', () {
      String? error;
      final traversalJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'tx_hack',
        'payloadType': 'audio_file',
        'title': 'Evil Track',
        'artist': 'Hacker',
        'sourceId': 'src_666',
        'fileSize': 1000,
        'fileName': '../../../../etc/shadow.mp3',
        'expectedSha256': 'b' * 64,
        'filePayloadId': 123,
      });

      final meta = MusicDropMetadata.tryParse(traversalJson, onError: (e) => error = e);
      expect(meta, isNull);
      expect(error, contains('illegal path traversal characters'));
    });

    test('Rejects unsupported audio format extensions', () {
      String? error;
      final badExtJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'tx_bad_ext',
        'payloadType': 'audio_file',
        'title': 'Dangerous File',
        'artist': 'Unknown',
        'sourceId': 'src_1',
        'fileSize': 2048,
        'fileName': 'malicious.exe',
        'expectedSha256': 'c' * 64,
        'filePayloadId': 456,
      });

      final meta = MusicDropMetadata.tryParse(badExtJson, onError: (e) => error = e);
      expect(meta, isNull);
      expect(error, contains('Unsupported audio extension: exe'));
    });

    test('Rejects oversized file metadata (> 150 MB)', () {
      String? error;
      final oversizedJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'tx_huge',
        'payloadType': 'audio_file',
        'title': 'Giant Audio',
        'artist': 'Artist',
        'sourceId': 'src_huge',
        'fileSize': 200 * 1024 * 1024, // 200 MB
        'fileName': 'giant.flac',
        'expectedSha256': 'd' * 64,
        'filePayloadId': 789,
      });

      final meta = MusicDropMetadata.tryParse(oversizedJson, onError: (e) => error = e);
      expect(meta, isNull);
      expect(error, contains('out of allowed bounds'));
    });

    test('Rejects oversized raw JSON payload (> 64 KB)', () {
      String? error;
      final giantString = 'x' * (70 * 1024);
      final meta = MusicDropMetadata.tryParse(giantString, onError: (e) => error = e);
      expect(meta, isNull);
      expect(error, contains('exceeds 65536 bytes'));
    });

    test('Duplicate filename collision avoidance algorithm', () {
      final existingFiles = {'Song.mp3', 'Song (1).mp3', 'Song (2).mp3'};

      final nonColliding = MusicDropMetadata.resolveNonCollidingFileName(
        'Song.mp3',
        existsCheck: (candidate) => existingFiles.contains(candidate),
      );

      expect(nonColliding, 'Song (3).mp3');
    });
  });

  group('MusicDropController Transfer State Transitions & Workflows', () {
    late MockMusicDropTransferBridge bridge;
    late MusicDropController controller;

    setUp(() {
      bridge = MockMusicDropTransferBridge();
      controller = MusicDropController(bridge: bridge);
    });

    tearDown(() {
      controller.dispose();
      bridge.dispose();
    });

    test('Outgoing metadata-only transfer flow: initiate -> completed', () async {
      await Future<void>.delayed(Duration.zero);

      final ok = await controller.sendMetadataOnly(
        endpointId: 'PEER_A',
        title: 'Save Your Tears',
        artist: 'The Weeknd',
        sourceId: 'yt_123',
      );

      expect(ok, isTrue);
      expect(controller.state.activeTransfers.length, 1);
      final tx = controller.state.activeTransfers.values.first;
      expect(tx.status, MusicDropTransferStatus.completed);
      expect(tx.metadata.title, 'Save Your Tears');
      expect(controller.state.lastCompletedTransfer?.transferId, tx.transferId);
    });

    test('Incoming audio file transfer lifecycle: metadata -> progress -> verifying -> completed', () async {
      await Future<void>.delayed(Duration.zero);

      final sha256 = 'f' * 64;
      final metadataJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'incoming_tx_1',
        'payloadType': 'audio_file',
        'title': 'Stay',
        'artist': 'Kid LAROI',
        'sourceId': 'local_src_55',
        'fileSize': 5242880, // 5 MB
        'fileName': 'Stay.mp3',
        'expectedSha256': sha256,
        'filePayloadId': 3333,
      });

      // 1. Peer sends metadata payload
      bridge.emitEvent({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'PEER_A',
        'payloadId': 2222,
        'data': metadataJson,
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.activeTransfers.containsKey('incoming_tx_1'), isTrue);
      var transfer = controller.state.activeTransfers['incoming_tx_1']!;
      expect(transfer.status, MusicDropTransferStatus.waiting);
      expect(transfer.metadata.fileName, 'Stay.mp3');

      // 2. Incoming file stream begins
      bridge.emitEvent({
        'type': 'payload_received',
        'payloadType': 'file',
        'endpointId': 'PEER_A',
        'payloadId': 3333,
      });
      await Future<void>.delayed(Duration.zero);
      transfer = controller.state.activeTransfers['incoming_tx_1']!;
      expect(transfer.status, MusicDropTransferStatus.receiving);

      // 3. File transfer in-progress update
      bridge.emitEvent({
        'type': 'payload_progress',
        'endpointId': 'PEER_A',
        'payloadId': 3333,
        'bytesTransferred': 2621440,
        'totalBytes': 5242880,
        'status': 'in_progress',
      });
      await Future<void>.delayed(Duration.zero);
      transfer = controller.state.activeTransfers['incoming_tx_1']!;
      expect(transfer.status, MusicDropTransferStatus.inProgress);
      expect(transfer.bytesTransferred, 2621440);
      expect(transfer.progress, closeTo(0.5, 0.01));

      // 4. Native integrity verification begins
      bridge.emitEvent({
        'type': 'transfer_verifying',
        'transferId': 'incoming_tx_1',
        'payloadId': 3333,
      });
      await Future<void>.delayed(Duration.zero);
      transfer = controller.state.activeTransfers['incoming_tx_1']!;
      expect(transfer.status, MusicDropTransferStatus.verifying);

      // 5. Checksum verified and staging ready
      bridge.emitEvent({
        'type': 'transfer_completed',
        'transferId': 'incoming_tx_1',
        'payloadId': 3333,
        'stagingPath': '/data/user/0/cache/music_drop_staging/incoming_tx_1_Stay.mp3',
        'sha256': sha256,
      });
      await Future<void>.delayed(Duration.zero);
      transfer = controller.state.activeTransfers['incoming_tx_1']!;
      expect(transfer.status, MusicDropTransferStatus.completed);
      expect(transfer.isIntegrityVerified, isTrue);
      expect(transfer.isCommitted, isFalse); // Strict consent requirement!
      expect(controller.state.lastCompletedTransfer?.transferId, 'incoming_tx_1');
    });

    test('Checksum mismatch rejects incoming file and sets failed state', () async {
      await Future<void>.delayed(Duration.zero);

      final metadataJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'corrupted_tx',
        'payloadType': 'audio_file',
        'title': 'Corrupted Track',
        'artist': 'Test',
        'sourceId': 'corrupt_1',
        'fileSize': 1000,
        'fileName': 'song.mp3',
        'expectedSha256': '1' * 64,
        'filePayloadId': 4444,
      });

      bridge.emitEvent({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'PEER_A',
        'payloadId': 1111,
        'data': metadataJson,
      });
      await Future<void>.delayed(Duration.zero);

      // Native reports CHECKSUM_MISMATCH
      bridge.emitEvent({
        'type': 'transfer_failed',
        'transferId': 'corrupted_tx',
        'payloadId': 4444,
        'reason': 'CHECKSUM_MISMATCH',
        'message': 'SHA-256 checksum mismatch: expected 1111..., got 2222...',
      });
      await Future<void>.delayed(Duration.zero);

      final transfer = controller.state.activeTransfers['corrupted_tx']!;
      expect(transfer.status, MusicDropTransferStatus.failed);
      expect(transfer.isIntegrityVerified, isFalse);
      expect(transfer.errorMessage, contains('checksum mismatch'));
    });

    test('User can cancel an in-progress transfer', () async {
      await Future<void>.delayed(Duration.zero);

      final metadataJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'cancel_me_tx',
        'payloadType': 'audio_file',
        'title': 'Cancel Track',
        'artist': 'Test',
        'sourceId': 'cancel_1',
        'fileSize': 100000,
        'fileName': 'cancel.mp3',
        'expectedSha256': '3' * 64,
        'filePayloadId': 7777,
      });

      bridge.emitEvent({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'PEER_A',
        'payloadId': 6666,
        'data': metadataJson,
      });
      await Future<void>.delayed(Duration.zero);

      expect(controller.state.activeTransfers.containsKey('cancel_me_tx'), isTrue);

      final cancelled = await controller.cancelTransfer('cancel_me_tx');
      expect(cancelled, isTrue);
      expect(bridge.lastCancelledPayloadId, 6666);
      expect(controller.state.activeTransfers['cancel_me_tx']!.status, MusicDropTransferStatus.cancelled);
    });

    test('User explicit consent: cannot commit unverified or incomplete transfer', () async {
      await Future<void>.delayed(Duration.zero);

      // Attempt to commit non-existent transfer
      final res1 = await controller.commitTransfer('non_existent');
      expect(res1, isNull);

      // Attempt to commit transfer in waiting status
      final metadataJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'pending_commit_tx',
        'payloadType': 'audio_file',
        'title': 'Pending Track',
        'artist': 'Artist',
        'sourceId': 'src_p',
        'fileSize': 1024,
        'fileName': 'pending.mp3',
        'expectedSha256': '4' * 64,
        'filePayloadId': 8881,
      });
      bridge.emitEvent({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'PEER_B',
        'payloadId': 8880,
        'data': metadataJson,
      });
      await Future<void>.delayed(Duration.zero);

      final res2 = await controller.commitTransfer('pending_commit_tx');
      expect(res2, isNull);
      expect(controller.state.errorMessage, contains('Cannot commit unverified or incomplete transfer'));

      // Now complete and verify transfer
      bridge.emitEvent({
        'type': 'transfer_completed',
        'transferId': 'pending_commit_tx',
        'payloadId': 8881,
        'stagingPath': '/cache/staged.mp3',
        'sha256': '4' * 64,
      });
      await Future<void>.delayed(Duration.zero);

      // Now explicit user consent commits the file
      final finalPath = await controller.commitTransfer('pending_commit_tx');
      expect(finalPath, isNotNull);
      expect(bridge.lastCommittedTransferId, 'pending_commit_tx');
      expect(controller.state.activeTransfers['pending_commit_tx']!.isCommitted, isTrue);
    });

    test('User can discard received transfer without committing', () async {
      await Future<void>.delayed(Duration.zero);

      final metadataJson = jsonEncode({
        'protocolVersion': 1,
        'transferId': 'discard_tx',
        'payloadType': 'audio_file',
        'title': 'Discard Track',
        'artist': 'Artist',
        'sourceId': 'src_d',
        'fileSize': 1024,
        'fileName': 'discard.mp3',
        'expectedSha256': '5' * 64,
        'filePayloadId': 9991,
      });
      bridge.emitEvent({
        'type': 'payload_received',
        'payloadType': 'bytes',
        'endpointId': 'PEER_B',
        'payloadId': 9990,
        'data': metadataJson,
      });
      await Future<void>.delayed(Duration.zero);

      final ok = await controller.rejectOrDiscardTransfer('discard_tx');
      expect(ok, isTrue);
      expect(bridge.lastDiscardedTransferId, 'discard_tx');
      expect(controller.state.activeTransfers['discard_tx']!.status, MusicDropTransferStatus.cancelled);
    });
  });
}

