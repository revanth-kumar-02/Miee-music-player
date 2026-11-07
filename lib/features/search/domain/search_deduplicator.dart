import 'dart:math' as math;
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/domain/music_result_classifier.dart';
import '../../../shared/models/music_item.dart';
import '../../recommendations/domain/music_language_service.dart';

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
  fanEdit,         // fan edit, edit audio, AMV edit, fanmade edit, standalone edits, trending
  slowedReverb,    // slowed + reverb, slowed down, reverse, slowed+reverse
  spedUpNightcore, // sped up, speed up, nightcore
  statusVideo,     // whatsapp status, status video, #shorts, reels
  compilationMix,  // jukebox, non-stop, continuous mix, full album
  mashupRemake,    // mashup, X spiderman, crossover, remake
  audioModified,   // bass audio, bass boosted, 8D audio
  promoTeaser,     // promo, teaser, trailer, preview, promo video, glimpse
  documentaryMaking, // documentary, making of, behind the scenes, interview
  nonMusicEntertainment, // comedy clips, podcasts, talk shows, vlogs, reactions, gaming, sketches
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
  final bool wantsMashup;
  final bool wantsAudioModified;
  final bool wantsPromo;
  final bool wantsDocumentary;

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
    this.wantsMashup = false,
    this.wantsAudioModified = false,
    this.wantsPromo = false,
    this.wantsDocumentary = false,
  });

  factory QueryIntent.fromQuery(String? rawQuery) {
    if (rawQuery == null || rawQuery.trim().isEmpty) {
      return const QueryIntent(normalizedQuery: '');
    }
    final q = rawQuery.toLowerCase();
    return QueryIntent(
      normalizedQuery: q,
      wants4kEdit: q.contains('4k') || q.contains('edit'),
      wantsFanEdit: q.contains('fan edit') || q.contains('edit audio') || q.contains('amv') || q.contains('edit'),
      wantsSlowed: q.contains('slowed') || q.contains('reverb') || q.contains('slow down') || q.contains('slow') || q.contains('reverse'),
      wantsSpedUp: q.contains('sped up') || q.contains('speed up') || q.contains('nightcore') || q.contains('speedup'),
      wantsStatus: q.contains('status') || q.contains('shorts') || q.contains('short') || q.contains('reels'),
      wantsCompilation: q.contains('jukebox') || q.contains('non stop') || q.contains('nonstop') || q.contains('mix') || q.contains('compilation'),
      wantsRemix: q.contains('remix') || q.contains('club mix') || q.contains('vip mix'),
      wantsLive: q.contains('live') || q.contains('concert') || q.contains('tour'),
      wantsAcoustic: q.contains('acoustic') || q.contains('unplugged'),
      wantsCover: q.contains('cover') || q.contains('tribute'),
      wantsInstrumental: q.contains('instrumental') || q.contains('karaoke'),
      wantsMashup: q.contains('mashup') || q.contains('crossover') || q.contains(' x ') || q.contains(' vs ') || q.contains('remake'),
      wantsAudioModified: q.contains('bass') || q.contains('8d') || q.contains('boosted') || q.contains('atmos'),
      wantsPromo: q.contains('promo') || q.contains('teaser') || q.contains('trailer') || q.contains('preview'),
      wantsDocumentary: q.contains('documentary') || q.contains('making of') || q.contains('interview') || q.contains('bts'),
    );
  }
}

/// Internal representation of a track's canonical identity for clustering.
class _CanonicalSongSignature {
  final String normalizedTitle;
  final String normalizedArtist;
  final VersionType versionType;
  final String versionTag;
  final String language;
  final int durationSeconds;
  final String rawTitle;
  final String rawChannel;
  final bool isGenericUploader;

  const _CanonicalSongSignature({
    required this.normalizedTitle,
    required this.normalizedArtist,
    required this.versionType,
    required this.versionTag,
    this.language = 'Unknown',
    required this.durationSeconds,
    required this.rawTitle,
    required this.rawChannel,
    required this.isGenericUploader,
  });
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

    // 1. Deduplicate by unique YouTube Video ID first and filter out confirmed non-music items
    final seenIds = <String>{};
    final uniqueVideos = <YouTubeVideo>[];
    for (final video in videos) {
      if (video.id.isNotEmpty && seenIds.add(video.id)) {
        if (MusicResultClassifier.isValidMusicTrack(video, query: query)) {
          uniqueVideos.add(video);
        }
      }
    }

    if (uniqueVideos.isEmpty) return const [];

    // 2. Group videos by canonical song signature while tracking first discovery index
    final groups = <List<YouTubeVideo>>[];
    final groupSignatures = <_CanonicalSongSignature>[];
    final groupFirstIndex = <int>[];

    for (var i = 0; i < uniqueVideos.length; i++) {
      final video = uniqueVideos[i];
      final sig = _computeCanonicalSignature(video);

      int matchingGroupIndex = -1;
      for (var g = 0; g < groups.length; g++) {
        if (_isSameCanonicalSong(groupSignatures[g], sig)) {
          matchingGroupIndex = g;
          break;
        }
      }

      if (matchingGroupIndex >= 0) {
        groups[matchingGroupIndex].add(video);
      } else {
        groups.add([video]);
        groupSignatures.add(sig);
        groupFirstIndex.add(i);
      }
    }

    // 3. For each group, rank candidates and pick the best representative
    final representatives = <({int orderIndex, YouTubeVideo video})>[];

