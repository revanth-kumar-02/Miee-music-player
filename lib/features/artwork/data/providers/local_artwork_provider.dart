import 'dart:io';
import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';

/// Highest priority provider that checks for local embedded or cached artwork on disk.
class LocalArtworkProvider implements ArtworkProvider {
  @override
  String get id => 'local';

  @override
  ArtworkSource get source => ArtworkSource.local;

  @override
  bool get isEnabled => true;

  @override
  int get priority => 1;

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    // Check candidate paths: localArtworkPath first, then localFilePath
    final candidates = <String>[];
    if (query.localArtworkPath != null && query.localArtworkPath!.trim().isNotEmpty) {
      candidates.add(query.localArtworkPath!.trim());
    }

    for (final path in candidates) {
      final resolved = await _validateLocalFile(path);
      if (resolved != null) {
        return resolved;
      }
    }

    return null;
  }

  Future<ResolvedArtwork?> _validateLocalFile(String rawPath) async {
    try {
      final cleanPath = rawPath.startsWith('file://')
          ? Uri.parse(rawPath).toFilePath()
          : rawPath;

      final file = File(cleanPath);
      if (!await file.exists()) {
        return null;
      }

      final length = await file.length();
      // An image file must be at least 100 bytes to be valid header + payload
      if (length < 100) {
        return null;
      }

      // Read magic bytes to ensure it's a valid image (JPEG, PNG, WEBP)
      final bytes = await file.openRead(0, 12).first;
      if (!_isImageMagicBytes(bytes)) {
        return null;
      }

      return ResolvedArtwork(
        imageUrl: cleanPath,
        source: ArtworkSource.local,
        confidence: 1.0,
        isLocal: true,
        attribution: 'Local device',
        resolvedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  bool _isImageMagicBytes(List<int> bytes) {
    if (bytes.length < 4) return false;

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;

    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return true;

    // WEBP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return true;
    }

    return false;
  }
}

