import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../../shared/models/music_item.dart';
import '../youtube_audio_service.dart';
import 'preload_cache_manager.dart';
import 'preload_models.dart';

typedef YouTubeStreamResolver = Future<ResolvedYouTubeStream?> Function(
  String videoIdOrUrl, {
  bool forceRefresh,
  String? title,
  String? artist,
});

typedef YouTubeQueryResolver = Future<String?> Function(String query);
typedef YouTubeUrlValidator = bool Function(String url);
typedef YouTubeCacheInvalidator = void Function(String videoIdOrUrl);
typedef ConnectivityProvider = Future<List<ConnectivityResult>> Function();
typedef FreeDiskBytesProvider = Future<int?> Function();
typedef LocalFileExistsProvider = bool Function(String path);
typedef RetryDelayProvider = Duration Function(int attempt);
typedef PreloadLogger = void Function(String message);

/// Rolling two-track audio preloader for Miee.
///
/// While the current track plays, prepares up to [PreloadConfig.maxUpcomingTracks]
/// (default 2) upcoming tracks in the active queue:
/// - Local tracks: verifies existing file path without copying or modifying it.
/// - YouTube tracks: resolves streams via [YouTubeAudioService] and marks them
///   [PreloadState.streamReady] (streaming-only by default; never falsely marked
///   [PreloadState.fullyCached]).
/// - Cacheable non-YouTube HTTP tracks: downloads full track to `.part`,
///   validates completeness/readability, and atomically promotes to
///   [PreloadState.fullyCached] when network policy and free storage allow.
class NextTrackPreloader {
  final PreloadConfig config;
  final PreloadCacheManager cacheManager;
  final YouTubeStreamResolver _resolveYouTubeStream;
  final YouTubeQueryResolver _resolveYouTubeQuery;
  final YouTubeUrlValidator _isYouTubeUrlValid;
  final YouTubeCacheInvalidator _invalidateYouTubeCache;
  final ConnectivityProvider _connectivityProvider;
  final FreeDiskBytesProvider _freeDiskBytesProvider;
  final LocalFileExistsProvider _localFileExistsProvider;
  final RetryDelayProvider _retryDelayProvider;
  final PreloadLogger _logger;
  final DateTime Function() _nowProvider;

  final Map<String, PreloadCancellationToken> _inFlightTokens = {};
  final Set<String> _activeTargetIds = {};
  Future<void> _workerChain = Future<void>.value();

  List<MusicItem> _lastQueue = const [];
  int _lastCurrentIndex = -1;
  LoopMode _lastLoopMode = LoopMode.off;
  String? _activePlayingTrackId;

  int _windowEpoch = 0;
  int _immediatePlaybackDepth = 0;
  bool _disposed = false;

  NextTrackPreloader({
    this.config = const PreloadConfig(),
    PreloadCacheManager? cacheManager,
    YouTubeStreamResolver? resolveYouTubeStream,
    YouTubeQueryResolver? resolveYouTubeQuery,
    YouTubeUrlValidator? isYouTubeUrlValid,
    YouTubeCacheInvalidator? invalidateYouTubeCache,
    ConnectivityProvider? connectivityProvider,
    FreeDiskBytesProvider? freeDiskBytesProvider,
    LocalFileExistsProvider? localFileExistsProvider,
    RetryDelayProvider? retryDelayProvider,
    PreloadLogger? logger,
    DateTime Function()? nowProvider,
  })  : cacheManager = cacheManager ?? PreloadCacheManager(config: config),
        _resolveYouTubeStream =
            resolveYouTubeStream ?? YouTubeAudioService().getAudioStream,
        _resolveYouTubeQuery =
            resolveYouTubeQuery ?? YouTubeAudioService().resolveVideoIdForQuery,
        _isYouTubeUrlValid =
            isYouTubeUrlValid ?? YouTubeAudioService().isUrlValid,
        _invalidateYouTubeCache =
            invalidateYouTubeCache ?? YouTubeAudioService().invalidateCache,
        _connectivityProvider =
            connectivityProvider ?? (() => Connectivity().checkConnectivity()),
        _freeDiskBytesProvider =
            freeDiskBytesProvider ?? _defaultFreeDiskBytesProvider,
        _localFileExistsProvider =
            localFileExistsProvider ?? ((p) => File(p).existsSync()),
        _retryDelayProvider = retryDelayProvider ?? _defaultRetryDelay,
        _logger = logger ?? ((msg) => debugPrint(msg)),
        _nowProvider = nowProvider ?? DateTime.now;