    for (var g = 0; g < groups.length; g++) {
      final candidates = groups[g];
      final orderIndex = groupFirstIndex[g];

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
        final rawTitle = (v.rawTitle ?? v.title).toLowerCase();
        final channelLower = (v.rawChannelTitle ?? v.channelTitle).toLowerCase();
        final isOfficial = channelLower.contains('- topic') ||
            channelLower.endsWith('topic') ||
            channelLower.contains('vevo') ||
            _isOfficialMusicLabel(channelLower) ||
            _isVerifiedArtist(channelLower);

        final isUnwantedEdit = editType != EditType.none;
        // Check relative view threshold: if maxViews is substantial (e.g. >= 100K)
        // and this video has extremely low views (< 5% of maxViews and < minViewCountForEdits)
        final isLowViewDerivative = maxViews >= 100000 &&
            views != null &&
            views < (maxViews * config.relativeViewRatioThreshold) &&
            views < config.minViewCountForEdits &&
            isUnwantedEdit;

        // Prune low-view fan lyric videos and unofficial re-uploads when an authoritative version exists
        final isFanLyricUpload = rawTitle.contains('lyrics') &&
            !rawTitle.contains('official') &&
            !isOfficial &&
            maxViews >= 500000 &&
            views != null &&
            views < (maxViews * 0.05);

        final isLowViewFanReupload = !isOfficial &&
            maxViews >= 500000 &&
            views != null &&
            views < (maxViews * 0.02) &&
            views < 50000;

        if (!isUnwantedEdit && !isLowViewDerivative && !isFanLyricUpload && !isLowViewFanReupload) {
          canonicalList.add(v);
        }
      }

      // Safe fallback: If filtering would eliminate every result because all were edits,
      // retain candidateList ONLY if it contains valid music tracks (not non-music entertainment).
      final validCandidates = candidateList
          .where((v) => detectEditType(v, intent) != EditType.nonMusicEntertainment)
          .toList();
      final resultPool = canonicalList.isNotEmpty ? canonicalList : validCandidates;
      if (resultPool.isEmpty) return const [];

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

  /// Checks whether two YouTube videos represent the same underlying canonical song.
  /// Computes a canonical recording key for any [MusicItem] (Track, Song, etc.).
  /// Used across Queue, PlayerController, Recommendations and Search to eliminate duplicate uploads.
  static String computeRecordingKey(MusicItem track) {
    final rawTitle = track.title;
    final rawArtist = track.artist;
    final versionInfo = _extractVersion(rawTitle, rawTitle);
    final baseTitle = _normalizeBaseTitle(rawTitle, rawTitle, rawArtist);
    final isGeneric = _isGenericUploader(rawArtist);
    if (isGeneric) {
      return '$baseTitle|${versionInfo.tag}';
    }
    final normArtist = _normalizeArtist(rawArtist);
    return '$baseTitle|$normArtist|${versionInfo.tag}';
  }

  /// Checks whether two [MusicItem]s represent the same underlying canonical recording.
  static bool isSameCanonicalRecording(MusicItem a, MusicItem b) {
    if (a.id.isNotEmpty && b.id.isNotEmpty && a.id == b.id) return true;
    final keyA = computeRecordingKey(a);
    final keyB = computeRecordingKey(b);
    if (keyA == keyB) return true;

    final vA = _extractVersion(a.title, a.title);
    final vB = _extractVersion(b.title, b.title);
    if (vA.tag != vB.tag) return false;

    final baseA = _normalizeBaseTitle(a.title, a.title, a.artist);
    final baseB = _normalizeBaseTitle(b.title, b.title, b.artist);
    if (_titlesMatchSubstantially(baseA, baseB)) {
      final genA = _isGenericUploader(a.artist);
      final genB = _isGenericUploader(b.artist);
      if (genA || genB) return true;
      final artA = _normalizeArtist(a.artist);
      final artB = _normalizeArtist(b.artist);
      if (artA == artB) return true;
    }
    return false;
  }

  static bool isSameCanonicalSong(YouTubeVideo a, YouTubeVideo b) {
    final sigA = _computeCanonicalSignature(a);
    final sigB = _computeCanonicalSignature(b);
    return _isSameCanonicalSong(sigA, sigB);
  }

  /// Computes a canonical signature for clustering YouTube results.
  static _CanonicalSongSignature _computeCanonicalSignature(YouTubeVideo video) {
    final rawOrCleanTitle = (video.rawTitle != null && video.rawTitle!.isNotEmpty)
        ? video.rawTitle!
        : video.title;
    final rawOrCleanChannel = (video.channelTitle.isNotEmpty)
        ? video.channelTitle
        : (video.rawChannelTitle ?? '');

    final versionInfo = _extractVersion(rawOrCleanTitle, video.title);
    final normalizedTitle = _normalizeBaseTitle(video.title, rawOrCleanTitle, rawOrCleanChannel);
    final normalizedArtist = _normalizeArtist(rawOrCleanChannel);
    final durSec = _parseDurationSeconds(video.duration);
    final isGeneric = _isGenericUploader(rawOrCleanChannel);
    final language = MusicLanguageService.detectLanguage(rawOrCleanTitle, artist: rawOrCleanChannel);

    return _CanonicalSongSignature(
      normalizedTitle: normalizedTitle,
      normalizedArtist: normalizedArtist,
      versionType: versionInfo.type,
      versionTag: versionInfo.tag,
      language: language,
      durationSeconds: durSec,
      rawTitle: rawOrCleanTitle,
      rawChannel: rawOrCleanChannel,
      isGenericUploader: isGeneric,
    );
  }

