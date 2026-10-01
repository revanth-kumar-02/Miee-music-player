import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Cache entry
// ─────────────────────────────────────────────────────────────────────────────

class _CachedStream {
  final String url;
  final DateTime expiresAt;
  const _CachedStream({required this.url, required this.expiresAt});
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// ─────────────────────────────────────────────────────────────────────────────
// Resolution result (carries source tag for logging)
// ─────────────────────────────────────────────────────────────────────────────

class _ResolvedStream {
  final String url;
  final String source;
  const _ResolvedStream({required this.url, required this.source});
}

// ─────────────────────────────────────────────────────────────────────────────
// YouTubeAudioService
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves direct audio-only stream URLs for YouTube video IDs.
///
/// Resolution waterfall (most stable → least stable):
///   1. Piped API   — server-side cipher/signature, no Google CDN 403s
///   2. Invidious   — independent instance network, same benefit
///   3. youtube_explode_dart — last resort (direct YT CDN, 403-prone)
///
/// Guarantees:
///   • Audio-only streams preferred (no video+audio mux).
///   • Expired URLs are evicted automatically on access.
///   • Concurrent calls for the same video ID are deduplicated.
///   • Cache bounded to [_maxCacheSize] entries.
class YouTubeAudioService {
  static final YouTubeAudioService _instance = YouTubeAudioService._internal();
  factory YouTubeAudioService() => _instance;
  YouTubeAudioService._internal();

  // ── Piped public instances (tried in order, skipped on failure) ────────────
  static const List<String> _pipedInstances = [
    'https://pipedapi.kavin.rocks',
    'https://pipedapi.tokhmi.xyz',
    'https://pipedapi.moomoo.me',
    'https://piped-api.garudalinux.org',
    'https://api.piped.yt',
  ];

  // ── Invidious public instances ─────────────────────────────────────────────
  static const List<String> _invidiousInstances = [
    'https://yewtu.be',
    'https://invidious.kavin.rocks',
    'https://inv.riverside.rocks',
    'https://invidious.nerdvpn.de',
    'https://invidious.snopyta.org',
  ];

  static const int _maxCacheSize = 60;
  static const Duration _httpTimeout = Duration(seconds: 12);