  static Future<int?> _defaultFreeDiskBytesProvider() async {
    // Dart stdlib does not expose cross-platform statvfs without FFI/platform channels.
    // Returning null allows preloading to proceed with bounded cache limits while
    // still enabling deterministic low-storage tests via injection.
    return null;
  }

  static Duration _defaultRetryDelay(int attempt) {
    final factor = 1 << attempt.clamp(0, 4);
    return Duration(milliseconds: 250 * factor);
  }

  bool get isDisposed => _disposed;
  bool get isPrioritizingImmediatePlayback => _immediatePlaybackDepth > 0;

  /// Computes the rolling upcoming window (max [PreloadConfig.maxUpcomingTracks])
  /// for the given queue state.
  ///
  /// - Returns empty when [loopMode] is [LoopMode.one] (repeat-one never preloads).
  /// - Excludes the currently playing track and deduplicates repeated track IDs.
  /// - Wraps around the queue when [loopMode] is [LoopMode.all].
  List<MusicItem> computeUpcomingWindow(
    List<MusicItem> queue,
    int currentIndex,
    LoopMode loopMode,
  ) {
    if (queue.isEmpty ||
        currentIndex < 0 ||
        currentIndex >= queue.length ||
        config.maxUpcomingTracks <= 0) {
      return const [];
    }
    if (loopMode == LoopMode.one) {
      return const [];
    }

    final currentTrackId = normalizePreloadTrackId(queue[currentIndex].id);
    final seenIds = <String>{currentTrackId};
    final upcoming = <MusicItem>[];

    if (loopMode == LoopMode.all) {
      for (int offset = 1; offset < queue.length; offset++) {
        final idx = (currentIndex + offset) % queue.length;
        final candidate = queue[idx];
        final candidateId = normalizePreloadTrackId(candidate.id);
        if (candidateId.isEmpty || seenIds.contains(candidateId)) continue;
        seenIds.add(candidateId);
        upcoming.add(candidate);
        if (upcoming.length >= config.maxUpcomingTracks) break;
      }
    } else {
      for (int idx = currentIndex + 1; idx < queue.length; idx++) {
        final candidate = queue[idx];
        final candidateId = normalizePreloadTrackId(candidate.id);
        if (candidateId.isEmpty || seenIds.contains(candidateId)) continue;
        seenIds.add(candidateId);
        upcoming.add(candidate);
        if (upcoming.length >= config.maxUpcomingTracks) break;
      }
    }

    return upcoming;
  }

  /// Marks [track] as currently playing so its cached file (if any) is protected
  /// from eviction or deletion.
  void markPlayingTrack(MusicItem? track) {
    if (track == null) {
      _activePlayingTrackId = null;
      cacheManager.setActiveProtectedTrack(null);
      return;
    }
    final trackId = normalizePreloadTrackId(track.id);
    _activePlayingTrackId = trackId;
    final existing = cacheManager.getEntry(trackId);
    cacheManager.setActiveProtectedTrack(
      trackId,
      filePath: existing?.cachedFilePath,
    );
    if (existing != null) {
      cacheManager.touchEntry(trackId);
    }
  }

