import 'dart:math' as math;
import '../../youtube/domain/youtube_model.dart';

/// Represents genuinely distinct recording version categories.
enum VersionType {
  standard,
  live,
  remix,
  cover,
  acoustic,
  spedUp,
  slowed,
  instrumental,
}

/// Identifies categorized derivative upload types.
enum EditType {
  none,
  fourKEdit,       // 4K edit, 4K status, 4K 60fps, 4K HDR edit
  fanEdit,         // fan edit, edit audio, AMV edit, fanmade edit
  slowedReverb,    // slowed + reverb, slowed down
  spedUpNightcore, // sped up, speed up, nightcore
  statusVideo,     // whatsapp status, status video, #shorts
  compilationMix,  // jukebox, non-stop, continuous mix, full album
}

/// Configuration for view-count ranking, edit filtering, and candidate pruning.
class SearchRankingConfig {
  /// Whether to filter out derivative edits (4K status, fan edits, slowed+reverb, nightcore, status videos, compilations).
  final bool filterDerivativeEdits;

  /// Relative view ratio threshold: when high-view canonical results exist,
  /// derivative or extreme low-view results with view counts below this fraction of the top match
  /// are filtered out (default: 0.05 = 5% of top match's view count).
  final double relativeViewRatioThreshold;

  /// Absolute minimum view count for derivative edits when canonical versions exist.
  final int minViewCountForEdits;

  /// Maximum number of candidates to return.
  final int maxResults;

  const SearchRankingConfig({
    this.filterDerivativeEdits = false,
    this.relativeViewRatioThreshold = 0.05,
    this.minViewCountForEdits = 50000,
    this.maxResults = 25,
  });
}

/// Structured detection of user search intent to avoid filtering requested variations.
class QueryIntent {
  final String normalizedQuery;
  final bool wants4kEdit;
  final bool wantsFanEdit;
  final bool wantsSlowed;
  final bool wantsSpedUp;
  final bool wantsStatus;
  final bool wantsCompilation;
  final bool wantsRemix;
  final bool wantsLive;
  final bool wantsAcoustic;
  final bool wantsCover;
  final bool wantsInstrumental;

  const QueryIntent({
    required this.normalizedQuery,
    this.wants4kEdit = false,
    this.wantsFanEdit = false,
    this.wantsSlowed = false,
    this.wantsSpedUp = false,
    this.wantsStatus = false,
    this.wantsCompilation = false,
    this.wantsRemix = false,
    this.wantsLive = false,
    this.wantsAcoustic = false,
    this.wantsCover = false,
    this.wantsInstrumental = false,
  });

  factory QueryIntent.fromQuery(String? rawQuery) {
    if (rawQuery == null || rawQuery.trim().isEmpty) {
      return const QueryIntent(normalizedQuery: '');
    }
    final q = rawQuery.toLowerCase();
    return QueryIntent(
      normalizedQuery: q,
      wants4kEdit: q.contains('4k') || q.contains('edit'),
      wantsFanEdit: q.contains('fan edit') || q.contains('edit audio') || q.contains('amv'),
      wantsSlowed: q.contains('slowed') || q.contains('reverb') || q.contains('slow down') || q.contains('slow'),
      wantsSpedUp: q.contains('sped up') || q.contains('speed up') || q.contains('nightcore') || q.contains('speedup'),
      wantsStatus: q.contains('status') || q.contains('shorts') || q.contains('short'),
      wantsCompilation: q.contains('jukebox') || q.contains('non stop') || q.contains('nonstop') || q.contains('mix') || q.contains('compilation'),
      wantsRemix: q.contains('remix') || q.contains('club mix') || q.contains('vip mix'),
      wantsLive: q.contains('live') || q.contains('concert') || q.contains('tour'),
      wantsAcoustic: q.contains('acoustic') || q.contains('unplugged'),
      wantsCover: q.contains('cover') || q.contains('tribute'),
      wantsInstrumental: q.contains('instrumental') || q.contains('karaoke'),
    );
  }
}

