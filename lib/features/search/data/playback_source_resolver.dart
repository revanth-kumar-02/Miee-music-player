import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../../core/network/network_request_coordinator.dart';
import '../../recommendations/domain/music_language_service.dart';
import '../../youtube/domain/youtube_metadata_cleaner.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/data/youtube_repository.dart';
import '../domain/query_relevance_evaluator.dart';

/// Playback Source Resolver.
///
/// Bridges the music-first discovery architecture with audio playback by resolving
/// authentic, high-fidelity YouTube audio streams for verified music recordings.
///
/// Replaces arbitrary general YouTube search by executing targeted queries
/// (e.g. `"$artist - $title (Official Audio)"`) with confidence-based fallback
/// to clean queries, rigorously scoring candidates against canonical recording
/// duration (with short-track tolerance), strict word-boundary title-token
/// identity, Topic channels, VEVO, and verified labels.
class PlaybackSourceResolver {
  static final PlaybackSourceResolver _instance =
      PlaybackSourceResolver._internal();
  factory PlaybackSourceResolver({YouTubeRepository? youtubeRepository}) {
    if (youtubeRepository != null) {
      return PlaybackSourceResolver.withRepository(youtubeRepository);
    }
    return _instance;
  }

  PlaybackSourceResolver._internal() : _youtubeRepository = YouTubeRepository();

  PlaybackSourceResolver.withRepository(YouTubeRepository repository)
      : _youtubeRepository = repository;

  final YouTubeRepository _youtubeRepository;

  /// Bounded LRU in-memory cache mapping canonical recording keys to resolved YouTube candidates.
  final Map<String, YouTubeVideo> _resolvedCandidateCache = {};
  static const int _maxCacheSize = 300;

  /// In-flight request deduplication map to prevent redundant parallel searches.
  final Map<String, Future<YouTubeVideo?>> _inFlightResolutions = {};

  /// Session-scoped temporarily failed video IDs (e.g. broken stream / PlayerException)
  /// so subsequent resolution attempts avoid selecting the same broken video ID again.
  final Map<String, DateTime> _failedVideoIds = {};
  static const Duration _failedVideoTtl = Duration(minutes: 5);

  /// Records a [videoId] as failed for the current resolution TTL and evicts any
  /// cached recording pointing to it.
  void markVideoFailed(String videoId) {
    final cleanId = videoId.trim();
    if (!isValidYouTubeVideoId(cleanId)) return;
    _failedVideoIds[cleanId] = DateTime.now().add(_failedVideoTtl);
    _resolvedCandidateCache.removeWhere((_, v) => v.id == cleanId);
  }

  Set<String> _activeFailedVideoIds() {
    if (_failedVideoIds.isEmpty) return const {};
    final now = DateTime.now();
    _failedVideoIds.removeWhere((_, expiry) => now.isAfter(expiry));
    return _failedVideoIds.keys.toSet();
  }

  /// Minimum acceptable candidate score required before returning a resolved recording.
  static const int _minAcceptableScore = 30;

  /// High-confidence score threshold allowing early exit without exhausting all query fallbacks.
  static const int _highConfidenceEarlyStopScore = 110;

  /// Verified record label channels prioritized during candidate scoring.
  static const List<String> _officialMusicLabels = [
    'sony music',
    't-series',
    'zee music',
    'aditya music',
    'think music',
    'speed records',
    'tips official',
    'universal music',
    'warner music',
    'interscope',
    'atlantic records',
    'columbia records',
    'republic records',
    'rca records',
    'epic records',
    'def jam',
    'virgin records',
    'lahari music',
    'sun tv',
    'yrf',
    'divo music',
    'saregama',
    'tips',
  ];

  static const Set<String> _glueStopWords = {
    'a',
    'an',
    'the',
    'of',
    'in',
    'on',
    'at',
    'to',
    'for',
    'from',
    'by',
    'with',
    'and',
    'or',
  };

  static const Set<String> _packagingDescriptors = {
    'official',
    'audio',
    'video',
    'music',
    'lyric',
    'lyrics',
    'lyrical',
    'visualizer',
    'full',
    'song',
    'songs',
    'hd',
    '4k',
    'uhd',
    'hq',
    'clean',
    'explicit',
    'tamil',
    'telugu',
    'hindi',
    'malayalam',
    'kannada',
    'punjabi',
    'english',
    'version',
    'remaster',
    'remastered',
  };

  static const Set<String> _distinctVersionMarkers = {
    'unplugged',
    'acoustic',
    'reprise',
    'live',
    'remix',
    'lofi',
    'instrumental',
    'karaoke',
    'cover',
    'slowed',
    'reverb',
    'sped',
    'nightcore',
    'mashup',
    'medley',
    'orchestral',
    'symphony',
    'suite',
    'overture',
    'jukebox',
  };