  /// Synchronizes the rolling two-track preload window with the latest queue state.
  ///
  /// Cancels any obsolete in-flight preloads outside the new window and schedules
  /// preparation for missing/expired upcoming tracks.
  Future<void> syncWindow({
    required List<MusicItem> queue,
    required int currentIndex,
    required LoopMode loopMode,
  }) async {
    if (_disposed) return;

    final epoch = ++_windowEpoch;
    _lastQueue = List<MusicItem>.unmodifiable(queue);
    _lastCurrentIndex = currentIndex;
    _lastLoopMode = loopMode;

    final targets = computeUpcomingWindow(queue, currentIndex, loopMode);
    final targetById = <String, MusicItem>{};
    final targetVersions = <String, String>{};
    for (final item in targets) {
      final id = normalizePreloadTrackId(item.id);
      targetById[id] = item;
      targetVersions[id] = _computeSourceVersion(item);
    }

    _activeTargetIds
      ..clear()
      ..addAll(targetById.keys);

    // Cancel obsolete or source-changed in-flight preloads.
    final toCancel = <String>[];
    for (final entry in _inFlightTokens.entries) {
      final expectedVersion = targetVersions[entry.key];
      if (expectedVersion == null ||
          entry.value.sourceVersion != expectedVersion) {
        toCancel.add(entry.key);
      }
    }
    for (final id in toCancel) {
      final token = _inFlightTokens.remove(id);
      if (token != null && !token.isCancelled) {
        token.cancel('Left rolling preload window');
        _markEntryCancelledIfInProgress(id, token.sourceVersion);
        _log(
          '[PreloadDiag] Cancelled obsolete preload track=$id reason=window_shifted',
        );
      }
    }

    // Remove/evict stale cache entries outside window + active track.
    final keepIds = <String>{
      ...targetById.keys,
      if (_activePlayingTrackId != null) _activePlayingTrackId!,
    };
    await cacheManager.evictExpiredAndUnused(keepTrackIds: keepIds);

    if (_disposed || epoch != _windowEpoch) return;

    if (targets.isEmpty) {
      _log(
        '[PreloadDiag] Rolling window empty (index=$currentIndex, loop=$loopMode, queueLen=${queue.length})',
      );
      return;
    }

    _log(
      '[PreloadDiag] Rolling window targets=${targets.map((t) => normalizePreloadTrackId(t.id)).join(",")} (index=$currentIndex, loop=$loopMode)',
    );

    // Schedule each target sequentially through the worker chain so next-1
    // finishes before next-2 and rapid window updates stay ordered.
    for (final target in targets) {
      _workerChain = _workerChain.then((_) async {
        if (_disposed || epoch != _windowEpoch) return;
        await _prepareIfNeeded(target, epoch);
      }).catchError((Object e) {
        _log('[PreloadDiag] Worker error: ${_sanitizeError(e.toString())}');
      });
    }

    await _workerChain;
  }

  /// Returns a usable prepared [PreloadEntry] for playback if valid, or `null`.
  ///
  /// Validates file readability for [PreloadState.fullyCached] entries and
  /// expiration/URL validity for [PreloadState.streamReady] entries.
  Future<PreloadEntry?> getPreparedEntry(MusicItem track) async {
    final trackId = normalizePreloadTrackId(track.id);
    final entry = cacheManager.getEntry(trackId);
    if (entry == null) return null;

    final expectedVersion = _computeSourceVersion(track);
    if (entry.sourceVersion != expectedVersion) {
      return null;
    }

    if (entry.state == PreloadState.fullyCached) {
      if (entry.isLocalOriginal) {
        final path = entry.cachedFilePath;
        if (path != null && _localFileExistsProvider(path)) {
          cacheManager.touchEntry(trackId);
          return entry;
        }
        cacheManager.removeEntry(trackId, deleteFile: false);
        return null;
      }

      final readable = await cacheManager.verifyCachedFileReadable(entry);
      if (readable) {
        cacheManager.touchEntry(trackId);
        return entry;
      }
      cacheManager.removeEntry(trackId, deleteFile: true);
      return null;
    }

    if (entry.state == PreloadState.streamReady) {
      final now = _nowProvider();
      final expiredByClock =
          entry.expiresAt != null && !now.isBefore(entry.expiresAt!);
      final invalidYoutubeUrl = entry.sourceKind == PreloadSourceKind.youtube &&
          (entry.streamUrl == null || !_isYouTubeUrlValid(entry.streamUrl!));

      if (expiredByClock || invalidYoutubeUrl) {
        cacheManager.putEntry(
          entry.copyWith(
            state: PreloadState.expired,
            updatedAt: now,
            failureReason: 'Prepared stream URL expired',
          ),
        );
        _log('[PreloadDiag] Prepared stream expired for track=$trackId');
        return null;
      }

      cacheManager.touchEntry(trackId);
      return entry;
    }

    return null;
  }

  /// Returns the current [PreloadEntry] for inspection/diagnostics/tests without
  /// altering its state.
  PreloadEntry? getEntrySnapshot(String trackId) =>
      cacheManager.getEntry(normalizePreloadTrackId(trackId));

  /// Invalidates any prepared entry (and optionally YouTube stream cache) when
  /// playback encounters an expired or rejected stream (e.g. HTTP 403/410).
  Future<void> invalidateTrack(
    String trackId, {
    bool isYoutube = false,
    bool deleteCachedFile = false,
  }) async {
    final normalized = normalizePreloadTrackId(trackId);
    final token = _inFlightTokens.remove(normalized);
    token?.cancel('Invalidated by playback');
    if (isYoutube) {
      _invalidateYouTubeCache(normalized);
    }
    cacheManager.removeEntry(normalized, deleteFile: deleteCachedFile);
    _log('[PreloadDiag] Invalidated track=$normalized youtube=$isYoutube');
  }