/// A deduplication and ranking engine for YouTube search results.
///
/// Detects multiple redundant uploads of the same canonical song (e.g.,
/// Official Audio, Lyrics, Music Video, Visualizer) and selects the single best
/// representative result for that canonical recording, while strictly preserving
/// genuinely distinct songs and valid artistic variations (Live, Remix, Cover,
/// Acoustic, Sped Up, Slowed, Instrumental).
class SearchDeduplicator {
  /// Deduplicates and ranks a list of YouTube search results.
  static List<YouTubeVideo> deduplicateAndRank(
    List<YouTubeVideo> videos, {
    String? query,
    SearchRankingConfig config = const SearchRankingConfig(),
  }) {
    if (videos.isEmpty) return const [];

    // 1. Deduplicate by unique YouTube Video ID first
    final seenIds = <String>{};
    final uniqueVideos = <YouTubeVideo>[];
    for (final video in videos) {
      if (video.id.isNotEmpty && seenIds.add(video.id)) {
        uniqueVideos.add(video);
      }
    }

    if (uniqueVideos.isEmpty) return const [];

    // 2. Group videos by canonical song key while tracking first discovery index
    final groups = <String, List<YouTubeVideo>>{};
    final groupFirstIndex = <String, int>{};

    for (var i = 0; i < uniqueVideos.length; i++) {
      final video = uniqueVideos[i];
      final key = _computeCanonicalKey(video);

      groups.putIfAbsent(key, () {
        groupFirstIndex[key] = i;
        return [];
      }).add(video);
    }

    // 3. For each group, rank candidates and pick the best representative
    final representatives = <({int orderIndex, YouTubeVideo video})>[];

    for (final entry in groups.entries) {
      final key = entry.key;
      final candidates = entry.value;
      final orderIndex = groupFirstIndex[key] ?? 0;

      final bestVideo = _selectBestCandidate(candidates, query: query);
      final rawOrCleanTitle = (bestVideo.rawTitle != null && bestVideo.rawTitle!.isNotEmpty)
          ? bestVideo.rawTitle!
          : bestVideo.title;
      final versionInfo = _extractVersion(rawOrCleanTitle, bestVideo.title);
      final finalizedVideo = _ensureVersionInTitle(bestVideo, versionInfo.type);

      representatives.add((orderIndex: orderIndex, video: finalizedVideo));
    }

    // 4. If filterDerivativeEdits is true, apply view-count filtering and quality ranking
    if (config.filterDerivativeEdits && query != null && query.trim().isNotEmpty) {
      final intent = QueryIntent.fromQuery(query);
      final candidateList = representatives.map((r) => r.video).toList();

      // Find max views among relevant candidates
      int maxViews = 0;
      for (final v in candidateList) {
        final rel = calculateQueryRelevance(v, query);
        if (rel >= 0.4) {
          final views = parseViewCount(v);
          if (views != null && views > maxViews) {
            maxViews = views;
          }
        }
      }

      // Separate canonical/legitimate songs from derivative edits
      final canonicalList = <YouTubeVideo>[];

      for (final v in candidateList) {
        final editType = detectEditType(v, intent);
        final views = parseViewCount(v);

        final isUnwantedEdit = editType != EditType.none;
        // Check relative view threshold: if maxViews is substantial (e.g. >= 100K)
        // and this video has extremely low views (< 5% of maxViews and < minViewCountForEdits)
        final isLowViewDerivative = maxViews >= 100000 &&
            views != null &&
            views < (maxViews * config.relativeViewRatioThreshold) &&
            views < config.minViewCountForEdits &&
            isUnwantedEdit;

        if (!isUnwantedEdit && !isLowViewDerivative) {
          canonicalList.add(v);
        }
      }

      // Safe fallback: If filtering would eliminate every result (e.g. indie/regional song
      // or only edits exist for this query), retain the candidate pool so the user isn't left empty.
      final resultPool = canonicalList.isNotEmpty ? canonicalList : candidateList;

      // Sort by global candidate score (relevance, official authenticity, view count)
      resultPool.sort((a, b) {
        final scoreA = calculateGlobalCandidateScore(a, query: query, maxViewsInResultSet: maxViews);
        final scoreB = calculateGlobalCandidateScore(b, query: query, maxViewsInResultSet: maxViews);
        return scoreB.compareTo(scoreA);
      });

      return resultPool.take(config.maxResults).toList();
    }

    // 5. Default sorting: by original discovery relevance order (preserves existing tests)
    representatives.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return representatives.map((item) => item.video).toList();
  }

