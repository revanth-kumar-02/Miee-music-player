import 'dart:collection';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/hive_boxes.dart';
import '../domain/resolved_artwork.dart';

/// Two-tiered cache combining fast in-memory LRU storage with persistent Hive backing
/// and validated local disk image caching.
class ArtworkCache {
  final int maxMemoryEntries;
  final LinkedHashMap<String, ResolvedArtwork> _memoryCache;
  final Box<dynamic>? _hiveBox;
  final Directory? _cacheDirOverride;
  final Dio? _dio;
  final Map<String, Future<String?>> _inFlightDownloads = {};

  ArtworkCache({
    this.maxMemoryEntries = 200,
    Box<dynamic>? hiveBox,
    Directory? cacheDirectory,
    Dio? dio,
  })  : _hiveBox = hiveBox,
        _cacheDirOverride = cacheDirectory,
        _dio = dio,
        _memoryCache = LinkedHashMap<String, ResolvedArtwork>();

  /// Checks magic header bytes for JPEG, PNG, WEBP, or GIF.
  static bool _hasImageMagicHeader(List<int> bytes) {
    if (bytes.length < 4) return false;
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return true;
    }
    // WEBP: RIFF....WEBP
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    // GIF: GIF87a / GIF89a
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }
    return false;
  }

  /// Validates that [bytes] represent a genuine, non-empty image (JPEG, PNG, WEBP, or GIF).
  static bool isValidImageBytes(List<int> bytes) {
    if (bytes.length < 100) return false;
    return _hasImageMagicHeader(bytes);
  }

  /// Checks whether [path] points to an existing, non-empty local image file.
  static bool hasValidLocalFile(String? path) {
    if (path == null || path.trim().isEmpty) return false;
    try {
      final f = File(path.trim());
      return f.existsSync() && f.lengthSync() >= 100;
    } catch (_) {
      return false;
    }
  }

  Future<Directory?> _getImageCacheDir() async {
    if (_cacheDirOverride != null) {
      if (!await _cacheDirOverride!.exists()) {
        await _cacheDirOverride!.create(recursive: true);
      }
      return _cacheDirOverride;
    }
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final dir = Directory('${docsDir.path}/artwork_cache');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (_) {
      return null;
    }
  }

  String _safeFileName(String cacheKey) {
    // Deterministic 64-bit FNV-1a hex hash to avoid filesystem path length/char issues
    var hash = 0xcbf29ce484222325;
    for (final unit in cacheKey.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'art_${hash.toRadixString(16).padLeft(16, '0')}.img';
  }

  /// Downloads and validates [imageUrl], storing it on disk and returning its local path.
  /// Returns `null` if the URL fails HTTP validation, redirects to an error page,
  /// or does not contain valid image bytes.
  Future<String?> cacheImageFromUrl(String cacheKey, String imageUrl) async {
    if (cacheKey.isEmpty || imageUrl.trim().isEmpty) return null;
    final cleanUrl = imageUrl.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      return null;
    }

    final inflightKey = '$cacheKey|$cleanUrl';
    if (_inFlightDownloads.containsKey(inflightKey)) {
      return _inFlightDownloads[inflightKey]!;
    }

    final future = _downloadAndValidate(cacheKey, cleanUrl).whenComplete(() {
      _inFlightDownloads.remove(inflightKey);
    });
    _inFlightDownloads[inflightKey] = future;
    return future;
  }

  Future<String?> _downloadAndValidate(String cacheKey, String url) async {
    final dir = await _getImageCacheDir();
    if (dir == null) return null;

    final targetFile = File('${dir.path}/${_safeFileName(cacheKey)}');
    if (await targetFile.exists() && await targetFile.length() >= 100) {
      try {
        final head = await targetFile.openRead(0, 16).first;
        if (_hasImageMagicHeader(head)) {
          return targetFile.path;
        }
      } catch (_) {}
    }

    final dio = _dio ??
        Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 8),
            followRedirects: true,
            maxRedirects: 5,
            headers: const {
              'User-Agent': 'MieeMusic/2.0 (Mobile; Audio)',
              'Accept': 'image/*,*/*;q=0.8',
            },
          ),
        );

    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.statusCode == null ||
          response.statusCode! < 200 ||
          response.statusCode! >= 300 ||
          response.data == null) {
        return null;
      }

      final contentType = response.headers.value('content-type')?.toLowerCase() ?? '';
      if (contentType.isNotEmpty &&
          !contentType.startsWith('image/') &&
          !contentType.contains('octet-stream')) {
        return null;
      }

      final bytes = response.data!;
      if (!isValidImageBytes(bytes)) {
        return null;
      }

      final partFile = File('${targetFile.path}.part');
      await partFile.writeAsBytes(bytes, flush: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await partFile.rename(targetFile.path);
      return targetFile.path;
    } catch (e) {
      debugPrint('[ArtworkCache] Image download/validation failed for $url: $e');
      return null;
    }
  }

  Box<dynamic>? get _box {
    if (_hiveBox != null && _hiveBox!.isOpen) return _hiveBox;
    try {
      if (Hive.isBoxOpen(HiveBoxes.artworkCache)) {
        return Hive.box<dynamic>(HiveBoxes.artworkCache);
      }
    } catch (_) {}
    return null;
  }

  /// Retrieves cached artwork by its deterministic [cacheKey].
  ResolvedArtwork? get(String cacheKey) {
    if (cacheKey.isEmpty) return null;

    // 1. Check in-memory LRU cache
    if (_memoryCache.containsKey(cacheKey)) {
      final item = _memoryCache.remove(cacheKey)!;
      _memoryCache[cacheKey] = item; // re-insert at end (most recently used)
      return item;
    }

    // 2. Check persistent Hive cache
    try {
      final box = _box;
      if (box != null && box.containsKey(cacheKey)) {
        final raw = box.get(cacheKey);
        if (raw is Map) {
          final resolved = ResolvedArtwork.fromJson(Map<String, dynamic>.from(raw));
          _putInMemory(cacheKey, resolved);
          return resolved;
        }
      }
    } catch (e) {
      debugPrint('[ArtworkCache] Error reading from Hive: $e');
    }

    return null;
  }

  /// Persists [artwork] under [cacheKey] in both memory and persistent storage.
  Future<void> put(String cacheKey, ResolvedArtwork artwork) async {
    if (cacheKey.isEmpty) return;

    _putInMemory(cacheKey, artwork);

    // Save to Hive
    try {
      final box = _box;
      if (box != null) {
        await box.put(cacheKey, artwork.toJson());
      }
    } catch (e) {
      debugPrint('[ArtworkCache] Error writing to Hive: $e');
    }
  }

  void _putInMemory(String key, ResolvedArtwork artwork) {
    if (_memoryCache.containsKey(key)) {
      _memoryCache.remove(key);
    } else if (_memoryCache.length >= maxMemoryEntries) {
      _memoryCache.remove(_memoryCache.keys.first); // Evict LRU
    }
    _memoryCache[key] = artwork;
  }

  /// Removes a cached entry.
  Future<void> evict(String cacheKey) async {
    _memoryCache.remove(cacheKey);
    try {
      final box = _box;
      if (box != null) {
        await box.delete(cacheKey);
      }
    } catch (_) {}
  }

  /// Clears both in-memory and persistent caches.
  Future<void> clear() async {
    _memoryCache.clear();
    try {
      final box = _box;
      if (box != null) {
        await box.clear();
      }
    } catch (_) {}
  }

  int get memoryCount => _memoryCache.length;
}
