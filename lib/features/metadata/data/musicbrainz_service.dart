import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../domain/musicbrainz_models.dart';
import 'musicbrainz_rate_limiter.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../onboarding/data/artist_discovery_repository.dart';

/// Primary metadata service leveraging the open-source, non-commercial
/// MusicBrainz Web Service v2 API (`https://musicbrainz.org/ws/2/`) and
/// Cover Art Archive (`https://coverartarchive.org/`).
///
/// Features:
/// - Enforces strict 1 req/sec rate limiting via [MusicBrainzRateLimiter].
/// - Descriptive User-Agent header with application name, version, and maintainer contact.
/// - Bounded LRU in-memory caching with TTL expiration.
/// - In-flight query deduplication.
/// - Resilient HTTP 503 backoff and graceful error recovery.
class MusicBrainzService {
  static final MusicBrainzService _instance = MusicBrainzService._internal();
  factory MusicBrainzService({Dio? dio, MusicBrainzRateLimiter? rateLimiter}) {
    if (dio != null || rateLimiter != null) {
      return MusicBrainzService.withClient(
        dio ?? Dio(),
        rateLimiter ?? MusicBrainzRateLimiter(),
      );
    }
    return _instance;
  }

  MusicBrainzService._internal()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 5),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'Miee/2.0.0 ( support@mieemusic.app )',
            },
            followRedirects: true,
            maxRedirects: 5,
          ),
        ),
        _rateLimiter = MusicBrainzRateLimiter();

  @visibleForTesting
  MusicBrainzService.withClient(Dio dio, MusicBrainzRateLimiter rateLimiter)
      : _dio = dio,
        _rateLimiter = rateLimiter;

  final Dio _dio;
  final MusicBrainzRateLimiter _rateLimiter;

  /// Bounded LRU in-memory cache for recording searches.
  final Map<String, _CachedEntry<List<MusicBrainzRecording>>> _recordingCache = {};
  static const int _maxRecordingCache = 250;
  static const Duration _recordingTtl = Duration(minutes: 15);

  /// Bounded LRU in-memory cache for artist searches.
  final Map<String, _CachedEntry<List<MusicBrainzArtist>>> _artistCache = {};
  static const int _maxArtistCache = 150;
  static const Duration _artistTtl = Duration(minutes: 20);

  /// Bounded LRU in-memory cache for resolved Cover Art Archive URLs.
  final Map<String, String> _coverArtCache = {};
  static const int _maxCoverCache = 500;

  /// In-flight request deduplication map.
  final Map<String, Future<List<MusicBrainzRecording>>> _inFlightRecordings = {};
  final Map<String, Future<List<MusicBrainzArtist>>> _inFlightArtists = {};

  /// Searches MusicBrainz for recordings matching [query] using the Lucene query syntax.
  Future<List<MusicBrainzRecording>> searchRecordings(
    String query, {
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final clean = _sanitizeQuery(query);
    if (clean.isEmpty) return const [];

    final cacheKey = '${clean.toLowerCase()}_$limit';
    if (!forceRefresh && _recordingCache.containsKey(cacheKey)) {
      final entry = _recordingCache[cacheKey]!;
      if (!entry.isExpired(_recordingTtl)) {
        return entry.data;
      }
      _recordingCache.remove(cacheKey);
    }

    if (!forceRefresh && _inFlightRecordings.containsKey(cacheKey)) {
      return await _inFlightRecordings[cacheKey]!;
    }

    final future = _executeRecordingSearch(clean, limit).whenComplete(() {
      _inFlightRecordings.remove(cacheKey);
    });

    _inFlightRecordings[cacheKey] = future;
    final results = await future;

    if (results.isNotEmpty) {
      if (_recordingCache.length >= _maxRecordingCache) {
        _recordingCache.remove(_recordingCache.keys.first);
      }
      _recordingCache[cacheKey] = _CachedEntry(results, DateTime.now());
    }

    return results;
  }

  Future<List<MusicBrainzRecording>> _executeRecordingSearch(String clean, int limit) async {
    return _rateLimiter.schedule(() async {
      final luceneQuery = _buildLuceneRecordingQuery(clean);
      try {
        final response = await _dio.get<dynamic>(
          'https://musicbrainz.org/ws/2/recording',
          queryParameters: {
            'query': luceneQuery,
            'fmt': 'json',
            'limit': limit,
          },
        );

        if (response.statusCode != 200 || response.data == null) {
          return const <MusicBrainzRecording>[];
        }

        final Map<String, dynamic> data;
        if (response.data is String) {
          data = jsonDecode(response.data as String) as Map<String, dynamic>;
        } else if (response.data is Map) {
          data = Map<String, dynamic>.from(response.data as Map);
        } else {
          return const <MusicBrainzRecording>[];
        }

        final rawRecordings = data['recordings'] as List<dynamic>? ?? const [];
        final recordings = <MusicBrainzRecording>[];

        for (final item in rawRecordings) {
          if (item is Map) {
            final rec = MusicBrainzRecording.fromJson(Map<String, dynamic>.from(item));
            if (rec.mbid.isNotEmpty && rec.title.isNotEmpty) {
              recordings.add(rec);
            }
          }
        }

        return _rankRecordings(recordings, clean);
      } on DioException catch (e) {
        if (e.response?.statusCode == 503) {
          debugPrint('[MusicBrainzService] 503 Server busy. Waiting 1500ms before retry...');
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          return _retryRecordingSearchOnce(luceneQuery, limit);
        }
        debugPrint('[MusicBrainzService] Recording search error for "$clean": $e');
        return const <MusicBrainzRecording>[];
      } catch (e) {
        debugPrint('[MusicBrainzService] Unexpected error for "$clean": $e');
        return const <MusicBrainzRecording>[];
      }
    });
  }

  Future<List<MusicBrainzRecording>> _retryRecordingSearchOnce(String luceneQuery, int limit) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://musicbrainz.org/ws/2/recording',
        queryParameters: {
          'query': luceneQuery,
          'fmt': 'json',
          'limit': limit,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        final Map<String, dynamic> data = (response.data is String)
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);
        final rawRecordings = data['recordings'] as List<dynamic>? ?? const [];
        return rawRecordings
            .whereType<Map<dynamic, dynamic>>()
            .map((m) => MusicBrainzRecording.fromJson(Map<String, dynamic>.from(m)))
            .where((r) => r.mbid.isNotEmpty && r.title.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  /// Searches MusicBrainz for artist entities matching [query].
  Future<List<MusicBrainzArtist>> searchArtists(
    String query, {
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    final clean = _sanitizeQuery(query);
    if (clean.isEmpty) return const [];

    final cacheKey = '${clean.toLowerCase()}_$limit';
    if (!forceRefresh && _artistCache.containsKey(cacheKey)) {
      final entry = _artistCache[cacheKey]!;
      if (!entry.isExpired(_artistTtl)) {
        return entry.data;
      }
      _artistCache.remove(cacheKey);
    }

    if (!forceRefresh && _inFlightArtists.containsKey(cacheKey)) {
      return await _inFlightArtists[cacheKey]!;
    }

    final future = _executeArtistSearch(clean, limit).whenComplete(() {
      _inFlightArtists.remove(cacheKey);
    });

    _inFlightArtists[cacheKey] = future;
    final results = await future;

    if (results.isNotEmpty) {
      if (_artistCache.length >= _maxArtistCache) {
        _artistCache.remove(_artistCache.keys.first);
      }
      _artistCache[cacheKey] = _CachedEntry(results, DateTime.now());
    }

    return results;
  }

  Future<List<MusicBrainzArtist>> _executeArtistSearch(String clean, int limit) async {
    return _rateLimiter.schedule(() async {
      try {
        final luceneQuery = 'artist:"$clean"^3 OR "$clean"';
        final response = await _dio.get<dynamic>(
          'https://musicbrainz.org/ws/2/artist',
          queryParameters: {
            'query': luceneQuery,
            'fmt': 'json',
            'limit': limit,
          },
        );

        if (response.statusCode != 200 || response.data == null) {
          return const <MusicBrainzArtist>[];
        }

        final Map<String, dynamic> data = (response.data is String)
            ? jsonDecode(response.data as String) as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);

        final rawArtists = data['artists'] as List<dynamic>? ?? const [];
        final artists = <MusicBrainzArtist>[];

        for (final item in rawArtists) {
          if (item is Map) {
            final a = MusicBrainzArtist.fromJson(Map<String, dynamic>.from(item));
            if (a.mbid.isNotEmpty && a.name.isNotEmpty) {
              artists.add(a);
            }
          }
        }

        return artists;
      } catch (e) {
        debugPrint('[MusicBrainzService] Artist search error for "$clean": $e');
        return const <MusicBrainzArtist>[];
      }
    });
  }

  /// Converts MusicBrainz artists to Miee's core [ArtistModel], enriching with curated portraits.
  Future<List<ArtistModel>> searchArtistsAsArtistModels(String query, {int limit = 10}) async {
    final mbArtists = await searchArtists(query, limit: limit);
    final models = <ArtistModel>[];

    for (final a in mbArtists) {
      final curated = DeezerArtistRepository.findCuratedByName(a.name);
      final imageUrl = curated?.imageUrl ?? '';
      final fanCount = curated != null && curated.fanCount > 0 ? curated.fanCount : (a.score * 100);
      final languages = curated?.languages ?? const <String>[];

      models.add(
        ArtistModel(
          id: 'mb_${a.mbid}',
          name: a.name,
          imageUrl: imageUrl,
          fanCount: fanCount,
          genres: a.genres,
          languages: languages,
          bio: a.disambiguation,
        ),
      );
    }

    return models;
  }

  /// Generates the standard Cover Art Archive front cover image URL.
  String? buildCoverArtArchiveUrl({
    String? releaseMbid,
    String? releaseGroupMbid,
    int size = 500,
  }) {
    if (releaseMbid != null && releaseMbid.isNotEmpty) {
      return 'https://coverartarchive.org/release/$releaseMbid/front-$size';
    }
    if (releaseGroupMbid != null && releaseGroupMbid.isNotEmpty) {
      return 'https://coverartarchive.org/release-group/$releaseGroupMbid/front-$size';
    }
    return null;
  }

  /// Resolves authenticated Cover Art Archive front cover image for a recording.
  Future<String?> resolveCoverArtUrl(MusicBrainzRecording recording) async {
    final candidateReleaseMbid = recording.releaseMbid;
    final candidateRgMbid = recording.releaseGroupMbid;

    if (candidateReleaseMbid != null && _coverArtCache.containsKey(candidateReleaseMbid)) {
      return _coverArtCache[candidateReleaseMbid];
    }
    if (candidateRgMbid != null && _coverArtCache.containsKey(candidateRgMbid)) {
      return _coverArtCache[candidateRgMbid];
    }

    // Try Release Front Cover
    if (candidateReleaseMbid != null && candidateReleaseMbid.isNotEmpty) {
      final url = 'https://coverartarchive.org/release/$candidateReleaseMbid/front-500';
      final isValid = await _verifyImageAvailability(url);
      if (isValid) {
        _cacheCover(candidateReleaseMbid, url);
        return url;
      }
    }

    // Try Release Group Front Cover
    if (candidateRgMbid != null && candidateRgMbid.isNotEmpty) {
      final url = 'https://coverartarchive.org/release-group/$candidateRgMbid/front-500';
      final isValid = await _verifyImageAvailability(url);
      if (isValid) {
        _cacheCover(candidateRgMbid, url);
        return url;
      }
    }

    return null;
  }

  Future<bool> _verifyImageAvailability(String url) async {
    try {
      final res = await _dio.head<dynamic>(
        url,
        options: Options(
          followRedirects: true,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );
      return res.statusCode == 200 || res.statusCode == 307;
    } catch (_) {
      return false;
    }
  }

  void _cacheCover(String id, String url) {
    if (_coverArtCache.length >= _maxCoverCache) {
      _coverArtCache.remove(_coverArtCache.keys.first);
    }
    _coverArtCache[id] = url;
  }

  /// Lucene query syntax construction.
  String _buildLuceneRecordingQuery(String clean) {
    // If query has hyphen or 'by', parse artist and title
    final cleanLower = clean.toLowerCase();
    if (clean.contains(' - ')) {
      final parts = clean.split(' - ');
      final a = parts[0].trim();
      final t = parts[1].trim();
      return '(recording:"$t" AND artist:"$a") OR (recording:"$t"^2) OR ("$clean")';
    } else if (cleanLower.contains(' by ')) {
      final parts = clean.split(RegExp(r'\s+by\s+', caseSensitive: false));
      final t = parts[0].trim();
      final a = parts[1].trim();
      return '(recording:"$t" AND artist:"$a") OR (recording:"$t"^2) OR ("$clean")';
    }

    return 'recording:"$clean"^3 OR "$clean"';
  }

  List<MusicBrainzRecording> _rankRecordings(List<MusicBrainzRecording> list, String query) {
    final qLower = query.toLowerCase().trim();
    list.sort((a, b) {
      final aExactTitle = a.title.toLowerCase() == qLower;
      final bExactTitle = b.title.toLowerCase() == qLower;
      if (aExactTitle && !bExactTitle) return -1;
      if (!aExactTitle && bExactTitle) return 1;

      final aStarts = a.title.toLowerCase().startsWith(qLower);
      final bStarts = b.title.toLowerCase().startsWith(qLower);
      if (aStarts && !bStarts) return -1;
      if (!aStarts && bStarts) return 1;

      return b.score.compareTo(a.score);
    });
    return list;
  }

  String _sanitizeQuery(String query) {
    return query
        .replaceAll(RegExp(r'[\/\\#\$\^]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void clearCache() {
    _recordingCache.clear();
    _artistCache.clear();
    _coverArtCache.clear();
    _inFlightRecordings.clear();
    _inFlightArtists.clear();
  }
}

class _CachedEntry<T> {
  final T data;
  final DateTime timestamp;

  const _CachedEntry(this.data, this.timestamp);

  bool isExpired(Duration ttl) => DateTime.now().difference(timestamp) > ttl;
}
