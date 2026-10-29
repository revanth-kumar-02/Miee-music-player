import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/music_drop_native_bridge.dart';
import '../domain/music_drop_models.dart';

/// StateNotifier managing peer-to-peer discovery, connection lifecycle,
/// and secure payload transfer engine for Miee Music Drop.
class MusicDropController extends StateNotifier<MusicDropState> {
  final MusicDropNativeBridge _bridge;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  // Internal mapping of payloadId -> transferId for transfer progress linking
  final Map<int, String> _payloadIdToTransferId = {};

  MusicDropController({MusicDropNativeBridge? bridge})
      : _bridge = bridge ?? MusicDropNativeBridge(),
        super(const MusicDropState()) {
    _init();
  }

  Future<void> _init() async {
    final supported = await _bridge.isSupported();
    final permStatus = await _bridge.checkPermissions();

    state = state.copyWith(
      isSupported: supported,
      isPermissionsGranted: permStatus['granted'] as bool? ?? false,
      missingPermissions: List<String>.from(permStatus['missing'] as List? ?? []),
      isBluetoothEnabled: permStatus['bluetoothEnabled'] as bool? ?? false,
      isLocationEnabled: permStatus['locationEnabled'] as bool? ?? false,
    );

    _subscription = _bridge.eventsStream.listen(_handleNativeEvent);
  }

  void _handleNativeEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'discovery_state':
        state = state.copyWith(
          isDiscovering: event['isDiscovering'] as bool? ?? false,
        );
        break;

      case 'advertising_state':
        state = state.copyWith(
          isAdvertising: event['isAdvertising'] as bool? ?? false,
        );
        break;

      case 'endpoint_found':
        final endpointId = event['endpointId'] as String?;
        final endpointName = event['endpointName'] as String?;
        final serviceId = event['serviceId'] as String?;
        if (endpointId != null && endpointName != null) {
          final newEndpoint = MusicDropEndpoint(
            endpointId: endpointId,
            endpointName: endpointName,
            serviceId: serviceId,
            discoveredAt: DateTime.now(),
          );
          final updated = List<MusicDropEndpoint>.from(state.discoveredEndpoints);
          updated.removeWhere((e) => e.endpointId == endpointId);
          updated.add(newEndpoint);
          state = state.copyWith(discoveredEndpoints: updated);
        }
        break;

      case 'endpoint_lost':
        final endpointId = event['endpointId'] as String?;
        if (endpointId != null) {
          final updated = List<MusicDropEndpoint>.from(state.discoveredEndpoints);
          updated.removeWhere((e) => e.endpointId == endpointId);
          state = state.copyWith(discoveredEndpoints: updated);
        }
        break;

      case 'connection_initiated':
        final endpointId = event['endpointId'] as String?;
        final endpointName = event['endpointName'] as String? ?? 'Nearby Miee Device';
        final authDigits = event['authDigits'] as String?;
        final isIncoming = event['isIncoming'] as bool? ?? false;
        if (endpointId != null) {
          state = state.copyWith(
            activeConnection: () => MusicDropConnection(
              endpointId: endpointId,
              endpointName: endpointName,
              authDigits: authDigits,
              isIncoming: isIncoming,
              status: MusicDropConnectionStatus.initiating,
            ),
          );
        }
        break;

      case 'connection_result':
        final isSuccess = event['isSuccess'] as bool? ?? false;
        final endpointId = event['endpointId'] as String?;
        if (endpointId != null && state.activeConnection?.endpointId == endpointId) {
          if (isSuccess) {
            state = state.copyWith(
              activeConnection: () => state.activeConnection?.copyWith(
                status: MusicDropConnectionStatus.connected,
              ),
            );
          } else {
            state = state.copyWith(
              activeConnection: () => state.activeConnection?.copyWith(
                status: MusicDropConnectionStatus.rejected,
              ),
              errorMessage: () => 'Connection failed (${event['statusMessage'] ?? 'Rejected'})',
            );
          }
        }
        break;