  /// Returns true if [id] represents a real 11-character YouTube video ID
  /// rather than an external catalog/discovery identifier (`itunes_`, `mb_`, `wm_`, `saavn_`).
  static bool isValidYouTubeVideoId(String id) {
    var clean = id.trim();
    if (clean.startsWith('youtube_')) {
      clean = clean.substring('youtube_'.length).trim();
    }
    if (clean.isEmpty) return false;
    if (clean.startsWith('itunes_') ||
        clean.startsWith('mb_') ||
        clean.startsWith('wm_') ||
        clean.startsWith('saavn_')) {
      return false;
    }
    return RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean);
  }

  /// Returns true when [durationStr] contains a concrete, non-placeholder duration.
  static bool hasConcreteDuration(String? durationStr) {
    if (durationStr == null) return false;
    final trimmed = durationStr.trim();
    if (trimmed.isEmpty ||
        trimmed == '0:00' ||
        trimmed == '00:00' ||
        trimmed == '00:00:00') {
      return false;
    }
    return _parseDurationSeconds(trimmed) > 0;
  }

  /// Resolves the optimal YouTube video ID for a canonical music recording.
  Future<String?> resolveVideoId({
    required String title,
    required String artist,
    String? durationStr,
    int? durationMs,
    String? album,
  }) async {
    final candidate = await resolveCandidate(
      title: title,
      artist: artist,
      durationStr: durationStr,
      durationMs: durationMs,
      album: album,
    );
    return candidate?.id;
  }

  /// Resolves the full optimal [YouTubeVideo] candidate for a canonical music recording.
  Future<YouTubeVideo?> resolveCandidate({
    required String title,
    required String artist,
    String? durationStr,
    int? durationMs,
    String? album,
    Set<String> excludeVideoIds = const {},
  }) async {
    final cleanTitle = _cleanQueryText(title);
    final cleanArtist = _cleanQueryText(artist);
    final cleanAlbum = album != null ? _cleanQueryText(album) : null;
    if (cleanTitle.isEmpty) return null;

    final targetSec = _parseTargetDurationSeconds(
      durationStr: durationStr,
      durationMs: durationMs,
    );
    final cacheKey = _buildCanonicalKey(
      cleanTitle,
      cleanArtist,
      targetDurationSec: targetSec,
    );

    final effectiveExcludeIds = <String>{
      ...excludeVideoIds,
      ..._activeFailedVideoIds(),
    };

    if (_resolvedCandidateCache.containsKey(cacheKey)) {
      final cached = _resolvedCandidateCache[cacheKey]!;
      if (!effectiveExcludeIds.contains(cached.id)) {
        debugPrint(
            '[PlaybackSourceResolver] Cache HIT for $cacheKey -> ${cached.id}');
        return cached;
      }
      debugPrint(
          '[PlaybackSourceResolver] Cache SKIPPED for $cacheKey (excluded ${cached.id})');
    }

    if (effectiveExcludeIds.isEmpty &&
        _inFlightResolutions.containsKey(cacheKey)) {
      return await _inFlightResolutions[cacheKey]!;
    }

    final future = _resolveCandidateInternal(
      cleanTitle: cleanTitle,
      cleanArtist: cleanArtist,
      targetSec: targetSec,
      album: cleanAlbum,
      excludeVideoIds: effectiveExcludeIds,
    ).whenComplete(() {
      if (effectiveExcludeIds.isEmpty) {
        _inFlightResolutions.remove(cacheKey);
      }
    });

    if (effectiveExcludeIds.isEmpty) {
      _inFlightResolutions[cacheKey] = future;
    }
    final resolved = await future;

    if (resolved != null &&
        isValidYouTubeVideoId(resolved.id) &&
        !effectiveExcludeIds.contains(resolved.id)) {
      if (_resolvedCandidateCache.length >= _maxCacheSize) {
        _resolvedCandidateCache.remove(_resolvedCandidateCache.keys.first);
      }
      _resolvedCandidateCache[cacheKey] = resolved;
    }

    return resolved;
  }

  /// Resolves audio playback source for an existing canonical [YouTubeVideo] instance,
  /// updating its [id] to the resolved 11-character YouTube video ID.
  Future<YouTubeVideo> resolveSourceTrack(YouTubeVideo canonicalVideo) async {
    if (isValidYouTubeVideoId(canonicalVideo.id)) {
      return canonicalVideo;
    }

    final resolved = await resolveCandidate(
      title: canonicalVideo.canonicalTitle ?? canonicalVideo.title,
      artist: canonicalVideo.canonicalArtist ?? canonicalVideo.channelTitle,
      durationStr: canonicalVideo.duration,
      album: canonicalVideo.albumName,
    );

    if (resolved != null && isValidYouTubeVideoId(resolved.id)) {
      return canonicalVideo.copyWith(id: resolved.id);
    }

    return canonicalVideo;
  }

  /// Selects the best matching [YouTubeVideo] from a pre-fetched [candidates] list
  /// using the unified duration, title-token, and artist/channel validation rules.
  YouTubeVideo? selectBestCandidate(
    List<YouTubeVideo> candidates, {
    required String title,
    required String artist,
    String? durationStr,
    int? durationMs,
    String? album,
  }) {
    final cleanTitle = _cleanQueryText(title);
    final cleanArtist = _cleanQueryText(artist);
    final cleanAlbum = album != null ? _cleanQueryText(album) : null;
    if (cleanTitle.isEmpty || candidates.isEmpty) return null;

    final targetSec = _parseTargetDurationSeconds(
      durationStr: durationStr,
      durationMs: durationMs,
    );

    final scored = _pickBestScoredCandidate(
      candidates: candidates,
      cleanTitle: cleanTitle,
      cleanArtist: cleanArtist,
      targetDurationSec: targetSec,
      album: cleanAlbum,
    );

    if (scored != null && isValidYouTubeVideoId(scored.video.id)) {
      return scored.video;
    }
    return null;
  }

  /// Evaluates a pre-fetched candidate list against a raw single-string query
  /// (when structured `title`/`artist` fields were not separated), preventing
  /// blind acceptance of unrelated tracks from the same album or artist.
  YouTubeVideo? selectBestCandidateForRawQuery(
    List<YouTubeVideo> candidates, {
    required String query,
    String? expectedDuration,
    String? album,
  }) {
    final cleanQuery = _cleanQueryText(query);
    if (cleanQuery.isEmpty || candidates.isEmpty) return null;

    // If query uses "Artist - Title" format, split directly
    for (final sep in const [' - ', ' – ', ' — ']) {
      if (cleanQuery.contains(sep)) {
        final idx = cleanQuery.indexOf(sep);
        final left = cleanQuery.substring(0, idx).trim();
        final right = cleanQuery.substring(idx + sep.length).trim();
        if (left.isNotEmpty && right.isNotEmpty) {
          final forward = selectBestCandidate(
            candidates,
            title: right,
            artist: left,
            durationStr: expectedDuration,
            album: album,
          );
          if (forward != null) return forward;

          // Also consider "Title - Artist" ordering
          final reverse = selectBestCandidate(
            candidates,
            title: left,
            artist: right,
            durationStr: expectedDuration,
            album: album,
          );
          if (reverse != null) return reverse;
        }
      }
    }

    final targetSec =
        _parseTargetDurationSeconds(durationStr: expectedDuration);
    final queryTokens = _tokenizeTitle(cleanQuery)
        .where((t) => !_packagingDescriptors.contains(t))
        .toList();
    if (queryTokens.isEmpty) return null;

    _ScoredCandidate? best;
    for (final candidate in candidates) {
      if (!isValidYouTubeVideoId(candidate.id)) continue;

      final candChan =
          (candidate.rawChannelTitle ?? candidate.channelTitle).trim();
      final candSongTitle = extractCandidateSongTitle(
        candidate.rawTitle ?? candidate.title,
        candChan,
      );
      final candSongTokens = _tokenizeTitle(candSongTitle).toSet();
      final candChanTokens = _tokenizeTitle(
        YouTubeMetadataCleaner.clean(
          rawTitle: candidate.rawTitle ?? candidate.title,
          rawChannel: candChan,
        ).artist,
      ).toSet();
      candChanTokens.addAll(_tokenizeTitle(candChan));

      // Exclude tokens from the query that identify the artist/channel so we verify
      // the remaining track-title tokens actually match the candidate's song title.
      final titleOnlyTokens =
          queryTokens.where((t) => !candChanTokens.contains(t)).toList();
      final effectiveTitleTokens =
          titleOnlyTokens.isNotEmpty ? titleOnlyTokens : queryTokens;

      final inferredTitle = effectiveTitleTokens.join(' ');
      final inferredArtistTokens =
          queryTokens.where((t) => candChanTokens.contains(t)).toList();
      final inferredArtist = inferredArtistTokens.join(' ');

      final candScore = _evaluateCandidate(
        candidate: candidate,
        cleanTitle: inferredTitle,
        cleanArtist: inferredArtist,
        targetDurationSec: targetSec,
        album: album,
      );

      // Extra guard: if no explicit expectedTitle was passed and inferredTitle collapsed,
      // require at least one concrete song token match inside candSongTokens.
      final hasDirectTitleTokenMatch = effectiveTitleTokens.any(
          (t) => !_glueStopWords.contains(t) && candSongTokens.contains(t));

      if (!hasDirectTitleTokenMatch && candScore.titleScore < 50) {
        continue;
      }

      if (candScore.score >= _minAcceptableScore &&
          candScore.titleScore > 0 &&
          isDurationCompatible(
            targetDurationSec: targetSec,
            candidateDurationStr: candidate.duration,
          )) {
        if (best == null ||
            candScore.score > best.score ||
            (candScore.score == best.score &&
                candScore.titleScore > best.titleScore)) {
          best = _ScoredCandidate(
              candidate, candScore.score, candScore.titleScore);
        }
      }
    }

    return best?.video;
  }

  /// Validates whether a candidate's duration is compatible with the canonical
  /// target duration before committing to stream loading.
  static bool isDurationCompatible({
    String? targetDurationStr,
    int? targetDurationMs,
    int? targetDurationSec,
    String? candidateDurationStr,
  }) {
    final targetSec = targetDurationSec ??
        _parseTargetDurationSeconds(
          durationStr: targetDurationStr,
          durationMs: targetDurationMs,
        );
    final candSec = candidateDurationStr != null
        ? _parseDurationSeconds(candidateDurationStr)
        : 0;

    if (targetSec <= 0 || candSec <= 0) return true;

    final diff = (candSec - targetSec).abs();
    if (targetSec < 90) {
      // Short tracks (<90s) allow small metadata rounding or brief intro/outro variance,
      // but reject major proportional discrepancies (e.g. 78s vs 43s -> diff 35s).
      return diff <= 20;
    }

    // Standard full tracks (>=90s): reject <60s teaser/promo clips and huge length mismatches
    if (candSec < 60) return false;
    final maxAllowedDiff = math.max(90, (targetSec * 0.65).round());
    return diff <= maxAllowedDiff;
  }

  Future<YouTubeVideo?> _resolveCandidateInternal({
    required String cleanTitle,
    required String cleanArtist,
    required int targetSec,
    String? album,
    Set<String> excludeVideoIds = const {},
  }) async {
    final queries = _buildSearchQueries(
      cleanTitle: cleanTitle,
      cleanArtist: cleanArtist,
      album: album,
    );

    final seenCandidateIds = <String>{};
    final accumulatedCandidates = <YouTubeVideo>[];
    _ScoredCandidate? bestOverall;

    for (var qIndex = 0; qIndex < queries.length; qIndex++) {
      final query = queries[qIndex];
      final label = qIndex == 0 ? 'Primary search' : 'Fallback search #$qIndex';
      debugPrint(
          '[PlaybackSourceResolver] $label: "$query" (targetDur: ${targetSec}s)');

      final batch = await _executeSearch(query);
      if (batch.isEmpty) {
        debugPrint('[PlaybackSourceResolver] Query "$query" returned 0 items');
        continue;
      }

      for (final c in batch) {
        if (seenCandidateIds.add(c.id)) {
          accumulatedCandidates.add(c);
        }
      }

      final batchBest = _pickBestScoredCandidate(
        candidates: batch,
        cleanTitle: cleanTitle,
        cleanArtist: cleanArtist,
        targetDurationSec: targetSec,
        album: album,
        excludeVideoIds: excludeVideoIds,
      );

      if (batchBest != null) {
        if (bestOverall == null ||
            batchBest.score > bestOverall.score ||
            (batchBest.score == bestOverall.score &&
                batchBest.titleScore > bestOverall.titleScore)) {
          bestOverall = batchBest;
        }

        // Only stop searching early when we have an unambiguous, high-confidence match
        // (strong title match + Artist/Duration/Label corroboration).
        // If candidates only achieved marginal score (or none matched), keep executing cleaner queries.
        if (bestOverall.score >= _highConfidenceEarlyStopScore &&
            bestOverall.titleScore >= 60) {
          debugPrint(
              '[PlaybackSourceResolver] High-confidence match found on query #$qIndex: "${bestOverall.video.title}" (${bestOverall.video.id}) score: ${bestOverall.score}');
          return bestOverall.video;
        }
      }
    }

    // Final evaluation over all accumulated candidates across all executed queries
    if (bestOverall != null && isValidYouTubeVideoId(bestOverall.video.id)) {
      debugPrint(
          '[PlaybackSourceResolver] SELECTED: "${bestOverall.video.title}" (${bestOverall.video.id}) score: ${bestOverall.score} (titleScore: ${bestOverall.titleScore})');
      return bestOverall.video;
    }

    debugPrint(
        '[PlaybackSourceResolver] No confident match for "$cleanTitle" by "$cleanArtist" across ${accumulatedCandidates.length} candidates');
    return null;
  }

  List<String> _buildSearchQueries({
    required String cleanTitle,
    required String cleanArtist,
    String? album,
  }) {
    final coreTitle = extractCoreTitle(cleanTitle);
    final effectiveTitle = coreTitle.isNotEmpty ? coreTitle : cleanTitle;
    final artistTokens = _extractArtistTokens(cleanArtist);
    final primaryArtist =
        artistTokens.isNotEmpty ? artistTokens.first : cleanArtist;

    final rawQueries = <String>[
      // 1. Primary Targeted Query: Artist + Core Title + Official Audio
      if (cleanArtist.isNotEmpty)
        '$cleanArtist - $effectiveTitle (Official Audio)'
      else
        '$effectiveTitle (Official Audio)',

      // 2. Clean Natural Query without synthetic "(Official Audio)" noise
      // (often resolves exact Topic uploads or short interludes missed by Query 1)
      if (cleanArtist.isNotEmpty)
        '$cleanArtist $effectiveTitle'
      else
        effectiveTitle,

      // 3. Primary Artist + Core Title (when multi-artist metadata has feat/commas)
      if (primaryArtist.isNotEmpty &&
          primaryArtist.toLowerCase() != cleanArtist.toLowerCase())
        '$primaryArtist $effectiveTitle',

      // 4. Title + Album (helps soundtrack recordings uploaded under label channels)
      if (album != null && album.isNotEmpty) ...[
        if (extractCoreTitle(album).isNotEmpty &&
            extractCoreTitle(album).toLowerCase() !=
                effectiveTitle.toLowerCase())
          '$effectiveTitle ${extractCoreTitle(album)}'
              '${primaryArtist.isNotEmpty ? ' $primaryArtist' : ''}',
      ],

      // 5. Full Clean Title + Artist (if coreTitle stripped useful subtitle modifiers)
      if (coreTitle.isNotEmpty &&
          coreTitle.toLowerCase() != cleanTitle.toLowerCase())
        (cleanArtist.isNotEmpty ? '$cleanArtist $cleanTitle' : cleanTitle),

      // 6. Effective Title alone as clean fallback when artist name formatting differs on YouTube
      if (cleanArtist.isNotEmpty) effectiveTitle,
    ];

    final deduped = <String>[];
    final seen = <String>{};
    for (final q in rawQueries) {
      final cleaned = _cleanQueryText(q);
      if (cleaned.isNotEmpty && seen.add(cleaned.toLowerCase())) {
        deduped.add(cleaned);
      }
    }
    return deduped;
  }

  _ScoredCandidate? _pickBestScoredCandidate({
    required List<YouTubeVideo> candidates,
    required String cleanTitle,
    required String cleanArtist,
    required int targetDurationSec,
    String? album,
    Set<String> excludeVideoIds = const {},
  }) {
    _ScoredCandidate? best;
    for (final candidate in candidates) {
      if (!isValidYouTubeVideoId(candidate.id)) continue;
      if (excludeVideoIds.contains(candidate.id)) continue;

      final candScore = _evaluateCandidate(
        candidate: candidate,
        cleanTitle: cleanTitle,
        cleanArtist: cleanArtist,
        targetDurationSec: targetDurationSec,
        album: album,
      );

      final durationOk = isDurationCompatible(
        targetDurationSec: targetDurationSec,
        candidateDurationStr: candidate.duration,
      );

      debugPrint(
          '[PlaybackSourceResolver] Candidate: "${candidate.title}" [chan: "${candidate.channelTitle}", dur: ${candidate.duration}] -> score: ${candScore.score} (titleScore: ${candScore.titleScore}, durationOk: $durationOk)');

      if (candScore.titleScore > 0 &&
          candScore.score >= _minAcceptableScore &&
          durationOk) {
        if (best == null ||
            candScore.score > best.score ||
            (candScore.score == best.score &&
                candScore.titleScore > best.titleScore)) {
          best = _ScoredCandidate(
              candidate, candScore.score, candScore.titleScore);
        }
      }
    }
    return best;
  }

  Future<List<YouTubeVideo>> _executeSearch(String query) async {
    try {
      return await _youtubeRepository.search(
        query,
        page: 1,
        forceFresh: false,
        priority: NetworkPriority.playbackResolution,
      );
    } catch (e) {
      debugPrint(
          '[PlaybackSourceResolver] YouTube search error for "$query": $e');
      return const [];
    }
  }

  @visibleForTesting
  CandidateScore evaluateCandidateInternal({
    required YouTubeVideo candidate,
    required String cleanTitle,
    required String cleanArtist,
    required int targetDurationSec,
    String? album,
  }) =>
      _evaluateCandidate(
        candidate: candidate,
        cleanTitle: cleanTitle,
        cleanArtist: cleanArtist,
        targetDurationSec: targetDurationSec,
        album: album,
      );

  CandidateScore _evaluateCandidate({
    required YouTubeVideo candidate,
    required String cleanTitle,
    required String cleanArtist,
    required int targetDurationSec,
    String? album,
  }) {
    int score = 0;

    final rawCandTitle = (candidate.rawTitle ?? candidate.title).trim();
    final rawCandChannel =
        (candidate.rawChannelTitle ?? candidate.channelTitle).trim();
    final titleLower = rawCandTitle.toLowerCase();
    final channelLower = rawCandChannel.toLowerCase();
    final normTitle = cleanTitle.toLowerCase();
    final normArtist = cleanArtist.toLowerCase();

    // 1. Duration Evaluation (strictly ordered from extreme deviations down; zero unreachable branches)
    final candidateSec = _parseDurationSeconds(candidate.duration);
    if (targetDurationSec > 0 && candidateSec > 0) {
      final diff = (candidateSec - targetDurationSec).abs();
      if (targetDurationSec < 90) {
        // Short-track-aware scoring (< 90 seconds):
        // Proportional variance matters much more for short tracks/interludes/themes.
        if (diff > 60) {
          score -= 140;
        } else if (diff > 25) {
          score -= 110;
        } else if (diff > 15) {
          score -= 80;
        } else if (diff <= 3) {
          score += 60;
        } else if (diff <= 8) {
          score += 35;
        } else {
          score += 10; // 9s..15s acceptable tolerance
        }
      } else {
        // Standard full-length track scoring (>= 90 seconds)
        if (diff > 120) {
          score -= 100;
        } else if (diff > 60) {
          score -= 60;
        } else if (diff > 30) {
          score -= 20;
        } else if (diff <= 4) {
          score += 60; // Near-perfect duration match
        } else if (diff <= 10) {
          score += 40; // High confidence duration
        } else if (diff <= 20) {
          score += 20; // Acceptable tolerance
        }

        if (candidateSec < 60) {
          score -=
              150; // Heavy penalty for teaser/promo clips when resolving full song
        }
      }
    }

    // 2. Strict Track Title Identity Evaluation (never compensated by artist/album match)
    final candSongTitle = extractCandidateSongTitle(
      rawCandTitle,
      rawCandChannel,
      cleanArtist: cleanArtist,
    );
    final titleEval = _evaluateTitleMatch(
      targetTitle: cleanTitle,
      candidateSongTitle: candSongTitle,
      rawCandidateTitle: rawCandTitle,
      cleanArtist: cleanArtist,
      album: album,
    );
    final int titleScore = titleEval;
    score += titleScore;

    // 3. Channel & Artist Authority (cannot rescue a negative titleScore)
    final artistTokens = _extractArtistTokens(cleanArtist);
    bool artistMatchedChannel = false;
    bool artistMatchedTitle = false;

    final normChannelNoSpace = _normalizeForComparison(channelLower);
    if (normArtist.isNotEmpty &&
        (channelLower.contains(normArtist) ||
            (normChannelNoSpace.length >= 5 &&
                _normalizeForComparison(normArtist).length >= 5 &&
                normChannelNoSpace
                    .contains(_normalizeForComparison(normArtist))))) {
      score += 40;
      artistMatchedChannel = true;
    } else {
      for (final token in artistTokens) {
        final normTok = _normalizeForComparison(token);
        if (_containsWordOrToken(channelLower, token) ||
            (normTok.length >= 5 && normChannelNoSpace.contains(normTok))) {
          score += 35;
          artistMatchedChannel = true;
          break;
        }
      }
    }

    for (final token in artistTokens) {
      if (_containsWordOrToken(titleLower, token)) {
        score += 15;
        artistMatchedTitle = true;
        break;
      }
    }

    if (channelLower.endsWith('- topic') || channelLower.contains('- topic')) {
      score +=
          90; // YouTube Music official auto-generated topic channel (studio audio)
    }
    if (channelLower.contains('vevo') || channelLower.contains('official')) {
      score += 40;
    }
    if (_isKnownLabel(channelLower)) {
      score += 35;
    }

    // 4. Audio / Video Signal in Title
    if (titleLower.contains('official audio')) {
      score += 45;
    } else if (titleLower.contains('official music video') ||
        titleLower.contains('official video')) {
      score += 20;
    } else if (titleLower.contains('official lyric video') ||
        titleLower.contains('lyric video') ||
        titleLower.contains('lyrical')) {
      score += 25;
    } else if (titleLower.contains('audio')) {
      score += 15;
    }

    // 5. Content Negative Cues (Banned/Penalized Content)
    final isExplicitCover = normTitle.contains('cover');
    final isExplicitKaraoke = normTitle.contains('karaoke');
    final isExplicitLive = normTitle.contains('live');
    final isExplicitRemix = normTitle.contains('remix');
    final isExplicitUnplugged = normTitle.contains('unplugged');
    final isExplicitAcoustic = normTitle.contains('acoustic');
    final isExplicitReprise = normTitle.contains('reprise');
    final isExplicitLofi = normTitle.contains('lofi');

    if (!isExplicitCover && _containsWordOrToken(titleLower, 'cover')) {
      score -= 120;
    }
    if (!isExplicitKaraoke && _containsWordOrToken(titleLower, 'karaoke')) {
      score -= 140;
    }
    if (!isExplicitLive &&
        (_containsWordOrToken(titleLower, 'live') ||
            titleLower.contains('live at') ||
            titleLower.contains('concert'))) {
      score -= 50;
    } else if (isExplicitLive &&
        (_containsWordOrToken(titleLower, 'live') ||
            titleLower.contains('live at') ||
            titleLower.contains('concert'))) {
      score += 40;
    }
    if (!normTitle.contains('instrumental') &&
        _containsWordOrToken(titleLower, 'instrumental')) {
      score -= 80;
    }
    if (!isExplicitUnplugged && _containsWordOrToken(titleLower, 'unplugged')) {
      score -= 40;
    }
    if (!isExplicitAcoustic && _containsWordOrToken(titleLower, 'acoustic')) {
      score -= 35;
    }
    if (!isExplicitReprise && _containsWordOrToken(titleLower, 'reprise')) {
      score -= 35;
    }
    if (!isExplicitLofi && _containsWordOrToken(titleLower, 'lofi')) {
      score -= 45;
    }
    if (!normTitle.contains('reaction') &&
        _containsWordOrToken(titleLower, 'reaction')) {
      score -= 150;
    }
    if (!normTitle.contains('scene') &&
        (_containsWordOrToken(titleLower, 'scene') ||
            titleLower.contains('movie clip') ||
            titleLower.contains('scene clip') ||
            titleLower.contains('film scene') ||
            titleLower.contains('ending scene') ||
            titleLower.contains('fight scene') ||
            titleLower.contains('soundtrack scene') ||
            titleLower.contains('full movie'))) {
      score -= 150;
    }
    if (!normTitle.contains('slowed') &&
        (titleLower.contains('slowed') ||
            titleLower.contains('sped up') ||
            titleLower.contains('reverb') ||
            titleLower.contains('bass boosted') ||
            RegExp(r'\b8d\b', caseSensitive: false).hasMatch(titleLower))) {
      score -= 80;
    }
    if (!normTitle.contains('audio edit') &&
        !normTitle.contains('re-edit') &&
        (titleLower.contains('audio edit') ||
            titleLower.contains('(edit)') ||
            titleLower.contains('[edit]'))) {
      score -= 75;
    }
    if (!isExplicitRemix && _containsWordOrToken(titleLower, 'remix')) {
      score -= 40;
    } else if (isExplicitRemix && _containsWordOrToken(titleLower, 'remix')) {
      score += 40;
    }

    // 6. Language & Dubbing Consistency Check:
    // Penalize unrequested regional dub markers (e.g. "[Telugu]", "(Hindi Version)")
    // or explicit language conflicts with the canonical track artist/metadata so a
    // dubbed version does not silently replace the requested recording.
    final explicitLanguageConflict = _detectUnrequestedLanguageConflict(
      cleanTitle: cleanTitle,
      cleanArtist: cleanArtist,
      album: album,
      rawCandidateTitle: rawCandTitle,
      rawCandidateChannel: rawCandChannel,
    );
    if (explicitLanguageConflict) {
      score -= 180;
    }

    // Require either artist or channel or title alignment when no label channel verified
    if (!artistMatchedChannel &&
        !artistMatchedTitle &&
        !_isKnownLabel(channelLower)) {
      score -= 45;
    }

    return CandidateScore(score: score, titleScore: titleScore);
  }

  bool _detectUnrequestedLanguageConflict({
    required String cleanTitle,
    required String cleanArtist,
    String? album,
    required String rawCandidateTitle,
    required String rawCandidateChannel,
  }) {
    final targetContext =
        '${cleanTitle.toLowerCase()} ${(album ?? '').toLowerCase()} ${cleanArtist.toLowerCase()}';
    const languages = [
      'tamil',
      'telugu',
      'hindi',
      'malayalam',
      'kannada',
      'punjabi',
      'bengali',
      'marathi',
      'english',
    ];

    final requestedLangs = <String>{};
    for (final lang in languages) {
      if (RegExp('\\b$lang\\b', caseSensitive: false).hasMatch(targetContext)) {
        requestedLangs.add(lang);
      }
    }

    final targetArtistLang =
        MusicLanguageService.detectLanguage(cleanTitle, artist: cleanArtist)
            .toLowerCase();
    if (targetArtistLang != 'unknown') {
      requestedLangs.add(targetArtistLang);
    }

    final candLower = rawCandidateTitle.toLowerCase();
    for (final lang in languages) {
      if (requestedLangs.contains(lang)) continue;

      final isBracketedOrDub = RegExp(
        '(\\[\\s*$lang\\b|\\(\\s*$lang\\b|\\b$lang\\s+(?:version|ver|dub|dubbed|song|audio|video)\\b|[\\-\\–\\|]\\s*$lang\\s*\$)',
        caseSensitive: false,
      ).hasMatch(candLower);
      if (isBracketedOrDub) {
        // Explicit bracketed dubbing/version tag in another language when unrequested
        // is always a mismatch unless it matches the artist's known sole language.
        return true;
      }

      if (targetArtistLang != 'unknown') {
        final candDetected = MusicLanguageService.detectLanguage(
          rawCandidateTitle,
          channelTitle: rawCandidateChannel,
        ).toLowerCase();
        if (candDetected == lang && candDetected != targetArtistLang) {
          return true;
        }
      }
    }
    return false;
  }

  /// Evaluates requested song title identity solely against the candidate's
  /// extracted song title (excluding cast, movie/album, or director credits after `|`).
  ///
  /// Uses word-boundary token comparison (never blind `.contains()` substring matching
  /// that causes false hits like matching `"this"` inside `"Keerthiswaran"`).
  int _evaluateTitleMatch({
    required String targetTitle,
    required String candidateSongTitle,
    required String rawCandidateTitle,
    required String cleanArtist,
    String? album,
  }) {
    final cleanTargetCore = extractCoreTitle(targetTitle);
    final effectiveTarget =
        cleanTargetCore.isNotEmpty ? cleanTargetCore : targetTitle;

    final normCleanTarget = _normalizeForComparison(targetTitle);
    final normCoreTarget = _normalizeForComparison(effectiveTarget);
    final normCandSong = _normalizeForComparison(candidateSongTitle);
    final candCoreOfSong = extractCoreTitle(candidateSongTitle);
    final normCandCoreOfSong = _normalizeForComparison(candCoreOfSong);

    if (normCoreTarget.isEmpty || normCandSong.isEmpty) {
      return -80;
    }

    // 1. Exact canonical/core song title match
    if (normCandSong == normCleanTarget ||
        normCandSong == normCoreTarget ||
        normCandCoreOfSong == normCoreTarget ||
        normCandCoreOfSong == normCleanTarget) {
      return 80;
    }

    final targetTokens = _tokenizeTitle(effectiveTarget);
    if (targetTokens.isEmpty) return -80;

    final candTokens = _tokenizeTitle(
      candCoreOfSong.isNotEmpty ? candCoreOfSong : candidateSongTitle,
    );
    if (candTokens.isEmpty) return -90;

    final candTokenSet = candTokens.toSet();
    final targetTokenSet = targetTokens.toSet();

    // Also include collapsed consecutive initials (e.g. "o m" -> "om") in candTokenSet
    final expandedCandTokens = _expandInitials(candTokens);
    final expandedTargetTokens = _expandInitials(targetTokens);

    // 1b. Exact transliteration / phonetic core match (e.g. "Paathi Nee Paathi Naan" vs "Paathi Nee Paathi Naa")
    if (candTokens.length == targetTokens.length &&
        _containsOrderedSubsequencePhonetically(candTokens, targetTokens)) {
      return 78;
    }

    // 2. Contiguous ordered word-boundary phrase match inside candidate song title
    if (_containsOrderedSubsequencePhonetically(candTokens, targetTokens)) {
      // Guard against Mashups/Medleys/Conflicting Parts (e.g. "Part 2" vs "Part 1", "Side B" vs "Side A")
      if (_hasConflictingQualifier(targetTokenSet, candTokenSet)) {
        return -70;
      }
      // Check how many non-packaging extra words candidate introduces
      final extraTokens = candTokenSet
          .where((t) =>
              !expandedTargetTokens.any((wt) => _tokensPhoneticallyMatch(wt, t)) &&
              !_packagingDescriptors.contains(t) &&
              !_glueStopWords.contains(t))
          .toList();
      if (extraTokens.any(_distinctVersionMarkers.contains)) {
        // E.g. Candidate is "Oorum Blood Unplugged" for requested "Oorum Blood"
        return 35;
      }
      if (extraTokens.length <= 2) {
        return 65;
      }
      // Candidate has target phrase inside a much longer title (e.g. "Dude - Who Is This Dude? ...")
      return 50;
    }

    // 3. Conflicting numeral / part / side guard (e.g. "Part 1" vs "Part 2", "Side A" vs "Side B")
    if (_hasConflictingQualifier(targetTokenSet, expandedCandTokens)) {
      return -90;
    }

    // 4. Whole-token overlap evaluation (with conservative Tamil/Indic transliteration folding)
    final matchedTokens = targetTokenSet
        .where((w) =>
            expandedCandTokens.any((c) => _tokensPhoneticallyMatch(w, c)))
        .toSet();

    if (matchedTokens.isEmpty) {
      // Last-chance check for Indian YouTube titles formatted as "Movie | Song Name | Artist"
      // ONLY allowed when the candidate has pipe separators AND another clause matches the exact song phrase!
      if (rawCandidateTitle.contains('|') &&
          _matchesExactPipeClause(
              rawCandidateTitle, normCoreTarget, cleanArtist)) {
        return 60;
      }
      return -100;
    }

    final ratio = matchedTokens.length / targetTokenSet.length;

    // 5. Album / Artist Overlap Compensation Guard:
    // If target shares a word with the album or artist name (e.g. "Dude" inside "Who Is This Dude?"),
    // matching ONLY that album/artist token while missing all distinctive song words MUST be rejected.
    // Never treat tokens of a self-titled single (where target == album) as non-song filler.
    final albumTokens = album != null
        ? _tokenizeTitle(extractCoreTitle(album)).toSet()
        : const <String>{};
    final isSingleNamedAfterTrack = albumTokens.isNotEmpty &&
        targetTokenSet.every((t) =>
            albumTokens.any((a) => _tokensPhoneticallyMatch(t, a)));
    final artistTokens = _tokenizeTitle(cleanArtist).toSet();

    final nonAlbumNonGlueMatched = matchedTokens.where((t) =>
        (isSingleNamedAfterTrack ||
            !albumTokens.any((a) => _tokensPhoneticallyMatch(a, t))) &&
        !artistTokens.any((ar) => _tokensPhoneticallyMatch(ar, t)) &&
        !_glueStopWords.contains(t));

    if (ratio < 1.0 && nonAlbumNonGlueMatched.isEmpty) {
      return -85;
    }

    if (matchedTokens.length == targetTokenSet.length) {
      // All target tokens appear as whole words in the candidate's song title
      if (candTokens.length > targetTokens.length * 3 &&
          candTokens.length >= 8) {
        // Likely compilation / medley
        return 20;
      }
      return 50;
    }

    // Partial match requires strong majority coverage (>= 65%) plus distinctive song tokens
    if (ratio >= 0.65 && nonAlbumNonGlueMatched.isNotEmpty) {
      return 25;
    }

    return -50;
  }

  /// Extracts ONLY the candidate's own song title from a raw YouTube video title,
  /// stripping channel handles, movie/cast/director credits after `|`, video/lyric
  /// packaging noise, and leading `Artist - ` prefixes without using target title knowledge.
  static String extractCandidateSongTitle(
    String rawTitle,
    String rawChannel, {
    String cleanArtist = '',
  }) {
    final cleaned = YouTubeMetadataCleaner.clean(
      rawTitle: rawTitle,
      rawChannel: rawChannel,
      reliableArtist: cleanArtist.isNotEmpty ? cleanArtist : null,
    );
    return extractCoreTitle(cleaned.title);
  }

  /// Extracts the essential core song title by stripping soundtrack parentheticals,
  /// featured artist parentheticals, album markers, and packaging noise.
  static String extractCoreTitle(String rawTitle) {
    var title = rawTitle.trim();
    // Remove (From "...") or (from ...) or [from ...]
    title = title.replaceAll(
      RegExp(
          r'[\(\[\{]\s*(from\s+(the\s+)?(movie|film|motion\s+picture|album)?|ost|soundtrack)[^\)\]\}]*[\)\]\}]',
          caseSensitive: false),
      ' ',
    );
    // Remove Apple Music / Spotify trailing "- From \"...\""
    title = title.replaceAll(
      RegExp(r'\s+[\-\–\—]\s+from\s+["\x27]?[^"\x27]+["\x27]?\s*$',
          caseSensitive: false),
      ' ',
    );
    // Remove featured artist parentheticals (feat. ...) / [ft. ...]
    title = title.replaceAll(
      RegExp(r'[\(\[\{]\s*(feat\.?|ft\.?|featuring|with)\s+[^\)\]\}]*[\)\]\}]',
          caseSensitive: false),
      ' ',
    );
    // Remove standard version and packaging brackets
    title = title.replaceAll(
      RegExp(
          r'[\(\[\{][^\)\]\}]*(official|music\s+video|video|audio|lyric|lyrics|lyrical|remaster|hd|4k|hq|1080p|clean|explicit|bonus\s+track|deluxe)[^\)\]\}]*[\)\]\}]',
          caseSensitive: false),
      ' ',
    );
    // Remove leading video prefixes if any
    title = title.replaceAll(
      RegExp(
          r'^(full\s+video(\s+song)?|official\s+video(\s+song)?|official\s+audio|lyric\s+video|video\s+song|full\s+song|song)\s*[:\-\–\—\|\•]\s*',
          caseSensitive: false),
      ' ',
    );
    // Remove trailing separator + video packaging descriptor
    title = title.replaceAll(
      RegExp(
          r'(\s*[\-\–\—\|•]\s*)(official\s*(music)?\s*video|official\s*audio|video\s*song|full\s*video\s*song|lyric\s*video|lyrical\s*video|audio\s*song|full\s*song|visualizer)\s*$',
          caseSensitive: false),
      ' ',
    );
    return title.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _matchesExactPipeClause(
    String rawCandidateTitle,
    String normCoreTarget,
    String cleanArtist,
  ) {
    final clauses = rawCandidateTitle.split(RegExp(r'\s*(\||•|\/\/)\s*'));
    for (var i = 0; i < clauses.length; i++) {
      final clause = extractCoreTitle(clauses[i].trim());
      if (clause.isEmpty) continue;
      // Ignore clauses that are obviously artist credits matching cleanArtist
      if (cleanArtist.isNotEmpty &&
          clause.toLowerCase().contains(cleanArtist.toLowerCase()) &&
          _normalizeForComparison(clause) != normCoreTarget) {
        continue;
      }
      if (_normalizeForComparison(clause) == normCoreTarget) {
        return true;
      }
    }
    return false;
  }

  static List<String> _tokenizeTitle(String input) {
    final normalized = input
        .toLowerCase()
        // Merge apostrophes so "don't" -> "dont", "mama's" -> "mamas"
        .replaceAll(RegExp(r"['’`]+"), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true), ' ')
        .trim();
    if (normalized.isEmpty) return const [];
    return normalized.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  }

  static Set<String> _expandInitials(List<String> tokens) {
    final expanded = <String>{...tokens};
    for (int i = 0; i < tokens.length - 1; i++) {
      if (tokens[i].length == 1 && tokens[i + 1].length == 1) {
        expanded.add('${tokens[i]}${tokens[i + 1]}');
      }
    }
    return expanded;
  }

  static bool _tokensPhoneticallyMatch(String a, String b) {
    if (a == b) return true;
    final aKeys = QueryRelevanceEvaluator.transliterationKeys(a);
    final bKeys = QueryRelevanceEvaluator.transliterationKeys(b);
    return aKeys.any(bKeys.contains);
  }

  static bool _containsOrderedSubsequencePhonetically(
    List<String> container,
    List<String> target,
  ) {
    if (target.isEmpty || container.length < target.length) return false;
    for (int i = 0; i <= container.length - target.length; i++) {
      bool match = true;
      for (int j = 0; j < target.length; j++) {
        if (!_tokensPhoneticallyMatch(container[i + j], target[j])) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  static bool _containsOrderedSubsequence(
    List<String> container,
    List<String> target,
  ) {
    if (target.isEmpty || container.length < target.length) return false;
    for (int i = 0; i <= container.length - target.length; i++) {
      bool match = true;
      for (int j = 0; j < target.length; j++) {
        if (container[i + j] != target[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  static bool _hasConflictingQualifier(
    Set<String> targetTokens,
    Set<String> candTokens,
  ) {
    // Detect numeric / side / part mismatches (e.g. target has "2", candidate has "1", or "side a" vs "side b")
    const numerals = {
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      'i',
      'ii',
      'iii',
      'iv',
      'v',
      'one',
      'two',
      'three',
      'four',
      'five',
    };
    final targetNums = targetTokens.intersection(numerals);
    final candNums = candTokens.intersection(numerals);
    if (targetNums.isNotEmpty &&
        candNums.isNotEmpty &&
        targetNums.difference(candNums).isNotEmpty) {
      return true;
    }

    if (targetTokens.contains('side') && candTokens.contains('side')) {
      final hasSideA = targetTokens.contains('a');
      final hasSideB = targetTokens.contains('b');
      if (hasSideA && candTokens.contains('b') && !candTokens.contains('a')) {
        return true;
      }
      if (hasSideB && candTokens.contains('a') && !candTokens.contains('b')) {
        return true;
      }
    }
    return false;
  }

  static bool _containsWordOrToken(String haystackLower, String needleLower) {
    final cleanNeedle = needleLower.trim();
    if (cleanNeedle.isEmpty) return false;
    final haystackTokens = _tokenizeTitle(haystackLower);
    final needleTokens = _tokenizeTitle(cleanNeedle);
    if (needleTokens.isEmpty) return false;
    if (needleTokens.length == 1) {
      return haystackTokens.contains(needleTokens.first);
    }
    return _containsOrderedSubsequence(haystackTokens, needleTokens);
  }

  List<String> _extractArtistTokens(String artist) {
    final tokens = <String>[];
    final parts = artist.split(RegExp(
        r'[,;&/]|(?:\s+(?:feat\.?|featuring|with|ft\.?|x|\+)\s+)',
        caseSensitive: false));
    for (final p in parts) {
      final t = p.trim().toLowerCase();
      if (t.isNotEmpty && t.length > 1) {
        tokens.add(t);
      }
    }
    return tokens;
  }

  static String _normalizeForComparison(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r"['’`]+"), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
  }

  bool _isKnownLabel(String channelLower) {
    for (final label in _officialMusicLabels) {
      if (channelLower.contains(label)) return true;
    }
    return false;
  }

  static int _parseTargetDurationSeconds(
      {String? durationStr, int? durationMs}) {
    if (durationMs != null && durationMs > 0) {
      return durationMs ~/ 1000;
    }
    if (durationStr != null && durationStr.isNotEmpty) {
      return _parseDurationSeconds(durationStr);
    }
    return 0;
  }

  static int _parseDurationSeconds(String duration) {
    if (duration.isEmpty) return 0;
    final parts = duration.trim().split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return 0;
  }

  String _cleanQueryText(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _buildCanonicalKey(
    String title,
    String artist, {
    int targetDurationSec = 0,
  }) {
    String sanitize(String s) => s
        .toLowerCase()
        .replaceAll(RegExp(r"['’`]+"), '')
        .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    final durPart = targetDurationSec > 0 ? '_${targetDurationSec}s' : '';
    return '${sanitize(artist)}_${sanitize(title)}$durPart';
  }

  void clearCache() {
    _resolvedCandidateCache.clear();
    _inFlightResolutions.clear();
    _failedVideoIds.clear();
  }
}

@visibleForTesting
class CandidateScore {
  final int score;
  final int titleScore;

  const CandidateScore({required this.score, required this.titleScore});
}

class _ScoredCandidate {
  final YouTubeVideo video;
  final int score;
  final int titleScore;

  const _ScoredCandidate(this.video, this.score, this.titleScore);
}
