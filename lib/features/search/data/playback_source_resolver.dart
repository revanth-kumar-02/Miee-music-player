import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/data/youtube_repository.dart';

/// Playback Source Resolver.
///
/// Bridges the music-first discovery architecture with audio playback by resolving
/// authentic, high-fidelity YouTube audio streams for verified music recordings.
///
/// Replaces arbitrary general YouTube search by executing targeted queries
/// (e.g. `"$artist - $title (Official Audio)"`) and rigorously scoring candidates
/// against canonical recording duration, Topic channels, VEVO, and verified labels.
class PlaybackSourceResolver {
  static final PlaybackSourceResolver _instance = PlaybackSourceResolver._internal();
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

  /// Bounded LRU in-memory cache mapping canonical recording keys to resolved YouTube video IDs.
  final Map<String, String> _resolvedVideoCache = {};
  static const int _maxCacheSize = 300;

  /// In-flight request deduplication map to prevent redundant parallel searches.
  final Map<String, Future<String?>> _inFlightResolutions = {};

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
  ];

  /// Resolves the optimal YouTube video ID for a canonical music recording.
  Future<String?> resolveVideoId({
    required String title,
    required String artist,
    String? durationStr,
    int? durationMs,
    String? album,
  }) async {
    final cleanTitle = _cleanQueryText(title);
    final cleanArtist = _cleanQueryText(artist);
    if (cleanTitle.isEmpty) return null;

    final cacheKey = _buildCanonicalKey(cleanTitle, cleanArtist);
    if (_resolvedVideoCache.containsKey(cacheKey)) {
      debugPrint('[PlaybackSourceResolver] Cache HIT for $cacheKey -> ${_resolvedVideoCache[cacheKey]}');
      return _resolvedVideoCache[cacheKey];
    }

    if (_inFlightResolutions.containsKey(cacheKey)) {
      return await _inFlightResolutions[cacheKey]!;
    }

    final future = _resolveInternal(
      cleanTitle: cleanTitle,
      cleanArtist: cleanArtist,
      durationStr: durationStr,
      durationMs: durationMs,
      album: album,
    ).whenComplete(() {
      _inFlightResolutions.remove(cacheKey);
    });

    _inFlightResolutions[cacheKey] = future;
    final resolvedId = await future;

    if (resolvedId != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(resolvedId)) {
      if (_resolvedVideoCache.length >= _maxCacheSize) {
        _resolvedVideoCache.remove(_resolvedVideoCache.keys.first);
      }
      _resolvedVideoCache[cacheKey] = resolvedId;
    }

    return resolvedId;
  }

  /// Resolves audio playback source for an existing canonical [YouTubeVideo] instance,
  /// updating its [id] to the resolved 11-character YouTube video ID.
  Future<YouTubeVideo> resolveSourceTrack(YouTubeVideo canonicalVideo) async {
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(canonicalVideo.id) &&
        !canonicalVideo.id.startsWith('itunes_')) {
      return canonicalVideo;
    }

    final resolvedId = await resolveVideoId(
      title: canonicalVideo.canonicalTitle ?? canonicalVideo.title,
      artist: canonicalVideo.canonicalArtist ?? canonicalVideo.channelTitle,
      durationStr: canonicalVideo.duration,
      album: canonicalVideo.albumName,
    );

    if (resolvedId != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(resolvedId)) {
      return canonicalVideo.copyWith(id: resolvedId);
    }

    return canonicalVideo;
  }

  Future<String?> _resolveInternal({
    required String cleanTitle,
    required String cleanArtist,
    String? durationStr,
    int? durationMs,
    String? album,
  }) async {
    final targetSec = _parseTargetDurationSeconds(durationStr: durationStr, durationMs: durationMs);
    final coreTitle = extractCoreTitle(cleanTitle);
    final effectiveTitle = coreTitle.isNotEmpty ? coreTitle : cleanTitle;

    // 1. Primary Targeted Query: Artist + Core Title + Official Audio
    final primaryQuery = cleanArtist.isNotEmpty
        ? '$cleanArtist - $effectiveTitle (Official Audio)'
        : '$effectiveTitle (Official Audio)';

    debugPrint('[PlaybackSourceResolver] Targeted search: "$primaryQuery" (targetDur: ${targetSec}s)');
    var candidates = await _executeSearch(primaryQuery);

    // 2. Secondary Targeted Query: Artist + Core Title (without Official Audio tag)
    if (candidates.isEmpty) {
      final secondaryQuery = cleanArtist.isNotEmpty ? '$cleanArtist $effectiveTitle' : effectiveTitle;
      debugPrint('[PlaybackSourceResolver] Secondary search: "$secondaryQuery"');
      candidates = await _executeSearch(secondaryQuery);
    }

    // 2b. Tertiary search with full clean title if coreTitle differed
    if (candidates.isEmpty && coreTitle.isNotEmpty && coreTitle != cleanTitle) {
      final tertiaryQuery = cleanArtist.isNotEmpty ? '$cleanArtist $cleanTitle' : cleanTitle;
      debugPrint('[PlaybackSourceResolver] Tertiary search: "$tertiaryQuery"');
      candidates = await _executeSearch(tertiaryQuery);
    }

    if (candidates.isEmpty) {
      debugPrint('[PlaybackSourceResolver] No candidates found for "$cleanTitle" by "$cleanArtist"');
      return null;
    }

    // 3. Score candidates rigorously
    _ScoredCandidate? best;
    for (final candidate in candidates) {
      final candScore = _evaluateCandidate(
        candidate: candidate,
        cleanTitle: cleanTitle,
        cleanArtist: cleanArtist,
        targetDurationSec: targetSec,
      );

      debugPrint('[PlaybackSourceResolver] Candidate: "${candidate.title}" [chan: "${candidate.channelTitle}", dur: ${candidate.duration}] -> score: ${candScore.score} (titleScore: ${candScore.titleScore})');

      if (candScore.score >= 20 && candScore.titleScore > 0) {
        if (best == null ||
            candScore.score > best.score ||
            (candScore.score == best.score && candScore.titleScore > best.titleScore)) {
          best = _ScoredCandidate(candidate, candScore.score, candScore.titleScore);
        }
      }
    }

    if (best != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(best.video.id)) {
      debugPrint('[PlaybackSourceResolver] SELECTED: "${best.video.title}" (${best.video.id}) score: ${best.score}');
      return best.video.id;
    }

    // Do NOT return an arbitrary unverified video when confidence is insufficient.
    debugPrint('[PlaybackSourceResolver] No confident match for "$cleanTitle" by "$cleanArtist" (best score: ${best?.score ?? 0})');
    return null;
  }

  Future<List<YouTubeVideo>> _executeSearch(String query) async {
    try {
      return await _youtubeRepository.search(query, page: 1, forceFresh: false);
    } catch (e) {
      debugPrint('[PlaybackSourceResolver] YouTube search error for "$query": $e');
      return const [];
    }
  }

  @visibleForTesting
  _CandidateScore evaluateCandidateInternal({
    required YouTubeVideo candidate,
    required String cleanTitle,
    required String cleanArtist,
    required int targetDurationSec,
  }) => _evaluateCandidate(
    candidate: candidate,
    cleanTitle: cleanTitle,
    cleanArtist: cleanArtist,
    targetDurationSec: targetDurationSec,
  );

  _CandidateScore _evaluateCandidate({
    required YouTubeVideo candidate,
    required String cleanTitle,
    required String cleanArtist,
    required int targetDurationSec,
  }) {
    int score = 0;
    int titleScore = 0;
    final titleLower = (candidate.rawTitle ?? candidate.title).toLowerCase();
    final channelLower = (candidate.rawChannelTitle ?? candidate.channelTitle).toLowerCase();
    final normTitle = cleanTitle.toLowerCase();
    final normArtist = cleanArtist.toLowerCase();
    final coreTitle = extractCoreTitle(cleanTitle).toLowerCase();

    // 1. Duration Evaluation
    final candidateSec = _parseDurationSeconds(candidate.duration);
    if (targetDurationSec > 0 && candidateSec > 0) {
      final diff = (candidateSec - targetDurationSec).abs();
      if (diff <= 4) {
        score += 60; // Near-perfect duration match
      } else if (diff <= 10) {
        score += 40; // High confidence duration
      } else if (diff <= 20) {
        score += 20; // Acceptable tolerance
      } else if (diff > 60) {
        score -= 60; // Deviates significantly (e.g. scene clip or compilation)
      } else if (diff > 120) {
        score -= 100;
      }
      if (candidateSec < 60 && targetDurationSec >= 90) {
        score -= 150; // Heavy penalty for teaser/promo clips when resolving full song
      }
    }

    // 2. Channel & Artist Authority
    final artistTokens = _extractArtistTokens(cleanArtist);
    bool artistMatchedChannel = false;
    bool artistMatchedTitle = false;

    if (normArtist.isNotEmpty && channelLower.contains(normArtist)) {
      score += 40;
      artistMatchedChannel = true;
    } else {
      for (final token in artistTokens) {
        if (channelLower.contains(token)) {
          score += 35;
          artistMatchedChannel = true;
          break;
        }
      }
    }

    for (final token in artistTokens) {
      if (titleLower.contains(token)) {
        score += 15;
        artistMatchedTitle = true;
        break;
      }
    }

    if (channelLower.endsWith('- topic') || channelLower.contains('- topic')) {
      score += 65; // YouTube Music official auto-generated topic channel
    }
    if (channelLower.contains('vevo') || channelLower.contains('official')) {
      score += 40;
    }
    if (_isKnownLabel(channelLower)) {
      score += 35;
    }

    // 3. Audio / Video Signal in Title
    if (titleLower.contains('official audio')) {
      score += 45;
    } else if (titleLower.contains('official music video') || titleLower.contains('official video')) {
      score += 35;
    } else if (titleLower.contains('official lyric video') || titleLower.contains('lyric video')) {
      score += 25;
    } else if (titleLower.contains('audio')) {
      score += 15;
    }

    // 4. Content Negative Cues (Banned/Penalized Content)
    final isExplicitCover = normTitle.contains('cover');
    final isExplicitKaraoke = normTitle.contains('karaoke');
    final isExplicitLive = normTitle.contains('live');
    final isExplicitRemix = normTitle.contains('remix');

    if (!isExplicitCover && titleLower.contains('cover')) {
      score -= 120;
    }
    if (!isExplicitKaraoke && titleLower.contains('karaoke')) {
      score -= 140;
    }
    if (!isExplicitLive && (titleLower.contains('live') || titleLower.contains('live at') || titleLower.contains('concert'))) {
      score -= 50;
    } else if (isExplicitLive && (titleLower.contains('live') || titleLower.contains('live at') || titleLower.contains('concert'))) {
      score += 40;
    }
    if (!normTitle.contains('instrumental') && titleLower.contains('instrumental')) {
      score -= 80;
    }
    if (!normTitle.contains('reaction') && titleLower.contains('reaction')) {
      score -= 150;
    }
    if (!normTitle.contains('scene') &&
        (titleLower.contains('scene') ||
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
    if (!isExplicitRemix && titleLower.contains('remix')) {
      score -= 40;
    } else if (isExplicitRemix && titleLower.contains('remix')) {
      score += 40;
    }

    // 5. Strict Title Match & Cross-Link Disambiguation
    final normCleanTitle = _normalizeForComparison(cleanTitle);
    final normCoreTitle = _normalizeForComparison(coreTitle);
    final candCoreTitle = extractCoreTitle(candidate.rawTitle ?? candidate.title);
    final normCandCoreTitle = _normalizeForComparison(candCoreTitle);
    final normCandTitle = _normalizeForComparison(candidate.rawTitle ?? candidate.title);

    final significantTargetWords = coreTitle
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^a-z0-9]'), ''))
        .where((w) => w.length >= 3)
        .toSet();

    if (normCandTitle == normCleanTitle || (normCoreTitle.isNotEmpty && normCandCoreTitle == normCoreTitle)) {
      score += 70; // Exact canonical or core title match
      titleScore = 70;
    } else if (normCoreTitle.isNotEmpty && normCandTitle.contains(normCoreTitle)) {
      score += 50; // Core title substring match
      titleScore = 50;
    } else if (titleLower.contains(coreTitle) || titleLower.contains(normTitle)) {
      score += 40;
      titleScore = 40;
    } else if (significantTargetWords.isNotEmpty) {
      final matchedWords = significantTargetWords.where((w) => titleLower.contains(w)).length;
      if (matchedWords == significantTargetWords.length) {
        score += 35; // All significant words present
        titleScore = 35;
      } else if (matchedWords > 0) {
        final ratio = matchedWords / significantTargetWords.length;
        if (ratio >= 0.5) {
          score += 15;
          titleScore = 15;
        } else {
          score -= 30; // Minor partial word overlap
          titleScore = -30;
        }
      } else {
        // Zero significant words matched from the core title!
        // This is a completely different song by the same artist/album!
        score -= 90;
        titleScore = -90;
      }
    } else {
      score -= 80;
      titleScore = -80;
    }

    // Require either artist or channel or title alignment
    if (!artistMatchedChannel && !artistMatchedTitle && !_isKnownLabel(channelLower)) {
      score -= 25;
    }

    return _CandidateScore(score: score, titleScore: titleScore);
  }

  /// Extracts the essential core song title by stripping soundtrack parentheticals,
  /// album markers, and packaging noise.
  static String extractCoreTitle(String rawTitle) {
    var title = rawTitle.trim();
    // Remove (From "...") or (from ...) or [from ...]
    title = title.replaceAll(
      RegExp(r'[\(\[\{]\s*(from\s+(the\s+)?(movie|film|motion\s+picture|album)?|ost|soundtrack)[^\)\]\}]*[\)\]\}]', caseSensitive: false),
      ' ',
    );
    // Remove standard version and packaging brackets
    title = title.replaceAll(
      RegExp(r'[\(\[\{][^\)\]\}]*(official|music\s+video|video|audio|lyric|lyrics|remaster|hd|4k|hq|1080p|clean|explicit)[^\)\]\}]*[\)\]\}]', caseSensitive: false),
      ' ',
    );
    // Remove leading movie prefixes if any
    title = title.replaceAll(
      RegExp(r'^(full\s+video(\s+song)?|official\s+video(\s+song)?|official\s+audio|lyric\s+video|video\s+song|full\s+song|song)\s*[:\-\–\—\|\•]\s*', caseSensitive: false),
      ' ',
    );
    return title.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  List<String> _extractArtistTokens(String artist) {
    final tokens = <String>[];
    final parts = artist.split(RegExp(r'[,;&/]|(?:\s+(?:feat\.?|featuring|with|ft\.?|x|\+)\s+)', caseSensitive: false));
    for (final p in parts) {
      final t = p.trim().toLowerCase();
      if (t.isNotEmpty && t.length > 1) {
        tokens.add(t);
      }
    }
    return tokens;
  }

  String _normalizeForComparison(String s) {
    return s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  bool _isKnownLabel(String channelLower) {
    for (final label in _officialMusicLabels) {
      if (channelLower.contains(label)) return true;
    }
    return false;
  }

  int _parseTargetDurationSeconds({String? durationStr, int? durationMs}) {
    if (durationMs != null && durationMs > 0) {
      return durationMs ~/ 1000;
    }
    if (durationStr != null && durationStr.isNotEmpty) {
      return _parseDurationSeconds(durationStr);
    }
    return 0;
  }

  int _parseDurationSeconds(String duration) {
    if (duration.isEmpty) return 0;
    final parts = duration.split(':');
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
    return text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildCanonicalKey(String title, String artist) {
    String sanitize(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '${sanitize(artist)}_${sanitize(title)}';
  }

  void clearCache() {
    _resolvedVideoCache.clear();
    _inFlightResolutions.clear();
  }
}

class _CandidateScore {
  final int score;
  final int titleScore;

  const _CandidateScore({required this.score, required this.titleScore});
}

class _ScoredCandidate {
  final YouTubeVideo video;
  final int score;
  final int titleScore;

  const _ScoredCandidate(this.video, this.score, this.titleScore);
}