      case 'disconnected':
        final endpointId = event['endpointId'] as String?;
        if (endpointId != null && state.activeConnection?.endpointId == endpointId) {
          state = state.copyWith(
            activeConnection: () => state.activeConnection?.copyWith(
              status: MusicDropConnectionStatus.disconnected,
            ),
          );
        }
        break;

      // ==========================================
      // Phase 2: Payload Event Handling
      // ==========================================

      case 'payload_received':
        _handlePayloadReceived(event);
        break;

      case 'payload_progress':
        _handlePayloadProgress(event);
        break;

      case 'transfer_verifying':
        final transferId = event['transferId'] as String?;
        if (transferId != null && state.activeTransfers.containsKey(transferId)) {
          final updated = state.activeTransfers[transferId]!.copyWith(
            status: MusicDropTransferStatus.verifying,
          );
          final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
          map[transferId] = updated;
          state = state.copyWith(activeTransfers: map);
        }
        break;

      case 'transfer_completed':
        final transferId = event['transferId'] as String?;
        final stagingPath = event['stagingPath'] as String?;
        if (transferId != null && state.activeTransfers.containsKey(transferId)) {
          final transfer = state.activeTransfers[transferId]!;
          final updated = transfer.copyWith(
            status: MusicDropTransferStatus.completed,
            stagingFilePath: stagingPath,
            isIntegrityVerified: true,
            bytesTransferred: transfer.totalBytes > 0 ? transfer.totalBytes : transfer.bytesTransferred,
          );
          final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
          map[transferId] = updated;
          state = state.copyWith(
            activeTransfers: map,
            lastCompletedTransfer: () => updated,
          );
        }
        break;

      case 'transfer_failed':
        final transferId = event['transferId'] as String?;
        final reason = event['reason'] as String? ?? 'Transfer error';
        final message = event['message'] as String? ?? reason;
        if (transferId != null && state.activeTransfers.containsKey(transferId)) {
          final updated = state.activeTransfers[transferId]!.copyWith(
            status: MusicDropTransferStatus.failed,
            errorMessage: message,
          );
          final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
          map[transferId] = updated;
          state = state.copyWith(
            activeTransfers: map,
            errorMessage: () => message,
          );
        }
        break;