  /// Computes a canonical key: `canonical_title|canonical_artist|version_tag`
  static String computeCanonicalKey(YouTubeVideo video) {
    final sig = _computeCanonicalSignature(video);
    return '${sig.normalizedTitle}|${sig.normalizedArtist}|${sig.versionTag}';
  }

  /// Evaluates whether two signatures represent identical recordings or distinct songs.
  static bool _isSameCanonicalSong(_CanonicalSongSignature a, _CanonicalSongSignature b) {
    // 1. Version tags MUST match (e.g. standard vs remix vs cover vs acoustic vs live)
    if (a.versionTag != b.versionTag) return false;

    // 1b. Distinct known languages must NOT be merged (e.g. Tamil vs Telugu vs Hindi)
    if (a.language != 'Unknown' && b.language != 'Unknown' && a.language != b.language) {
      return false;
    }

    // 2. Base titles must match substantially
    final titlesMatch = _titlesMatchSubstantially(a.normalizedTitle, b.normalizedTitle);
    if (!titlesMatch) return false;

    // 3. If normalized artists match, it's definitely the same song
    if (a.normalizedArtist == b.normalizedArtist) return true;

    // 4. Check durations if available
    final hasDurations = a.durationSeconds > 0 && b.durationSeconds > 0;
    final durDiff = (a.durationSeconds - b.durationSeconds).abs();

    // 4b. When titles match substantially and version tags match:
    // Fan uploads and re-uploads regularly trim musical intros or add end cards (durDiff up to 45s).
    if (hasDurations && durDiff <= 45) {
      if (a.isGenericUploader || b.isGenericUploader) return true;
      final rawTitleA = a.rawTitle.toLowerCase();
      final rawTitleB = b.rawTitle.toLowerCase();
      if (a.normalizedArtist.isNotEmpty && rawTitleB.contains(a.normalizedArtist)) return true;
      if (b.normalizedArtist.isNotEmpty && rawTitleA.contains(b.normalizedArtist)) return true;
    }

    // If durations differ by more than 45s, they are distinct recordings
    if (hasDurations && durDiff > 45) {
      return false;
    }

    // 5. If one or both uploaders is a generic channel / record label / fan distributor,
    // and durations match within 20s, they are alternate uploads of the same underlying track
    if (a.isGenericUploader || b.isGenericUploader) {
      return true;
    }

    // 6. Check if one artist is credited in the other's raw title or channel credits
    final rawTitleA = a.rawTitle.toLowerCase();
    final rawTitleB = b.rawTitle.toLowerCase();
    final artistA = a.normalizedArtist;
    final artistB = b.normalizedArtist;

    if (artistA.isNotEmpty && rawTitleB.contains(artistA)) return true;
    if (artistB.isNotEmpty && rawTitleA.contains(artistB)) return true;

    // 7. For film music with identical duration (within 5s) and identical titles:
    // (e.g. composer credited on one upload vs singer credited on another)
    if (hasDurations && durDiff <= 5 && a.normalizedTitle == b.normalizedTitle) {
      return true;
    }

    // Otherwise, conservatively preserve as different songs by different artists
    return false;
  }

  /// Collapses interchangeable doubled vowels and phonetic variants in transliterated titles
  static String _phoneticCollapse(String text) {
    return text
        .replaceAll('aa', 'a')
        .replaceAll('ee', 'e')
        .replaceAll('ii', 'i')
        .replaceAll('oo', 'o')
        .replaceAll('uu', 'u')
        .replaceAll('dha', 'tha')
        .replaceAll('dhe', 'the')
        .replaceAll('dhi', 'thi');
  }

  /// Checks if two normalized titles match substantially (ignoring common regional prefixes and transliterations).
  static bool _titlesMatchSubstantially(String t1, String t2) {
    if (t1 == t2) return true;
    if (t1.isEmpty || t2.isEmpty) return false;
    if (t1 == 'en $t2' || t2 == 'en $t1') return true;
    if ((t1.startsWith(t2) || t2.startsWith(t1)) && (t1.length - t2.length).abs() <= 5) {
      return true;
    }

    final p1 = _phoneticCollapse(t1);
    final p2 = _phoneticCollapse(t2);
    if (p1 == p2) return true;
    if (p1 == 'en $p2' || p2 == 'en $p1') return true;
    if ((p1.startsWith(p2) || p2.startsWith(p1)) && (p1.length - p2.length).abs() <= 5) {
      return true;
    }

    return false;
  }

