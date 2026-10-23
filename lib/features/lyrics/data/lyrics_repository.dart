import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../domain/lyrics_model.dart';
import '../domain/lyrics_search_query_builder.dart';
import '../domain/lyrics_validator.dart';

abstract class LyricsRepository {
  Future<LyricsData> getLyrics(MusicItem track);
  void clearCache();
}

class LrclibLyricsRepository implements LyricsRepository {
  final Dio _dio;

  // In-memory cache for resolved lyrics keyed by track identity
  final Map<String, LyricsData> _cache = {};

  // Tracks in-flight futures to prevent duplicate concurrent network requests for the same track
  final Map<String, Future<LyricsData>> _inFlightRequests = {};

  LrclibLyricsRepository({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: {
                  'User-Agent':
                      'MieeMusic/1.0.0 (https://github.com/revanth-kumar-02/Miee-music-player)',
                },
              ),
            );

  @override
  void clearCache() {
    _cache.clear();
    _inFlightRequests.clear();
  }

  String _cacheKey(MusicItem track) {
    if (track.id.trim().isNotEmpty) {
      return track.id.trim();
    }
    return '${track.title.trim().toLowerCase()}|${track.artist.trim().toLowerCase()}';
  }

  @override
  Future<LyricsData> getLyrics(MusicItem track) async {
    final key = _cacheKey(track);

    // 1. Check in-memory cache
    if (_cache.containsKey(key)) {
      return _cache[key]!;
    }

    // 2. Prevent duplicate in-flight requests for the same track
    if (_inFlightRequests.containsKey(key)) {
      return await _inFlightRequests[key]!;
    }

    final future = _resolveLyrics(track);
    _inFlightRequests[key] = future;

    try {
      final result = await future;
      // Cache successful or definitively empty results
      _cache[key] = result;
      return result;
    } catch (e) {
      // Do NOT cache transient failures (e.g. 503, network timeouts) permanently
      rethrow;
    } finally {
      _inFlightRequests.remove(key);
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

    // Step B: Generate structured search candidates
    final candidates = LyricsSearchQueryBuilder.buildCandidates(
      title: track.title,
      artist: track.artist,
      rawTitle: rawTitle,
    );

    // Step C: Try exact match /api/get with high-confidence primary candidate
    if (candidates.isNotEmpty) {
      final primary = candidates.first;
      if (primary.artistName.isNotEmpty) {
        try {
          final queryParams = <String, dynamic>{
            'track_name': primary.trackName,
            'artist_name': primary.artistName,
          };
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
          debugPrint('[Lyrics] LRCLIB get query failed: $e. Proceeding to search candidates...');
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

            // Validate candidate match before accepting
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

  Future<Response?> _requestWithRetry(
    String url, {
    required Map<String, dynamic> queryParams,
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final response = await _dio.get(url, queryParameters: queryParams);
        return response;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode;
        // Handle rate limiting (429) or temporary service unavailable (503)
        if ((statusCode == 429 || statusCode == 503) && attempt < maxRetries - 1) {
          final delayMs = 350 * (attempt + 1);
          await Future.delayed(Duration(milliseconds: delayMs));
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
