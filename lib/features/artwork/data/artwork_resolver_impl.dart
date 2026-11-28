import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../shared/utils/display_title_normalizer.dart';
import '../../youtube/domain/youtube_metadata_cleaner.dart';
import '../domain/artwork_query.dart';
import '../domain/artwork_source.dart';
import '../domain/resolved_artwork.dart';
import 'artwork_cache.dart';
import 'providers/cover_art_archive_provider.dart';
import 'providers/deezer_artwork_provider.dart';
import 'providers/fanart_artwork_provider.dart';
import 'providers/itunes_artwork_provider.dart';
import 'providers/local_artwork_provider.dart';
import 'providers/musicbrainz_provider.dart';
import 'providers/youtube_fallback_provider.dart';

/// Central coordinator for the Artwork Resolution System.
///
/// Executes the deterministic provider hierarchy, manages multi-tiered caching,
/// deduplicates in-flight requests, and strictly enforces artwork source priority:
/// 1. Verified high-confidence external album artwork (Apple iTunes, Deezer, CoverArtArchive).
/// 2. Valid embedded local album artwork.
/// 3. YouTube video thumbnail as last-resort fallback.
/// 4. Nordic Cobalt neutral fallback.
class ArtworkResolver {
  final ArtworkCache cache;
  final LocalArtworkProvider localProvider;
  final MusicBrainzProvider musicBrainzProvider;
  final CoverArtArchiveProvider coverArtArchiveProvider;
  final DeezerArtworkProvider deezerProvider;
  final FanartArtworkProvider fanartProvider;
  final ItunesArtworkProvider itunesProvider;
  final YouTubeFallbackProvider youtubeFallbackProvider;

  /// Whether resolved remote artwork should also be downloaded, validated,
  /// and cached on local disk.
  final bool cacheImagesLocally;

  /// Global timeout for the entire online resolution cascade per query.
  final Duration timeout;

  /// In-flight deduplication map keyed by normalized [ArtworkQuery.cacheKey].
  final Map<String, Future<ResolvedArtwork>> _inFlight = {};

  ArtworkResolver({
    ArtworkCache? cache,
    LocalArtworkProvider? localProvider,
    MusicBrainzProvider? musicBrainzProvider,
    CoverArtArchiveProvider? coverArtArchiveProvider,
    DeezerArtworkProvider? deezerProvider,
    FanartArtworkProvider? fanartProvider,
    ItunesArtworkProvider? itunesProvider,
    YouTubeFallbackProvider? youtubeFallbackProvider,
    this.cacheImagesLocally = false,
    this.timeout = const Duration(seconds: 8),
  })  : cache = cache ?? ArtworkCache(),
        localProvider = localProvider ?? LocalArtworkProvider(),
        musicBrainzProvider = musicBrainzProvider ?? MusicBrainzProvider(),
        coverArtArchiveProvider =
            coverArtArchiveProvider ?? CoverArtArchiveProvider(),
        deezerProvider = deezerProvider ?? DeezerArtworkProvider(),
        fanartProvider = fanartProvider ?? const FanartArtworkProvider(),
        itunesProvider = itunesProvider ?? const ItunesArtworkProvider(),
        youtubeFallbackProvider =
            youtubeFallbackProvider ?? const YouTubeFallbackProvider();

  /// Evicts cached metadata for [query] so the next [resolve] fetches fresh artwork.
  Future<void> invalidate(ArtworkQuery query) async {
    await cache.evict(query.cacheKey);
    await cache.evict(query.canonicalKey);
  }

  /// Resolves artwork for the given [query] following the deterministic priority chain.
  Future<ResolvedArtwork> resolve(ArtworkQuery query,
      {bool forceRefresh = false}) {
    final key = query.cacheKey;
    final inflightKey = forceRefresh ? '${key}_refresh' : key;

    // In-flight deduplication: return the active future if already running
    if (_inFlight.containsKey(inflightKey)) {
      return _inFlight[inflightKey]!;
    }

    final future =
        _resolveInternal(query, forceRefresh: forceRefresh).whenComplete(() {
      _inFlight.remove(inflightKey);
    });

    _inFlight[inflightKey] = future;
    return future;
  }

