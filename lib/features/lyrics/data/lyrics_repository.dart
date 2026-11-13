import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../media/domain/models.dart';
import '../domain/lyrics_model.dart';
import '../domain/lyrics_search_query_builder.dart';
import '../domain/lyrics_title_normalizer.dart';
import '../domain/lyrics_validator.dart';

/// Entry representing a cached lyrics result with timestamp for negative caching TTL.
class _CachedLyricsEntry {
  final LyricsData data;
  final DateTime timestamp;

  const _CachedLyricsEntry(this.data, this.timestamp);

  bool get isNegative => data.isEmpty;

  bool isExpired({required Duration negativeTtl}) {
    if (!isNegative) return false;
    return DateTime.now().difference(timestamp) > negativeTtl;
  }
}

abstract class LyricsRepository {
  Future<LyricsData> getLyrics(MusicItem track);
  void clearCache();
}

class LrclibLyricsRepository implements LyricsRepository {
  final Dio _dio;

  /// In-memory cache for resolved lyrics keyed by stable track identity or normalized title+artist.
  final Map<String, _CachedLyricsEntry> _cache = {};

  /// Tracks in-flight futures to prevent duplicate concurrent network requests for the same track.
  final Map<String, Future<LyricsData>> _inFlightRequests = {};

  /// TTL for negative results (unmatched tracks) to avoid hammering the provider while allowing retries later.
  final Duration _negativeCacheTtl;

  LrclibLyricsRepository({
    Dio? dio,
    Duration negativeCacheTtl = const Duration(minutes: 10),
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: {
                  'User-Agent':
                      'MieeMusic/1.0.0 (https://github.com/revanth-kumar-02/Miee-music-player)',
                },
              ),
            ),
        _negativeCacheTtl = negativeCacheTtl;

  @override
  void clearCache() {
    _cache.clear();
    _inFlightRequests.clear();
  }

  String _cacheKey(MusicItem track) {
    if (track.id.trim().isNotEmpty) {
      return track.id.trim();
    }
    final normTitle = LyricsTitleNormalizer.normalize(track.title).toLowerCase();
    final normArtist = track.artist.trim().toLowerCase();
    return '$normTitle|$normArtist';
  }

  @override
  Future<LyricsData> getLyrics(MusicItem track) async {
    final key = _cacheKey(track);

    // 1. Check in-memory cache
    if (_cache.containsKey(key)) {
      final entry = _cache[key]!;
      if (!entry.isExpired(negativeTtl: _negativeCacheTtl)) {
        return entry.data;
      }
      _cache.remove(key);
    }

    // 2. Prevent duplicate in-flight requests for the same track
    if (_inFlightRequests.containsKey(key)) {
      return await _inFlightRequests[key]!;
    }

    final future = _resolveLyrics(track);
    _inFlightRequests[key] = future;

    try {
      final result = await future;
      // Cache result with timestamp (including negative result with TTL)
      _cache[key] = _CachedLyricsEntry(result, DateTime.now());
      return result;
    } catch (e) {
      // Do NOT cache transient network errors permanently so user can retry
      rethrow;
    } finally {
      _inFlightRequests.remove(key); // ignore: unawaited_futures
    }
  }

