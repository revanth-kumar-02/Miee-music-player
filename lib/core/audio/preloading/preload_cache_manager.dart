import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'preload_models.dart';

/// Result of an atomic complete-file audio download.
class CachedAudioDownloadResult {
  final String filePath;
  final int sizeBytes;
  final Duration elapsed;

  const CachedAudioDownloadResult({
    required this.filePath,
    required this.sizeBytes,
    required this.elapsed,
  });
}

/// Manages the bounded temporary audio preload cache, `.part` atomic commits,
/// active-playback file protection, and LRU/expiration eviction.
class PreloadCacheManager {
  final PreloadConfig config;
  final Future<Directory?> Function()? cacheDirectoryProvider;

  final Map<String, PreloadEntry> _entries = {};
  final Set<String> _activeProtectedTrackIds = {};
  final Set<String> _activeProtectedPaths = {};

  Directory? _resolvedCacheDir;
  bool _orphanSweepDone = false;

  PreloadCacheManager({
    this.config = const PreloadConfig(),
    this.cacheDirectoryProvider,
  });

  Map<String, PreloadEntry> get entries => Map.unmodifiable(_entries);

  int get totalCachedBytes {
    var total = 0;
    for (final entry in _entries.values) {
      if (!entry.isLocalOriginal && entry.state == PreloadState.fullyCached) {
        total += entry.fileSizeBytes;
      }
    }
    return total;
  }

  int get cachedTrackCount {
    var count = 0;
    for (final entry in _entries.values) {
      if (!entry.isLocalOriginal && entry.state == PreloadState.fullyCached) {
        count++;
      }
    }
    return count;
  }

  /// Marks a track (and optional file path) as actively in use by the player so
  /// eviction and cleanup will never delete its file.
  void setActiveProtectedTrack(String? trackId, {String? filePath}) {
    _activeProtectedTrackIds.clear();
    _activeProtectedPaths.clear();
    if (trackId != null && trackId.isNotEmpty) {
      _activeProtectedTrackIds.add(normalizePreloadTrackId(trackId));
    }
    if (filePath != null && filePath.isNotEmpty) {
      _activeProtectedPaths.add(filePath);
    }
  }

  PreloadEntry? getEntry(String trackId) {
    final key = normalizePreloadTrackId(trackId);
    return _entries[key];
  }

  void putEntry(PreloadEntry entry) {
    _entries[entry.trackId] = entry;
  }

  void touchEntry(String trackId) {
    final key = normalizePreloadTrackId(trackId);
    final existing = _entries[key];
    if (existing != null) {
      _entries[key] = existing.copyWith(lastAccessedAt: DateTime.now());
    }
  }

  void removeEntry(String trackId, {bool deleteFile = false}) {
    final key = normalizePreloadTrackId(trackId);
    final existing = _entries[key];
    if (existing == null) return;

    if (deleteFile &&
        !existing.isLocalOriginal &&
        existing.cachedFilePath != null &&
        !_isProtected(existing.trackId, existing.cachedFilePath)) {
      _deleteFileSilently(existing.cachedFilePath!);
    }
    _entries.remove(key);
  }