  Future<ResolvedArtwork> _cacheAndReturn(String key, ResolvedArtwork artwork,
      {String? canonicalKey}) async {
    if (artwork.source == ArtworkSource.youtube) {
      return ResolvedArtwork.neutralFallback();
    }
    ResolvedArtwork result = artwork;
    if (cacheImagesLocally &&
        !artwork.isLocal &&
        !artwork.isNeutralFallback &&
        artwork.imageUrl.startsWith('http') &&
        !ArtworkCache.hasValidLocalFile(artwork.localCachedPath)) {
      final localPath = await cache.cacheImageFromUrl(key, artwork.imageUrl);
      if (localPath != null) {
        result = artwork.copyWith(localCachedPath: localPath);
        debugPrint(
            '[ArtworkDiag] Cached remote image locally on disk: $localPath');
      }
    }
    await cache.put(key, result);
    if (canonicalKey != null &&
        canonicalKey.isNotEmpty &&
        canonicalKey != key) {
      if (result.source != ArtworkSource.youtube && !result.isNeutralFallback) {
        await cache.put(canonicalKey, result);
      }
    }
    return result;
  }

  ArtworkQuery _cleanYoutubeQueryForCatalog(ArtworkQuery query) {
    final cleaned = YouTubeMetadataCleaner.clean(
      rawTitle: DisplayTitleNormalizer.normalize(query.title),
      rawChannel: query.artist,
    );
    if (cleaned.title == query.title && cleaned.artist == query.artist) {
      return query;
    }
    return ArtworkQuery(
      id: query.id,
      title: cleaned.title,
      artist: cleaned.artist,
      album: query.album,
      albumArtworkUrl: query.albumArtworkUrl,
      isrc: query.isrc,
      durationMs: query.durationMs,
      localFilePath: query.localFilePath,
      localArtworkPath: query.localArtworkPath,
      fallbackThumbnailUrl: query.fallbackThumbnailUrl,
      source: query.source,
    );
  }