  /// Runs [action] (such as manual skip or immediate playback load) with priority
  /// over background preloading so current track playback is never starved.
  Future<T> prioritizeImmediatePlayback<T>(Future<T> Function() action) async {
    _immediatePlaybackDepth++;
    // Cancel any active remote HTTP downloads so bandwidth goes to immediate playback.
    for (final entry in _inFlightTokens.entries.toList()) {
      final existing = cacheManager.getEntry(entry.key);
      if (existing?.state == PreloadState.downloading) {
        entry.value.cancel('Prioritizing immediate playback');
        _inFlightTokens.remove(entry.key);
        _markEntryCancelledIfInProgress(entry.key, entry.value.sourceVersion);
      }
    }
    try {
      return await action();
    } finally {
      _immediatePlaybackDepth--;
      if (!_disposed &&
          _immediatePlaybackDepth == 0 &&
          _lastQueue.isNotEmpty &&
          _lastCurrentIndex >= 0) {
        // Schedule re-sync asynchronously without blocking the caller.
        unawaited(
          syncWindow(
            queue: _lastQueue,
            currentIndex: _lastCurrentIndex,
            loopMode: _lastLoopMode,
          ),
        );
      }
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _windowEpoch++;
    for (final token in _inFlightTokens.values) {
      token.cancel('Preloader disposed');
    }
    _inFlightTokens.clear();
    _activeTargetIds.clear();
    await cacheManager.disposeCleanup();
    _log('[PreloadDiag] NextTrackPreloader disposed');
  }

  Future<void> _prepareIfNeeded(MusicItem track, int epoch) async {
    if (_disposed || epoch != _windowEpoch) return;
    if (_immediatePlaybackDepth > 0) return;

    final trackId = normalizePreloadTrackId(track.id);
    if (trackId.isEmpty || !_activeTargetIds.contains(trackId)) return;

    final sourceKind = _classifySource(track);
    final sourceVersion = _computeSourceVersion(track);

    // Deduplicate: skip if already in-flight with the same sourceVersion.
    final inFlight = _inFlightTokens[trackId];
    if (inFlight != null &&
        !inFlight.isCancelled &&
        inFlight.sourceVersion == sourceVersion) {
      return;
    }

    // Deduplicate: skip if already validly prepared for the same sourceVersion.
    final existing = cacheManager.getEntry(trackId);
    if (existing != null && existing.sourceVersion == sourceVersion) {
      if (existing.state == PreloadState.fullyCached) {
        if (existing.isLocalOriginal) {
          if (existing.cachedFilePath != null &&
              _localFileExistsProvider(existing.cachedFilePath!)) {
            cacheManager.touchEntry(trackId);
            return;
          }
        } else if (await cacheManager.verifyCachedFileReadable(existing)) {
          cacheManager.touchEntry(trackId);
          return;
        }
      } else if (existing.state == PreloadState.streamReady) {
        final now = _nowProvider();
        final notExpired =
            existing.expiresAt == null || now.isBefore(existing.expiresAt!);
        final urlValid = existing.sourceKind != PreloadSourceKind.youtube ||
            (existing.streamUrl != null &&
                _isYouTubeUrlValid(existing.streamUrl!));
        if (notExpired && urlValid) {
          cacheManager.touchEntry(trackId);
          return;
        }
        cacheManager.putEntry(
          existing.copyWith(
            state: PreloadState.expired,
            updatedAt: now,
            failureReason: 'Stream expired before reuse',
          ),
        );
      }
    }

    final token = PreloadCancellationToken(
      trackId: trackId,
      sourceVersion: sourceVersion,
    );
    _inFlightTokens[trackId] = token;

    try {
      await _executePreparation(
        track: track,
        trackId: trackId,
        sourceKind: sourceKind,
        sourceVersion: sourceVersion,
        token: token,
        epoch: epoch,
      );
    } finally {
      if (identical(_inFlightTokens[trackId], token)) {
        _inFlightTokens.remove(trackId);
      }
    }
  }

  Future<void> _executePreparation({
    required MusicItem track,
    required String trackId,
    required PreloadSourceKind sourceKind,
    required String sourceVersion,
    required PreloadCancellationToken token,
    required int epoch,
  }) async {
    final now = _nowProvider();

    if (sourceKind == PreloadSourceKind.local) {
      final path = track.filePath;
      if (path.isNotEmpty && _localFileExistsProvider(path)) {
        cacheManager.putEntry(
          PreloadEntry(
            trackId: trackId,
            rawTrackId: track.id,
            sourceVersion: sourceVersion,
            sourceKind: PreloadSourceKind.local,
            state: PreloadState.fullyCached,
            cachedFilePath: path,
            isLocalOriginal: true,
            updatedAt: now,
            lastAccessedAt: now,
          ),
        );
        _log('[PreloadDiag] Local track verified in-place track=$trackId');
      } else {
        cacheManager.putEntry(
          PreloadEntry(
            trackId: trackId,
            rawTrackId: track.id,
            sourceVersion: sourceVersion,
            sourceKind: PreloadSourceKind.local,
            state: PreloadState.failed,
            updatedAt: now,
            lastAccessedAt: now,
            failureReason: 'Local file missing',
          ),
        );
        _log('[PreloadDiag] Local track missing track=$trackId');
      }
      return;
    }

    // Remote tracks: check network policy first.
    final policy = await _resolveNetworkPolicy();
    if (token.isCancelled || _disposed || epoch != _windowEpoch) {
      _markEntryCancelledIfInProgress(trackId, sourceVersion);
      return;
    }
    if (policy == NetworkPreloadPolicy.offline) {
      _log('[PreloadDiag] Offline; skipping remote preload track=$trackId');
      return;
    }

    // Mark resolving.
    cacheManager.putEntry(
      PreloadEntry(
        trackId: trackId,
        rawTrackId: track.id,
        sourceVersion: sourceVersion,
        sourceKind: sourceKind,
        state: PreloadState.resolving,
        updatedAt: _nowProvider(),
        lastAccessedAt: _nowProvider(),
      ),
    );

    if (sourceKind == PreloadSourceKind.youtube) {
      await _prepareYouTubeTrack(
        track: track,
        trackId: trackId,
        sourceVersion: sourceVersion,
        token: token,
        epoch: epoch,
      );
      return;
    }

    // Remote non-YouTube HTTP track.
    await _prepareRemoteHttpTrack(
      track: track,
      trackId: trackId,
      sourceVersion: sourceVersion,
      policy: policy,
      token: token,
      epoch: epoch,
    );
  }

  Future<void> _prepareYouTubeTrack({
    required MusicItem track,
    required String trackId,
    required String sourceVersion,
    required PreloadCancellationToken token,
    required int epoch,
  }) async {
    String? lastError;

    for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
      if (token.isCancelled || _disposed || epoch != _windowEpoch) {
        _markEntryCancelledIfInProgress(trackId, sourceVersion);
        return;
      }

      try {
        ResolvedYouTubeStream? resolved;
        final isPreviewUrl = track.filePath.contains('itunes.apple.com') ||
            track.filePath.contains('preview');
        final hasDirectHttp =
            _isHttpUrl(track.filePath) && !isPreviewUrl && attempt == 0;

        if (hasDirectHttp && _isYouTubeUrlValid(track.filePath)) {
          resolved = ResolvedYouTubeStream(
            url: track.filePath,
            userAgent:
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            clientName: 'Direct',
          );
        } else {
          String videoIdOrUrl = trackId;
          if (videoIdOrUrl.isEmpty || track.id.startsWith('itunes_')) {
            final query = '${track.artist} - ${track.title}'.trim();
            final matchedId = await _resolveYouTubeQuery(query);
            if (matchedId != null && matchedId.isNotEmpty) {
              videoIdOrUrl = matchedId;
            }
          }

          resolved = await _resolveYouTubeStream(
            videoIdOrUrl,
            forceRefresh: attempt > 0,
            title: track.title,
            artist: track.artist,
          ).timeout(config.operationTimeout);
        }

        if (token.isCancelled || _disposed || epoch != _windowEpoch) {
          _markEntryCancelledIfInProgress(trackId, sourceVersion);
          return;
        }

        if (resolved != null &&
            resolved.url.isNotEmpty &&
            _isYouTubeUrlValid(resolved.url)) {
          final now = _nowProvider();
          // YouTube remains streaming-only by default (allowYouTubeFullCaching=false).
          // Never falsely mark YouTube tracks as PreloadState.fullyCached without
          // a real verified complete audio file.
          cacheManager.putEntry(
            PreloadEntry(
              trackId: trackId,
              rawTrackId: track.id,
              sourceVersion: sourceVersion,
              sourceKind: PreloadSourceKind.youtube,
              state: PreloadState.streamReady,
              streamUrl: resolved.url,
              userAgent: resolved.userAgent,
              clientName: resolved.clientName,
              expiresAt: _extractYouTubeExpiry(resolved.url),
              updatedAt: now,
              lastAccessedAt: now,
            ),
          );
          _log(
            '[PreloadDiag] YouTube track streamReady track=$trackId client=${resolved.clientName}',
          );
          return;
        }

        lastError = 'No valid YouTube stream resolved';
        _invalidateYouTubeCache(trackId);
      } catch (e) {
        lastError = _sanitizeError(e.toString());
        _invalidateYouTubeCache(trackId);
      }

      if (attempt < config.maxRetries) {
        final delay = _retryDelayProvider(attempt);
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
      }
    }

    if (!token.isCancelled && !_disposed && epoch == _windowEpoch) {
      final now = _nowProvider();
      cacheManager.putEntry(
        PreloadEntry(
          trackId: trackId,
          rawTrackId: track.id,
          sourceVersion: sourceVersion,
          sourceKind: PreloadSourceKind.youtube,
          state: PreloadState.failed,
          updatedAt: now,
          lastAccessedAt: now,
          failureReason: lastError ?? 'YouTube preload failed',
        ),
      );
      _log(
        '[PreloadDiag] YouTube preload failed track=$trackId reason=$lastError',
      );
    }
  }