  /// Appends appropriate version suffix to track title if it was stripped by metadata cleaning.
  static YouTubeVideo _ensureVersionInTitle(YouTubeVideo video, VersionType type) {
    final lowerTitle = video.title.toLowerCase();
    switch (type) {
      case VersionType.slowed:
        if (!lowerTitle.contains('slowed')) {
          return video.copyWith(title: '${video.title} (Slowed)');
        }
        break;
      case VersionType.spedUp:
        if (!lowerTitle.contains('sped') && !lowerTitle.contains('speed')) {
          return video.copyWith(title: '${video.title} (Sped Up)');
        }
        break;
      case VersionType.live:
        if (!lowerTitle.contains('live')) {
          return video.copyWith(title: '${video.title} (Live)');
        }
        break;
      case VersionType.remix:
        if (!lowerTitle.contains('remix')) {
          return video.copyWith(title: '${video.title} (Remix)');
        }
        break;
      case VersionType.acoustic:
        if (!lowerTitle.contains('acoustic')) {
          return video.copyWith(title: '${video.title} (Acoustic)');
        }
        break;
      case VersionType.instrumental:
        if (!lowerTitle.contains('instrumental')) {
          return video.copyWith(title: '${video.title} (Instrumental)');
        }
        break;
      case VersionType.cover:
        if (!lowerTitle.contains('cover')) {
          return video.copyWith(title: '${video.title} (Cover)');
        }
        break;
      case VersionType.standard:
        break;
    }
    return video;
  }

  /// Computes a canonical key: `canonical_title|canonical_artist|version_tag`
  static String _computeCanonicalKey(YouTubeVideo video) {
    // Prefer video.title / video.channelTitle which have already undergone
    // artist-separator splitting in YouTubeMetadataCleaner.
    final rawOrCleanTitle = (video.rawTitle != null && video.rawTitle!.isNotEmpty)
        ? video.rawTitle!
        : video.title;
    final rawOrCleanChannel = (video.channelTitle.isNotEmpty)
        ? video.channelTitle
        : (video.rawChannelTitle ?? '');

    final versionInfo = _extractVersion(rawOrCleanTitle, video.title);
    final normalizedTitle = _normalizeBaseTitle(video.title, rawOrCleanTitle, rawOrCleanChannel);
    final normalizedArtist = _normalizeArtist(rawOrCleanChannel);

    return '$normalizedTitle|$normalizedArtist|${versionInfo.tag}';
  }