  Future<ResolvedArtwork> _resolveInternal(
    ArtworkQuery query, {
    bool forceRefresh = false,
  }) async {
    final key = query.cacheKey;
    final canonKey = query.canonicalKey;

    debugPrint(
        '[ArtworkDiag] Track: ${query.id} "${query.title}" by "${query.artist}" | isYoutube: ${query.isYoutube}');

    if (forceRefresh) {
      await cache.evict(key);
      await cache.evict(canonKey);
    }

    // 0. Pre-attached verified external album artwork (e.g. from iTunes catalogue)
    if (query.albumArtworkUrl != null &&
        query.albumArtworkUrl!.isNotEmpty &&
        query.albumArtworkUrl!.startsWith('http')) {
      if (!forceRefresh) {
        final existing = cache.get(key);
        if (existing != null &&
            existing.imageUrl == query.albumArtworkUrl &&
            (!cacheImagesLocally ||
                ArtworkCache.hasValidLocalFile(existing.localCachedPath))) {
          return existing;
        }
      }
      final src = query.albumArtworkUrl!.contains('dzcdn.net')
          ? ArtworkSource.deezer
          : ArtworkSource.itunes;
      final preResolved = ResolvedArtwork(
        imageUrl: query.albumArtworkUrl!,
        source: src,
        confidence: 0.95,
        attribution: src == ArtworkSource.itunes ? 'Apple iTunes' : 'Deezer',
        resolvedAt: DateTime.now(),
      );
      debugPrint(
          '[ArtworkDiag] Selected pre-attached external album artwork: ${preResolved.imageUrl} | Source: ${src.name} | Score: 0.95');
      return await _cacheAndReturn(key, preResolved, canonicalKey: canonKey);
    }

    // 1. Check local embedded artwork first (Highest Priority for offline tracks)
    if (!query.isYoutube) {
      try {
        final localArtwork = await localProvider.resolve(query);
        if (localArtwork != null) {
          debugPrint(
              '[ArtworkDiag] Resolved embedded local artwork for "${query.title}"');
          await cache.put(key, localArtwork);
          return localArtwork;
        }
      } catch (e) {
        debugPrint('[ArtworkDiag] Local provider error: $e');
      }
    }

    // 2. Check canonical cache for authoritative external album artwork
    if (!forceRefresh) {
      final canonCached = cache.get(canonKey);
      if (canonCached != null &&
          canonCached.source != ArtworkSource.youtube &&
          !canonCached.isNeutralFallback &&
          canonCached.confidence >= 0.80) {
        debugPrint(
            '[ArtworkDiag] Canonical album cache HIT for "${query.title}": ${canonCached.imageUrl} (${canonCached.source.name})');
        await cache.put(key, canonCached);
        return canonCached;
      }

      final cached = cache.get(key);
      if (cached != null) {
        // High-confidence external artwork or local file
        if (cached.source != ArtworkSource.youtube &&
            !cached.isNeutralFallback &&
            cached.confidence >= 0.80) {
          if (cacheImagesLocally &&
              !cached.isLocal &&
              cached.imageUrl.startsWith('http') &&
              !ArtworkCache.hasValidLocalFile(cached.localCachedPath)) {
            final localPath =
                await cache.cacheImageFromUrl(key, cached.imageUrl);
            if (localPath != null) {
              final updated = cached.copyWith(localCachedPath: localPath);
              await cache.put(key, updated);
              return updated;
            } else {
              // Remote URL expired/invalid, evict and proceed to fresh resolution
              debugPrint(
                  '[ArtworkDiag] Cached remote URL invalid/expired, evicting ($key)');
              await cache.evict(key);
              await cache.evict(canonKey);
            }
          } else {
            debugPrint(
                '[ArtworkDiag] Cache HIT (${cached.source.name}) for "${query.title}": ${cached.imageUrl}');
            return cached;
          }
        }
      } else {
        debugPrint('[ArtworkDiag] Cache MISS for "${query.title}" ($key)');
      }
    }

    // 3. YouTube Music resolution path:
    // Priority 1: Apple iTunes Search API (Studio 600x600bb)
    // Priority 2: Deezer catalog
    // Priority 3: MusicBrainz / Cover Art Archive
    // Priority 4: Nordic Cobalt Neutral Fallback (Never YouTube thumbnails)
    if (query.isYoutube) {
      final catalogQuery = _cleanYoutubeQueryForCatalog(query);

      // Snappy iTunes catalog check (max 3500ms) to upgrade to studio 600x600 artwork
      if (itunesProvider.isEnabled) {
        try {
          debugPrint(
              '[ArtworkDiag] Provider queried: Apple iTunes for "${catalogQuery.title}" by "${catalogQuery.artist}"');
          final itunesArtwork = await itunesProvider
              .resolve(catalogQuery, forceRefresh: forceRefresh)
              .timeout(
            const Duration(milliseconds: 3500),
            onTimeout: () {
              debugPrint(
                  '[ArtworkDiag] iTunes provider timed out (>3500ms) for "${catalogQuery.title}"');
              return null;
            },
          );
          if (itunesArtwork != null && itunesArtwork.confidence >= 0.80) {
            debugPrint(
                '[ArtworkDiag] iTunes response: ${itunesArtwork.imageUrl} | Score: ${itunesArtwork.confidence}');
            debugPrint(
                '[ArtworkDiag] Selected artwork source: Apple iTunes | URL: ${itunesArtwork.imageUrl}');
            return await _cacheAndReturn(key, itunesArtwork,
                canonicalKey: canonKey);
          } else if (itunesArtwork != null) {
            debugPrint(
                '[ArtworkDiag] iTunes match rejected: low confidence (${itunesArtwork.confidence} < 0.80)');
          }
        } catch (e) {
          debugPrint('[ArtworkDiag] iTunes provider exception: $e');
        }
      }

      // Secondary catalog check: Deezer (max 3000ms) with cleaned YouTube metadata
      if (deezerProvider.isEnabled) {
        try {
          debugPrint(
              '[ArtworkDiag] Provider queried: Deezer for "${catalogQuery.title}" by "${catalogQuery.artist}"');
          final deezerArtwork =
              await deezerProvider.resolve(catalogQuery).timeout(
            const Duration(milliseconds: 3000),
            onTimeout: () {
              debugPrint(
                  '[ArtworkDiag] Deezer provider timed out (>3000ms) for "${catalogQuery.title}"');
              return null;
            },
          );
          if (deezerArtwork != null && deezerArtwork.confidence >= 0.80) {
            debugPrint(
                '[ArtworkDiag] Deezer response: ${deezerArtwork.imageUrl} | Score: ${deezerArtwork.confidence}');
            debugPrint(
                '[ArtworkDiag] Selected artwork source: Deezer | URL: ${deezerArtwork.imageUrl}');
            return await _cacheAndReturn(key, deezerArtwork,
                canonicalKey: canonKey);
          }
        } catch (e) {
          debugPrint('[ArtworkDiag] Deezer provider exception: $e');
        }
      }

      // Tertiary catalog check: MusicBrainz / Cover Art Archive
      try {
        final mbMatch =
            await musicBrainzProvider.findReleaseMatch(catalogQuery);
        if (mbMatch != null && mbMatch.releaseMbid.isNotEmpty) {
          final caaArtwork = await coverArtArchiveProvider.fetchCoverArt(
            mbid: mbMatch.releaseMbid,
            confidence: mbMatch.confidence,
          );
          if (caaArtwork != null && caaArtwork.confidence >= 0.80) {
            debugPrint(
                '[ArtworkDiag] Selected artwork source: CoverArtArchive | URL: ${caaArtwork.imageUrl}');
            return await _cacheAndReturn(key, caaArtwork,
                canonicalKey: canonKey);
          }
        }
      } catch (e) {
        debugPrint(
            '[ArtworkDiag] MusicBrainz/CAA lookup failed for YouTube track: $e');
      }

      debugPrint(
          '[ArtworkDiag] External providers unconfident or unavailable for "${query.title}". Returning neutral fallback (never YouTube thumbnail).');
      return ResolvedArtwork.neutralFallback();
    }

    // Online resolution cascade wrapped in global timeout for local/standard tracks
    try {
      return await _executeOnlineCascade(query, forceRefresh: forceRefresh)
          .timeout(
        timeout,
        onTimeout: () {
          debugPrint(
              '[ArtworkDiag] Online resolution timed out for "${query.title}" — falling back');
          return _fallbackOrNeutral(query);
        },
      );
    } catch (e) {
      debugPrint('[ArtworkDiag] Online resolution failed: $e — falling back');
      return _fallbackOrNeutral(query);
    }
  }

