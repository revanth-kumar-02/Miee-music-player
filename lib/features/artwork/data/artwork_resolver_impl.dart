import 'dart:async';
import 'package:flutter/foundation.dart';

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
/// deduplicates in-flight requests, and gracefully handles network timeouts.
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
    this.timeout = const Duration(seconds: 6),
  })  : cache = cache ?? ArtworkCache(),
        localProvider = localProvider ?? LocalArtworkProvider(),
        musicBrainzProvider = musicBrainzProvider ?? MusicBrainzProvider(),
        coverArtArchiveProvider = coverArtArchiveProvider ?? CoverArtArchiveProvider(),
        deezerProvider = deezerProvider ?? DeezerArtworkProvider(),
        fanartProvider = fanartProvider ?? const FanartArtworkProvider(),
        itunesProvider = itunesProvider ?? const ItunesArtworkProvider(),
        youtubeFallbackProvider = youtubeFallbackProvider ?? const YouTubeFallbackProvider();

  /// Evicts cached metadata for [query] so the next [resolve] fetches fresh artwork.
  Future<void> invalidate(ArtworkQuery query) {
    return cache.evict(query.cacheKey);
  }

  /// Resolves artwork for the given [query] following the deterministic priority chain.
  Future<ResolvedArtwork> resolve(ArtworkQuery query, {bool forceRefresh = false}) {
    final key = query.cacheKey;
    final inflightKey = forceRefresh ? '${key}_refresh' : key;

    // In-flight deduplication: return the active future if already running
    if (_inFlight.containsKey(inflightKey)) {
      return _inFlight[inflightKey]!;
    }

    final future = _resolveInternal(query, forceRefresh: forceRefresh).whenComplete(() {
      _inFlight.remove(inflightKey);
    });

    _inFlight[inflightKey] = future;
    return future;
  }

  Future<ResolvedArtwork> _cacheAndReturn(String key, ResolvedArtwork artwork) async {
    ResolvedArtwork result = artwork;
    if (cacheImagesLocally &&
        !artwork.isLocal &&
        !artwork.isNeutralFallback &&
        artwork.imageUrl.startsWith('http') &&
        !ArtworkCache.hasValidLocalFile(artwork.localCachedPath)) {
      final localPath = await cache.cacheImageFromUrl(key, artwork.imageUrl);
      if (localPath != null) {
        result = artwork.copyWith(localCachedPath: localPath);
      }
    }
    await cache.put(key, result);
    return result;
  }

  ArtworkQuery _cleanYoutubeQueryForCatalog(ArtworkQuery query) {
    if (!query.isYoutube) return query;
    final cleaned = YouTubeMetadataCleaner.clean(
      rawTitle: query.title,
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

    if (forceRefresh) {
      await cache.evict(key);
    }

    // 1. Check local embedded artwork first (Highest Priority - zero latency disk check)
    if (!query.isYoutube) {
      try {
        final localArtwork = await localProvider.resolve(query);
        if (localArtwork != null) {
          await cache.put(key, localArtwork);
          return localArtwork;
        }
      } catch (e) {
        debugPrint('[ArtworkResolver] Local provider error: $e');
      }
    }

    // 2. Check persistent & memory cache (unless forceRefresh)
    if (!forceRefresh) {
      final cached = cache.get(key);
      if (cached != null) {
        // If we have a valid local cached image file, reuse it immediately
        if (ArtworkCache.hasValidLocalFile(cached.localCachedPath)) {
          return cached;
        }
        // If disk caching is enabled and remote image isn't cached on disk yet,
        // try caching it without blocking if it's already a valid entry.
        if (cacheImagesLocally && !cached.isLocal && cached.imageUrl.startsWith('http')) {
          final localPath = await cache.cacheImageFromUrl(key, cached.imageUrl);
          if (localPath != null) {
            final updated = cached.copyWith(localCachedPath: localPath);
            await cache.put(key, updated);
            return updated;
          }
          // Cached remote URL failed to download/validate (e.g. expired URL):
          // fall through to re-resolve fresh artwork!
        } else {
          return cached;
        }
      }
    }

    // 3. YouTube Music resolution path:
    // Try iTunes -> Deezer -> authentic YouTube thumbnail fallback.
    if (query.isYoutube) {
      // Check if candidate already carries verified studio album artwork
      if (query.fallbackThumbnailUrl != null &&
          query.fallbackThumbnailUrl!.isNotEmpty &&
          (query.fallbackThumbnailUrl!.contains('mzstatic.com') ||
              query.fallbackThumbnailUrl!.contains('dzcdn.net'))) {
        final studioArtwork = ResolvedArtwork(
          imageUrl: query.fallbackThumbnailUrl!,
          source: query.fallbackThumbnailUrl!.contains('dzcdn.net')
              ? ArtworkSource.deezer
              : ArtworkSource.itunes,
          confidence: 0.95,
          attribution: 'Studio Album Cover',
          resolvedAt: DateTime.now(),
        );
        if (!cacheImagesLocally) {
          await cache.put(key, studioArtwork);
          return studioArtwork;
        }
        final localPath = await cache.cacheImageFromUrl(key, studioArtwork.imageUrl);
        if (localPath != null) {
          final withLocal = studioArtwork.copyWith(localCachedPath: localPath);
          await cache.put(key, withLocal);
          return withLocal;
        }
        // If pre-attached studio URL expired/failed, continue to re-resolve below.
      }

      // Snappy iTunes catalog check (max 2000ms) to upgrade to studio 600x600 artwork
      if (itunesProvider.isEnabled) {
        try {
          final itunesArtwork = await itunesProvider
              .resolve(query, forceRefresh: forceRefresh)
              .timeout(
            const Duration(milliseconds: 2000),
            onTimeout: () => null,
          );
          if (itunesArtwork != null) {
            return await _cacheAndReturn(key, itunesArtwork);
          }
        } catch (_) {}
      }

      // Secondary catalog check: Deezer (max 2000ms) with cleaned YouTube metadata
      if (deezerProvider.isEnabled) {
        try {
          final catalogQuery = _cleanYoutubeQueryForCatalog(query);
          final deezerArtwork = await deezerProvider.resolve(catalogQuery).timeout(
            const Duration(milliseconds: 2000),
            onTimeout: () => null,
          );
          if (deezerArtwork != null) {
            return await _cacheAndReturn(key, deezerArtwork);
          }
        } catch (_) {}
      }

      // Fall back to authentic YouTube thumbnail
      try {
        final ytFallback = await youtubeFallbackProvider.resolve(query);
        if (ytFallback != null) {
          return await _cacheAndReturn(key, ytFallback);
        }
      } catch (_) {}

      return ResolvedArtwork.neutralFallback();
    }

    // Online resolution cascade wrapped in global timeout for local/standard tracks
    try {
      return await _executeOnlineCascade(query, forceRefresh: forceRefresh).timeout(
        timeout,
        onTimeout: () {
          debugPrint('[ArtworkResolver] Resolution timed out for "${query.title}" — falling back');
          return _fallbackOrNeutral(query);
        },
      );
    } catch (e) {
      debugPrint('[ArtworkResolver] Online resolution failed: $e — falling back');
      return _fallbackOrNeutral(query);
    }
  }

  Future<ResolvedArtwork> _executeOnlineCascade(
    ArtworkQuery query, {
    bool forceRefresh = false,
  }) async {
    final key = query.cacheKey;

    // 1. Primary Online Priority: Apple iTunes Search API (Studio 600x600bb from Apple CDN)
    if (itunesProvider.isEnabled) {
      try {
        final itunesArtwork = await itunesProvider.resolve(
          query,
          forceRefresh: forceRefresh,
        );
        if (itunesArtwork != null) {
          return await _cacheAndReturn(key, itunesArtwork);
        }
      } catch (e) {
        debugPrint('[ArtworkResolver] iTunes lookup failed: $e');
      }
    }

    // 2. Secondary Priority: Deezer track/album search (Fast, global catalog, high-res 1000x1000)
    if (deezerProvider.isEnabled) {
      try {
        final deezerArtwork = await deezerProvider.resolve(query);
        if (deezerArtwork != null) {
          return await _cacheAndReturn(key, deezerArtwork);
        }
      } catch (e) {
        debugPrint('[ArtworkResolver] Deezer lookup failed: $e');
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
        if (caaArtwork != null) {
          return await _cacheAndReturn(key, caaArtwork);
        }
      }
    } catch (e) {
      debugPrint('[ArtworkResolver] MusicBrainz/CAA lookup failed: $e');
    }

    // 4. Priority: Fanart.tv (if enabled)
    if (fanartProvider.isEnabled) {
      try {
        final fanartArtwork = await fanartProvider.resolve(query);
        if (fanartArtwork != null) {
          return await _cacheAndReturn(key, fanartArtwork);
        }
      } catch (_) {}
    }

    // Fall back to YouTube thumbnail or neutral fallback
    return _fallbackOrNeutral(query);
  }

  Future<ResolvedArtwork> _fallbackOrNeutral(ArtworkQuery query) async {
    final key = query.cacheKey;

    // 7. Last-resort fallback: original YouTube thumbnail
    try {
      final ytFallback = await youtubeFallbackProvider.resolve(query);
      if (ytFallback != null) {
        return await _cacheAndReturn(key, ytFallback);
      }
    } catch (_) {}

    // 8. Deterministic neutral fallback
    // Note: Do NOT write neutral fallback into persistent Hive storage.
    // This ensures transient network hiccups or empty early queries do not
    // permanently suppress artwork resolution for this track in future sessions.
    return ResolvedArtwork.neutralFallback();
  }
}