  Future<void> _prepareRemoteHttpTrack({
    required MusicItem track,
    required String trackId,
    required String sourceVersion,
    required NetworkPreloadPolicy policy,
    required PreloadCancellationToken token,
    required int epoch,
  }) async {
    final now = _nowProvider();

    // On mobile data-saver, do not download full audio files; prepare stream metadata only.
    if (policy == NetworkPreloadPolicy.mobileDataSaver) {
      cacheManager.putEntry(
        PreloadEntry(
          trackId: trackId,
          rawTrackId: track.id,
          sourceVersion: sourceVersion,
          sourceKind: PreloadSourceKind.remoteHttp,
          state: PreloadState.streamReady,
          streamUrl: track.filePath,
          updatedAt: now,
          lastAccessedAt: now,
        ),
      );
      _log(
        '[PreloadDiag] Mobile data-saver active; streamReady fallback track=$trackId',
      );
      return;
    }

    // Check free disk space if available.
    int? freeBytes;
    try {
      freeBytes = await _freeDiskBytesProvider();
    } catch (_) {
      freeBytes = null;
    }
    if (freeBytes != null && freeBytes < config.minRequiredFreeBytes) {
      cacheManager.putEntry(
        PreloadEntry(
          trackId: trackId,
          rawTrackId: track.id,
          sourceVersion: sourceVersion,
          sourceKind: PreloadSourceKind.remoteHttp,
          state: PreloadState.streamReady,
          streamUrl: track.filePath,
          updatedAt: _nowProvider(),
          lastAccessedAt: _nowProvider(),
          failureReason: 'Low storage; streaming fallback',
        ),
      );
      _log(
        '[PreloadDiag] Low storage (free=$freeBytes); streamReady fallback track=$trackId',
      );
      return;
    }

    String? lastError;
    for (int attempt = 0; attempt <= config.maxRetries; attempt++) {
      if (token.isCancelled || _disposed || epoch != _windowEpoch) {
        _markEntryCancelledIfInProgress(trackId, sourceVersion);
        return;
      }

      cacheManager.putEntry(
        PreloadEntry(
          trackId: trackId,
          rawTrackId: track.id,
          sourceVersion: sourceVersion,
          sourceKind: PreloadSourceKind.remoteHttp,
          state: PreloadState.downloading,
          streamUrl: track.filePath,
          updatedAt: _nowProvider(),
          lastAccessedAt: _nowProvider(),
        ),
      );

      try {
        final result = await cacheManager.downloadCompleteAudio(
          trackId: trackId,
          url: track.filePath,
          sourceVersion: sourceVersion,
          cancellationToken: token,
        );

        if (token.isCancelled) {
          _markEntryCancelledIfInProgress(trackId, sourceVersion);
          return;
        }

        final doneNow = _nowProvider();
        cacheManager.putEntry(
          PreloadEntry(
            trackId: trackId,
            rawTrackId: track.id,
            sourceVersion: sourceVersion,
            sourceKind: PreloadSourceKind.remoteHttp,
            state: PreloadState.fullyCached,
            cachedFilePath: result.filePath,
            fileSizeBytes: result.sizeBytes,
            isLocalOriginal: false,
            streamUrl: track.filePath,
            updatedAt: doneNow,
            lastAccessedAt: doneNow,
          ),
        );

        final keepIds = <String>{
          ..._activeTargetIds,
          if (_activePlayingTrackId != null) _activePlayingTrackId!,
        };
        await cacheManager.evictExpiredAndUnused(keepTrackIds: keepIds);

        _log(
          '[PreloadDiag] Remote track fullyCached track=$trackId bytes=${result.sizeBytes}',
        );
        return;
      } catch (e) {
        if (token.isCancelled) {
          _markEntryCancelledIfInProgress(trackId, sourceVersion);
          return;
        }
        lastError = _sanitizeError(e.toString());
        if (attempt < config.maxRetries) {
          final delay = _retryDelayProvider(attempt);
          if (delay > Duration.zero) {
            await Future<void>.delayed(delay);
          }
        }
      }
    }

    if (!token.isCancelled && !_disposed && epoch == _windowEpoch) {
      final failNow = _nowProvider();
      cacheManager.putEntry(
        PreloadEntry(
          trackId: trackId,
          rawTrackId: track.id,
          sourceVersion: sourceVersion,
          sourceKind: PreloadSourceKind.remoteHttp,
          state: PreloadState.failed,
          updatedAt: failNow,
          lastAccessedAt: failNow,
          failureReason: lastError ?? 'Remote download failed',
        ),
      );
      _log(
        '[PreloadDiag] Remote download failed track=$trackId reason=$lastError',
      );
    }
  }

