import 'package:dio/dio.dart';

/// Lifecycle states for a track in the rolling preload pipeline.
///
/// [fullyCached] and [streamReady] are intentionally distinct:
/// - [fullyCached]: Complete audio file is verified on disk (local original or
///   atomically committed cache file).
/// - [streamReady]: Stream metadata / URL is resolved and validated for immediate
///   streaming, without claiming complete offline file persistence.
enum PreloadState {
  resolving,
  downloading,
  streamReady,
  fullyCached,
  failed,
  expired,
  cancelled,
}

/// Source classification used to enforce caching & legal/technical policies.
enum PreloadSourceKind {
  local,
  youtube,
  remoteHttp,
}

/// Network condition policy controlling background preload aggressiveness.
enum NetworkPreloadPolicy {
  wifiFull,
  mobileDataSaver,
  mobileFullAllowed,
  offline,
}

/// Bounded configuration for [PreloadCacheManager] and [NextTrackPreloader].
class PreloadConfig {
  /// Maximum number of upcoming tracks in the rolling preload window.
  final int maxUpcomingTracks;

  /// Maximum total bytes retained in the preload cache directory (default: 150 MB).
  final int maxCacheBytes;

  /// Maximum number of cached audio files retained on disk (default: 12).
  final int maxCachedTracks;

  /// Minimum free disk space required before attempting full-file downloads (default: 250 MB).
  final int minRequiredFreeBytes;

  /// Whether full-file downloads are permitted on cellular/mobile data.
  final bool allowMobileDataFullCaching;

  /// Whether full-file downloading is permitted for YouTube streams.
  ///
  /// Defaults to `false` to respect YouTube restrictions and service terms;
  /// YouTube tracks remain streaming-only (`PreloadState.streamReady`).
  final bool allowYouTubeFullCaching;

  /// Maximum retry attempts per track preparation.
  final int maxRetries;

  /// Timeout for a single stream resolution or download attempt.
  final Duration operationTimeout;

  const PreloadConfig({
    this.maxUpcomingTracks = 2,
    this.maxCacheBytes = 150 * 1024 * 1024,
    this.maxCachedTracks = 12,
    this.minRequiredFreeBytes = 250 * 1024 * 1024,
    this.allowMobileDataFullCaching = false,
    this.allowYouTubeFullCaching = false,
    this.maxRetries = 2,
    this.operationTimeout = const Duration(seconds: 25),
  });
}

/// Metadata record for a prepared or in-progress preload entry.
class PreloadEntry {
  final String trackId;
  final String rawTrackId;
  final String sourceVersion;
  final PreloadSourceKind sourceKind;
  final PreloadState state;

  /// Local filesystem path when [state] == [PreloadState.fullyCached].
  final String? cachedFilePath;

  /// True when [cachedFilePath] points to a user's existing local music file.
  /// Local original files are NEVER duplicated or deleted by cache eviction.
  final bool isLocalOriginal;

  final int fileSizeBytes;

  /// Resolved stream URL when [state] == [PreloadState.streamReady].
  /// Never expose this in logs.
  final String? streamUrl;
  final String? userAgent;
  final String? clientName;

  final DateTime? expiresAt;
  final DateTime updatedAt;
  final DateTime lastAccessedAt;
  final String? failureReason;

  const PreloadEntry({
    required this.trackId,
    required this.rawTrackId,
    required this.sourceVersion,
    required this.sourceKind,
    required this.state,
    this.cachedFilePath,
    this.isLocalOriginal = false,
    this.fileSizeBytes = 0,
    this.streamUrl,
    this.userAgent,
    this.clientName,
    this.expiresAt,
    required this.updatedAt,
    required this.lastAccessedAt,
    this.failureReason,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get isUsable =>
      (state == PreloadState.fullyCached || state == PreloadState.streamReady) &&
      !isExpired;

  PreloadEntry copyWith({
    PreloadState? state,
    String? cachedFilePath,
    bool? isLocalOriginal,
    int? fileSizeBytes,
    String? streamUrl,
    String? userAgent,
    String? clientName,
    DateTime? expiresAt,
    DateTime? updatedAt,
    DateTime? lastAccessedAt,
    String? failureReason,
  }) {
    return PreloadEntry(
      trackId: trackId,
      rawTrackId: rawTrackId,
      sourceVersion: sourceVersion,
      sourceKind: sourceKind,
      state: state ?? this.state,
      cachedFilePath: cachedFilePath ?? this.cachedFilePath,
      isLocalOriginal: isLocalOriginal ?? this.isLocalOriginal,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      streamUrl: streamUrl ?? this.streamUrl,
      userAgent: userAgent ?? this.userAgent,
      clientName: clientName ?? this.clientName,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      failureReason: failureReason ?? this.failureReason,
    );
  }
}

/// Safe cancellation handle for in-flight preload operations.
class PreloadCancellationToken {
  final String trackId;
  final String sourceVersion;
  final CancelToken dioCancelToken = CancelToken();

  bool _isCancelled = false;
  String? _reason;
  final List<void Function()> _listeners = [];

  PreloadCancellationToken({
    required this.trackId,
    required this.sourceVersion,
  });

  bool get isCancelled => _isCancelled;
  String? get reason => _reason;

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void cancel(String reason) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;
    if (!dioCancelToken.isCancelled) {
      try {
        dioCancelToken.cancel(reason);
      } catch (_) {}
    }
    for (final listener in List<void Function()>.from(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
    _listeners.clear();
  }
}

/// Computes a stable, normalized track identifier safe for cache keys & filenames.
String normalizePreloadTrackId(String id) {
  var clean = id.trim();
  if (clean.startsWith('youtube_')) {
    clean = clean.substring('youtube_'.length);
  }
  return clean;
}

/// Safe filename stem derived from a normalized track ID.
String safeCacheFileStem(String trackId) {
  final normalized = trackId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return normalized.isEmpty ? 'track' : normalized;
}
