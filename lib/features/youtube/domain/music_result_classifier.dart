import 'youtube_model.dart';

/// Level of confidence that a YouTube result represents a genuine, playable music track.
enum MusicTrackConfidence {
  /// Confirmed official music release (Official Music Video, Official Audio,
  /// verified record label / artist channel, VEVO, YouTube Music category).
  officialMusic,

  /// Highly likely to be a legitimate song, performance, or version
  /// (matches standard song conventions, reasonable duration, positive musical cues).
  likelyMusic,

  /// Ambiguous metadata: lacks strong positive music markers, but also lacks
  /// any non-music evidence. Treated cautiously.
  uncertain,

  /// Confirmed non-music content (comedy sketch, podcast, talk show, reaction,
  /// vlog, gameplay, review, drama episode, movie scene, advertisement, etc.).
  rejected,
}

/// Detailed classification verdict for a YouTube video.
class MusicTrackClassification {
  final MusicTrackConfidence confidence;
  final bool isMusic;
  final String? rejectionReason;
  final int musicScore;

  const MusicTrackClassification({
    required this.confidence,
    required this.isMusic,
    this.rejectionReason,
    this.musicScore = 0,
  });

  @override
  String toString() =>
      'MusicTrackClassification(confidence: $confidence, isMusic: $isMusic, score: $musicScore, reason: $rejectionReason)';
}

/// A comprehensive, deterministic, zero-AI classifier that identifies genuine
/// music tracks and rejects irrelevant general YouTube videos (comedy clips, podcasts,
/// talk shows, vlogs, reactions, gameplay, web series, movie scenes, roasts, etc.).
class MusicResultClassifier {
  /// Classifies a [video] into a [MusicTrackClassification].
  static MusicTrackClassification classify(YouTubeVideo video, {String? query}) {
    final rawTitle = (video.rawTitle ?? video.title).trim();
    final rawChannel = (video.rawChannelTitle ?? video.channelTitle).trim();
    final durationSec = _parseDurationSeconds(video.duration);

    final titleLower = rawTitle.toLowerCase();
    final channelLower = rawChannel.toLowerCase();
    final queryLower = (query ?? '').toLowerCase().trim();

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Definite Non-Music Signals (REJECTION CHECKS)
    // ─────────────────────────────────────────────────────────────────────────

    // A. Comedy, sketches, jokes, roasts, pranks, memes, and laughter emojis
    final comedyPatterns = [
      'standup comedy',
      'stand-up comedy',
      'standup',
      'stand-up',
      'roast video',
      'roast',
      'prank video',
      'prank',
      'funny video',
      'funny clips',
      'funny clip',
      'funny scenes',
      'comedy scenes',
      'comedy scene',
      'comedy sketch',
      'comedy clips',
      'comedy club',
      'kaathadi club',
      'troll video',
      'meme video',
      'jokes',
      'laughter club',
      'mimicry',
      'stress buster',
      'non-stop comedy',
      'non stop comedy',
      'comedy show',
      'chiri show',
    ];

    for (final pattern in comedyPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        if (!_isExplicitQueryMatch(pattern, queryLower)) {
          return const MusicTrackClassification(
            confidence: MusicTrackConfidence.rejected,
            isMusic: false,
            rejectionReason: 'Comedy or entertainment sketch content',
          );
        }
      }
    }

    // Check for laughter emojis (😂, 🤣, 😆) in titles
    if (rawTitle.contains('😂') || rawTitle.contains('🤣') || rawTitle.contains('😆')) {
      // Unless this video is explicitly an official music release from a verified record label
      if (!_isOfficialMusicLabel(channelLower)) {
        return const MusicTrackClassification(
          confidence: MusicTrackConfidence.rejected,
          isMusic: false,
          rejectionReason: 'Comedy / meme laughter marker in title',
        );
      }
    }

    // B. Podcasts, talk shows, interviews, Q&A, and episodic content
    final podcastPatterns = [
      'podcast',
      'talk show',
      'round table',
      'interview',
      'press meet',
      'success meet',
      'press conference',
      'conversation with',
      'q&a',
      'full episode',
      'part - ',
      'part -',
      'part- ',
      'part-',
    ];

