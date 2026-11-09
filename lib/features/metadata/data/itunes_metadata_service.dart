import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../../artwork/data/artwork_match_validator.dart';
import '../../youtube/domain/youtube_metadata_cleaner.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../../shared/models/track.dart';
import '../domain/itunes_song.dart';
import '../domain/metadata_match_result.dart';

/// Primary metadata service leveraging the Apple iTunes Search API
/// (`https://itunes.apple.com/search`) for canonical song titles, artists,
/// album collections, and high-resolution studio artwork.
///
/// Follows Miee's core architecture principle:
/// Separation of music metadata (Apple iTunes) from audio streaming (YouTube).
class ItunesMetadataService {
  static final ItunesMetadataService _instance = ItunesMetadataService._internal();
  factory ItunesMetadataService({Dio? dio}) {
    if (dio != null) {
      return ItunesMetadataService._withDio(dio);
    }
    return _instance;
  }

  ItunesMetadataService._internal()
      : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'MieeMusic/2.0 (Mobile; Audio)',
            },
          ),
        );

  ItunesMetadataService._withDio(Dio dio) : _dio = dio;

  final Dio _dio;

  /// Bounded LRU in-memory cache for raw iTunes search term queries.
  final Map<String, List<ItunesSong>> _termSearchCache = {};
  static const int _maxTermCache = 250;

  /// Bounded LRU in-memory cache for evaluated matching results.
  final Map<String, MetadataMatchResult> _matchCache = {};
  static const int _maxMatchCache = 600;

  /// In-flight request deduplication map.
  final Map<String, Future<MetadataMatchResult>> _inFlightMatches = {};

  /// Version tags that indicate specialized audio recordings.
  static const List<String> _specializedVersionTags = [
    'remix',
    'live',
    'acoustic',
    'instrumental',
    'orchestral',
    'cover',
    'karaoke',
    'slowed',
    'reverb',
    'sped up',
    'deluxe',
    'unplugged',
    'reprise',
    'extended',
    'radio edit',
  ];

  /// Promotional / video fluff tags stripped before iTunes querying.
  static final RegExp _videoFluffPattern = RegExp(
    r'\b(official\s*(music)?\s*video|official\s*audio|official\s*lyric\s*video|lyric\s*video|lyrical\s*video|full\s*video\s*song|video\s*song|visualizer|4k|hd|1080p|audio\s*track)\b',
    caseSensitive: false,
  );

  /// Performs raw iTunes Search API query with parameters:
  /// `term`, `entity=song`, `media=music`, `limit`.
  Future<List<ItunesSong>> searchSongs(String term, {int limit = 10}) async {
    final cleanTerm = term.trim();
    if (cleanTerm.isEmpty) return const [];

    final cacheKey = '${cleanTerm.toLowerCase()}_$limit';
    if (_termSearchCache.containsKey(cacheKey)) {
      return _termSearchCache[cacheKey]!;
    }

    try {
      final response = await _dio.get<dynamic>(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': cleanTerm,
          'entity': 'song',
          'media': 'music',
          'limit': limit,
        },
      );

      if (response.statusCode != 200 || response.data == null) {
        return const [];
      }

      final Map<String, dynamic> data;
      if (response.data is String) {
        data = jsonDecode(response.data as String) as Map<String, dynamic>;
      } else if (response.data is Map) {
        data = Map<String, dynamic>.from(response.data as Map);
      } else {
        return const [];
      }

      final rawResults = data['results'] as List<dynamic>? ?? const [];
      final songs = <ItunesSong>[];

      for (final item in rawResults) {
        if (item is Map) {
          final song = ItunesSong.fromJson(Map<String, dynamic>.from(item));
          if (song.trackId > 0 && song.trackName.isNotEmpty) {
            songs.add(song);
          }
        }
      }

      // Maintain cache capacity
      if (_termSearchCache.length >= _maxTermCache) {
        _termSearchCache.remove(_termSearchCache.keys.first);
      }
      _termSearchCache[cacheKey] = songs;

      return songs;
    } catch (e) {
      debugPrint('[ItunesMetadataService] Search API error for "$cleanTerm": $e');
      return const [];
    }
  }

  /// Evaluates and matches a song candidate against iTunes catalogue entries
  /// using normalized title, artist, album, duration, and version guards.
  Future<MetadataMatchResult> matchCandidate({
    required String rawTitle,
    required String rawArtist,
    String? durationStr,
    String? album,
  }) async {
    final cacheKey = _buildMatchCacheKey(rawTitle, rawArtist, durationStr, album);
    if (_matchCache.containsKey(cacheKey)) {
      return _matchCache[cacheKey]!;
    }

    if (_inFlightMatches.containsKey(cacheKey)) {
      return _inFlightMatches[cacheKey]!;
    }

    final future = _evaluateMatchInternal(
      rawTitle: rawTitle,
      rawArtist: rawArtist,
      durationStr: durationStr,
      album: album,
    ).whenComplete(() {
      _inFlightMatches.remove(cacheKey);
    });

    _inFlightMatches[cacheKey] = future;
    final result = await future;

    if (_matchCache.length >= _maxMatchCache) {
      _matchCache.remove(_matchCache.keys.first);
    }
    _matchCache[cacheKey] = result;

    return result;
  }

  Future<MetadataMatchResult> _evaluateMatchInternal({
    required String rawTitle,
    required String rawArtist,
    String? durationStr,
    String? album,
  }) async {
    // 1. Initial cleanup using universal YouTube metadata cleaner
    final cleaned = YouTubeMetadataCleaner.clean(
      rawTitle: rawTitle,
      rawChannel: rawArtist,
    );

    // 2. Strip video-specific fluff words from search query
    String queryTitle = cleaned.title.replaceAll(_videoFluffPattern, ' ');
    queryTitle = queryTitle.replaceAll(RegExp(r'\s+'), ' ').trim();

    String queryArtist = cleaned.artist.replaceAll(_videoFluffPattern, ' ');
    queryArtist = queryArtist.replaceAll(RegExp(r'\s+'), ' ').trim();

    // 3. Formulate search term
    String primaryTerm;
    if (queryArtist.isNotEmpty &&
        !queryArtist.toLowerCase().contains('unknown') &&
        !queryArtist.toLowerCase().contains('various')) {
      primaryTerm = '$queryTitle $queryArtist';
    } else {
      primaryTerm = queryTitle;
    }

    // 4. Query iTunes
    var candidates = await searchSongs(primaryTerm, limit: 8);

    // If no candidates and term had both title & artist, try title alone
    if (candidates.isEmpty && primaryTerm != queryTitle && queryTitle.isNotEmpty) {
      candidates = await searchSongs(queryTitle, limit: 6);
    }

    if (candidates.isEmpty) {
      return MetadataMatchResult.noMatch('No candidates found in iTunes catalogue');
    }

    // 5. Evaluate candidates against confidence criteria
    final int? targetDurationMs = _parseDurationToMs(durationStr);

    ItunesSong? bestSong;
    double highestScore = 0.0;
    String? bestDiagnostic;

    for (final candidate in candidates) {
      final scoreData = _scoreCandidate(
        queryTitle: cleaned.title,
        queryArtist: cleaned.artist,
        queryAlbum: album,
        targetDurationMs: targetDurationMs,
        candidate: candidate,
      );

      if (scoreData.score > highestScore) {
        highestScore = scoreData.score;
        bestSong = candidate;
        bestDiagnostic = scoreData.reason;
      }
    }

    // Strict confidence threshold: >= 0.80
    if (highestScore >= 0.80 && bestSong != null) {
      return MetadataMatchResult(
        isConfident: true,
        confidence: highestScore,
        itunesSong: bestSong,
        diagnosticReason: bestDiagnostic ?? 'Confident studio metadata match',
      );
    }

    return MetadataMatchResult.unconfident(
      confidence: highestScore,
      candidate: bestSong,
      reason: bestDiagnostic ?? 'Top candidate score (${highestScore.toStringAsFixed(2)}) fell below threshold 0.80',
    );
  }

  ({double score, String reason}) _scoreCandidate({
    required String queryTitle,
    required String queryArtist,
    String? queryAlbum,
    int? targetDurationMs,
    required ItunesSong candidate,
  }) {
    // 1. Version Compatibility Guard
    // If query has "remix" and candidate does not, or vice-versa, reject completely
    if (!_areVersionsCompatible(queryTitle, candidate.trackName)) {
      return (score: 0.0, reason: 'Incompatible version: remix/live/acoustic mismatch');
    }

    final normQueryTitle = ArtworkMatchValidator.normalize(queryTitle);
    final normCandTitle = ArtworkMatchValidator.normalize(candidate.trackName);
    final normQueryArtist = ArtworkMatchValidator.normalize(queryArtist);
    final normCandArtist = ArtworkMatchValidator.normalize(candidate.artistName);

    // 2. Title Similarity
    final titleSim = _calculateSimilarity(normQueryTitle, normCandTitle);
    if (titleSim < 0.65) {
      return (score: 0.0, reason: 'Title similarity too low (${titleSim.toStringAsFixed(2)})');
    }

    // 3. Artist Matching
    final artistSim = _calculateArtistSimilarity(normQueryArtist, normCandArtist);
    if (artistSim < 0.60) {
      // Check if candidate artist appears in the query title (common in movie/soundtrack tracks)
      final candInTitle = normQueryTitle.contains(normCandArtist) ||
          normCandArtist.split(' ').any((t) => t.length > 3 && normQueryTitle.contains(t));
      if (!candInTitle) {
        return (score: 0.0, reason: 'Artist mismatch ("$normQueryArtist" vs "$normCandArtist")');
      }
    }

    // 4. Duration Check
    double durationMultiplier = 1.0;
    if (targetDurationMs != null && candidate.trackTimeMillis != null) {
      final diffSeconds = (targetDurationMs - candidate.trackTimeMillis!).abs() / 1000;
      if (diffSeconds > 40) {
        // Discrepancy greater than 40s strongly suggests an extended video, medley or different version
        return (score: 0.0, reason: 'Duration discrepancy exceeds 40s (${diffSeconds.toStringAsFixed(0)}s)');
      } else if (diffSeconds > 15) {
        durationMultiplier = 0.85;
      }
    }

    // 5. Album Boost
    double albumBoost = 0.0;
    if (queryAlbum != null &&
        queryAlbum.isNotEmpty &&
        candidate.collectionName != null &&
        candidate.collectionName!.isNotEmpty) {
      final albumSim = _calculateSimilarity(
        ArtworkMatchValidator.normalize(queryAlbum),
        ArtworkMatchValidator.normalize(candidate.collectionName!),
      );
      if (albumSim > 0.75) {
        albumBoost = 0.08;
      }
    }

    // Final weighted score
    final effectiveArtistSim = artistSim > 0.60 ? artistSim : 0.75;
    double rawScore = (titleSim * 0.60) + (effectiveArtistSim * 0.40) + albumBoost;
    rawScore = (rawScore * durationMultiplier).clamp(0.0, 1.0);

    return (
      score: rawScore,
      reason: 'Title: ${titleSim.toStringAsFixed(2)}, Artist: ${effectiveArtistSim.toStringAsFixed(2)}',
    );
  }

  /// Matches a [YouTubeVideo] result and returns enriched metadata.
  Future<MetadataMatchResult> matchYouTubeVideo(YouTubeVideo video) {
    return matchCandidate(
      rawTitle: video.rawTitle ?? video.title,
      rawArtist: video.rawChannelTitle ?? video.channelTitle,
      durationStr: video.duration,
    );
  }

  /// Enriches a single [YouTubeVideo] with canonical iTunes metadata if confidently matched.
  Future<YouTubeVideo> enrichYouTubeVideo(YouTubeVideo video) async {
    try {
      final match = await matchYouTubeVideo(video);
      if (match.isConfident && match.itunesSong != null) {
        final song = match.itunesSong!;
        return video.copyWith(
          title: song.trackName,
          channelTitle: song.artistName,
          canonicalTitle: song.trackName,
          canonicalArtist: song.artistName,
          albumName: song.collectionName,
          highResArtworkUrl: song.highResArtworkUrl,
          metadataProvider: 'itunes',
          metadataIdentifier: song.trackId.toString(),
        );
      }
    } catch (e) {
      debugPrint('[ItunesMetadataService] Enrichment error for "${video.title}": $e');
    }
    return video;
  }

  /// Concurrently enriches a list of [YouTubeVideo] results with controlled parallelism.
  Future<List<YouTubeVideo>> enrichYouTubeResults(
    List<YouTubeVideo> videos, {
    int maxConcurrent = 5,
  }) async {
    if (videos.isEmpty) return const [];

    final enriched = List<YouTubeVideo>.filled(videos.length, videos.first);
    final chunks = <List<int>>[];
    for (int i = 0; i < videos.length; i += maxConcurrent) {
      final end = (i + maxConcurrent < videos.length) ? i + maxConcurrent : videos.length;
      chunks.add(List.generate(end - i, (index) => i + index));
    }

    for (final chunk in chunks) {
      await Future.wait(
        chunk.map((idx) async {
          enriched[idx] = await enrichYouTubeVideo(videos[idx]);
        }),
      );
    }

    return enriched;
  }

  /// Enriches an existing [Track] with iTunes canonical metadata if confidently matched.
  Future<Track> enrichTrack(Track track) async {
    // If track already has iTunes metadata, return unchanged
    if (track.metadataProvider == 'itunes' && track.albumName != null) {
      return track;
    }

    try {
      final match = await matchCandidate(
        rawTitle: track.rawTitle ?? track.title,
        rawArtist: track.rawArtist ?? track.artist,
        durationStr: track.duration,
        album: track.albumName,
      );

      if (match.isConfident && match.itunesSong != null) {
        final song = match.itunesSong!;
        return track.copyWith(
          title: song.trackName,
          artist: song.artistName,
          albumName: song.collectionName,
          imageUrl: song.highResArtworkUrl.isNotEmpty ? song.highResArtworkUrl : track.imageUrl,
          metadataProvider: 'itunes',
          metadataIdentifier: song.trackId.toString(),
          sourceProvider: track.sourceProvider ?? (track.isYoutube ? 'youtube' : 'local'),
          sourceId: track.sourceId ?? (track.isYoutube ? track.id.replaceFirst('youtube_', '') : null),
        );
      }
    } catch (_) {}

    return track;
  }

  bool _areVersionsCompatible(String queryTitle, String candidateTitle) {
    final qLower = queryTitle.toLowerCase();
    final cLower = candidateTitle.toLowerCase();

    for (final tag in _specializedVersionTags) {
      final qHas = qLower.contains(tag);
      final cHas = cLower.contains(tag);
      if (qHas != cHas) {
        return false;
      }
    }
    return true;
  }

  bool _matchTokens(Set<String> setA, Set<String> setB) {
    if (setA.isEmpty || setB.isEmpty) return false;
    if (setA.containsAll(setB) || setB.containsAll(setA)) return true;
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union > 0 && (intersection / union) >= 0.50;
  }

  double _calculateArtistSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final tokensA = a.split(' ').where((t) => t.length > 1).toSet();
    final tokensB = b.split(' ').where((t) => t.length > 1).toSet();

    if (_matchTokens(tokensA, tokensB)) return 0.95;

    return _calculateSimilarity(a, b);
  }

  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final tokensA = a.split(' ').where((t) => t.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((t) => t.isNotEmpty).toSet();

    final intersection = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    final jaccard = union == 0 ? 0.0 : intersection / union;

    final maxLen = a.length > b.length ? a.length : b.length;
    final lev = _levenshtein(a, b);
    final levSim = maxLen == 0 ? 1.0 : 1.0 - (lev / maxLen);

    return (jaccard * 0.4) + (levSim * 0.6);
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < v0.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        final a = v1[j] + 1;
        final b = v0[j + 1] + 1;
        final c = v0[j] + cost;
        v1[j + 1] = a < b ? (a < c ? a : c) : (b < c ? b : c);
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }

  int? _parseDurationToMs(String? duration) {
    if (duration == null || duration.trim().isEmpty) return null;
    final parts = duration.trim().split(':');
    if (parts.length == 2) {
      final mins = int.tryParse(parts[0]) ?? 0;
      final secs = int.tryParse(parts[1]) ?? 0;
      return ((mins * 60) + secs) * 1000;
    } else if (parts.length == 3) {
      final hrs = int.tryParse(parts[0]) ?? 0;
      final mins = int.tryParse(parts[1]) ?? 0;
      final secs = int.tryParse(parts[2]) ?? 0;
      return ((hrs * 3600) + (mins * 60) + secs) * 1000;
    }
    return null;
  }

  String _buildMatchCacheKey(String title, String artist, String? duration, String? album) {
    return '${title.trim().toLowerCase()}_${artist.trim().toLowerCase()}_${duration ?? ''}_${album ?? ''}';
  }

  /// Clears in-memory caches.
  void clearCache() {
    _termSearchCache.clear();
    _matchCache.clear();
  }
}