  Future<ResolvedArtwork> _executeOnlineCascade(
    ArtworkQuery query, {
    bool forceRefresh = false,
  }) async {
    final key = query.cacheKey;
    final canonKey = query.canonicalKey;

    // 1. Primary Online Priority: Apple iTunes Search API (Studio 600x600bb from Apple CDN)
    if (itunesProvider.isEnabled) {
      try {
        debugPrint(
            '[ArtworkDiag] Online cascade: querying iTunes for "${query.title}" by "${query.artist}"');
        final itunesArtwork = await itunesProvider.resolve(
          query,
          forceRefresh: forceRefresh,
        );
        if (itunesArtwork != null && itunesArtwork.confidence >= 0.80) {
          debugPrint(
              '[ArtworkDiag] Selected artwork source: Apple iTunes | URL: ${itunesArtwork.imageUrl} | Score: ${itunesArtwork.confidence}');
          return await _cacheAndReturn(key, itunesArtwork,
              canonicalKey: canonKey);
        }
      } catch (e) {
        debugPrint('[ArtworkDiag] iTunes lookup failed: $e');
      }
    }

    // 2. Secondary Priority: Deezer track/album search (Fast, global catalog, high-res 1000x1000)
    if (deezerProvider.isEnabled) {
      try {
        debugPrint(
            '[ArtworkDiag] Online cascade: querying Deezer for "${query.title}"');
        final deezerArtwork = await deezerProvider.resolve(query);
        if (deezerArtwork != null && deezerArtwork.confidence >= 0.80) {
          debugPrint(
              '[ArtworkDiag] Selected artwork source: Deezer | URL: ${deezerArtwork.imageUrl} | Score: ${deezerArtwork.confidence}');
          return await _cacheAndReturn(key, deezerArtwork,
              canonicalKey: canonKey);
        }
      } catch (e) {
        debugPrint('[ArtworkDiag] Deezer lookup failed: $e');
      }
    }

    // 3. Priority: MusicBrainz metadata match -> Cover Art Archive retrieval
    try {
      final mbMatch = await musicBrainzProvider.findReleaseMatch(query);
      if (mbMatch != null && mbMatch.releaseMbid.isNotEmpty) {
        final caaArtwork = await coverArtArchiveProvider.fetchCoverArt(
          mbid: mbMatch.releaseMbid,
          confidence: mbMatch.confidence,
        );
        if (caaArtwork != null && caaArtwork.confidence >= 0.80) {
          debugPrint(
              '[ArtworkDiag] Selected artwork source: CoverArtArchive | URL: ${caaArtwork.imageUrl}');
          return await _cacheAndReturn(key, caaArtwork, canonicalKey: canonKey);
        }
      }
    } catch (e) {
      debugPrint('[ArtworkDiag] MusicBrainz/CAA lookup failed: $e');
    }

    // 4. Priority: Fanart.tv (if enabled)
    if (fanartProvider.isEnabled) {
      try {
        final fanartArtwork = await fanartProvider.resolve(query);
        if (fanartArtwork != null) {
          return await _cacheAndReturn(key, fanartArtwork,
              canonicalKey: canonKey);
        }
      } catch (_) {}
    }

    // Fall back to YouTube thumbnail or neutral fallback
    return _fallbackOrNeutral(query);
  }

  Future<ResolvedArtwork> _fallbackOrNeutral(ArtworkQuery query) async {
    // Return deterministic neutral fallback (never YouTube thumbnails as album artwork)
    debugPrint(
        '[ArtworkDiag] Selected artwork source: NeutralFallback for "${query.title}"');
    return ResolvedArtwork.neutralFallback();
  }
}