      case 'error':
        final msg = event['message'] as String? ?? 'Proximity connection error';
        state = state.copyWith(errorMessage: () => msg);
        break;
    }
  }

  void _handlePayloadReceived(Map<String, dynamic> event) {
    final payloadType = event['payloadType'] as String?;
    final endpointId = event['endpointId'] as String? ?? '';
    final payloadId = (event['payloadId'] as num?)?.toInt();

    if (payloadType == 'bytes') {
      final rawJson = event['data'] as String?;
      if (rawJson == null) return;

      String? validationError;
      final metadata = MusicDropMetadata.tryParse(
        rawJson,
        onError: (err) => validationError = err,
      );

      if (metadata == null) {
        state = state.copyWith(
          errorMessage: () => 'Rejected incoming payload: ${validationError ?? 'Invalid metadata'}',
        );
        return;
      }

      if (payloadId != null) {
        _payloadIdToTransferId[payloadId] = metadata.transferId;
      }
      if (metadata.filePayloadId != null) {
        _payloadIdToTransferId[metadata.filePayloadId!] = metadata.transferId;
      }

      final isAudioFile = metadata.payloadType == MusicDropPayloadType.audioFile;
      final initialStatus = isAudioFile
          ? MusicDropTransferStatus.waiting
          : MusicDropTransferStatus.completed;

      final transfer = MusicDropTransfer(
        transferId: metadata.transferId,
        endpointId: endpointId,
        direction: MusicDropTransferDirection.incoming,
        metadata: metadata,
        status: initialStatus,
        bytesTransferred: 0,
        totalBytes: metadata.fileSize ?? 0,
        isIntegrityVerified: !isAudioFile,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
      map[metadata.transferId] = transfer;

      state = state.copyWith(
        activeTransfers: map,
        lastCompletedTransfer: () => !isAudioFile ? transfer : state.lastCompletedTransfer,
      );
    } else if (payloadType == 'file') {
      if (payloadId != null && _payloadIdToTransferId.containsKey(payloadId)) {
        final transferId = _payloadIdToTransferId[payloadId]!;
        if (state.activeTransfers.containsKey(transferId)) {
          final transfer = state.activeTransfers[transferId]!;
          final updated = transfer.copyWith(status: MusicDropTransferStatus.receiving);
          final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
          map[transferId] = updated;
          state = state.copyWith(activeTransfers: map);
        }
      }
    }
  }

  void _handlePayloadProgress(Map<String, dynamic> event) {
    final payloadId = (event['payloadId'] as num?)?.toInt();
    if (payloadId == null || !_payloadIdToTransferId.containsKey(payloadId)) {
      return;
    }

    final transferId = _payloadIdToTransferId[payloadId]!;
    final transfer = state.activeTransfers[transferId];
    if (transfer == null) return;

    final bytesTransferred = (event['bytesTransferred'] as num?)?.toInt() ?? transfer.bytesTransferred;
    final totalBytes = (event['totalBytes'] as num?)?.toInt() ?? transfer.totalBytes;
    final statusStr = event['status'] as String? ?? 'in_progress';

    MusicDropTransferStatus newStatus = transfer.status;
    if (statusStr == 'in_progress') {
      newStatus = MusicDropTransferStatus.inProgress;
    } else if (statusStr == 'cancelled') {
      newStatus = MusicDropTransferStatus.cancelled;
    } else if (statusStr == 'failure') {
      newStatus = MusicDropTransferStatus.failed;
    } else if (statusStr == 'success' && transfer.metadata.payloadType == MusicDropPayloadType.metadataOnly) {
      newStatus = MusicDropTransferStatus.completed;
    }

    final updated = transfer.copyWith(
      bytesTransferred: bytesTransferred,
      totalBytes: totalBytes > 0 ? totalBytes : transfer.totalBytes,
      status: newStatus,
    );

    final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
    map[transferId] = updated;
    state = state.copyWith(
      activeTransfers: map,
      lastCompletedTransfer: () => newStatus == MusicDropTransferStatus.completed ? updated : state.lastCompletedTransfer,
    );
  }

  // ==========================================
  // Sender and Receiver Control APIs
  // ==========================================

  /// Sends a metadata-only track reference to the connected endpoint.
  Future<bool> sendMetadataOnly({
    required String endpointId,
    required String title,
    required String artist,
    String? album,
    String? artworkUrl,
    required String sourceId,
  }) async {
    state = state.copyWith(errorMessage: () => null);

    final transferId = 'md_tx_${DateTime.now().millisecondsSinceEpoch}';
    final metadata = MusicDropMetadata(
      transferId: transferId,
      payloadType: MusicDropPayloadType.metadataOnly,
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl,
      sourceId: sourceId,
    );

    final transfer = MusicDropTransfer(
      transferId: transferId,
      endpointId: endpointId,
      direction: MusicDropTransferDirection.outgoing,
      metadata: metadata,
      status: MusicDropTransferStatus.inProgress,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
    map[transferId] = transfer;
    state = state.copyWith(activeTransfers: map);

    final payloadId = await _bridge.sendMetadata(
      endpointId: endpointId,
      metadataJson: metadata.toJsonString(),
    );

    if (payloadId != null) {
      _payloadIdToTransferId[payloadId] = transferId;
      final completed = transfer.copyWith(status: MusicDropTransferStatus.completed);
      map[transferId] = completed;
      state = state.copyWith(
        activeTransfers: map,
        lastCompletedTransfer: () => completed,
      );
      return true;
    } else {
      final failed = transfer.copyWith(
        status: MusicDropTransferStatus.failed,
        errorMessage: 'Failed to send metadata payload',
      );
      map[transferId] = failed;
      state = state.copyWith(
        activeTransfers: map,
        errorMessage: () => 'Failed to send metadata payload',
      );
      return false;
    }
  }

  /// Sends a local audio file and accompanying metadata to the connected endpoint.
  Future<bool> sendAudioFile({
    required String endpointId,
    required String filePath,
    required String title,
    required String artist,
    String? album,
    String? artworkUrl,
    required String sourceId,
  }) async {
    state = state.copyWith(errorMessage: () => null);

    final transferId = 'md_tx_${DateTime.now().millisecondsSinceEpoch}';
    final metadata = MusicDropMetadata(
      transferId: transferId,
      payloadType: MusicDropPayloadType.audioFile,
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl,
      sourceId: sourceId,
    );

    final transfer = MusicDropTransfer(
      transferId: transferId,
      endpointId: endpointId,
      direction: MusicDropTransferDirection.outgoing,
      metadata: metadata,
      status: MusicDropTransferStatus.waiting,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
    map[transferId] = transfer;
    state = state.copyWith(activeTransfers: map);

    final result = await _bridge.sendAudioFile(
      endpointId: endpointId,
      filePath: filePath,
      metadataJson: metadata.toJsonString(),
    );

    if (result != null) {
      final metaPayloadId = (result['metaPayloadId'] as num?)?.toInt();
      final filePayloadId = (result['filePayloadId'] as num?)?.toInt();
      final fileSize = (result['fileSize'] as num?)?.toInt() ?? 0;
      final sha256 = result['sha256'] as String?;
      final fileName = result['fileName'] as String?;

      if (metaPayloadId != null) _payloadIdToTransferId[metaPayloadId] = transferId;
      if (filePayloadId != null) _payloadIdToTransferId[filePayloadId] = transferId;

      final updatedMeta = MusicDropMetadata(
        transferId: transferId,
        payloadType: MusicDropPayloadType.audioFile,
        title: title,
        artist: artist,
        album: album,
        artworkUrl: artworkUrl,
        sourceId: sourceId,
        fileSize: fileSize,
        fileName: fileName,
        expectedSha256: sha256,
        filePayloadId: filePayloadId,
      );

      final inProgressTransfer = transfer.copyWith(
        status: MusicDropTransferStatus.inProgress,
        totalBytes: fileSize,
      );

      final activeMap = Map<String, MusicDropTransfer>.from(state.activeTransfers);
      activeMap[transferId] = MusicDropTransfer(
        transferId: transferId,
        endpointId: endpointId,
        direction: MusicDropTransferDirection.outgoing,
        metadata: updatedMeta,
        status: MusicDropTransferStatus.inProgress,
        bytesTransferred: 0,
        totalBytes: fileSize,
        createdAt: inProgressTransfer.createdAt,
        updatedAt: DateTime.now(),
      );
      state = state.copyWith(activeTransfers: activeMap);
      return true;
    } else {
      final failed = transfer.copyWith(
        status: MusicDropTransferStatus.failed,
        errorMessage: 'Failed to initiate audio file transfer',
      );
      map[transferId] = failed;
      state = state.copyWith(
        activeTransfers: map,
        errorMessage: () => 'Failed to initiate audio file transfer',
      );
      return false;
    }
  }

  /// Cancels an active or pending transfer.
  Future<bool> cancelTransfer(String transferId) async {
    final transfer = state.activeTransfers[transferId];
    if (transfer == null) return false;

    int? payloadId;
    for (final entry in _payloadIdToTransferId.entries) {
      if (entry.value == transferId) {
        payloadId = entry.key;
        break;
      }
    }

    if (payloadId != null) {
      await _bridge.cancelPayload(payloadId);
    }

    final updated = transfer.copyWith(status: MusicDropTransferStatus.cancelled);
    final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
    map[transferId] = updated;
    state = state.copyWith(activeTransfers: map);
    return true;
  }

  /// Commits a verified received file with user consent to the final destination.
  Future<String?> commitTransfer(
    String transferId, {
    String? destinationDir,
    String? customFileName,
  }) async {
    final transfer = state.activeTransfers[transferId];
    if (transfer == null) {
      state = state.copyWith(errorMessage: () => 'Transfer not found: $transferId');
      return null;
    }

    if (!transfer.isIntegrityVerified || transfer.status != MusicDropTransferStatus.completed) {
      state = state.copyWith(
        errorMessage: () => 'Cannot commit unverified or incomplete transfer: $transferId',
      );
      return null;
    }

    final finalPath = await _bridge.commitReceivedFile(
      transferId: transferId,
      destinationDir: destinationDir,
      customName: customFileName,
    );

    if (finalPath != null) {
      final updated = transfer.copyWith(
        finalFilePath: finalPath,
        isCommitted: true,
      );
      final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
      map[transferId] = updated;
      state = state.copyWith(
        activeTransfers: map,
        lastCompletedTransfer: () => updated,
      );
      return finalPath;
    } else {
      state = state.copyWith(errorMessage: () => 'Failed to commit file to storage');
      return null;
    }
  }

  /// Rejects or discards a received file without committing it.
  Future<bool> rejectOrDiscardTransfer(String transferId) async {
    final transfer = state.activeTransfers[transferId];
    if (transfer == null) return false;

    await _bridge.discardReceivedFile(transferId);

    final updated = transfer.copyWith(
      status: MusicDropTransferStatus.cancelled,
      errorMessage: 'Transfer rejected by user',
    );
    final map = Map<String, MusicDropTransfer>.from(state.activeTransfers);
    map[transferId] = updated;
    state = state.copyWith(activeTransfers: map);
    return true;
  }

  // ==========================================
  // Connection and Session Lifecycle APIs
  // ==========================================

  /// Refreshes permission and connectivity status.
  Future<void> refreshPermissions() async {
    final permStatus = await _bridge.checkPermissions();
    state = state.copyWith(
      isPermissionsGranted: permStatus['granted'] as bool? ?? false,
      missingPermissions: List<String>.from(permStatus['missing'] as List? ?? []),
      isBluetoothEnabled: permStatus['bluetoothEnabled'] as bool? ?? false,
      isLocationEnabled: permStatus['locationEnabled'] as bool? ?? false,
    );
  }

  /// Prompts the user for missing Nearby Connections permissions.
  Future<bool> requestPermissions() async {
    final granted = await _bridge.requestPermissions();
    await refreshPermissions();
    return granted;
  }

  /// Starts Nearby advertising as a Miee peer.
  Future<bool> startAdvertising({String? customName}) async {
    state = state.copyWith(errorMessage: () => null);
    final ok = await _bridge.startAdvertising(customName: customName);
    return ok;
  }

  /// Stops Nearby advertising.
  Future<bool> stopAdvertising() async {
    final ok = await _bridge.stopAdvertising();
    state = state.copyWith(isAdvertising: false);
    return ok;
  }

  /// Starts scanning for nearby Miee instances.
  Future<bool> startDiscovery() async {
    state = state.copyWith(errorMessage: () => null);
    final ok = await _bridge.startDiscovery();
    return ok;
  }

  /// Stops scanning for nearby instances.
  Future<bool> stopDiscovery() async {
    final ok = await _bridge.stopDiscovery();
    state = state.copyWith(
      isDiscovering: false,
      discoveredEndpoints: const [],
    );
    return ok;
  }

  /// Requests a connection to a discovered endpoint.
  Future<bool> connect(String endpointId) async {
    state = state.copyWith(errorMessage: () => null);
    return _bridge.connect(endpointId);
  }

  /// Accepts an incoming connection request.
  Future<bool> acceptConnection(String endpointId) async {
    return _bridge.acceptConnection(endpointId);
  }

  /// Rejects an incoming connection request.
  Future<bool> rejectConnection(String endpointId) async {
    final ok = await _bridge.rejectConnection(endpointId);
    if (state.activeConnection?.endpointId == endpointId) {
      state = state.copyWith(activeConnection: () => null);
    }
    return ok;
  }

  /// Disconnects from an active connection.
  Future<bool> disconnect(String endpointId) async {
    final ok = await _bridge.disconnect(endpointId);
    if (state.activeConnection?.endpointId == endpointId) {
      state = state.copyWith(activeConnection: () => null);
    }
    return ok;
  }

  /// Closes all sessions and resets state.
  Future<void> stopAll() async {
    await _bridge.stopAll();
    _payloadIdToTransferId.clear();
    state = state.copyWith(
      isAdvertising: false,
      isDiscovering: false,
      discoveredEndpoints: const [],
      activeConnection: () => null,
      activeTransfers: const {},
      lastCompletedTransfer: () => null,
      errorMessage: () => null,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.stopAll();
    super.dispose();
  }
}