  Future<LyricsData> _resolveLyrics(MusicItem track) async {
    // Step A: Local .lrc file for offline tracks
    if (!track.isYoutube && track.filePath.isNotEmpty) {
      try {
        final songFile = File(track.filePath);
        if (await songFile.exists()) {
          final dotIndex = songFile.path.lastIndexOf('.');
          if (dotIndex != -1) {
            final baseName = songFile.path.substring(0, dotIndex);
            final lrcFile = File('$baseName.lrc');
            if (await lrcFile.exists()) {
              final content = await lrcFile.readAsString();
              final list = LyricParser.parse(content);
              if (list.isNotEmpty) {
                return LyricsData(lines: list, isSynced: true, source: 'local_lrc');
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Lyrics] Local .lrc read error: $e');
      }
    }

    String? plainFallback;
    final trackDuration = _parseDuration(track.duration);
    final rawTitle = track is Track ? track.rawTitle : null;
    final album = _extractAlbum(track);

    // Step B: Generate structured search candidates covering Stages 1-7
    final candidates = LyricsSearchQueryBuilder.buildCandidates(
      title: track.title,
      artist: track.artist,
      album: album,
      rawTitle: rawTitle,
    );

    // Step C: Try exact /api/get query using high-confidence candidates (normalized/exact title + artist)
    for (final candidate in candidates.take(3)) {
      if (candidate.artistName.isNotEmpty) {
        try {
          final queryParams = <String, dynamic>{
            'track_name': candidate.trackName,
            'artist_name': candidate.artistName,
          };
          if (candidate.albumName != null && candidate.albumName!.isNotEmpty) {
            queryParams['album_name'] = candidate.albumName;
          }
          if (trackDuration != null && trackDuration.inSeconds > 0) {
            queryParams['duration'] = trackDuration.inSeconds;
          }

          final response = await _requestWithRetry(
            'https://lrclib.net/api/get',
            queryParams: queryParams,
          );

          if (response?.statusCode == 200 && response?.data is Map) {
            final data = response!.data as Map;
            final synced = data['syncedLyrics'] as String?;
            if (synced != null && synced.trim().isNotEmpty) {
              final parsed = LyricParser.parse(synced);
              if (parsed.isNotEmpty) {
                return LyricsData(lines: parsed, isSynced: true, source: 'lrclib_get_synced');
              }
            }
            final plain = data['plainLyrics'] as String?;
            if (plain != null && plain.trim().isNotEmpty) {
              plainFallback = plain;
            }
          }
        } catch (e) {
          debugPrint('[Lyrics] LRCLIB get query failed for "${candidate.trackName}": $e. Continuing to search candidates...');
        }
      }
    }

    // Step D: Controlled candidate search loop via /api/search
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      try {
        final queryParams = <String, dynamic>{};
        if (candidate.artistName.isNotEmpty) {
          queryParams['track_name'] = candidate.trackName;
          queryParams['artist_name'] = candidate.artistName;
          if (candidate.albumName != null && candidate.albumName!.isNotEmpty) {
            queryParams['album_name'] = candidate.albumName;
          }
        } else {
          queryParams['q'] = candidate.trackName;
        }

        final searchResp = await _requestWithRetry(
          'https://lrclib.net/api/search',
          queryParams: queryParams,
        );

        if (searchResp?.statusCode == 200 &&
            searchResp?.data is List &&
            (searchResp!.data as List).isNotEmpty) {
          final results = searchResp.data as List;

          for (final item in results) {
            if (item is! Map) continue;

            final itemTrackName = item['trackName'] as String? ?? '';
            final itemDurationSec = (item['duration'] as num?)?.round();
            final itemDuration = itemDurationSec != null ? Duration(seconds: itemDurationSec) : null;

            // Validate candidate match before accepting to protect against wrong-song false positives
            final isValid = LyricsValidator.validate(
              queryTrackName: candidate.trackName,
              candidateTrackName: itemTrackName,
              queryDuration: trackDuration,
              candidateDuration: itemDuration,
            );

            if (!isValid) continue;

            final synced = item['syncedLyrics'] as String?;
            if (synced != null && synced.trim().isNotEmpty) {
              final parsed = LyricParser.parse(synced);
              if (parsed.isNotEmpty) {
                return LyricsData(lines: parsed, isSynced: true, source: 'lrclib_search_synced');
              }
            }

            if (plainFallback == null) {
              final plain = item['plainLyrics'] as String?;
              if (plain != null && plain.trim().isNotEmpty) {
                plainFallback = plain;
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Lyrics] LRCLIB search failed for "${candidate.trackName}": $e');
      }
    }

    // Step E: Unsynchronized plain lyrics fallback (Duration.zero, no fake timestamps)
    if (plainFallback != null && plainFallback.trim().isNotEmpty) {
      final plainLines = plainFallback
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((text) => LyricLine(time: Duration.zero, text: text))
          .toList();
      if (plainLines.isNotEmpty) {
        return LyricsData(lines: plainLines, isSynced: false, source: 'plain_fallback');
      }
    }

    return LyricsData.empty;
  }

  Future<Response<dynamic>?> _requestWithRetry(
    String url, {
    required Map<String, dynamic> queryParams,
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _dio.get<dynamic>(url, queryParameters: queryParams);
        return response;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        // Handle rate limiting (429) or temporary service unavailable (503)
        if ((statusCode == 429 || statusCode == 503) && attempt < maxRetries - 1) {
          final delayMs = 350 * (attempt + 1);
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        if (statusCode == 404) {
          return null; // Normal missing result
        }
        rethrow;
      } catch (_) {
        rethrow;
      }
    }
    return null;
  }

  String? _extractAlbum(MusicItem track) {
    if (track is Track && track.albumName != null && track.albumName!.trim().isNotEmpty) {
      return track.albumName!.trim();
    }
    if (track is MediaSong && track.album.trim().isNotEmpty) {
      return track.album.trim();
    }
    return null;
  }

  Duration? _parseDuration(String durationStr) {
    final parts = durationStr.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]);
      final s = int.tryParse(parts[1]);
      if (m != null && s != null) return Duration(minutes: m, seconds: s);
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final s = int.tryParse(parts[2]);
      if (h != null && m != null && s != null) {
        return Duration(hours: h, minutes: m, seconds: s);
      }
    }
    return null;
  }
}