  /// Checks whether a channel is a generic record label, distributor, or fan uploader.
  static bool _isGenericUploader(String channel) {
    final lower = channel.toLowerCase();
    // Do not flag official artist VEVO as generic (e.g. AdeleVEVO, LionelRichieVEVO)
    final clean = lower.endsWith('vevo') ? lower.substring(0, lower.length - 4) : lower;
    if (clean == 'adele' || clean == 'lionelrichie' || clean == 'lanadelrey') {
      return false;
    }

    return lower.startsWith('@') ||
        lower.contains('@') ||
        lower.contains('vevo') ||
        lower.contains('topic') ||
        lower.contains('music') ||
        lower.contains('records') ||
        lower.contains('record') ||
        lower.contains('label') ||
        lower.contains('channel') ||
        lower.contains('series') ||
        lower.contains('saregama') ||
        lower.contains('aditya') ||
        lower.contains('lahari') ||
        lower.contains('production') ||
        lower.contains('productions') ||
        lower.contains('entertainment') ||
        lower.contains('studios') ||
        lower.contains('studio') ||
        lower.contains('films') ||
        lower.contains('film') ||
        lower.contains('media') ||
        lower.contains('company') ||
        lower.contains('audio') ||
        lower.contains('creations') ||
        lower.contains('creation') ||
        lower.contains('divo') ||
        lower.contains('think') ||
        lower.contains('wunderbar') ||
        lower.contains('t-series') ||
        lower.contains('tseries') ||
        lower.contains('sony') ||
        lower.contains('zee') ||
        lower.contains('sun') ||
        lower.contains('gemini') ||
        lower.contains('kalaignar') ||
        lower.contains('vijay') ||
        lower.contains('tv') ||
        lower.contains('television') ||
        lower.contains('network') ||
        lower.contains('lyric') ||
        lower.contains('lyrics') ||
        lower.contains('lyrical') ||
        lower.contains('lyricist') ||
        lower.contains('songs') ||
        lower.contains('song') ||
        lower.contains('melody') ||
        lower.contains('info') ||
        lower.contains('zone') ||
        lower.contains('tune') ||
        lower.contains('tunes') ||
        lower.contains('hub') ||
        lower.contains('box') ||
        lower.contains('central') ||
        lower.contains('red') ||
        lower.contains('jan') ||
        lower.contains('club') ||
        lower.contains('upload') ||
        lower.contains('uploads') ||
        lower.contains('beatz') ||
        lower.contains('beats') ||
        lower.contains('fx') ||
        lower.contains('status') ||
        lower.contains('editz') ||
        lower.contains('edits') ||
        lower.contains('edit') ||
        lower.contains('amv') ||
        lower.contains('vfx') ||
        lower.contains('toono1') ||
        lower.contains('bgm') ||
        lower.contains('looper') ||
        lower.contains('vibes') ||
        lower == 'youtube' ||
        lower == 'unknown' ||
        lower == 'various artists';
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

    // 2. Remove bracketed upload packaging noise (e.g. [Official Video], (Lyrics), (Tamil), (Visualizer + HQ + SFX), (NEW), etc.)
    final bracketNoiseRegex = RegExp(
      r'[\(\[\{][^\)\]\}]*(official|music\s+video|video|audio|lyric|lyrics|lyrical|visualizer|mv|hd|4k|hq|1080p|remaster|high\s+quality|explicit|clean|sfx|new|trend|trending|status|hit|hits|tamil|telugu|hindi|malayalam|kannada|bengali|marathi|punjabi|gujarati|bhojpuri|odia|assamese|english|spanish|french|german|korean|japanese)[^\)\]\}]*[\)\]\}]',
      caseSensitive: false,
    );
    title = title.replaceAll(bracketNoiseRegex, ' ');

    // 2b. Remove common parenthetical commentary noise (e.g. "(but your life will be changed)", "(listen with headphones)")
    final commentaryBracketRegex = RegExp(
      r'[\(\[\{]\s*(but\s+|you\s+|feeling\s+|listening\s+|read\s+|listen\s+|pov\s*[\:\-]|headphones)[^\)\]\}]*[\)\]\}]',
      caseSensitive: false,
    );
    title = title.replaceAll(commentaryBracketRegex, ' ');

    // 2c. Remove leading packaging noise (e.g. "Full Video: ", "Video Song: ", "Official Video: ", "HD Video Song: ")
    final leadingNoiseRegex = RegExp(
      r'^(full\s+video(\s+song)?|official\s+video(\s+song)?|official\s+music\s+video|video\s+song|lyric\s+video|official\s+audio|audio\s+song|hd\s+video(\s+song)?|4k\s+video(\s+song)?|full\s+song|song)\s*[:\-\–\—\|\•]\s*',
      caseSensitive: false,
    );
    title = title.replaceAll(leadingNoiseRegex, ' ');

    // 2d. Remove leading composer brand prefixes (e.g. "A.R. Rahman Musical - ")
    final composerPrefixRegex = RegExp(
      r'^[a-z0-9\.\s]+musical\s*[:\-\–\—\|\•]\s*',
      caseSensitive: false,
    );
    title = title.replaceAll(composerPrefixRegex, ' ');

    // 2e. Remove movie prefix with colon (e.g. "Galatta Kalyanam: Kaadhalai Solla Mudiyatha")
    if (title.contains(':')) {
      final colonParts = title.split(':');
      if (colonParts.length == 2 && colonParts[1].trim().length >= 4) {
        title = colonParts[1].trim();
      }
    }

    // 3. Remove trailing upload noise (e.g. " - Official Audio", " | Lyric Video", " Song")
    final trailingNoiseRegex = RegExp(
      r'[\s\-\–\—\|\:]+(official\s+music\s+video|official\s+video|official\s+audio|lyrical\s+video|lyrics\s+video|lyric\s+video|lyrical|lyrics|lyric|video\s+song|video|visualizer|mv|hd|4k|hq|1080p|audio|full\s+song|song)[\s]*$',
      caseSensitive: false,
    );
    while (trailingNoiseRegex.hasMatch(title)) {
      title = title.replaceFirst(trailingNoiseRegex, ' ').trim();
    }

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

  /// Checks if channel belongs to a verified music artist or official channel.
  static bool _isVerifiedArtist(String rawChannel) {
    if (_isOfficialMusicLabel(rawChannel)) return true;
    final lower = rawChannel.toLowerCase().trim();
    final verified = [
      'dhanush',
      'anirudh ravichander',
      'anirudh',
      'a.r. rahman',
      'ar rahman',
      'sai abhyankkar',
      'yuvan shankar raja',
      'yuvan',
      'harris jayaraj',
      'sid sriram',
      'devi sri prasad',
      'santhosh narayanan',
      'g.v. prakash',
      'gv prakash',
      'tippu',
      'pradeep kumar',
      'karthik',
      'shreya ghoshal',
      'arijit singh',
      'coldplay',
      'ed sheeran',
      'dua lipa',
      'taylor swift',
      'the weeknd',
      'bts',
      'drake',
      'eminem',
      'adele',
      'billie eilish',
      'sanjay subrahmanyan',
    ];
    for (final a in verified) {
      if (lower == a ||
          lower.startsWith('$a ') ||
          lower.endsWith(' $a') ||
          lower == '$a official' ||
          lower.contains('$a vevo')) {
        return true;
      }
    }
    return false;
  }

  /// Checks whether a channel is a recognized major music record label.
  static bool _isOfficialMusicLabel(String rawChannel) {
    final lower = rawChannel.toLowerCase();
    return lower.contains('think music') ||
        lower.contains('think indie') ||
        lower.contains('sony music') ||
        lower.contains('t-series') ||
        lower.contains('tseries') ||
        lower.contains('saregama') ||
        lower.contains('zee music') ||
        lower.contains('aditya music') ||
        lower.contains('lahari music') ||
        lower.contains('yrf') ||
        lower.contains('speed records') ||
        lower.contains('tips official') ||
        lower.contains('muzik247') ||
        lower.contains('satyam') ||
        lower.contains('universal music') ||
        lower.contains('warner music') ||
        lower.contains('atlantic records') ||
        lower.contains('columbia records') ||
        lower.contains('def jam') ||
        lower.contains('interscope') ||
        lower.contains('sun tv') ||
        lower.contains('sun pictures') ||
        lower.contains('sun gemini') ||
        lower.contains('sun nxt') ||
        lower.contains('kalaignar') ||
        lower.contains('vijay television') ||
        lower.contains('star vijay') ||
        lower.contains('star maa') ||
        lower.contains('zee tamil') ||
        lower.contains('zee telugu');
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
      score += 130; // Official YouTube Music track delivery
    } else if (rawChannel.contains('vevo') || _isOfficialMusicLabel(rawChannel)) {
      score += 130; // Official major music label or VEVO channel
    } else if (rawChannel.contains('official')) {
      score += 40;
    }

    // 2. Official audio / music video upload signals
    if (rawTitle.contains('official audio')) {
      score += 100; // Preferred standard recording upload
    } else if (rawTitle.contains('official music video') ||
        rawTitle.contains('official video') ||
        rawTitle.contains('(music video)') ||
        rawTitle.contains('[music video]') ||
        rawTitle.contains('music video') ||
        rawTitle.contains('video song')) {
      score += 85;
    } else if (rawTitle.contains('full video')) {
      score += 20; // Video releases often contain extended non-musical intros/dialogue
    } else if (rawTitle.contains('official visualizer') || rawTitle.contains('visualizer')) {
      score += 50;
    } else if (rawTitle.contains('audio')) {
      score += 30;
    }

    // Lyrics uploads are legitimate backups but ranked lower than authentic releases
    if (rawTitle.contains('lyrics') || rawTitle.contains('lyric video')) {
      score -= 15;
    }

    // 3. Query match bonuses with phonetic variant support (e.g. radhima vs radhimaa)
    if (query != null && query.trim().isNotEmpty) {
      final sanitizedQuery = _sanitizeText(query);
      final sanitizedCleanTitle = _sanitizeText(cleanTitle);
      final pQuery = _phoneticCollapse(sanitizedQuery);
      final pTitle = _phoneticCollapse(sanitizedCleanTitle);
      if (sanitizedCleanTitle == sanitizedQuery || pTitle == pQuery) {
        score += 50;
      } else if (sanitizedCleanTitle.contains(sanitizedQuery) || pTitle.contains(pQuery)) {
        score += 25;
      }
    }

    // 4. View count popularity bonus (scaled logarithmic scaling)
    final views = parseViewCount(video);
    if (views != null && views > 0) {
      score += ((math.log(views + 1) / math.ln10) * 12).toInt();
    }

    // 5. Duration sanity check
    final durationSeconds = _parseDurationSeconds(video.duration);
    if (durationSeconds > 0) {
      // Normal song range: 75 seconds (1:15) to 480 seconds (8:00)
      if (durationSeconds >= 75 && durationSeconds <= 480) {
        score += 20;
      } else if (durationSeconds > 900) {
        // Demote long duration unless it is classical, symphony, or live concert
        final isClassicalOrConcert = rawTitle.contains('symphony') ||
            rawTitle.contains('classical') ||
            rawTitle.contains('concert') ||
            rawTitle.contains('raga') ||
            rawTitle.contains('live at') ||
            rawTitle.contains('extended mix');
        if (!isClassicalOrConcert) {
          score -= 150;
        }
      } else if (durationSeconds < 40) {
        // Less than 40 seconds is likely a ringtone, teaser, or preview
        score -= 100;
      }
    }

    // 6. Demote clickbait, unofficial edit channels, and low-quality modifiers
    if ((rawChannel.contains('editz') ||
            rawChannel.contains('edits') ||
            rawChannel.contains('beatz') ||
            rawChannel.contains('status')) &&
        !_isOfficialMusicLabel(rawChannel)) {
      score -= 100;
    }

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
      'promo',
      'documentary',
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
    // 0. Non-music entertainment check (comedy, podcasts, vlogs, reactions, web series, roasts, etc.)
    if (!MusicResultClassifier.isValidMusicTrack(video, query: intent.normalizedQuery)) {
      return EditType.nonMusicEntertainment;
    }

    final rawTitle = (video.rawTitle ?? video.title).toLowerCase();
    final cleanTitle = video.title.toLowerCase();
    final channelLower = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();
    final collapsedTitle = rawTitle.replaceAll(RegExp(r'\s+'), '');

    // 1. 4K edit / status check
    if (!intent.wants4kEdit) {
      if (rawTitle.contains('4k edit') ||
          rawTitle.contains('4k status') ||
          rawTitle.contains('4k 60fps') ||
          rawTitle.contains('4k hdr edit') ||
          collapsedTitle.contains('4kedit') ||
          collapsedTitle.contains('4kstatus') ||
          RegExp(r'\b4k\s+(edit|audio|status|version)\b').hasMatch(rawTitle)) {
        return EditType.fourKEdit;
      }
    }

    // 2. Fan edit / edit audio / standalone edits / trending
    if (!intent.wantsFanEdit && !intent.wants4kEdit) {
      if (rawTitle.contains('fan edit') ||
          rawTitle.contains('edit audio') ||
          rawTitle.contains('audio edit') ||
          rawTitle.contains('amv edit') ||
          rawTitle.contains('amv') ||
          rawTitle.contains('editz') ||
          channelLower.contains('editz') ||
          channelLower.contains('amv') ||
          channelLower.contains('vfx') ||
          (channelLower.contains('edit') && !_isOfficialMusicLabel(channelLower)) ||
          rawTitle.contains('fanmade edit') ||
          rawTitle.contains('anime edit') ||
          rawTitle.contains('trending') ||
          rawTitle.contains('new trending') ||
          rawTitle.contains('viral song') ||
          rawTitle.contains('trend song') ||
          collapsedTitle.contains('fanedit') ||
          collapsedTitle.contains('audioedit') ||
          RegExp(r'[\(\[\{\|\-]\s*(edit|edits|editz|fan\s*edit|audio\s*edit|trending)\b', caseSensitive: false).hasMatch(rawTitle) ||
          RegExp(r'\b(edit|edits|editz)\b', caseSensitive: false).hasMatch(rawTitle)) {
        if (!rawTitle.contains('radio edit') && !rawTitle.contains('edition')) {
          return EditType.fanEdit;
        }
      }
    }

    // 3. Status video / shorts / reels / ringtones
    if (!intent.wantsStatus) {
      if (rawTitle.contains('whatsapp status') ||
          rawTitle.contains('status video') ||
          rawTitle.contains('fullscreen status') ||
          rawTitle.contains('full screen status') ||
          rawTitle.contains('shorts video') ||
          rawTitle.contains('#shorts') ||
          rawTitle.contains('short video') ||
          rawTitle.contains('#short') ||
          rawTitle.contains('#reels') ||
          rawTitle.contains('reels video') ||
          rawTitle.contains('ringtone') ||
          rawTitle.contains('ringtones') ||
          channelLower.contains('ringtone') ||
          channelLower.contains('ringtones') ||
          collapsedTitle.contains('statusvideo') ||
          collapsedTitle.contains('whatsappstatus') ||
          RegExp(r'\b(status\s+video|wa\s+status|lyric\s+status|ringtone|ringtones)\b').hasMatch(rawTitle)) {
        return EditType.statusVideo;
      }

      // Check short duration clip (<= 85s) from fan/status channels unless user requested edits
      if (!intent.wants4kEdit && !intent.wantsFanEdit) {
        final durSec = _parseDurationSeconds(video.duration);
        if (durSec > 0 && durSec <= 85) {
          if (channelLower.contains('status') ||
              channelLower.contains('fx') ||
              channelLower.contains('beatz') ||
              channelLower.contains('beats') ||
              channelLower.contains('edit') ||
              channelLower.contains('creation') ||
              channelLower.contains('ringtone') ||
              rawTitle.contains('status') ||
              rawTitle.contains('edit') ||
              rawTitle.contains('clip') ||
              rawTitle.contains('bgm')) {
            return EditType.statusVideo;
          }
        }
      }
    }

    // 4. Slowed + reverb / reverse (Conservative: don't flag "Slow Down" or "Slow Hands")
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
            rawTitle.contains('reverse') ||
            rawTitle.contains('slowed+reverse') ||
            rawTitle.contains('slowed + reverse') ||
            rawTitle.contains('slowed & reverse') ||
            collapsedTitle.contains('slowed') ||
            collapsedTitle.contains('reverb') ||
            collapsedTitle.contains('reverse') ||
            RegExp(r'[\(\[\{]\s*(slowed|reverb|reverse)\s*[\)\]\}]').hasMatch(rawTitle)) {
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
            collapsedTitle.contains('nightcore') ||
            collapsedTitle.contains('spedup') ||
            collapsedTitle.contains('speedup') ||
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
          rawTitle.contains('all songs') ||
          rawTitle.contains('all song') ||
          rawTitle.contains('song collection') ||
          rawTitle.contains('songs collection') ||
          rawTitle.contains('hits collection') ||
          rawTitle.contains('best songs of') ||
          rawTitle.contains('best of songs') ||
          rawTitle.contains('top 10 songs') ||
          rawTitle.contains('top 20 songs') ||
          rawTitle.contains('top 50 songs') ||
          rawTitle.contains('back to back songs') ||
          rawTitle.contains('b2b songs') ||
          rawTitle.contains('all songs compilation') ||
          rawTitle.contains('full album compilation') ||
          rawTitle.contains('full album songs') ||
          rawTitle.contains('full album jukebox') ||
          rawTitle.contains('full songs jukebox')) {
        return EditType.compilationMix;
      }
      final durSec = _parseDurationSeconds(video.duration);
      if (durSec > 600 &&
          !rawTitle.contains('symphony') &&
          !rawTitle.contains('raga') &&
          !rawTitle.contains('recital') &&
          !rawTitle.contains('classical') &&
          !rawTitle.contains('concerto') &&
          !rawTitle.contains('concert')) {
        return EditType.compilationMix;
      }
    }

    // 7. Mashups / Crossovers / Remakes / Multimixes
        if (!intent.wantsMashup) {
      if (RegExp(r'\b(batman|spiderman|superman|iron\s*man|anime|amv|goku|naruto|luffy)\b.*\b(ft\.?|x|vs\.?)\b', caseSensitive: false).hasMatch(rawTitle)) {
        return EditType.mashupRemake;
      }
      if (rawTitle.contains('mashup') ||
          rawTitle.contains('mash up') ||
          rawTitle.contains('crossover') ||
          rawTitle.contains('remake') ||
          rawTitle.contains('re-make') ||
          rawTitle.contains('multimix') ||
          rawTitle.contains('multi mix') ||
          rawTitle.contains('megamix') ||
          rawTitle.contains('mega mix') ||
          rawTitle.contains(' vs ') ||
          rawTitle.contains(' vs. ') ||
          rawTitle.contains('×') ||
          rawTitle.contains('\u00D7') ||
          rawTitle.contains('\u2715') ||
          rawTitle.contains('\u2716') ||
          rawTitle.contains(' x ') ||
          rawTitle.contains(' x-') ||
          rawTitle.contains('-x ') ||
          rawTitle.contains('500 days of summer') ||
          rawTitle.contains('500 days') ||
          rawTitle.contains('premalu') ||
          collapsedTitle.contains('multimix') ||
          collapsedTitle.contains('megamix') ||
          collapsedTitle.contains('mashup') ||
          RegExp(r'[\s\(\[\{]([xX\u00D7]|vs\.?)\s+[a-zA-Z0-9]', caseSensitive: false).hasMatch(rawTitle) ||
          RegExp(r'\b[a-zA-Z0-9]+\s*[xX\u00D7]\s*[a-zA-Z0-9]+\b').hasMatch(rawTitle)) {
        return EditType.mashupRemake;
      }
    }

    // 8. Audio Modifications / Boosts (e.g. "bass audio", "bass boosted", "8D audio")
    if (!intent.wantsAudioModified) {
      if (rawTitle.contains('bass audio') ||
          rawTitle.contains('bass boosted') ||
          rawTitle.contains('bassboosted') ||
          rawTitle.contains('bass boost') ||
          rawTitle.contains('bass pro') ||
          rawTitle.contains('8d audio') ||
          rawTitle.contains('3d audio') ||
          rawTitle.contains('16d audio') ||
          rawTitle.contains('dolby atmos edit') ||
          rawTitle.contains('dts audio') ||
          rawTitle.contains('earrape') ||
          rawTitle.contains('boosted') ||
          collapsedTitle.contains('boosted') ||
          collapsedTitle.contains('bassboost') ||
          collapsedTitle.contains('8daudio') ||
          RegExp(r'\b(bass\s+(audio|boosted|boost)|8d\s+audio|boosted)\b').hasMatch(rawTitle)) {
        return EditType.audioModified;
      }
    }

    // 9. Promos, Teasers, Previews, Trailers & Brand Promo Ads (e.g. "Radhimaa (Promo)", "Be a Thangamaana Paiyan | Spotify India")
    if (!intent.wantsPromo) {
      if (rawTitle.contains('promo') ||
          rawTitle.contains('teaser') ||
          rawTitle.contains('trailer') ||
          rawTitle.contains('preview') ||
          rawTitle.contains('sneak peek') ||
          rawTitle.contains('glimpse') ||
          rawTitle.contains('be a thangamaana paiyan') ||
          collapsedTitle.contains('promo') ||
          collapsedTitle.contains('teaser') ||
          collapsedTitle.contains('trailer') ||
          collapsedTitle.contains('thangamaanapaiyan') ||
          RegExp(r'[\(\[\{\|\-]\s*(promo|teaser|trailer|preview|glimpse)\b', caseSensitive: false).hasMatch(rawTitle) ||
          RegExp(r'\b(promo|teaser|trailer|preview|glimpse)\b', caseSensitive: false).hasMatch(rawTitle)) {
        return EditType.promoTeaser;
      }

      // Short clips (<= 90s) from streaming brands / sponsors
      final durSec = _parseDurationSeconds(video.duration);
      if (durSec > 0 && durSec <= 90) {
        if (channelLower.contains('spotify') ||
            channelLower.contains('amazon music') ||
            channelLower.contains('jiosaavn') ||
            channelLower.contains('wynk') ||
            channelLower.contains('apple music')) {
          return EditType.promoTeaser;
        }
      }
    }

    // 10. Documentaries, Behind the Scenes, Making of, Interviews
    if (!intent.wantsDocumentary) {
      if (rawTitle.contains('documentary') ||
          rawTitle.contains('making of') ||
          rawTitle.contains('behind the scenes') ||
          rawTitle.contains('interview') ||
          rawTitle.contains('press meet') ||
          rawTitle.contains('success meet') ||
          rawTitle.contains('audio launch') ||
          collapsedTitle.contains('documentary') ||
          collapsedTitle.contains('behindthescenes') ||
          RegExp(r'[\(\[\{\|\-]\s*(documentary|bts|making)\b', caseSensitive: false).hasMatch(rawTitle) ||
          RegExp(r'\b(documentary|bts)\b', caseSensitive: false).hasMatch(rawTitle)) {
        return EditType.documentaryMaking;
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

    // 1. Exact match to query (including phonetic variants like radhima / radhimaa)
    final pQuery = _phoneticCollapse(normQuery);
    final pClean = _phoneticCollapse(cleanTitle);
    final pRaw = _phoneticCollapse(rawTitle);

    if (cleanTitle == normQuery || rawTitle == normQuery || pClean == pQuery || pRaw == pQuery) {
      return 1.0;
    }

    // 2. Title contains query phrase or query phrase contains title
    if (cleanTitle.contains(normQuery) || rawTitle.contains(normQuery) || pClean.contains(pQuery) || pRaw.contains(pQuery)) {
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
      final pToken = _phoneticCollapse(token);
      if (cleanTitle.contains(token) || rawTitle.contains(token) || pClean.contains(pToken) || pRaw.contains(pToken)) {
        titleTokensMatched++;
      }
      if (allText.contains(token) || _phoneticCollapse(allText).contains(pToken)) {
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
    final rawTitle = (video.rawTitle ?? video.title).toLowerCase();
    final channel = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();
    final lang = MusicLanguageService.detectLanguage(rawTitle, artist: channel);

    final isOfficialChannel = channel.contains('- topic') ||
        channel.endsWith('topic') ||
        channel.contains('vevo') ||
        _isOfficialMusicLabel(channel) ||
        _isVerifiedArtist(channel);

    final isAlternateLanguage = lang != 'Unknown' && !query.toLowerCase().contains(lang.toLowerCase());

    // If relevance is low, but it is an official release in another language (e.g. Telugu version)
    if (relevance < 0.25) {
      if (isOfficialChannel && isAlternateLanguage) {
        // Retain legitimate official multilingual version with baseline
      } else {
        return relevance * 10.0;
      }
    }

    double score = relevance * 1000.0;

    // 1. Official channel bonus
    if (channel.contains('- topic') || channel.endsWith('topic')) {
      score += 250; // Official YouTube Music delivery
    } else if (channel.contains('vevo')) {
      score += 200; // Official VEVO
    } else if (_isOfficialMusicLabel(channel)) {
      score += 220; // Official major music label (Think Music, Sony, T-Series, etc.)
    } else if (_isVerifiedArtist(channel)) {
      score += 210; // Verified artist / composer channel (e.g. Dhanush, Anirudh)
    } else if (channel.contains('official')) {
      score += 80;
    }

    // 2. Title upload signals (hierarchical ranking)
    // Rank 1: Official original song / official music video
    if (rawTitle.contains('official music video') ||
        rawTitle.contains('official video') ||
        rawTitle.contains('(music video)') ||
        rawTitle.contains('[music video]') ||
        rawTitle.contains('music video') ||
        rawTitle.contains('video song')) {
      score += 180;
    } else if (rawTitle.contains('official audio')) {
      score += 150; // Rank 2: Official audio
    } else if (rawTitle.contains('official lyric video') ||
        rawTitle.contains('official visualizer') ||
        (rawTitle.contains('lyrical') && isOfficialChannel)) {
      score += 130; // Rank 2: Official lyrical release
    } else if (rawTitle.contains('full video')) {
      score += 100;
    } else if (rawTitle.contains('audio')) {
      score += 30;
    }

    // Rank 3: Official releases in other languages (Telugu, Hindi, etc.)
    if (isOfficialChannel && isAlternateLanguage) {
      score += 220;
    }

    // Rank 4: Legitimate version indicators (Remixes, acoustic, unplugged)
    if (rawTitle.contains('remix') || rawTitle.contains('acoustic') || rawTitle.contains('unplugged')) {
      score += 70;
    }

    // 3. View count signal (logarithmic & relative)
    final views = parseViewCount(video);
    if (views != null && views > 0) {
      final logScore = (math.log(views + 1) / math.ln10) * 14.0;
      score += logScore;

      if (maxViewsInResultSet > 0) {
        final ratio = views / maxViewsInResultSet;
        score += ratio * 55.0;
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

    // Demote unofficial info, edit, status channels
    if (!isOfficialChannel) {
      if (channel.contains('info') ||
          channel.contains('editz') ||
          channel.contains('edits') ||
          channel.contains('status')) {
        score -= 400.0;
      }
    }

    // 5. Derivative edit demotion
    final intent = QueryIntent.fromQuery(query);
    final editType = detectEditType(video, intent);
    if (editType != EditType.none) {
      score -= 400.0;
    }

    // 6. Fan lyric-only upload demotion compared to official
    if (rawTitle.contains('lyrics') && !rawTitle.contains('official') && !isOfficialChannel) {
      score -= 100.0;
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