  Future<NetworkPreloadPolicy> _resolveNetworkPolicy() async {
    try {
      final results = await _connectivityProvider();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return NetworkPreloadPolicy.offline;
      }
      if (results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet)) {
        return NetworkPreloadPolicy.wifiFull;
      }
      if (results.contains(ConnectivityResult.mobile)) {
        return config.allowMobileDataFullCaching
            ? NetworkPreloadPolicy.mobileFullAllowed
            : NetworkPreloadPolicy.mobileDataSaver;
      }
      return NetworkPreloadPolicy.wifiFull;
    } catch (_) {
      return NetworkPreloadPolicy.wifiFull;
    }
  }

  void _markEntryCancelledIfInProgress(String trackId, String sourceVersion) {
    final existing = cacheManager.getEntry(trackId);
    if (existing != null &&
        existing.sourceVersion == sourceVersion &&
        (existing.state == PreloadState.resolving ||
            existing.state == PreloadState.downloading)) {
      cacheManager.putEntry(
        existing.copyWith(
          state: PreloadState.cancelled,
          updatedAt: _nowProvider(),
          failureReason: 'Cancelled',
        ),
      );
    }
  }

  PreloadSourceKind _classifySource(MusicItem track) {
    if (track.isYoutube) return PreloadSourceKind.youtube;
    if (_isHttpUrl(track.filePath)) return PreloadSourceKind.remoteHttp;
    return PreloadSourceKind.local;
  }

  String _computeSourceVersion(MusicItem track) {
    final kind = _classifySource(track);
    return '${kind.name}|${track.filePath}|${track.isYoutube}';
  }

  static bool _isHttpUrl(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  static DateTime? _extractYouTubeExpiry(String url) {
    final uri = Uri.tryParse(url);
    final expireStr = uri?.queryParameters['expire'];
    if (expireStr == null) return null;
    final seconds = int.tryParse(expireStr);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static String _sanitizeError(String raw) {
    // Strip URLs, query parameters, tokens, and auth/cookie values.
    return raw
        .replaceAll(RegExp(r'https?://[^\s]+'), '[redacted-url]')
        .replaceAll(
          RegExp(r'(sig|lsig|token|signature|expire|key)=[^&\s]+',
              caseSensitive: false),
          '[redacted-param]',
        )
        .replaceAll(
          RegExp(r'(authorization|cookie)\s*:\s*[^\r\n]+',
              caseSensitive: false),
          '[redacted-header]',
        );
  }

  void _log(String message) {
    _logger(_sanitizeError(message));
  }
}