  // ── Shared Dio client ──────────────────────────────────────────────────────
  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: _httpTimeout,
      receiveTimeout: _httpTimeout,
      sendTimeout: _httpTimeout,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        'Accept': 'application/json',
        'Accept-Language': 'en-US,en;q=0.9',
      },
      validateStatus: (_) => true, // handle status manually
    ),
  );

  // ── Cache & in-flight deduplication ───────────────────────────────────────
  final Map<String, _CachedStream> _urlCache = {};
  final Map<String, Future<String?>> _inFlight = {};

  // ── youtube_explode_dart (last resort) ────────────────────────────────────
  final YoutubeExplode _yt = YoutubeExplode();

  // ─────────────────────────────────────────────────────────────────────────
  // Public API
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns an audio-only stream URL for [videoIdOrUrl].
  ///
  /// Serves from cache if valid; deduplicates concurrent calls for the same ID.
  /// Pass [forceRefresh]=true to bypass cache (e.g. after a playback error).
  Future<String?> getAudioStreamUrl(
    String videoIdOrUrl, {
    bool forceRefresh = false,
  }) {
    final videoId = _extractVideoId(videoIdOrUrl);
    if (videoId == null || videoId.isEmpty) {
      debugPrint('[YouTubeResolver] Invalid video ID: "$videoIdOrUrl"');
      return Future.value(null);
    }

    // Serve valid cache entry unless caller forces refresh
    if (!forceRefresh && _urlCache.containsKey(videoId)) {
      final cached = _urlCache[videoId]!;
      if (!cached.isExpired) {
        debugPrint('[StreamCache] HIT for $videoId');
        return Future.value(cached.url);
      }
      debugPrint('[StreamCache] EXPIRED for $videoId, evicting');
      _urlCache.remove(videoId);
    }

    // Deduplicate concurrent resolution calls
    if (_inFlight.containsKey(videoId)) {
      debugPrint('[YouTubeResolver] In-flight dedup for $videoId');
      return _inFlight[videoId]!;
    }

    final future = _resolveWithFallback(videoId).whenComplete(() {
      _inFlight.remove(videoId);
    });
    _inFlight[videoId] = future;
    return future;
  }

  /// Returns true if [url] is non-empty, parseable, and not past its `expire` param.
  bool isUrlValid(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || !uri.hasAuthority) return false;
      final exp = uri.queryParameters['expire'];
      if (exp != null) {
        final secs = int.tryParse(exp);
        if (secs != null) {
          return DateTime.now()
              .isBefore(DateTime.fromMillisecondsSinceEpoch(secs * 1000));
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Evicts [videoIdOrUrl] from the URL cache.
  /// Call this when a playback error suggests the cached URL is stale.
  void invalidateCache(String videoIdOrUrl) {
    final videoId = _extractVideoId(videoIdOrUrl);
    if (videoId != null && _urlCache.containsKey(videoId)) {
      _urlCache.remove(videoId);
      debugPrint('[StreamCache] INVALIDATED $videoId');
    }
  }

  void clearCache() {
    _urlCache.clear();
    debugPrint('[StreamCache] Cache cleared');
  }

  void dispose() {
    _yt.close();
    _dio.close(force: false);
    debugPrint('[YouTubeResolver] Disposed');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Resolution waterfall
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> _resolveWithFallback(String videoId) async {
    debugPrint('[YouTubeResolver] START resolving $videoId');

    // ── Layer 1: Piped API ─────────────────────────────────────────────────
    for (final instance in _pipedInstances) {
      try {
        final result = await _resolveViaPiped(videoId, instance);
        if (result != null) {
          debugPrint('[YouTubeResolver] ✓ Piped ($instance) for $videoId');
          _cacheUrl(videoId, result.url, ttlMinutes: 80);
          return result.url;
        }
      } catch (e) {
        debugPrint('[YouTubeResolver] ✗ Piped $instance: $e');
      }
    }
    debugPrint('[YouTubeResolver] All Piped instances failed for $videoId');

    // ── Layer 2: Invidious API ─────────────────────────────────────────────
    for (final instance in _invidiousInstances) {
      try {
        final result = await _resolveViaInvidious(videoId, instance);
        if (result != null) {
          debugPrint('[YouTubeResolver] ✓ Invidious ($instance) for $videoId');
          _cacheUrl(videoId, result.url, ttlMinutes: 80);
          return result.url;
        }
      } catch (e) {
        debugPrint('[YouTubeResolver] ✗ Invidious $instance: $e');
      }
    }
    debugPrint('[YouTubeResolver] All Invidious instances failed for $videoId');

    // ── Layer 3: youtube_explode_dart ─────────────────────────────────────
    try {
      debugPrint('[YouTubeResolver] Trying youtube_explode_dart for $videoId');
      final result = await _resolveViaExplode(videoId);
      if (result != null) {
        debugPrint('[YouTubeResolver] ✓ youtube_explode_dart for $videoId');
        _cacheUrl(videoId, result.url, ttlMinutes: 50);
        return result.url;
      }
    } catch (e) {
      debugPrint('[YouTubeResolver] ✗ youtube_explode_dart: $e');
    }

    debugPrint('[YouTubeResolver] ALL layers exhausted for $videoId');
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layer 1 — Piped API
  // GET {instance}/streams/{videoId}
  // ─────────────────────────────────────────────────────────────────────────

  Future<_ResolvedStream?> _resolveViaPiped(
      String videoId, String instance) async {
    final url = '$instance/streams/$videoId';
    debugPrint('[Piped] GET $url');

    final resp = await _dio.get<Map<String, dynamic>>(url);

    if (resp.statusCode != 200 || resp.data == null) {
      debugPrint('[Piped] HTTP ${resp.statusCode} from $instance');
      return null;
    }

    final data = resp.data!;
    if (data.containsKey('message') || data.containsKey('error')) {
      debugPrint('[Piped] Error body: ${data['message'] ?? data['error']}');
      return null;
    }

    final audioStreams = (data['audioStreams'] as List<dynamic>?) ?? [];
    if (audioStreams.isEmpty) return null;

    return _pickBestAudio(
      audioStreams,
      mimeKey: 'mimeType',
      urlKey: 'url',
      bitrateKey: 'bitrate',
      source: 'piped:$instance',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layer 2 — Invidious API
  // GET {instance}/api/v1/videos/{videoId}?fields=adaptiveFormats
  // ─────────────────────────────────────────────────────────────────────────

  Future<_ResolvedStream?> _resolveViaInvidious(
      String videoId, String instance) async {
    final url = '$instance/api/v1/videos/$videoId?fields=adaptiveFormats';
    debugPrint('[Invidious] GET $url');

    final resp = await _dio.get<Map<String, dynamic>>(url);

    if (resp.statusCode != 200 || resp.data == null) {
      debugPrint('[Invidious] HTTP ${resp.statusCode} from $instance');
      return null;
    }

    final data = resp.data!;
    if (data.containsKey('error')) {
      debugPrint('[Invidious] Error body: ${data['error']}');
      return null;
    }

    final formats = (data['adaptiveFormats'] as List<dynamic>?) ?? [];
    // Keep only audio-only adaptive formats
    final audioFormats =
        formats.where((f) => ((f as Map)['type'] as String? ?? '').startsWith('audio')).toList();

    if (audioFormats.isEmpty) return null;

    return _pickBestAudio(
      audioFormats,
      mimeKey: 'type',
      urlKey: 'url',
      bitrateKey: 'bitrate',
      source: 'invidious:$instance',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Layer 3 — youtube_explode_dart
  // ─────────────────────────────────────────────────────────────────────────

  Future<_ResolvedStream?> _resolveViaExplode(String videoId) async {
    final manifest =
        await _yt.videos.streamsClient.getManifest(videoId);
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) return null;

    final aacStreams = audioStreams.where((s) =>
        s.container.name.toLowerCase() == 'm4a' ||
        s.container.name.toLowerCase() == 'mp4' ||
        s.audioCodec.toLowerCase().contains('mp4a') ||
        s.audioCodec.toLowerCase().contains('aac'));

    final selected = aacStreams.isNotEmpty
        ? aacStreams.withHighestBitrate()
        : audioStreams.withHighestBitrate();

    final url = selected.url.toString();
    if (url.isEmpty) return null;

    debugPrint(
      '[yt-explode] Selected: ${selected.container.name} '
      '${selected.audioCodec} ${selected.bitrate}',
    );
    return _ResolvedStream(url: url, source: 'yt-explode');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Picks the best audio stream from a list, preferring AAC/MP4 over others.
  _ResolvedStream? _pickBestAudio(
    List<dynamic> streams, {
    required String mimeKey,
    required String urlKey,
    required String bitrateKey,
    required String source,
  }) {
    Map<String, dynamic>? aacBest;
    int aacBitrate = 0;
    Map<String, dynamic>? anyBest;
    int anyBitrate = 0;

    for (final s in streams) {
      final stream = s as Map<String, dynamic>;
      final mime = (stream[mimeKey] as String? ?? '').toLowerCase();
      final bitrate = (stream[bitrateKey] as num? ?? 0).toInt();
      final url = stream[urlKey] as String? ?? '';
      if (url.isEmpty) continue;

      final isAac = mime.contains('mp4') || mime.contains('aac') || mime.contains('m4a');
      if (isAac && bitrate > aacBitrate) {
        aacBitrate = bitrate;
        aacBest = stream;
      }
      if (bitrate > anyBitrate) {
        anyBitrate = bitrate;
        anyBest = stream;
      }
    }

    final chosen = aacBest ?? anyBest;
    if (chosen == null) return null;

    final url = chosen[urlKey] as String? ?? '';
    if (url.isEmpty || !isUrlValid(url)) return null;

    debugPrint(
      '[Resolver] Picked: mime=${chosen[mimeKey]} bitrate=${chosen[bitrateKey]} src=$source',
    );
    return _ResolvedStream(url: url, source: source);
  }

  void _cacheUrl(String videoId, String url, {int ttlMinutes = 80}) {
    // Evict oldest entry if at capacity
    if (_urlCache.length >= _maxCacheSize) {
      final oldest = _urlCache.keys.first;
      _urlCache.remove(oldest);
    }

    // Use URL's own `expire` param when present (more accurate)
    DateTime expiresAt;
    try {
      final uri = Uri.parse(url);
      final exp = uri.queryParameters['expire'];
      if (exp != null) {
        final secs = int.tryParse(exp);
        if (secs != null) {
          // 3-minute safety buffer before actual expiry
          expiresAt = DateTime.fromMillisecondsSinceEpoch(secs * 1000)
              .subtract(const Duration(minutes: 3));
          _urlCache[videoId] =
              _CachedStream(url: url, expiresAt: expiresAt);
          debugPrint(
              '[StreamCache] STORED $videoId (expires ${expiresAt.toIso8601String()})');
          return;
        }
      }
    } catch (_) {}

    expiresAt = DateTime.now().add(Duration(minutes: ttlMinutes));
    _urlCache[videoId] = _CachedStream(url: url, expiresAt: expiresAt);
    debugPrint(
        '[StreamCache] STORED $videoId (TTL ${ttlMinutes}min | cache=${_urlCache.length})');
  }

  String? _extractVideoId(String input) {
    var clean = input.trim();
    if (clean.startsWith('youtube_')) clean = clean.replaceFirst('youtube_', '');
    if (clean.contains('watch?v=')) {
      return Uri.tryParse(clean)?.queryParameters['v'] ?? clean;
    }
    if (clean.contains('youtu.be/')) {
      final segs = Uri.tryParse(clean)?.pathSegments ?? [];
      return segs.isNotEmpty ? segs.last : clean;
    }
    return clean.isNotEmpty ? clean : null;
  }
}
