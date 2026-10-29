import 'dart:convert';

/// Supported Nearby Connections protocol version for Miee Music Drop.
const int kMusicDropProtocolVersion = 1;

/// Maximum allowed metadata payload size (64 KB).
const int kMaxMetadataSizeBytes = 64 * 1024;

/// Maximum allowed audio file transfer size (150 MB).
const int kMaxAudioFileSizeBytes = 150 * 1024 * 1024;

/// Supported local audio file extensions.
const Set<String> kSupportedAudioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'flac',
  'wav',
  'ogg',
  'opus',
};

/// Connection status during Nearby Connections negotiation.
enum MusicDropConnectionStatus {
  idle,
  initiating,
  connected,
  rejected,
  disconnected,
}

/// Type of payload being transferred.
enum MusicDropPayloadType {
  metadataOnly,
  audioFile,
}

/// Status of an active or past Music Drop transfer.
enum MusicDropTransferStatus {
  waiting,
  receiving,
  inProgress,
  verifying,
  completed,
  failed,
  cancelled,
}

/// Transfer direction relative to the local device.
enum MusicDropTransferDirection {
  outgoing,
  incoming,
}

/// Represents a discovered nearby Miee endpoint advertising on the local network.
class MusicDropEndpoint {
  final String endpointId;
  final String endpointName;
  final String? serviceId;
  final DateTime discoveredAt;

