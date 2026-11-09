import 'dart:async';
import 'package:flutter/foundation.dart';

import '../domain/artwork_query.dart';
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
    this.timeout = const Duration(seconds: 6),
  })  : cache = cache ?? ArtworkCache(),
        localProvider = localProvider ?? LocalArtworkProvider(),
        musicBrainzProvider = musicBrainzProvider ?? MusicBrainzProvider(),
        coverArtArchiveProvider = coverArtArchiveProvider ?? CoverArtArchiveProvider(),
        deezerProvider = deezerProvider ?? DeezerArtworkProvider(),
        fanartProvider = fanartProvider ?? const FanartArtworkProvider(),
        itunesProvider = itunesProvider ?? ItunesArtworkProvider(),
        youtubeFallbackProvider = youtubeFallbackProvider ?? YouTubeFallbackProvider();

  /// Resolves artwork for the given [query] following the deterministic priority chain.
  Future<ResolvedArtwork> resolve(ArtworkQuery query) {
    final key = query.cacheKey;

    // In-flight deduplication: return the active future if already running
    if (_inFlight.containsKey(key)) {
      return _inFlight[key]!;
    }

    final future = _resolveInternal(query).whenComplete(() {
      _inFlight.remove(key);
    });

    _inFlight[key] = future;
    return future;
  }

  Future<ResolvedArtwork> _resolveInternal(ArtworkQuery query) async {
    final key = query.cacheKey;

    // 1. Check local embedded artwork first (Highest Priority - zero latency disk check)
    try {
      final localArtwork = await localProvider.resolve(query);
      if (localArtwork != null) {
        await cache.put(key, localArtwork);
        return localArtwork;
      }
    } catch (e) {
      debugPrint('[ArtworkResolver] Local provider error: $e');
    }

    // 2. Check persistent & memory cache
    final cached = cache.get(key);
    if (cached != null) {
      return cached;
    }

    // Online resolution cascade wrapped in global timeout
    try {
      return await _executeOnlineCascade(query).timeout(
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

  Future<ResolvedArtwork> _executeOnlineCascade(ArtworkQuery query) async {
    final key = query.cacheKey;

    // 1. Primary Online Priority: Apple iTunes Search API (Studio 600x600bb from Apple CDN)
    if (itunesProvider.isEnabled) {
      try {
        final itunesArtwork = await itunesProvider.resolve(query);
        if (itunesArtwork != null) {
          await cache.put(key, itunesArtwork);
          return itunesArtwork;
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
          await cache.put(key, deezerArtwork);
          return deezerArtwork;
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
          await cache.put(key, caaArtwork);
          return caaArtwork;
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
          await cache.put(key, fanartArtwork);
          return fanartArtwork;
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
        await cache.put(key, ytFallback);
        return ytFallback;
      }
    } catch (_) {}

    // 8. Deterministic neutral fallback
    // Note: Do NOT write neutral fallback into persistent Hive storage.
    // This ensures transient network hiccups or empty early queries do not
    // permanently suppress artwork resolution for this track in future sessions.
    return ResolvedArtwork.neutralFallback();
  }
}