  /// Validates that an existing [PreloadEntry] with [PreloadState.fullyCached]
  /// still exists on disk, has non-zero size, and is readable.
  Future<bool> verifyCachedFileReadable(PreloadEntry entry) async {
    if (entry.state != PreloadState.fullyCached) return false;
    final path = entry.cachedFilePath;
    if (path == null || path.isEmpty) return false;
    if (kIsWeb) return false;

    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final size = await file.length();
      if (size <= 0) return false;
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.readByte();
      } finally {
        await raf.close();
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Directory?> getCacheDirectory() async {
    if (kIsWeb) return null;
    if (_resolvedCacheDir != null) return _resolvedCacheDir;

    Directory? baseDir;
    if (cacheDirectoryProvider != null) {
      baseDir = await cacheDirectoryProvider!();
    } else {
      final tmp = await getTemporaryDirectory();
      baseDir = Directory('${tmp.path}${Platform.pathSeparator}miee_preload_cache');
    }

    if (baseDir == null) return null;
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
    _resolvedCacheDir = baseDir;

    if (!_orphanSweepDone) {
      _orphanSweepDone = true;
      await cleanupOrphanPartFiles();
    }
    return _resolvedCacheDir;
  }

  /// Downloads the COMPLETE audio file into a `.part` file, verifies non-zero
  /// readability and expected length, and atomically commits it to `.audio`.
  ///
  /// Throws on HTTP 403/410, cancellation, network failure, or validation failure,
  /// and always removes incomplete `.part` files before returning.
  Future<CachedAudioDownloadResult> downloadCompleteAudio({
    required String trackId,
    required String url,
    required String sourceVersion,
    Map<String, String>? headers,
    required PreloadCancellationToken cancellationToken,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('Disk caching is not supported on Web');
    }

    final dir = await getCacheDirectory();
    if (dir == null) {
      throw StateError('Cache directory unavailable');
    }

    final stem = '${safeCacheFileStem(trackId)}_${sourceVersion.hashCode.abs()}';
    final partPath = '${dir.path}${Platform.pathSeparator}$stem.part';
    final finalPath = '${dir.path}${Platform.pathSeparator}$stem.audio';
    final partFile = File(partPath);
    final finalFile = File(finalPath);
    final sw = Stopwatch()..start();

    // Clean any stale partial file from an earlier aborted attempt.
    await _deleteFileSilently(partPath);

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: config.operationTimeout,
      followRedirects: false,
      validateStatus: (_) => true,
    ));