  const MusicDropEndpoint({
    required this.endpointId,
    required this.endpointName,
    this.serviceId,
    required this.discoveredAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicDropEndpoint &&
          runtimeType == other.runtimeType &&
          endpointId == other.endpointId;

  @override
  int get hashCode => endpointId.hashCode;

  @override
  String toString() => 'MusicDropEndpoint(id: $endpointId, name: $endpointName)';
}

/// Represents an active or pending P2P connection session.
class MusicDropConnection {
  final String endpointId;
  final String endpointName;
  final String? authDigits;
  final bool isIncoming;
  final MusicDropConnectionStatus status;

  const MusicDropConnection({
    required this.endpointId,
    required this.endpointName,
    this.authDigits,
    required this.isIncoming,
    required this.status,
  });

  MusicDropConnection copyWith({
    String? endpointId,
    String? endpointName,
    String? authDigits,
    bool? isIncoming,
    MusicDropConnectionStatus? status,
  }) {
    return MusicDropConnection(
      endpointId: endpointId ?? this.endpointId,
      endpointName: endpointName ?? this.endpointName,
      authDigits: authDigits ?? this.authDigits,
      isIncoming: isIncoming ?? this.isIncoming,
      status: status ?? this.status,
    );
  }

  @override
  String toString() =>
      'MusicDropConnection(id: $endpointId, name: $endpointName, status: $status, isIncoming: $isIncoming)';
}

/// Validated metadata for a Music Drop transfer.
class MusicDropMetadata {
  final int protocolVersion;
  final String transferId;
  final MusicDropPayloadType payloadType;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final String sourceId;
  final int? fileSize;
  final String? fileName;
  final String? audioFormat;
  final String? expectedSha256;
  final int? filePayloadId;

  const MusicDropMetadata({
    this.protocolVersion = kMusicDropProtocolVersion,
    required this.transferId,
    required this.payloadType,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    required this.sourceId,
    this.fileSize,
    this.fileName,
    this.audioFormat,
    this.expectedSha256,
    this.filePayloadId,
  });

  Map<String, dynamic> toJson() {
    return {
      'protocolVersion': protocolVersion,
      'transferId': transferId,
      'payloadType': payloadType == MusicDropPayloadType.audioFile
          ? 'audio_file'
          : 'metadata_only',
      'title': title,
      'artist': artist,
      if (album != null) 'album': album,
      if (artworkUrl != null) 'artworkUrl': artworkUrl,
      'sourceId': sourceId,
      if (fileSize != null) 'fileSize': fileSize,
      if (fileName != null) 'fileName': fileName,
      if (audioFormat != null) 'audioFormat': audioFormat,
      if (expectedSha256 != null) 'expectedSha256': expectedSha256,
      if (filePayloadId != null) 'filePayloadId': filePayloadId,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  /// Attempts to parse and strictly validate raw JSON into a [MusicDropMetadata].
  /// Returns `null` and invokes [onError] if the payload is malformed or violates security rules.
  static MusicDropMetadata? tryParse(
    String rawJson, {
    void Function(String reason)? onError,
  }) {
    if (rawJson.length > kMaxMetadataSizeBytes) {
      onError?.call('Metadata payload size exceeds $kMaxMetadataSizeBytes bytes');
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (e) {
      onError?.call('Malformed JSON syntax: $e');
      return null;
    }

    if (decoded is! Map) {
      onError?.call('Invalid JSON format: expected JSON object');
      return null;
    }

    final map = Map<String, dynamic>.from(decoded);

    // 1. Validate protocol version
    final version = map['protocolVersion'] as int?;
    if (version == null || version != kMusicDropProtocolVersion) {
      onError?.call('Unsupported protocol version: $version (expected $kMusicDropProtocolVersion)');
      return null;
    }

    // 2. Validate transfer ID
    final transferId = (map['transferId'] as String?)?.trim();
    if (transferId == null ||
        transferId.isEmpty ||
        transferId.length > 128 ||
        !RegExp(r'^[a-zA-Z0-9_\-]+$').hasMatch(transferId)) {
      onError?.call('Invalid or missing transferId');
      return null;
    }

    // 3. Validate payload type
    final typeStr = map['payloadType'] as String?;
    final MusicDropPayloadType payloadType;
    if (typeStr == 'audio_file') {
      payloadType = MusicDropPayloadType.audioFile;
    } else if (typeStr == 'metadata_only') {
      payloadType = MusicDropPayloadType.metadataOnly;
    } else {
      onError?.call('Unsupported payloadType: $typeStr');
      return null;
    }

    // 4. Validate mandatory track fields
    final title = (map['title'] as String?)?.trim();
    if (title == null || title.isEmpty || title.length > 256) {
      onError?.call('Invalid title: must be between 1 and 256 characters');
      return null;
    }

    final artist = (map['artist'] as String?)?.trim();
    if (artist == null || artist.isEmpty || artist.length > 256) {
      onError?.call('Invalid artist: must be between 1 and 256 characters');
      return null;
    }

    final sourceId = (map['sourceId'] as String?)?.trim();
    if (sourceId == null || sourceId.isEmpty || sourceId.length > 256) {
      onError?.call('Invalid sourceId');
      return null;
    }

    final album = (map['album'] as String?)?.trim();
    if (album != null && album.length > 256) {
      onError?.call('Album name exceeds maximum length');
      return null;
    }

    final artworkUrl = (map['artworkUrl'] as String?)?.trim();
    if (artworkUrl != null && (artworkUrl.length > 2048 || !artworkUrl.startsWith('http'))) {
      onError?.call('Invalid artwork URL format');
      return null;
    }

    // 5. If audio file, validate file attributes
    int? fileSize;
    String? sanitizedName;
    String? audioFormat;
    String? expectedSha256;
    int? filePayloadId;

    if (payloadType == MusicDropPayloadType.audioFile) {
      fileSize = map['fileSize'] as int?;
      if (fileSize == null || fileSize <= 0 || fileSize > kMaxAudioFileSizeBytes) {
        onError?.call('File size ($fileSize) out of allowed bounds (max $kMaxAudioFileSizeBytes bytes)');
        return null;
      }

      final rawFileName = map['fileName'] as String?;
      if (rawFileName == null || rawFileName.trim().isEmpty) {
        onError?.call('Audio file payload missing fileName');
        return null;
      }

      // Check for path traversal or malicious chars
      if (rawFileName.contains('..') || rawFileName.contains('/') || rawFileName.contains('\\')) {
        onError?.call('Filename contains illegal path traversal characters');
        return null;
      }

      // Validate extension on raw filename before sanitization
      final dot = rawFileName.lastIndexOf('.');
      if (dot == -1 || dot == rawFileName.length - 1) {
        onError?.call('Filename is missing extension');
        return null;
      }
      audioFormat = rawFileName.substring(dot + 1).toLowerCase();
      if (!kSupportedAudioExtensions.contains(audioFormat)) {
        onError?.call('Unsupported audio extension: $audioFormat');
        return null;
      }

      sanitizedName = sanitizeFileName(rawFileName);

      expectedSha256 = (map['expectedSha256'] as String?)?.trim().toLowerCase();
      if (expectedSha256 == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSha256)) {
        onError?.call('Invalid or missing expected SHA-256 checksum format');
        return null;
      }

      filePayloadId = map['filePayloadId'] as int?;
    }

    return MusicDropMetadata(
      protocolVersion: version,
      transferId: transferId,
      payloadType: payloadType,
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl,
      sourceId: sourceId,
      fileSize: fileSize,
      fileName: sanitizedName,
      audioFormat: audioFormat,
      expectedSha256: expectedSha256,
      filePayloadId: filePayloadId,
    );
  }

  /// Sanitizes arbitrary input strings into safe filesystem file basenames.
  static String sanitizeFileName(String input, {String defaultExtension = 'mp3'}) {
    var name = input.split(RegExp(r'[\\/]')).last.trim();
    name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F/\\:*?"<>|]'), '_');
    if (name.isEmpty || name == '.') {
      name = 'miee_audio_${DateTime.now().millisecondsSinceEpoch}';
    }
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex != -1 && dotIndex < name.length - 1) {
      final ext = name.substring(dotIndex + 1).toLowerCase();
      if (!kSupportedAudioExtensions.contains(ext)) {
        name = '${name.substring(0, dotIndex)}.$defaultExtension';
      }
    } else {
      name = '$name.$defaultExtension';
    }
    if (name.length > 70) {
      final ext = name.substring(name.lastIndexOf('.'));
      name = '${name.substring(0, 70 - ext.length)}$ext';
    }
    return name;
  }

  /// Resolves non-colliding filename candidate if a target file already exists.
  static String resolveNonCollidingFileName(
    String baseName, {
    required bool Function(String candidate) existsCheck,
  }) {
    if (!existsCheck(baseName)) return baseName;

    final dot = baseName.lastIndexOf('.');
    final name = dot != -1 ? baseName.substring(0, dot) : baseName;
    final ext = dot != -1 ? baseName.substring(dot) : '';

    var counter = 1;
    while (counter < 10000) {
      final candidate = '$name ($counter)$ext';
      if (!existsCheck(candidate)) {
        return candidate;
      }
      counter++;
    }
    return '$name (${DateTime.now().millisecondsSinceEpoch})$ext';
  }
}

/// Active or completed transfer record in the Music Drop engine.
class MusicDropTransfer {
  final String transferId;
  final String endpointId;
  final MusicDropTransferDirection direction;
  final MusicDropMetadata metadata;
  final MusicDropTransferStatus status;
  final int bytesTransferred;
  final int totalBytes;
  final String? stagingFilePath;
  final String? finalFilePath;
  final String? errorMessage;
  final bool isIntegrityVerified;
  final bool isCommitted;
  final DateTime createdAt;
  final DateTime updatedAt;

  const MusicDropTransfer({
    required this.transferId,
    required this.endpointId,
    required this.direction,
    required this.metadata,
    required this.status,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.stagingFilePath,
    this.finalFilePath,
    this.errorMessage,
    this.isIntegrityVerified = false,
    this.isCommitted = false,
    required this.createdAt,
    required this.updatedAt,
  });

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
  }

  bool get isComplete => status == MusicDropTransferStatus.completed;
  bool get isFailed => status == MusicDropTransferStatus.failed;
  bool get isCancelled => status == MusicDropTransferStatus.cancelled;

  MusicDropTransfer copyWith({
    MusicDropTransferStatus? status,
    int? bytesTransferred,
    int? totalBytes,
    String? stagingFilePath,
    String? finalFilePath,
    String? errorMessage,
    bool? isIntegrityVerified,
    bool? isCommitted,
    DateTime? updatedAt,
  }) {
    return MusicDropTransfer(
      transferId: transferId,
      endpointId: endpointId,
      direction: direction,
      metadata: metadata,
      status: status ?? this.status,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      stagingFilePath: stagingFilePath ?? this.stagingFilePath,
      finalFilePath: finalFilePath ?? this.finalFilePath,
      errorMessage: errorMessage ?? this.errorMessage,
      isIntegrityVerified: isIntegrityVerified ?? this.isIntegrityVerified,
      isCommitted: isCommitted ?? this.isCommitted,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}

/// Overall reactive state of the Miee Music Drop proximity foundation.
class MusicDropState {
  final bool isSupported;
  final bool isPermissionsGranted;
  final List<String> missingPermissions;
  final bool isBluetoothEnabled;
  final bool isLocationEnabled;
  final bool isAdvertising;
  final bool isDiscovering;
  final List<MusicDropEndpoint> discoveredEndpoints;
  final MusicDropConnection? activeConnection;
  final Map<String, MusicDropTransfer> activeTransfers;
  final MusicDropTransfer? lastCompletedTransfer;
  final String? errorMessage;

  const MusicDropState({
    this.isSupported = true,
    this.isPermissionsGranted = false,
    this.missingPermissions = const [],
    this.isBluetoothEnabled = true,
    this.isLocationEnabled = true,
    this.isAdvertising = false,
    this.isDiscovering = false,
    this.discoveredEndpoints = const [],
    this.activeConnection,
    this.activeTransfers = const {},
    this.lastCompletedTransfer,
    this.errorMessage,
  });

  MusicDropState copyWith({
    bool? isSupported,
    bool? isPermissionsGranted,
    List<String>? missingPermissions,
    bool? isBluetoothEnabled,
    bool? isLocationEnabled,
    bool? isAdvertising,
    bool? isDiscovering,
    List<MusicDropEndpoint>? discoveredEndpoints,
    MusicDropConnection? Function()? activeConnection,
    Map<String, MusicDropTransfer>? activeTransfers,
    MusicDropTransfer? Function()? lastCompletedTransfer,
    String? Function()? errorMessage,
  }) {
    return MusicDropState(
      isSupported: isSupported ?? this.isSupported,
      isPermissionsGranted: isPermissionsGranted ?? this.isPermissionsGranted,
      missingPermissions: missingPermissions ?? this.missingPermissions,
      isBluetoothEnabled: isBluetoothEnabled ?? this.isBluetoothEnabled,
      isLocationEnabled: isLocationEnabled ?? this.isLocationEnabled,
      isAdvertising: isAdvertising ?? this.isAdvertising,
      isDiscovering: isDiscovering ?? this.isDiscovering,
      discoveredEndpoints: discoveredEndpoints ?? this.discoveredEndpoints,
      activeConnection:
          activeConnection != null ? activeConnection() : this.activeConnection,
      activeTransfers: activeTransfers ?? this.activeTransfers,
      lastCompletedTransfer: lastCompletedTransfer != null
          ? lastCompletedTransfer()
          : this.lastCompletedTransfer,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}