  /// Extracts version type and a specific version identifier (e.g. remixer name).
  static ({VersionType type, String tag}) _extractVersion(String rawTitle, String cleanTitle) {
    final combined = '$rawTitle $cleanTitle'.toLowerCase();

    // Check remix (extract specific remixer if available inside brackets/parentheses)
    final remixRegex = RegExp(
      r'[\(\[\{]([^\)\]\}]+?\s+remix)[\)\]\}]',
      caseSensitive: false,
    );
    final remixMatch = remixRegex.firstMatch(rawTitle) ?? remixRegex.firstMatch(cleanTitle);
    if (remixMatch != null) {
      final specificRemix = _sanitizeText(remixMatch.group(1) ?? 'remix');
      return (type: VersionType.remix, tag: 'remix:$specificRemix');
    }
    if (combined.contains('remix') ||
        combined.contains('club mix') ||
        combined.contains('vip mix') ||
        combined.contains('dance mix') ||
        combined.contains('dub mix') ||
        combined.contains('extended mix')) {
      return (type: VersionType.remix, tag: 'remix');
    }

    // Check live
    final liveRegex = RegExp(r'\b(live(\s+(at|in|performance|session|version|from))?)\b', caseSensitive: false);
    if (liveRegex.hasMatch(combined)) {
      return (type: VersionType.live, tag: 'live');
    }

    // Check cover
    final coverRegex = RegExp(r'\b(cover|tribute)\b', caseSensitive: false);
    if (coverRegex.hasMatch(combined)) {
      return (type: VersionType.cover, tag: 'cover');
    }

    // Check acoustic
    final acousticRegex = RegExp(r'\b(acoustic(\s+version)?|unplugged)\b', caseSensitive: false);
    if (acousticRegex.hasMatch(combined)) {
      return (type: VersionType.acoustic, tag: 'acoustic');
    }

    // Check sped up
    final spedUpRegex = RegExp(r'\b(sped\s+up|speed\s+up|nightcore)\b', caseSensitive: false);
    if (spedUpRegex.hasMatch(combined)) {
      return (type: VersionType.spedUp, tag: 'sped_up');
    }

    // Check slowed / reverb
    final slowedRegex = RegExp(r"\b(slowed(\s*(\+|&|and|n|'n'|\/)\s*reverb)?|slowed\s+down|reverb)\b", caseSensitive: false);
    if (slowedRegex.hasMatch(combined)) {
      return (type: VersionType.slowed, tag: 'slowed');
    }

    // Check instrumental
    final instrumentalRegex = RegExp(r'\b(instrumental|karaoke|backing\s+track)\b', caseSensitive: false);
    if (instrumentalRegex.hasMatch(combined)) {
      return (type: VersionType.instrumental, tag: 'instrumental');
    }

    return (type: VersionType.standard, tag: 'standard');
  }

  /// Normalizes base title by removing upload noise, packaging decorations, and version markers.
  static String _normalizeBaseTitle(String cleanTitle, String rawTitle, String channel) {
    var title = cleanTitle.isNotEmpty ? cleanTitle : rawTitle;

    // 1. Remove version markers from brackets/parentheses so that different uploads of the same version
    // share the identical base song title (e.g. "West Coast (Live at Coachella)" -> "West Coast")
    final versionBracketRegex = RegExp(
      r'[\(\[\{]\s*(live(\s+[^\)\]\}]+)?|remix(\s+[^\)\]\}]+)?|acoustic(\s+version)?|sped\s+up(\s+[^\)\]\}]+)?|slowed(\s+[^\)\]\}]+)?|instrumental|cover(\s+[^\)\]\}]+)?)\s*[\)\]\}]',
      caseSensitive: false,
    );
    title = title.replaceAll(versionBracketRegex, ' ');

    // 2. Remove bracketed upload packaging noise (e.g. [Official Video], (Lyrics), (Visualizer + HQ + SFX), etc.)
    final bracketNoiseRegex = RegExp(
      r'[\(\[\{][^\)\]\}]*(official|music\s+video|video|audio|lyric|visualizer|mv|hd|4k|hq|1080p|remaster|high\s+quality|explicit|clean|sfx)[^\)\]\}]*[\)\]\}]',
      caseSensitive: false,
    );
    title = title.replaceAll(bracketNoiseRegex, ' ');

    // 2b. Remove common parenthetical commentary noise (e.g. "(but your life will be changed)", "(listen with headphones)")
    final commentaryBracketRegex = RegExp(
      r'[\(\[\{]\s*(but\s+|you\s+|feeling\s+|listening\s+|read\s+|listen\s+|pov\s*[\:\-]|headphones)[^\)\]\}]*[\)\]\}]',
      caseSensitive: false,
    );
    title = title.replaceAll(commentaryBracketRegex, ' ');

    // 3. Remove trailing upload noise (e.g. " - Official Audio", " | Lyric Video")
    final trailingNoiseRegex = RegExp(
      r'[\s\-\–\—\|\:]+(official\s+music\s+video|official\s+video|official\s+audio|lyric\s+video|lyrics|visualizer|mv|hd|4k|hq|1080p|audio|video)[\s]*$',
      caseSensitive: false,
    );
    title = title.replaceAll(trailingNoiseRegex, ' ');

    // 4. Remove artist prefix/suffix if present with a standard separator
    final separators = [' – ', ' — ', ' - ', ' | ', ' : '];
    for (final sep in separators) {
      if (title.contains(sep)) {
        final parts = title.split(sep);
        if (parts.length >= 2) {
          final p0 = parts[0].trim();
          final p1 = parts.sublist(1).join(sep).trim();
          if (_isArtistMatch(p0, channel)) {
            title = p1;
            break;
          } else if (_isArtistMatch(p1, channel)) {
            title = p0;
            break;
          }
        }
      }
    }

    // 5. Sanitize text (remove punctuation, quotes, normalize whitespace)
    return _sanitizeText(title);
  }

