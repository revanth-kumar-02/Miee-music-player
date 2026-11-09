import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../media/domain/models.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../domain/artist_classifier.dart';

/// Centralized, high-performance service for resolving and associating tracks
/// with verified artist profiles.
///
/// Features:
/// 1. Zero redundant network calls: Deduplicates in-flight resolution requests.
/// 2. Multi-tier memory caching: Caches verified artist entities by canonical name and ID.
/// 3. Strict match validation: Prevents associating unrelated artist profiles.
/// 4. Graceful unlinked fallback: Preserves artist name without creating false links.
class ArtistResolutionService {
  final Map<String, ArtistModel> _cache = {};
  final Map<String, Future<ArtistModel>> _inFlight = {};
  static const int _maxCacheSize = 200;

  /// Canonical normalization string helper.
  static String canonical(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Resolves the verified [ArtistModel] for any [MusicItem] (Track, MediaSong, YouTubeVideo).
  Future<ArtistModel> resolveTrackArtist(
    MusicItem track, {
    List<MediaArtist> localArtists = const [],
    ArtistRepository? artistRepo,
  }) async {
    final rawArtist = track.artist.trim();
    if (rawArtist.isEmpty) {
      return const ArtistModel(id: '', name: 'Unknown Artist', imageUrl: '');
    }

    // 0. Primary artist extraction if multi-artist string
    final delimiters = RegExp(r'[,/|&]|\s+(feat\.?|ft\.?)\s+', caseSensitive: false);
    final parts = rawArtist.split(delimiters);
    final primaryName = parts.isNotEmpty && parts.first.trim().isNotEmpty
        ? parts.first.trim()
        : rawArtist;

    final cPrimary = canonical(primaryName);
    final cFull = canonical(rawArtist);

    String? stableArtistId;
    if (track is Track) {
      stableArtistId = track.artistId;
    } else if (track is YouTubeVideo) {
      stableArtistId = track.channelId;
    }

    // 1. If track already carries a stable artist identifier (e.g. Deezer ID, Curated ID, Channel ID)
    if (stableArtistId != null && stableArtistId.trim().isNotEmpty) {
      final aId = stableArtistId.trim();

      // Check curated by ID
      final curated = DeezerArtistRepository.findCuratedById(aId);
      if (curated != null) {
        _cacheResult(cPrimary, curated);
        return curated;
      }

      // Check cache by ID
      if (_cache.containsKey('id_$aId')) {
        return _cache['id_$aId']!;
      }

      // Check local artists by ID
      final localMatch = localArtists.where((a) => a.id == aId).firstOrNull;
      if (localMatch != null) {
        final model = ArtistModel(
          id: localMatch.id,
          name: localMatch.name,
          imageUrl: localMatch.artworkPath ?? '',
        );
        _cacheResult('id_$aId', model);
        return model;
      }

      // If integer Deezer ID, try details lookup
      if (int.tryParse(aId) != null && artistRepo != null) {
        final details = await artistRepo.getArtistDetails(aId);
        if (details != null && ArtistClassifier.isLegitimateMusicArtist(details.name, fanCount: details.fanCount)) {
          _cacheResult('id_$aId', details);
          _cacheResult(cPrimary, details);
          return details;
        }
      }
    }

    // 2. Check curated catalog by canonical name (Instant, 0 network)
    final curatedByName = DeezerArtistRepository.findCuratedByName(primaryName) ??
        (primaryName != rawArtist ? DeezerArtistRepository.findCuratedByName(rawArtist) : null);
    if (curatedByName != null) {
      _cacheResult(cPrimary, curatedByName);
      return curatedByName;
    }

    // 3. Check local device artists (Instant, 0 network)
    final localMatch = localArtists.where((a) {
      final an = canonical(a.name);
      return an == cPrimary || an == cFull;
    }).firstOrNull;
    if (localMatch != null) {
      final model = ArtistModel(
        id: localMatch.id,
        name: localMatch.name,
        imageUrl: localMatch.artworkPath ?? '',
      );
      _cacheResult(cPrimary, model);
      return model;
    }

    // 4. Check in-memory resolution cache (Instant, 0 network)
    if (_cache.containsKey(cPrimary)) {
      return _cache[cPrimary]!;
    }
    if (_cache.containsKey(cFull)) {
      return _cache[cFull]!;
    }

    // 5. In-flight request deduplication for online lookup
    if (_inFlight.containsKey(cPrimary)) {
      return _inFlight[cPrimary]!;
    }

    if (artistRepo == null) {
      return ArtistModel(id: '', name: primaryName, imageUrl: '');
    }

    // Execute online lookup with strict matching
    final future = _fetchAndVerifyOnlineArtist(primaryName, cPrimary, artistRepo);
    _inFlight[cPrimary] = future;

    try {
      final resolved = await future;
      _cacheResult(cPrimary, resolved);
      return resolved;
    } finally {
      unawaited(_inFlight.remove(cPrimary));
    }
  }

  Future<ArtistModel> _fetchAndVerifyOnlineArtist(
    String primaryName,
    String cPrimary,
    ArtistRepository artistRepo,
  ) async {
    try {
      final results = await artistRepo.searchArtists(primaryName);
      if (results.isNotEmpty) {
        // Filter out non-music entities
        final validCandidates = results
            .where((a) => ArtistClassifier.isLegitimateMusicArtist(
                  a.name,
                  fanCount: a.fanCount,
                  query: primaryName,
                ))
            .toList();

        // STRICT MATCHING: Only associate if canonical names match substantially
        for (final candidate in validCandidates) {
          final cCandidate = canonical(candidate.name);
          if (cCandidate == cPrimary) {
            return candidate;
          }
          // Accept prefix match if length is substantial (e.g. "Anirudh" matching "Anirudh Ravichander")
          if (cPrimary.length >= 5 && cCandidate.startsWith(cPrimary)) {
            return candidate;
          }
        }
      }
    } catch (_) {}

    // Safe unlinked fallback: Display credited artist name without inventing a fake profile association
    return ArtistModel(
      id: '',
      name: primaryName,
      imageUrl: '',
    );
  }

  void _cacheResult(String key, ArtistModel artist) {
    if (_cache.length >= _maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = artist;
  }

  void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }
}

/// Global provider for [ArtistResolutionService].
final artistResolutionServiceProvider = Provider<ArtistResolutionService>((ref) {
  return ArtistResolutionService();
});
