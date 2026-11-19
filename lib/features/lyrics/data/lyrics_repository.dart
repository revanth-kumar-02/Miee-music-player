import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yte;
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
  yte.YoutubeExplode? _sharedYt;
  yte.YoutubeExplode get _yt => _sharedYt ??= yte.YoutubeExplode();

  /// In-memory cache for resolved lyrics keyed by stable track identity or normalized title+artist+version+lang.
  final Map<String, _CachedLyricsEntry> _cache = {};

  /// Tracks in-flight futures to prevent duplicate concurrent network requests for the same track.
  final Map<String, Future<LyricsData>> _inFlightRequests = {};

  /// TTL for negative results (unmatched tracks) to avoid hammering the provider while allowing retries later.
  final Duration _negativeCacheTtl;

  LrclibLyricsRepository({
    Dio? dio,
    yte.YoutubeExplode? ytClient,
    Duration negativeCacheTtl = const Duration(minutes: 10),
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8),
                headers: {
                  'User-Agent':
                      'MieeMusic/2.0.0 (https://github.com/revanth-kumar-02/Miee-music-player)',
                },
              ),
            ),
        _sharedYt = ytClient,
        _negativeCacheTtl = negativeCacheTtl;

  @override
  void clearCache() {
    _cache.clear();
    _inFlightRequests.clear();
  }

  String _cacheKey(MusicItem track) {
    final normTitle = LyricsTitleNormalizer.normalize(track.title).toLowerCase();
    final primaryArtist = LyricsTitleNormalizer.splitArtists(track.artist).firstOrNull?.toLowerCase() ?? track.artist.trim().toLowerCase();
    final version = LyricsTitleNormalizer.extractVersionModifier(track.title) ?? '';
    final lang = LyricsTitleNormalizer.extractLanguageTag(track.title) ?? '';

    if (track.id.trim().isNotEmpty) {
      return '${track.id.trim()}|$version|$lang';
    }
    return '$normTitle|$primaryArtist|$version|$lang';
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
    // Step A: Local .lrc file check for offline tracks
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

    // Step B: Generate structured search candidates covering Stages 1-8
    final candidates = LyricsSearchQueryBuilder.buildCandidates(
      title: track.title,
      artist: track.artist,
      album: album,
      rawTitle: rawTitle,
    );

    // Step C: Try exact /api/get query using high-confidence candidates (normalized title + primary artist)
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
            final itemTrackName = data['trackName'] as String? ?? '';
            final itemArtistName = data['artistName'] as String? ?? '';
            final itemAlbumName = data['albumName'] as String?;
            final itemDurationSec = (data['duration'] as num?)?.round();
            final itemDuration = itemDurationSec != null ? Duration(seconds: itemDurationSec) : null;

            // Rigorously validate the exact match candidate before accepting
            final matchResult = LyricsValidator.evaluateMatch(
              queryTrackName: candidate.trackName,
              candidateTrackName: itemTrackName,
              queryArtistName: candidate.originalQueryArtist.isNotEmpty
                  ? candidate.originalQueryArtist
                  : candidate.artistName,
              candidateArtistName: itemArtistName,
              queryDuration: trackDuration,
              candidateDuration: itemDuration,
              queryAlbum: candidate.albumName ?? album,
              candidateAlbum: itemAlbumName,
            );

            if (matchResult.isValid) {
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
            } else {
              debugPrint('[Lyrics] LRCLIB exact get candidate rejected: ${matchResult.reason}');
            }
          }
        } catch (e) {
          debugPrint('[Lyrics] LRCLIB get query failed for "${candidate.trackName}": $e. Continuing to search candidates...');
        }
      }
    }

    // Step D: Controlled candidate search loop via /api/search with scoring
    Map<dynamic, dynamic>? bestCandidateItem;
    double bestConfidenceScore = 0.0;

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
            final itemArtistName = item['artistName'] as String? ?? '';
            final itemAlbumName = item['albumName'] as String?;
            final itemDurationSec = (item['duration'] as num?)?.round();
            final itemDuration = itemDurationSec != null ? Duration(seconds: itemDurationSec) : null;

            final matchResult = LyricsValidator.evaluateMatch(
              queryTrackName: candidate.trackName,
              candidateTrackName: itemTrackName,
              queryArtistName: candidate.originalQueryArtist.isNotEmpty
                  ? candidate.originalQueryArtist
                  : candidate.artistName,
              candidateArtistName: itemArtistName,
              queryDuration: trackDuration,
              candidateDuration: itemDuration,
              queryAlbum: candidate.albumName ?? album,
              candidateAlbum: itemAlbumName,
            );

            if (matchResult.isValid && matchResult.confidence > bestConfidenceScore) {
              bestConfidenceScore = matchResult.confidence;
              bestCandidateItem = item;

              // If candidate is a near-perfect match (>= 0.90) with synced lyrics, accept immediately
              final synced = item['syncedLyrics'] as String?;
              if (synced != null && synced.trim().isNotEmpty && matchResult.confidence >= 0.90) {
                final parsed = LyricParser.parse(synced);
                if (parsed.isNotEmpty) {
                  return LyricsData(lines: parsed, isSynced: true, source: 'lrclib_search_synced');
                }
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[Lyrics] LRCLIB search failed for "${candidate.trackName}": $e');
      }
    }

    // If a best candidate was found above the acceptance threshold
    if (bestCandidateItem != null && bestConfidenceScore >= LyricsValidator.acceptanceThreshold) {
      final synced = bestCandidateItem['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final parsed = LyricParser.parse(synced);
        if (parsed.isNotEmpty) {
          return LyricsData(lines: parsed, isSynced: true, source: 'lrclib_search_synced');
        }
      }
      final plain = bestCandidateItem['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        plainFallback = plain;
      }
    }

    // Step E: Tier 4 Fallback — YouTube Timed Closed Captions
    if (track.isYoutube || track.id.startsWith('youtube_') || RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(track.id)) {
      final ytCaptions = await _fetchYouTubeClosedCaptions(track);
      if (ytCaptions != null && ytCaptions.isNotEmpty) {
        return ytCaptions;
      }
    }

    // Step F: Unsynchronized plain lyrics fallback (Duration.zero, no fake timestamps)
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

  /// Fetches timed closed captions directly from YouTube for official video songs / lyric videos.
  Future<LyricsData?> _fetchYouTubeClosedCaptions(MusicItem track) async {
    try {
      final videoIdStr = _extractYouTubeVideoId(track);
      if (videoIdStr == null || videoIdStr.isEmpty) return null;

      final manifest = await _yt.videos.closedCaptions.getManifest(videoIdStr);
      if (manifest.tracks.isEmpty) return null;

      yte.ClosedCaptionTrackInfo? selectedTrack;
      final lang = LyricsTitleNormalizer.extractLanguageTag(track.title);
      final langCode = _mapLanguageToCode(lang);

      if (langCode != null) {
        // When language is explicitly known (e.g. 'ta' for Tamil), NEVER accept other Indian language captions!
        selectedTrack = manifest.getByLanguage(langCode, autoGenerated: false).firstOrNull ??
            manifest.getByLanguage(langCode, autoGenerated: true).firstOrNull ??
            manifest.getByLanguage('en', autoGenerated: false).firstOrNull;
      } else {
        selectedTrack = manifest.tracks.where((t) => !t.isAutoGenerated).firstOrNull ??
            manifest.tracks.firstOrNull;
      }

      if (selectedTrack == null) return null;

      final captionTrack = await _yt.videos.closedCaptions.get(selectedTrack);
      if (captionTrack.captions.isEmpty) return null;

      final lyricLines = <LyricLine>[];
      for (final caption in captionTrack.captions) {
        final text = caption.text.trim();
        if (text.isEmpty || text == '♪' || text == '[Music]') continue;
        lyricLines.add(LyricLine(
          time: caption.offset,
          text: text.replaceAll('\n', ' ').trim(),
        ));
      }

      if (lyricLines.isNotEmpty) {
        // Enforce script compatibility: if track is Tamil, lyrics must NOT contain Kannada, Telugu, etc.
        if (langCode != null) {
          final sample = lyricLines.take(15).map((l) => l.text).join(' ');
          if (!_isScriptCompatible(sample, langCode)) {
            debugPrint('[Lyrics] YouTube closed captions rejected: script incompatible with language $langCode');
            return null;
          }
        }

        debugPrint('[Lyrics] Resolved ${lyricLines.length} timed lines from YouTube Closed Captions (${selectedTrack.language.name})');
        return LyricsData(
          lines: lyricLines,
          isSynced: true,
          source: 'youtube_timed_captions_${selectedTrack.language.code}',
        );
      }
    } catch (e) {
      debugPrint('[Lyrics] YouTube closed captions lookup failed for "${track.title}": $e');
    }
    return null;
  }

  String? _extractYouTubeVideoId(MusicItem track) {
    if (track.id.startsWith('youtube_')) {
      return track.id.replaceFirst('youtube_', '').trim();
    }
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(track.id)) {
      return track.id;
    }
    if (track is Track && track.sourceId != null && track.sourceId!.isNotEmpty) {
      return track.sourceId!.replaceFirst('youtube_', '').trim();
    }
    if (track.filePath.contains('v=')) {
      final uri = Uri.tryParse(track.filePath);
      return uri?.queryParameters['v'];
    }
    return null;
  }

  String? _mapLanguageToCode(String? lang) {
    if (lang == null) return null;
    switch (lang.toLowerCase()) {
      case 'tamil':
        return 'ta';
      case 'telugu':
        return 'te';
      case 'hindi':
        return 'hi';
      case 'malayalam':
        return 'ml';
      case 'kannada':
        return 'kn';
      case 'punjabi':
        return 'pa';
      case 'bengali':
        return 'bn';
      case 'marathi':
        return 'mr';
      case 'english':
        return 'en';
      case 'spanish':
        return 'es';
      default:
        return null;
    }
  }

  bool _isScriptCompatible(String text, String langCode) {
    switch (langCode) {
      case 'ta': // Tamil
        // Reject if contains Kannada, Telugu, Devanagari, Malayalam, Bengali
        if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return false; // Kannada
        if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return false; // Telugu
        if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return false; // Devanagari
        if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(text)) return false; // Malayalam
        return true;
      case 'te': // Telugu
        if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return false; // Tamil
        if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return false; // Kannada
        if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return false; // Devanagari
        return true;
      case 'kn': // Kannada
        if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return false; // Tamil
        if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return false; // Telugu
        if (RegExp(r'[\u0900-\u097F]').hasMatch(text)) return false; // Devanagari
        return true;
      case 'hi': // Hindi / Devanagari
        if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return false; // Tamil
        if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return false; // Kannada
        if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(text)) return false; // Telugu
        return true;
      case 'ml': // Malayalam
        if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(text)) return false; // Tamil
        if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(text)) return false; // Kannada
        return true;
      default:
        return true;
    }
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