    try {
      var currentUrl = url;
      Response<ResponseBody>? response;

      for (var hop = 0; hop < 5; hop++) {
        if (cancellationToken.isCancelled) {
          throw DioException.requestCancelled(
            requestOptions: RequestOptions(path: currentUrl),
            reason: cancellationToken.reason ?? 'cancelled',
          );
        }

        final res = await dio.get<ResponseBody>(
          currentUrl,
          cancelToken: cancellationToken.dioCancelToken,
          options: Options(
            responseType: ResponseType.stream,
            headers: headers,
          ),
        );

        final status = res.statusCode ?? 0;
        final location = res.headers.value('location');
        if ((status == 301 ||
                status == 302 ||
                status == 303 ||
                status == 307 ||
                status == 308) &&
            location != null &&
            location.isNotEmpty) {
          await res.data?.stream
              .listen((_) {}, onError: (_) {}, cancelOnError: true)
              .cancel();
          currentUrl = Uri.parse(currentUrl).resolve(location).toString();
          continue;
        }

        response = res;
        break;
      }

      if (response == null) {
        throw const HttpException('Too many redirects while preloading audio');
      }

      final status = response.statusCode ?? 0;
      if (status == 403 || status == 410) {
        await response.data?.stream
            .listen((_) {}, onError: (_) {}, cancelOnError: true)
            .cancel();
        throw HttpException('HTTP $status rejected audio preload');
      }
      if (status < 200 || status >= 300) {
        await response.data?.stream
            .listen((_) {}, onError: (_) {}, cancelOnError: true)
            .cancel();
        throw HttpException('HTTP $status while preloading audio');
      }

      final body = response.data;
      if (body == null) {
        throw const HttpException('Empty response body while preloading audio');
      }

      final contentLengthHeader = response.headers.value(HttpHeaders.contentLengthHeader);
      final expectedBytes =
          contentLengthHeader != null ? int.tryParse(contentLengthHeader) : null;

      final sink = partFile.openWrite(mode: FileMode.writeOnly);
      var bytesWritten = 0;
      var streamCompleted = false;

      try {
        await for (final chunk in body.stream) {
          if (cancellationToken.isCancelled) {
            throw DioException.requestCancelled(
              requestOptions: RequestOptions(path: currentUrl),
              reason: cancellationToken.reason ?? 'cancelled',
            );
          }
          if (chunk.isNotEmpty) {
            sink.add(chunk);
            bytesWritten += chunk.length;
          }
        }
        await sink.flush();
        streamCompleted = true;
      } finally {
        await sink.close();
      }

      if (!streamCompleted || cancellationToken.isCancelled) {
        throw StateError('Download interrupted before completion');
      }

      if (!await partFile.exists()) {
        throw StateError('Partial cache file missing after download');
      }

      final actualSize = await partFile.length();
      if (actualSize <= 0 || bytesWritten <= 0) {
        throw StateError('Downloaded audio file is empty (0 bytes)');
      }

      if (expectedBytes != null && expectedBytes > 0 && actualSize != expectedBytes) {
        throw StateError(
          'Incomplete download: expected $expectedBytes bytes, got $actualSize bytes',
        );
      }

      // Verify the file can be opened and read before committing.
      final raf = await partFile.open(mode: FileMode.read);
      try {
        await raf.readByte();
      } finally {
        await raf.close();
      }

      // Atomic commit: replace existing un-protected target if any, then rename.
      if (await finalFile.exists() && !_isProtected(trackId, finalPath)) {
        await finalFile.delete();
      }
      await partFile.rename(finalPath);
      sw.stop();

      return CachedAudioDownloadResult(
        filePath: finalPath,
        sizeBytes: actualSize,
        elapsed: sw.elapsed,
      );
    } catch (_) {
      await _deleteFileSilently(partPath);
      rethrow;
    } finally {
      dio.close(force: true);
    }
  }

  /// Removes expired entries, entries no longer in [keepTrackIds] when obsolete,
  /// and enforces [config.maxCacheBytes] and [config.maxCachedTracks] via LRU.
  Future<List<String>> evictExpiredAndUnused({
    required Set<String> keepTrackIds,
  }) async {
    final removedIds = <String>[];
    final normalizedKeep = keepTrackIds.map(normalizePreloadTrackId).toSet();

    // 1. Remove expired or obsolete non-protected entries.
    final currentKeys = _entries.keys.toList();
    for (final key in currentKeys) {
      final entry = _entries[key]!;
      if (_isProtected(key, entry.cachedFilePath)) continue;

      if (entry.isExpired) {
        if (!entry.isLocalOriginal && entry.cachedFilePath != null) {
          await _deleteFileSilently(entry.cachedFilePath!);
        }
        _entries.remove(key);
        removedIds.add(key);
        continue;
      }

      final isObsoleteState = entry.state == PreloadState.failed ||
          entry.state == PreloadState.cancelled ||
          entry.state == PreloadState.expired;
      if (isObsoleteState && !normalizedKeep.contains(key)) {
        _entries.remove(key);
        removedIds.add(key);
      }
    }

    // 2. Enforce maxCachedTracks and maxCacheBytes on disk-cached non-original entries.
    while (cachedTrackCount > config.maxCachedTracks ||
        totalCachedBytes > config.maxCacheBytes) {
      final evictable = _entries.values
          .where((e) =>
              !e.isLocalOriginal &&
              e.state == PreloadState.fullyCached &&
              !normalizedKeep.contains(e.trackId) &&
              !_isProtected(e.trackId, e.cachedFilePath))
          .toList()
        ..sort((a, b) => a.lastAccessedAt.compareTo(b.lastAccessedAt));

      if (evictable.isEmpty) break;
      final victim = evictable.first;
      if (victim.cachedFilePath != null) {
        await _deleteFileSilently(victim.cachedFilePath!);
      }
      _entries.remove(victim.trackId);
      removedIds.add(victim.trackId);
    }

    return removedIds;
  }

  /// Deletes any orphaned `.part` temporary files in the preload cache directory.
  Future<void> cleanupOrphanPartFiles() async {
    if (kIsWeb) return;
    final dir = _resolvedCacheDir;
    if (dir == null || !await dir.exists()) return;

    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && entity.path.endsWith('.part')) {
          await _deleteFileSilently(entity.path);
        }
      }
    } catch (_) {}
  }

  /// Safe shutdown cleanup: sweeps `.part` files and clears non-protected cache entries.
  Future<void> disposeCleanup() async {
    await cleanupOrphanPartFiles();
    final keys = _entries.keys.toList();
    for (final key in keys) {
      final entry = _entries[key]!;
      if (_isProtected(key, entry.cachedFilePath)) continue;
      if (!entry.isLocalOriginal && entry.cachedFilePath != null) {
        await _deleteFileSilently(entry.cachedFilePath!);
      }
      _entries.remove(key);
    }
  }

  bool _isProtected(String trackId, String? filePath) {
    if (_activeProtectedTrackIds.contains(normalizePreloadTrackId(trackId))) {
      return true;
    }
    if (filePath != null && _activeProtectedPaths.contains(filePath)) {
      return true;
    }
    return false;
  }

  Future<void> _deleteFileSilently(String path) async {
    if (kIsWeb || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
  }
}