  /// Normalizes artist/channel name.
  static String _normalizeArtist(String rawChannel) {
    var artist = rawChannel.trim();

    // Strip common YouTube channel suffixes
    final channelSuffixes = [
      RegExp(r'\s*-\s*topic$', caseSensitive: false),
      RegExp(r'\s*topic$', caseSensitive: false),
      RegExp(r'vevo$', caseSensitive: false),
      RegExp(r'\s*official$', caseSensitive: false),
      RegExp(r'\s*music$', caseSensitive: false),
      RegExp(r'\s*records$', caseSensitive: false),
      RegExp(r'\s*channel$', caseSensitive: false),
    ];

    for (final suffix in channelSuffixes) {
      artist = artist.replaceFirst(suffix, '');
    }

    final sanitized = _sanitizeText(artist);
    // If completely empty, fall back to "unknown_artist"
    return sanitized.isEmpty ? 'unknown_artist' : sanitized;
  }

  /// Sanitizes text into clean lowercase alphanumeric words.
  static String _sanitizeText(String text) {
    return text
        .toLowerCase()
        // Replace smart quotes, normal quotes, and special characters
        .replaceAll(RegExp('["\u201C\u201D\u2018\u2019\'`\u00B4]'), '')
        // Replace punctuation symbols with space
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        // Collapse multiple spaces
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isArtistMatch(String text, String channel) {
    final normText = _sanitizeText(text);
    final normChannel = _normalizeArtist(channel);
    if (normText.isEmpty || normChannel.isEmpty) return false;
    return normText == normChannel ||
        normText.contains(normChannel) ||
        normChannel.contains(normText);
  }

  /// Ranks candidates within the same canonical group and picks the best representative.
  static YouTubeVideo _selectBestCandidate(
    List<YouTubeVideo> candidates, {
    String? query,
  }) {
    if (candidates.length == 1) return candidates.first;

    YouTubeVideo? best;
    var bestScore = -999999;

    for (final candidate in candidates) {
      final score = _calculateCandidateScore(candidate, query: query);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    return best ?? candidates.first;
  }

  /// Calculates a heuristic quality score for a YouTube video candidate.
  static int _calculateCandidateScore(
    YouTubeVideo video, {
    String? query,
  }) {
    var score = 0;

    final rawTitle = (video.rawTitle ?? video.title).toLowerCase();
    final rawChannel = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();
    final cleanTitle = video.title.toLowerCase();

    // 1. High-confidence official channel signals
    if (rawChannel.contains('- topic') || rawChannel.endsWith('topic')) {
      score += 120; // Official YouTube Music track delivery
    }
    if (rawChannel.contains('vevo')) {
      score += 100; // Official VEVO channel
    }
    if (rawChannel.contains('official')) {
      score += 40;
    }

    // 2. Official audio / music video upload signals
    if (rawTitle.contains('official audio')) {
      score += 90; // Preferred standard recording upload
    } else if (rawTitle.contains('official music video') || rawTitle.contains('official video')) {
      score += 80;
    } else if (rawTitle.contains('official visualizer') || rawTitle.contains('visualizer')) {
      score += 50;
    } else if (rawTitle.contains('audio')) {
      score += 30;
    }

    // Lyrics uploads are legitimate backups but ranked lower than authentic releases
    if (rawTitle.contains('lyrics') || rawTitle.contains('lyric video')) {
      score -= 15;
    }

    // 3. Query match bonuses
    if (query != null && query.trim().isNotEmpty) {
      final sanitizedQuery = _sanitizeText(query);
      final sanitizedCleanTitle = _sanitizeText(cleanTitle);
      if (sanitizedCleanTitle == sanitizedQuery) {
        score += 50;
      } else if (sanitizedCleanTitle.contains(sanitizedQuery)) {
        score += 25;
      }
    }

    // 4. View count popularity bonus (logarithmic scaling)
    final views = parseViewCount(video);
    if (views != null && views > 0) {
      score += ((math.log(views + 1) / math.ln10) * 6).toInt();
    }

    // 5. Duration sanity check
    final durationSeconds = _parseDurationSeconds(video.duration);
    if (durationSeconds > 0) {
      // Normal song range: 75 seconds (1:15) to 480 seconds (8:00)
      if (durationSeconds >= 75 && durationSeconds <= 480) {
        score += 20;
      } else if (durationSeconds > 900) {
        // More than 15 minutes is almost certainly a loop, playlist, or 10-hour compilation
        score -= 150;
      } else if (durationSeconds < 40) {
        // Less than 40 seconds is likely a ringtone, teaser, or preview
        score -= 100;
      }
    }

    // 6. Demote clickbait and low-quality modifiers
    final clickbaitKeywords = [
      'bass boosted',
      'earrape',
      'slowed to perfection',
      'tiktok version',
      'whatsapp status',
      'status video',
      'ringtone',
      'reaction',
      '10 hours',
      '1 hour',
      'loop',
      'teaser',
      'snippet',
    ];

    for (final kw in clickbaitKeywords) {
      if (rawTitle.contains(kw)) {
        score -= 120;
      }
    }

    return score;
  }

  /// Parses duration string like "3:45", "03:45", or "1:02:15" into seconds.
  static int _parseDurationSeconds(String durationStr) {
    if (durationStr.isEmpty) return 0;
    final parts = durationStr.split(':');
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

  /// Parses view count from a YouTubeVideo or formatted String.
  /// Returns null when reliable view count is missing or unavailable.
  static int? parseViewCount(dynamic viewCountOrVideo) {
    if (viewCountOrVideo is YouTubeVideo) {
      if (viewCountOrVideo.rawViewCount != null) {
        return viewCountOrVideo.rawViewCount;
      }
      return _parseViewCount(viewCountOrVideo.viewCount);
    } else if (viewCountOrVideo is String) {
      return _parseViewCount(viewCountOrVideo);
    }
    return null;
  }

  /// Parses view count string like "1.2M views", "450K views", or "12,400 views".
  static int? _parseViewCount(String viewCountStr) {
    if (viewCountStr.isEmpty) return null;
    final clean = viewCountStr.toLowerCase().replaceAll('views', '').replaceAll(',', '').trim();
    if (clean.isEmpty || clean.contains('no views')) return null;

    if (clean.endsWith('b')) {
      final val = double.tryParse(clean.replaceAll('b', '')) ?? 0.0;
      return (val * 1000000000).toInt();
    } else if (clean.endsWith('m')) {
      final val = double.tryParse(clean.replaceAll('m', '')) ?? 0.0;
      return (val * 1000000).toInt();
    } else if (clean.endsWith('k')) {
      final val = double.tryParse(clean.replaceAll('k', '')) ?? 0.0;
      return (val * 1000).toInt();
    }
    return int.tryParse(clean);
  }

  /// Identifies derivative / edit upload types unless explicitly requested in query intent.
  static EditType detectEditType(YouTubeVideo video, QueryIntent intent) {
    final rawTitle = (video.rawTitle ?? video.title).toLowerCase();
    final cleanTitle = video.title.toLowerCase();

    // 1. 4K edit / status check
    if (!intent.wants4kEdit) {
      if (rawTitle.contains('4k edit') ||
          rawTitle.contains('4k status') ||
          rawTitle.contains('4k 60fps') ||
          rawTitle.contains('4k hdr edit') ||
          RegExp(r'\b4k\s+(edit|audio|status|version)\b').hasMatch(rawTitle)) {
        return EditType.fourKEdit;
      }
    }

    // 2. Fan edit / edit audio
    if (!intent.wantsFanEdit && !intent.wants4kEdit) {
      if (rawTitle.contains('fan edit') ||
          rawTitle.contains('edit audio') ||
          rawTitle.contains('audio edit') ||
          rawTitle.contains('amv edit') ||
          rawTitle.contains('fanmade edit') ||
          RegExp(r'[\(\[\{]\s*(edit|fan\s*edit|audio\s*edit)\s*[\)\]\}]').hasMatch(rawTitle)) {
        return EditType.fanEdit;
      }
    }

    // 3. Status video / shorts
    if (!intent.wantsStatus) {
      if (rawTitle.contains('whatsapp status') ||
          rawTitle.contains('status video') ||
          rawTitle.contains('fullscreen status') ||
          rawTitle.contains('full screen status') ||
          rawTitle.contains('shorts video') ||
          rawTitle.contains('#shorts') ||
          rawTitle.contains('short video') ||
          RegExp(r'\b(status\s+video|wa\s+status|lyric\s+status)\b').hasMatch(rawTitle)) {
        return EditType.statusVideo;
      }
    }

    // 4. Slowed + reverb (Conservative: don't flag "Slow Down" or "Slow Hands")
    if (!intent.wantsSlowed) {
      final isSongTitleSlow = cleanTitle == 'slow down' ||
          cleanTitle == 'slow hands' ||
          cleanTitle.startsWith('slow down ') ||
          cleanTitle.startsWith('slow hands ');
      if (!isSongTitleSlow) {
        if (rawTitle.contains('slowed') ||
            rawTitle.contains('slowed + reverb') ||
            rawTitle.contains('slowed and reverb') ||
            rawTitle.contains('slowed & reverb') ||
            rawTitle.contains('slowed down') ||
            RegExp(r'[\(\[\{]\s*(slowed|reverb)\s*[\)\]\}]').hasMatch(rawTitle)) {
          return EditType.slowedReverb;
        }
      }
    }

    // 5. Sped up / Nightcore (Conservative: don't flag "Speed Demon")
    if (!intent.wantsSpedUp) {
      final isSongTitleSpeed = cleanTitle == 'speed demon' || cleanTitle.startsWith('speed demon ');
      if (!isSongTitleSpeed) {
        if (rawTitle.contains('nightcore') ||
            rawTitle.contains('sped up') ||
            rawTitle.contains('speed up') ||
            rawTitle.contains('speedup') ||
            RegExp(r'[\(\[\{]\s*(sped\s+up|speed\s+up|nightcore)\s*[\)\]\}]').hasMatch(rawTitle)) {
          return EditType.spedUpNightcore;
        }
      }
    }

    // 6. Jukebox / Non-stop compilations
    if (!intent.wantsCompilation) {
      if (rawTitle.contains('jukebox') ||
          rawTitle.contains('non stop') ||
          rawTitle.contains('nonstop') ||
          rawTitle.contains('continuous mix') ||
          rawTitle.contains('audio jukebox') ||
          rawTitle.contains('video jukebox') ||
          rawTitle.contains('all songs compilation') ||
          rawTitle.contains('full album compilation')) {
        return EditType.compilationMix;
      }
      final durSec = _parseDurationSeconds(video.duration);
      if (durSec > 900 &&
          !rawTitle.contains('symphony') &&
          !rawTitle.contains('raga') &&
          !rawTitle.contains('recital') &&
          !rawTitle.contains('classical')) {
        return EditType.compilationMix;
      }
    }

    return EditType.none;
  }

  /// Calculates text relevance of video title & artist to search query (0.0 to 1.0).
  static double calculateQueryRelevance(YouTubeVideo video, String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return 1.0;

    final normQuery = _sanitizeText(cleanQuery);
    if (normQuery.isEmpty) return 1.0;

    final cleanTitle = _sanitizeText(video.title);
    final rawTitle = _sanitizeText(video.rawTitle ?? video.title);
    final channel = _sanitizeText(video.rawChannelTitle ?? video.channelTitle);
    final allText = '$cleanTitle $rawTitle $channel';

    // 1. Exact match to query
    if (cleanTitle == normQuery || rawTitle == normQuery) {
      return 1.0;
    }

    // 2. Title contains query phrase or query phrase contains title
    if (cleanTitle.contains(normQuery) || rawTitle.contains(normQuery)) {
      return 0.95;
    }
    if (normQuery.contains(cleanTitle) && cleanTitle.length >= 3) {
      return 0.90;
    }

    // 3. Token overlap
    final qTokens = normQuery.split(' ').where((s) => s.isNotEmpty).toList();
    if (qTokens.isEmpty) return 1.0;

    int titleTokensMatched = 0;
    int allTokensMatched = 0;

    for (final token in qTokens) {
      if (cleanTitle.contains(token) || rawTitle.contains(token)) {
        titleTokensMatched++;
      }
      if (allText.contains(token)) {
        allTokensMatched++;
      }
    }

    final titleRatio = titleTokensMatched / qTokens.length;
    final allRatio = allTokensMatched / qTokens.length;

    // Weighted composite
    return (titleRatio * 0.75) + (allRatio * 0.25);
  }

  /// Calculates global candidate score combining query relevance, official channel signals,
  /// view-count popularity, duration, and edit demotions.
  static double calculateGlobalCandidateScore(
    YouTubeVideo video, {
    required String query,
    required int maxViewsInResultSet,
  }) {
    final relevance = calculateQueryRelevance(video, query);
    // If relevance is near zero, video is completely unrelated to query!
    // A completely unrelated video (e.g. Despacito with 8B views when searching Enna Sona)
    // will be severely clamped down and will never outrank a relevant song.
    if (relevance < 0.25) {
      return relevance * 10.0;
    }

    double score = relevance * 1000.0;

    final rawTitle = (video.rawTitle ?? video.title).toLowerCase();
    final channel = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();

    // 1. Official channel bonus
    if (channel.contains('- topic') || channel.endsWith('topic')) {
      score += 250; // Official YouTube Music delivery
    } else if (channel.contains('vevo')) {
      score += 200; // Official VEVO
    } else if (channel.contains('official')) {
      score += 80;
    }

    // 2. Title upload signals
    if (rawTitle.contains('official audio')) {
      score += 150;
    } else if (rawTitle.contains('official music video') || rawTitle.contains('official video')) {
      score += 130;
    } else if (rawTitle.contains('official lyric video') || rawTitle.contains('official visualizer')) {
      score += 70;
    } else if (rawTitle.contains('audio')) {
      score += 30;
    }

    // 3. View count signal (logarithmic & relative)
    final views = parseViewCount(video);
    if (views != null && views > 0) {
      final logScore = (math.log(views + 1) / math.ln10) * 12.0;
      score += logScore;

      if (maxViewsInResultSet > 0) {
        final ratio = views / maxViewsInResultSet;
        score += ratio * 50.0;
      }
    }

    // 4. Duration sanity
    final durSec = _parseDurationSeconds(video.duration);
    if (durSec > 0) {
      if (durSec >= 75 && durSec <= 480) {
        score += 25;
      } else if (durSec > 900) {
        score -= 250;
      } else if (durSec < 40) {
        score -= 150;
      }
    }

    // 5. Derivative edit demotion
    final intent = QueryIntent.fromQuery(query);
    final editType = detectEditType(video, intent);
    if (editType != EditType.none) {
      score -= 400.0;
    }

    // 6. Fan lyric-only upload slight demotion compared to official
    if (rawTitle.contains('lyrics') && !rawTitle.contains('official')) {
      score -= 40.0;
    }

    return score;
  }

  /// Checks whether candidates contain a high proportion of edits or low-quality results.
  static bool hasHighEditRatio(List<YouTubeVideo> videos, String query) {
    if (videos.isEmpty) return false;
    final intent = QueryIntent.fromQuery(query);
    int editCount = 0;
    for (final v in videos) {
      if (detectEditType(v, intent) != EditType.none) {
        editCount++;
      }
    }
    return (editCount / videos.length) >= 0.35;
  }
}