    for (final pattern in podcastPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        // Distinguish from legitimate multi-part musical suites e.g. "Shine On You Crazy Diamond (Parts I-V)"
        if (!_isLegitimateMusicalSuite(titleLower)) {
          return const MusicTrackClassification(
            confidence: MusicTrackConfidence.rejected,
            isMusic: false,
            rejectionReason: 'Podcast, talk show, interview, or episodic content',
          );
        }
      }
    }

    // Check episodic regex (e.g. "Ep 12", "Ep. 45", "Episode 10")
    final episodeRegex = RegExp(r'\b(ep|episode)\.?\s*#?\s*\d+\b', caseSensitive: false);
    if (episodeRegex.hasMatch(rawTitle) && !_isLegitimateMusicalSuite(titleLower)) {
      return const MusicTrackClassification(
        confidence: MusicTrackConfidence.rejected,
        isMusic: false,
        rejectionReason: 'Episodic numbering indicates non-music show/series',
      );
    }

    // C. Reactions, reviews, critiques, and breakdowns
    final reactionPatterns = [
      'reaction',
      'reacts to',
      'reacting to',
      'first time hearing',
      'first listen',
      'honest review',
      'album review',
      'song review',
      'breakdown',
      'analysis',
      'critique',
    ];

    for (final pattern in reactionPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        return const MusicTrackClassification(
          confidence: MusicTrackConfidence.rejected,
          isMusic: false,
          rejectionReason: 'Reaction, review, or critique video',
        );
      }
    }

    // D. Gaming, walkthroughs, vlogs, tech, tutorials, and unboxings
    final generalVideoPatterns = [
      'gameplay',
      'playthrough',
      'walkthrough',
      'gaming',
      'vlog',
      'daily vlog',
      'travel vlog',
      'unboxing',
      'tutorial',
      'how to',
      'diy',
      'live stream',
      'livestream',
      'stream archive',
      'news live',
      'highlights',
      'match highlights',
    ];

    for (final pattern in generalVideoPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        return const MusicTrackClassification(
          confidence: MusicTrackConfidence.rejected,
          isMusic: false,
          rejectionReason: 'Gaming, vlog, tutorial, news, or general video',
        );
      }
    }

    // E. Web series, movies, serials, and dramatic scenes
    final dramaScenePatterns = [
      'web series',
      'short film',
      'full movie',
      'movie scene',
      'movie scenes',
      'climax scene',
      'action scene',
      'fight scene',
      'death scene',
      'emotional scene',
      'serial',
      'telefilm',
      'natok',
      'behind the scenes',
      'making of',
    ];

    for (final pattern in dramaScenePatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        return const MusicTrackClassification(
          confidence: MusicTrackConfidence.rejected,
          isMusic: false,
          rejectionReason: 'Movie scene, short film, web series, or drama content',
        );
      }
    }

    // F. Commercial trailers, promos, teasers, ads
    final promoPatterns = [
      'official trailer',
      'movie trailer',
      'teaser trailer',
      'first look',
      'motion poster',
      'sneak peek',
    ];

    for (final pattern in promoPatterns) {
      if (titleLower.contains(pattern)) {
        return const MusicTrackClassification(
          confidence: MusicTrackConfidence.rejected,
          isMusic: false,
          rejectionReason: 'Commercial trailer or promotional preview',
        );
      }
    }

    // G. Long duration check with lack of musical evidence
    // Standard songs are typically 1.5 to 10 minutes.
    // Classical music, full concerts, DJ sets, and extended mixes are legitimate long music.
    // If a video is > 15 minutes (900 seconds) and lacks any positive musical indicators,
    // it is highly likely general entertainment, podcast, or a compilation of comedy clips.
    if (durationSec > 900) {
      final hasPositiveMusicIndicator = _hasPositiveMusicIndicator(titleLower, channelLower);
      if (!hasPositiveMusicIndicator) {
        return MusicTrackClassification(
          confidence: MusicTrackConfidence.rejected,
          isMusic: false,
          rejectionReason: 'Long duration (${video.duration}) with zero musical indicators',
        );
      }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Positive Music Signals & Confidence Scoring
    // ─────────────────────────────────────────────────────────────────────────

    int score = 25; // Baseline starting score for unverified candidates
    bool hasMusicIndicator = false;

    // Signal: Official Music Label or VEVO channel (+50 points)
    if (_isOfficialMusicLabel(channelLower)) {
      score += 50;
      hasMusicIndicator = true;
    }

    // Signal: Official Audio / Official Music Video (+40 points)
    if (titleLower.contains('official music video') ||
        titleLower.contains('official audio') ||
        titleLower.contains('official video') ||
        titleLower.contains('lyric video') ||
        titleLower.contains('audio song') ||
        titleLower.contains('video song') ||
        titleLower.contains('visualizer')) {
      score += 40;
      hasMusicIndicator = true;
    }

    // Signal: Recognized music track structure (Artist - Title) (+25 points)
    if (rawTitle.contains(' - ') || rawTitle.contains(' – ') || rawTitle.contains(' — ') || rawTitle.contains(' | ')) {
      score += 25;
      hasMusicIndicator = true;
    }

    // Signal: Legitimate musical version indicators (+30 points)
    if (_isLegitimateMusicVersion(titleLower)) {
      score += 30;
      hasMusicIndicator = true;
    }

    // Signal: Musical collaboration markers (+20 points)
    if (RegExp(r'\b(feat\.?|ft\.?|prod\.?|with)\b', caseSensitive: false).hasMatch(rawTitle)) {
      score += 20;
      hasMusicIndicator = true;
    }

    // Signal: Typical song duration (2:00 to 6:30) (+15 points)
    if (durationSec >= 120 && durationSec <= 390) {
      score += 15;
    }

    // Signal: Verified song marker in view count (+30 points)
    if (video.viewCount.toLowerCase().contains('verified song')) {
      score += 30;
      hasMusicIndicator = true;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Final Confidence Determination
    // ─────────────────────────────────────────────────────────────────────────

    if (score >= 80) {
      return MusicTrackClassification(
        confidence: MusicTrackConfidence.officialMusic,
        isMusic: true,
        musicScore: score,
      );
    } else if (hasMusicIndicator && score >= 50) {
      return MusicTrackClassification(
        confidence: MusicTrackConfidence.likelyMusic,
        isMusic: true,
        musicScore: score,
      );
    } else {
      // Ambiguous metadata (e.g. unknown channel, generic title, short/missing duration)
      // Check if it has at least some plausible music identity
      final isVeryShortClip = durationSec > 0 && durationSec < 45;
      if (isVeryShortClip && !titleLower.contains('song') && !titleLower.contains('intro')) {
        return const MusicTrackClassification(
          confidence: MusicTrackConfidence.rejected,
          isMusic: false,
          rejectionReason: 'Sub-45s short clip without musical evidence',
          musicScore: 20,
        );
      }

      return MusicTrackClassification(
        confidence: MusicTrackConfidence.uncertain,
        isMusic: true, // Preserved cautiously for indie/obscure tracks
        musicScore: score,
      );
    }
  }

  /// Convenience helper: returns true if the video is classified as acceptable music.
  static bool isValidMusicTrack(YouTubeVideo video, {String? query}) {
    final verdict = classify(video, query: query);
    return verdict.isMusic && verdict.confidence != MusicTrackConfidence.rejected;
  }

  /// Filters out rejected non-music videos and ranks results with official music prioritized.
  static List<YouTubeVideo> filterAndRankMusicTracks(
    List<YouTubeVideo> videos, {
    String? query,
    int maxResults = 30,
  }) {
    if (videos.isEmpty) return const [];

    final classified = <({YouTubeVideo video, MusicTrackClassification verdict})>[];
    for (final v in videos) {
      final verdict = classify(v, query: query);
      if (verdict.isMusic && verdict.confidence != MusicTrackConfidence.rejected) {
        classified.add((video: v, verdict: verdict));
      }
    }

    // Sort by music confidence score descending, while preserving original discovery order
    // for equal confidence tiers
    classified.sort((a, b) {
      final tierA = _confidenceTier(a.verdict.confidence);
      final tierB = _confidenceTier(b.verdict.confidence);
      if (tierA != tierB) {
        return tierB.compareTo(tierA);
      }
      return b.verdict.musicScore.compareTo(a.verdict.musicScore);
    });

    return classified.map((c) => c.video).take(maxResults).toList();
  }

  static int _confidenceTier(MusicTrackConfidence confidence) {
    switch (confidence) {
      case MusicTrackConfidence.officialMusic:
        return 3;
      case MusicTrackConfidence.likelyMusic:
        return 2;
      case MusicTrackConfidence.uncertain:
        return 1;
      case MusicTrackConfidence.rejected:
        return 0;
    }
  }

  /// Identifies whether channel is a known music label, distributor, or official artist channel.
  static bool _isOfficialMusicLabel(String channelLower) {
    if (channelLower.contains('vevo') ||
        channelLower.contains('records') ||
        channelLower.contains('recordings') ||
        channelLower.contains('music') ||
        channelLower.contains('audio') ||
        channelLower.contains('sound') ||
        channelLower.contains('t-series') ||
        channelLower.contains('saregama') ||
        channelLower.contains('sony music') ||
        channelLower.contains('zee music') ||
        channelLower.contains('aditya music') ||
        channelLower.contains('think music') ||
        channelLower.contains('speed records') ||
        channelLower.contains('lahari music') ||
        channelLower.contains('warner') ||
        channelLower.contains('universal music') ||
        channelLower.contains('atlantic') ||
        channelLower.contains('def jam') ||
        channelLower.contains('columbia') ||
        channelLower.contains('interscope') ||
        channelLower.contains('spinnin') ||
        channelLower.contains('monstercat') ||
        channelLower.contains('anjunabeats') ||
        channelLower.contains('ultra records')) {
      return true;
    }
    return false;
  }

  /// Checks if long video has legitimate musical cues (concert, symphony, classical recital, extended mix, etc.).
  static bool _hasPositiveMusicIndicator(String titleLower, String channelLower) {
    final musicIndicators = [
      'symphony',
      'orchestra',
      'philharmonic',
      'raga',
      'classical',
      'recital',
      'sonata',
      'concerto',
      'nocturne',
      'live at',
      'live in',
      'live from',
      'concert',
      'full concert',
      'live performance',
      'unplugged',
      'extended mix',
      'club mix',
      'dj mix',
      'continuous mix',
      'ambient mix',
      'chillout mix',
      'soundtrack',
      'ost',
      'score',
      'suite',
      'medley',
      'album',
      'full album',
      'discography',
      'remaster',
      'opera',
    ];

    for (final ind in musicIndicators) {
      if (titleLower.contains(ind) || channelLower.contains(ind)) {
        return true;
      }
    }
    return _isOfficialMusicLabel(channelLower);
  }

  /// Checks legitimate musical variations (live, acoustic, remix, cover, instrumental).
  static bool _isLegitimateMusicVersion(String titleLower) {
    return titleLower.contains('live') ||
        titleLower.contains('acoustic') ||
        titleLower.contains('unplugged') ||
        titleLower.contains('remix') ||
        titleLower.contains('mix') ||
        titleLower.contains('extended') ||
        titleLower.contains('instrumental') ||
        titleLower.contains('karaoke') ||
        titleLower.contains('cover') ||
        titleLower.contains('orchestral') ||
        titleLower.contains('piano version') ||
        titleLower.contains('guitar version') ||
        titleLower.contains('sped up') ||
        titleLower.contains('slowed');
  }

  /// Identifies legitimate multi-part musical suites (e.g. Pink Floyd's "Parts I-IX", "Pt. 1").
  static bool _isLegitimateMusicalSuite(String titleLower) {
    if (titleLower.contains('parts ') ||
        titleLower.contains('pt. ') ||
        titleLower.contains('pt ') ||
        titleLower.contains('symphony') ||
        titleLower.contains('suite') ||
        titleLower.contains('act ') ||
        titleLower.contains('movement')) {
      return true;
    }
    return false;
  }

  static bool _isExplicitQueryMatch(String term, String queryLower) {
    if (queryLower.isEmpty) return false;
    return queryLower.contains(term);
  }

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
}
