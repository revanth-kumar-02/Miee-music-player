import 'package:flutter/foundation.dart';
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
  static MusicTrackClassification classify(
    YouTubeVideo video, {
    String? query,
    bool forIndividualPlayback = false,
    bool enableLogging = true,
  }) {
    final rawTitle = (video.rawTitle ?? video.title).trim();
    final rawChannel = (video.rawChannelTitle ?? video.channelTitle).trim();
    final durationSec = _parseDurationSeconds(video.duration);

    final titleLower = rawTitle.toLowerCase();
    final channelLower = rawChannel.toLowerCase();
    final queryLower = (query ?? '').toLowerCase().trim();

    MusicTrackClassification makeVerdict(
      MusicTrackConfidence confidence,
      bool isMusic,
      String? rejectionReason,
      int score,
    ) {
      final verdict = MusicTrackClassification(
        confidence: confidence,
        isMusic: isMusic,
        rejectionReason: rejectionReason,
        musicScore: score,
      );
      if (enableLogging) {
        if (!isMusic || confidence == MusicTrackConfidence.rejected) {
          debugPrint(
            '[MusicClassifier] REJECTED: "$rawTitle" [dur: ${video.duration}, chan: "$rawChannel"] -> ${rejectionReason ?? "Rejected"}',
          );
        } else {
          debugPrint(
            '[MusicClassifier] ACCEPTED: "$rawTitle" [dur: ${video.duration}, chan: "$rawChannel"] -> tier: ${confidence.name}, score: $score',
          );
        }
      }
      return verdict;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 1. Definite Non-Music Signals (REJECTION CHECKS)
    // ─────────────────────────────────────────────────────────────────────────

    // Channel-level rejection: non-music entertainment, scene vaults, clips & comedy channels
    final nonMusicChannelPatterns = [
      // Scene / Vault / Piracy channels
      'cinema vault',
      'movie vault',
      'comedy vault',
      'film vault',
      'scenes hub',
      'comedy galatta',
      'comedy junction',
      'comedy club',
      'tamil comedy',
      'telugu comedy',
      'hindi comedy',
      'cine comedy',
      'movie scenes',
      'movie scene',
      'film scenes',
      'action scenes',
      'scene clips',
      'entertainment vault',
      'tamil cinema vault',
      'telugu cinema vault',
      'filmnagar',
      'sillymonks',
      'movie masala',
      // Influencer / Vlogger / Commentary / Roasting / Creator channels
      'irfan\'s view',
      'irfans view',
      'irfan view',
      'madan gowri',
      'mg squad',
      'parithabangal',
      'gopi sudhakar',
      'mic set',
      'micset',
      'jump cuts',
      'jumpcuts',
      'plip plip',
      'plipplip',
      'black sheep',
      'blacksheep',
      'ttf vasan',
      'twin throttlers',
      'village cooking',
      'peppa foodie',
      'food lovers tv',
      'dindigul food court',
      'a2d channel',
      'tech boss',
      'tamil tech',
      'tamil pokkisham',
      'vj siddhu vlogs',
      'vj siddhu',
      'puvi vlogs',
      'cherry vlogs',
      'sivaangi krishnakumar',
      'sivaangi',
      'pugazh',
      'manimegalai',
      'blue sattai',
      'tamil talkies',
      'touring talkies',
      'redn owl',
      'red\'n owl',
      'it is prashanth',
      'valai pechu',
      // Sports Entertainment / Wrestling / Combat channels
      'wwe',
      'world wrestling entertainment',
      'wrestling',
      'smackdown',
      'wrestlemania',
      'royal rumble',
      'all elite wrestling',
      'aew',
      'ufc',
      'mma',
      'bellator',
      // Instagram Meme / Skit / Reel / Comedy page channels
      'kaathadi club',
      'editz',
      'amv',
      'vfx',
      'kaathadi',
      'guyskills',
      'guy skills',
      'awesome machi',
      'awesomemachi',
      'mokkapostu',
      'mokka postu',
      'mokka post',
      'chennai memes',
      'tamil memes',
      'troll cinema',
      'troll machi',
      'fun panrom',
      'nakkalites',
      'temple monkeys',
      'fully sury',
      'bad company',
      'put chutney',
      'singam pulli',
      'karikku',
      'filtercopy',
      'hasley india',
      'round2hell',
      'r2h',
      'ashish chanchlani',
      'carryminati',
      'harsh beniwal',
      'bb ki vines',
      'bhuvan bam',
      // Media / Gossip / News / Public Review portals
      'behindwoods',
      'behindwoods air',
      'behindwoods ice',
      'behindwoods tv',
      'behindwoods o2',
      'galatta tamil',
      'galatta plus',
      'galatta voice',
      'indiaglitz',
      'cinema vikatan',
      'vikatan tv',
      'time pass vikatan',
      'filmibeat',
      'cineulagam',
      'cinema express',
      'polimer news',
      'sun news',
      'news7 tamil',
      'puthiyathalaimurai',
      'thanthi tv',
    ];

    for (final pattern in nonMusicChannelPatterns) {
      if (channelLower.contains(pattern)) {
        if (!_isOfficialMusicLabel(channelLower)) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Non-music entertainment or scene vault channel: "$rawChannel"',
            0,
          );
        }
      }
    }

    // Universal non-music creator / influencer / vlogger / entertainment channel archetypes
    if (_hasCreatorChannelArchetype(channelLower)) {
      if (!_isOfficialMusicLabel(channelLower)) {
        final hasMusicProof = _hasExplicitMusicKeyword(titleLower) ||
            titleLower.contains('official audio') ||
            titleLower.contains('official video') ||
            titleLower.contains('lyric video');
        if (!hasMusicProof) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Creator / influencer / vlogger channel ($rawChannel) lacking verified music release',
            0,
          );
        }
      }
    }

    // Universal non-music creator / influencer / review / challenge title archetypes
    if (_hasCreatorTitleArchetype(titleLower, rawTitle)) {
      final isOfficialSong = titleLower.contains('official music video') ||
          titleLower.contains('official audio') ||
          titleLower.contains('lyric video') ||
          titleLower.contains('lyrical video') ||
          titleLower.contains('full video song') ||
          titleLower.contains('original soundtrack');
      if (!isOfficialSong && !_isOfficialMusicLabel(channelLower)) {
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Creator vlog, challenge, review, or lifestyle title structure',
          0,
        );
      }
    }

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
      'comedy track',
      'comedy galatta',
      'comedy time',
      'laughter time',
      'goundamani',
      'senthil',
      'vadivelu',
      'vivek comedy',
      'santhanam comedy',
      'brahmanandam',
      'ali comedy',
      'sunil comedy',
      'jagathy',
      'suraj venjaramoodu',
      'innocent comedy',
      'kapil sharma',
      'johnny lever',
      'ultimate comedy',
      'super comedy',
      'blockbuster comedy',
      'evergreen comedy',
    ];

    for (final pattern in comedyPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        if (!_isExplicitQueryMatch(pattern, queryLower)) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Comedy or entertainment sketch content ($pattern)',
            0,
          );
        }
      }
    }

    // Check for laughter emojis (😂, 🤣, 😆) in titles
    if (rawTitle.contains('😂') || rawTitle.contains('🤣') || rawTitle.contains('😆')) {
      if (!_isOfficialMusicLabel(channelLower)) {
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Comedy / meme laughter marker in title',
          0,
        );
      }
    }

    // Wrestling / Combat Sports Entertainment Promos & Shows (e.g. WWE: Voices, Smackdown highlights)
    if (RegExp(r'\b(wwe:|wwe\s|smackdown|raw highlights|wrestlemania|royal rumble|aew dynamite|ufc \d+|mma fight)\b', caseSensitive: false).hasMatch(titleLower)) {
      if (!_isExplicitQueryMatch('wwe', queryLower) &&
          !_isExplicitQueryMatch('wrestling', queryLower) &&
          !_isExplicitQueryMatch('ufc', queryLower)) {
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Wrestling / combat sports entertainment content',
          0,
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
        if (!_isLegitimateMusicalSuite(titleLower)) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Podcast, talk show, interview, or episodic content ($pattern)',
            0,
          );
        }
      }
    }

    // Check episodic regex (e.g. "Ep 12", "Ep. 45", "Episode 10")
    final episodeRegex = RegExp(r'\b(ep|episode)\.?\s*#?\s*\d+\b', caseSensitive: false);
    if (episodeRegex.hasMatch(rawTitle) && !_isLegitimateMusicalSuite(titleLower)) {
      return makeVerdict(
        MusicTrackConfidence.rejected,
        false,
        'Episodic numbering indicates non-music show/series',
        0,
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
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Reaction, review, or critique video',
          0,
        );
      }
    }

    // C.2. Video essays, commentary, documentaries, exposé videos, controversy breakdowns, and industry discussions
    final commentaryAndDocPatterns = [
      'dark truth',
      'the dark truth',
      'truth of',
      'the truth of',
      'truth about',
      'the truth about',
      'music industry',
      'film industry',
      'cinema industry',
      'paid pr',
      'pr game',
      'video essay',
      'case study',
      'documentary',
      'scam exposed',
      'exposed',
      'expose',
      'controversy',
      'downfall of',
      'rise and fall',
      'rise & fall',
      'what happened to',
      'untold story',
      'hidden truth',
      'dark side of',
      'conspiracy',
      'biography',
      'history of',
      'evolution of',
      'ending explained',
      'story explained',
      'scene breakdown',
    ];

    for (final pattern in commentaryAndDocPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        if (!_isLegitimateMusicalSuite(titleLower)) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Commentary, documentary, video essay, or industry discussion ($pattern)',
            0,
          );
        }
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
      // 'diy' moved to word boundary
      'live stream',
      'livestream',
      'stream archive',
      'news live',
      'highlights',
      'match highlights',
    ];

    for (final pattern in generalVideoPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Gaming, vlog, tutorial, news, or general video',
          0,
        );
      }
    }

    // E. Web series, movies, serials, dramatic scenes, dialogues
    final dramaScenePatterns = [
      'web series',
      'short film',
      'full movie',
      'movie scene',
      'movie scenes',
      'climax scene',
      'action scene',
      'action scenes',
      'fight scene',
      'fight scenes',
      'death scene',
      'emotional scene',
      'sentiment scene',
      'mass scene',
      'mass scenes',
      'entry scene',
      'intro scene',
      'interval scene',
      'court scene',
      'chase scene',
      'bgm scene',
      'bgm scenes',
      'dialogue scene',
      'punch dialogue',
      'mass dialogue',
      'famous dialogue',
      'best dialogues',
      'dialogues',
      'serial',
      'telefilm',
      'natok',
      'behind the scenes',
      'making of',
      'audio launch',
      'trailer launch',
      'teaser launch',
    ];

    for (final pattern in dramaScenePatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Movie scene, short film, web series, dialogue, or drama content ($pattern)',
          0,
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
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Commercial trailer or promotional preview',
          0,
        );
      }
    }

    // G. Influencer vlogs, lifestyle, food reviews, commentary, reality shows & public reactions
    final influencerVlogPatterns = [
      'tn info',
      'cinema info',
      'movie info',
      'vlog',
      'vlogs',
      'daily vlog',
      'travel vlog',
      'family vlog',
      'lifestyle vlog',
      'house tour',
      'home tour',
      'room tour',
      'car delivery',
      'bike delivery',
      'shopping vlog',
      'what i eat',
      'grwm',
      'morning routine',
      'daily routine',
      'day in my life',
      'q&a session',
      'q and a',
      'our wedding',
      'food review',
      'food vlog',
      'biryani review',
      'street food',
      'village cooking',
      'traditional cooking',
      'eating challenge',
      'kitchen vlog',
      'recipe vlog',
      'eating 100',
      'food street',
      'public review',
      'theatre response',
      'theater response',
      'theatre reaction',
      'audience response',
      'audience reaction',
      'fdfs review',
      'fdfs response',
      'fdfs',
      'movie review',
      'trailer review',
      'teaser review',
      'teaser reaction',
      'trailer reaction',
      'box office collection',
      'box office report',
      'box office',
      'valai pechu',
      'press meet',
      'success meet',
      'celebrity interview',
      'exclusive interview',
      'face to face interview',
      'bigg boss',
      'cook with comali',
      'cwc',
      'super singer',
      'serial promo',
      'today episode',
      'full episode',
      'mega serial',
      'parithabangal',
      'plip plip',
      'jump cuts',
      'mic set',
      'black sheep',
      '24 hours challenge',
      'challenge video',
      'prank video',
      'prank call',
      'roast video',
      'roasting video',
      'troll video',
      'moto vlog',
      'motovlog',
      'superbike ride',
      'ladakh ride',
      'unboxing video',
      'smartphone review',
      'specifications',
    ];

    for (final pattern in influencerVlogPatterns) {
      if (titleLower.contains(pattern) || channelLower.contains(pattern)) {
        if (!_isExplicitQueryMatch(pattern, queryLower)) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Influencer vlog, review, commentary, reality show, or lifestyle content ($pattern)',
            0,
          );
        }
      }
    }

    // H. Multi-song compilations and jukeboxes (when individual song is expected)
    final compilationPatterns = [
      'jukebox',
      'audio jukebox',
      'video jukebox',
      'songs jukebox',
      'all songs jukebox',
      'full songs jukebox',
      'full album songs',
      'full album jukebox',
      'all songs',
      'all song',
      'song collection',
      'songs collection',
      'hits collection',
      'best songs of',
      'best of songs',
      'top 10 songs',
      'top 20 songs',
      'top 50 songs',
      'non stop songs',
      'nonstop songs',
      'back to back songs',
      'b2b songs',
      'mashup mix',
      'continuous mix',
      'evergreen hits collection',
    ];

    final wantsCompilation = queryLower.contains('jukebox') ||
        queryLower.contains('compilation') ||
        queryLower.contains('all songs');

    if (forIndividualPlayback || !wantsCompilation) {
      for (final pattern in compilationPatterns) {
        if (titleLower.contains(pattern)) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Multi-song compilation or jukebox not suitable for individual song playback ($pattern)',
            0,
          );
        }
      }
    }

    // H. Long duration check with lack of musical evidence
    // Standard songs are typically 1.5 to 7.0 minutes.
    // Classical music, full concerts, DJ sets, OSTs, and extended mixes are legitimate long music.
    final isLongMusic = _hasPositiveMusicIndicator(titleLower, channelLower);
    final isVerifiedChannel = _isOfficialMusicLabel(channelLower) || _isVerifiedMusicArtist(channelLower);

    if (durationSec > 540 && !isLongMusic && !isVerifiedChannel) {
      return makeVerdict(
        MusicTrackConfidence.rejected,
        false,
        'Long duration (${video.duration}) exceeds single-track limit without long-music genre indicators or verified music channel',
        0,
      );
    }

    if (durationSec > 420 && !isLongMusic && !isVerifiedChannel) {
      return makeVerdict(
        MusicTrackConfidence.rejected,
        false,
        'Extended duration (${video.duration}) lacking positive music indicators',
        0,
      );
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

    // Signal: Official Audio / Video Song / Lyrical (+40 points)
    if (titleLower.contains('official music video') ||
        titleLower.contains('official audio') ||
        titleLower.contains('official video') ||
        titleLower.contains('lyric video') ||
        titleLower.contains('lyrical video') ||
        titleLower.contains('full video song') ||
        titleLower.contains('video song') ||
        titleLower.contains('audio song') ||
        titleLower.contains('lyrical song') ||
        titleLower.contains('theme track') ||
        titleLower.contains('theme song') ||
        titleLower.contains('original score') ||
        titleLower.contains('original soundtrack') ||
        titleLower.contains('soundtrack') ||
        RegExp(r'\b(theme|ost|bgm|score|instrumental)\b', caseSensitive: false).hasMatch(titleLower) ||
        titleLower.contains('original soundtrack') ||
        titleLower.contains('visualizer')) {
      score += 40;
      hasMusicIndicator = true;
    }

    final hasMusicKeywordInTitle = _hasExplicitMusicKeyword(titleLower);
    final isMusicLabelChannel = _isOfficialMusicLabel(channelLower);

    // Signal: Recognized music track structure (Artist - Title or Title | Movie | Artist) (+25 points)
    // NOTE: ' | ' and ' - ' are commonly used by influencers & vloggers (e.g. "Biryani Review | Irfan's view").
    // A separator ONLY awards points if the title has an explicit music keyword OR channel is a verified music label.
    if (rawTitle.contains(' - ') ||
        rawTitle.contains(' – ') ||
        rawTitle.contains(' — ') ||
        rawTitle.contains(' | ')) {
      if (hasMusicKeywordInTitle || isMusicLabelChannel) {
        score += 25;
        hasMusicIndicator = true;
      }
    }

    // Signal: Legitimate musical version indicators (+30 points)
    if (_isLegitimateMusicVersion(titleLower)) {
      score += 30;
      hasMusicIndicator = true;
    }

    // Signal: Musical collaboration / credit markers (+20 points)
    if (RegExp(r'\b(feat\.?|ft\.?|prod\.?|with|singers?:|composer:|music:)\b', caseSensitive: false).hasMatch(rawTitle)) {
      score += 20;
      hasMusicIndicator = true;
    }

    // Signal: Typical song duration (2:00 to 6:30) (+15 points)
    if ((durationSec >= 120 && durationSec <= 390) || (durationSec >= 45 && durationSec <= 390 && (hasMusicIndicator || isMusicLabelChannel || hasMusicKeywordInTitle))) {
      score += 15;
    }

    // Signal: Verified song marker in view count (+30 points)
    if (video.viewCount.toLowerCase().contains('verified song')) {
      score += 30;
      hasMusicIndicator = true;
    }

    // Signal: Soundtrack / Film Album Structure (e.g. (From "Leo"), (From "Amaran"), [From "..."]) (+35 points)
    final hasSoundtrackPattern = titleLower.contains('(from ') ||
        titleLower.contains('[from ') ||
        titleLower.contains('{from ') ||
        RegExp(r'\bfrom\s+["\u201C\u201D\u2018\u2019]', caseSensitive: false).hasMatch(rawTitle);
    if (hasSoundtrackPattern) {
      score += 35;
      hasMusicIndicator = true;
    }

    // Signal: Verified Music Artist or Composer Channel (+40 points)
    final isVerifiedArtistChannel = _isVerifiedMusicArtist(channelLower);
    if (isVerifiedArtistChannel) {
      score += 40;
      hasMusicIndicator = true;
    }

    // Signal: High View Count on Valid Song Format (+15 to +30 points)
    final numericViews = _parseNumericViews(video);
    if (numericViews != null && numericViews >= 1000000) {
      score += 30;
      hasMusicIndicator = true;
    } else if (numericViews != null && numericViews >= 100000) {
      score += 15;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Final Confidence Determination
    // ─────────────────────────────────────────────────────────────────────────

    if (score >= 75) {
      return makeVerdict(
        MusicTrackConfidence.officialMusic,
        true,
        null,
        score,
      );
    } else if (hasMusicIndicator && score >= 45) {
      return makeVerdict(
        MusicTrackConfidence.likelyMusic,
        true,
        null,
        score,
      );
    } else {
      // Ambiguous metadata (e.g. unknown channel, generic title, short/missing duration)
      final isVeryShortClip = durationSec > 0 && durationSec < 45;
      if (isVeryShortClip && !titleLower.contains('song') && !titleLower.contains('intro')) {
        return makeVerdict(
          MusicTrackConfidence.rejected,
          false,
          'Sub-45s short clip without musical evidence',
          20,
        );
      }

      // If video has zero musical indicators and is from an unverified channel:
      // In individual playback mode, strictly reject it.
      // For general classification, mark as uncertain so official tracks rank above it.
      if (!hasMusicIndicator && !isMusicLabelChannel && !isVerifiedArtistChannel) {
        if (forIndividualPlayback || durationSec > 300) {
          return makeVerdict(
            MusicTrackConfidence.rejected,
            false,
            'Non-music video lacking verifiable musical indicators (song, audio, lyric, or label)',
            score,
          );
        }
      }

      return makeVerdict(
        MusicTrackConfidence.uncertain,
        true, // Preserved cautiously for indie/obscure tracks
        null,
        score,
      );
    }
  }

  /// Convenience helper: returns true if the video is classified as acceptable music.
  static bool isValidMusicTrack(YouTubeVideo video, {String? query}) {
    final verdict = classify(video, query: query, enableLogging: false);
    if (!verdict.isMusic || verdict.confidence == MusicTrackConfidence.rejected) {
      return false;
    }
    if (verdict.confidence == MusicTrackConfidence.uncertain) {
      final channelLower = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();
      final rawTitle = (video.rawTitle ?? video.title).toLowerCase();
      if (_hasCreatorChannelArchetype(channelLower) ||
          _hasCreatorTitleArchetype(rawTitle, video.rawTitle ?? video.title)) {
        return false;
      }
    }
    return true;
  }

  /// Returns true if the video is verified as a legitimate individual music track,
  /// rejecting compilations, jukeboxes, scene clips, and uncertain candidates lacking musical indicators.
  static bool isValidIndividualSong(YouTubeVideo video, {String? query}) {
    final verdict = classify(
      video,
      query: query,
      forIndividualPlayback: true,
      enableLogging: false,
    );
    if (!verdict.isMusic || verdict.confidence == MusicTrackConfidence.rejected) {
      return false;
    }
    if (verdict.confidence == MusicTrackConfidence.uncertain) {
      final rawTitle = (video.rawTitle ?? video.title).toLowerCase();
      final channelLower = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();
      final titleL = (video.rawTitle ?? video.title).toLowerCase();
      final hasSoundtrack = titleL.contains('(from ') ||
          titleL.contains('[from ') ||
          titleL.contains('{from ') ||
          RegExp(r'\bfrom\s+["\u201C\u201D\u2018\u2019]', caseSensitive: false).hasMatch(video.rawTitle ?? video.title);
      final hasPositiveProof = _hasExplicitMusicKeyword(rawTitle) ||
          _isOfficialMusicLabel(channelLower) ||
          _isVerifiedMusicArtist(channelLower) ||
          hasSoundtrack ||
          _hasMusicCredits(video.rawTitle ?? video.title) ||
          _isLegitimateMusicVersion(rawTitle) ||
          _hasPositiveMusicIndicator(rawTitle, channelLower);
      return hasPositiveProof && verdict.musicScore >= 35;
    }
    return true;
  }

  /// Filters out rejected non-music videos and ranks results with official music prioritized.
  static List<YouTubeVideo> filterAndRankMusicTracks(
    List<YouTubeVideo> videos, {
    String? query,
    int maxResults = 30,
    bool individualOnly = false,
  }) {
    if (videos.isEmpty) return const [];

    final classified = <({YouTubeVideo video, MusicTrackClassification verdict})>[];
    for (final v in videos) {
      final verdict = classify(
        v,
        query: query,
        forIndividualPlayback: individualOnly,
        enableLogging: false,
      );
      if (verdict.isMusic && verdict.confidence != MusicTrackConfidence.rejected) {
        if (!individualOnly || verdict.confidence != MusicTrackConfidence.uncertain || verdict.musicScore >= 35) {
          classified.add((video: v, verdict: verdict));
        }
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

  /// Checks whether title has music industry credit markers (singers, composer, feat, prod).
  static bool _hasMusicCredits(String rawTitle) {
    return RegExp(
      r'\b(feat\.?|ft\.?|prod\.?|with|singers?:|composer:|music:)\b',
      caseSensitive: false,
    ).hasMatch(rawTitle);
  }

  /// Detects whether a channel matches universal non-music creator / vlogger / entertainment archetypes.
  /// This protects against both established influencers and new / growing creators without needing hardcoded names.
  static bool _hasCreatorChannelArchetype(String channelLower) {
    if (_isOfficialMusicLabel(channelLower) || _isVerifiedMusicArtist(channelLower)) return false;

    final creatorWords = [
      'vlog',
      'vlogs',
      'vlogger',
      'vlogging',
      'lifestyle',
      'diaries',
      'diary',
      'stories',
      'foodie',
      'foodies',
      'food hunt',
      'food hunter',
      'street food',
      'kitchen',
      'cooking',
      'cooks',
      'recipes',
      'recipe',
      'bites',
      'tastes',
      'feast',
      'technology',
      'unboxing',
      'reviewer',
      'reviews',
      'gaming',
      'gamer',
      'gameplay',
      'gadgets',
      'mobiles',
      'comedy',
      'trolls',
      'memes',
      'prank',
      'roast',
      'filmibeat',
      'cineulagam',
      'behindwoods',
      'galatta',
      'talkies',
      'cinema vault',
      'movie vault',
      'comedy vault',
      'scenes hub',
      'action scenes',
      'movie scenes',
      'fitness',
      'workout',
      'pasanga',
      'pullingo',
      'nanbargal',
      'tamizhan',
      'tamilan',
      'telugodu',
      'kannadiga',
      'malayali',
      // Instagram & Meme page archetypes
      'editz',
      'amv',
      'vfx',
      'kaathadi',
      'guyskills',
      'skills',
      'machi',
      'mokkapostu',
      'mokka',
      'reels',
      'reel',
      'insta',
      'instagram',
      'vines',
      'skits',
      'skit',
      'spoof',
      'parody',
      'troll',
      'trolls',
      'meme',
      'memes',
    ];

    for (final word in creatorWords) {
      if (channelLower.contains(word)) {
        return true;
      }
    }

    final tokenRegex = RegExp(
      r'\b(tech|unbox|review|games|plays|troll|meme|pranks|roasts|cine|vault|scenes|gym|nanban|boys|girls|media|tube|talks|speaks)\b',
      caseSensitive: false,
    );
    return tokenRegex.hasMatch(channelLower);
  }

  /// Detects whether a title matches universal creator / vlogger / influencer / review / challenge tropes.
  static bool _hasCreatorTitleArchetype(String titleLower, String rawTitle) {
    final creatorPatterns = [
      // 1. First-Person Narratives & Personal Activities
      'my new',
      'our new',
      'my first',
      'our first',
      'my dream',
      'our dream',
      'i bought',
      'we bought',
      'i purchased',
      'we purchased',
      'i got',
      'we got',
      'i tried',
      'we tried',
      'i visited',
      'we visited',
      'i went',
      'we went',
      'i traveled',
      'we traveled',
      'i spent',
      'we spent',
      'i challenged',
      'i survived',
      'we survived',
      'how i',
      'why i',
      'what happened',
      'what i eat',
      'a day in my',
      'day in my life',
      'day in the life',
      'morning routine',
      'night routine',
      'daily routine',
      'grwm',
      'get ready with me',
      'house tour',
      'home tour',
      'room tour',
      'car delivery',
      'bike delivery',
      'superbike delivery',
      'taking delivery',
      'surprise for',
      'surprise gift',
      'emotional moment',
      'meeting my',
      'with my wife',
      'with my mom',
      'with my dad',
      'with my family',
      'with my friends',
      'answering your',
      'q&a',
      'ask me anything',

      // 2. Transliterated Regional Creator Tropes
      'enga veedu',
      'enga veetu',
      'ennoda pudhu',
      'en pudhu',
      'enoda pudhu',
      'puthu bike',
      'puthu car',
      'pudhu bike',
      'pudhu car',
      'naan vangitaen',
      'naan vangiten',
      'naanga vangitom',
      'vangitom',
      'vangiyachi',
      'saptom',
      'saptingala',
      'saapda ponom',
      'ponom',
      'vandhom',
      'paathom',
      'kelambitom',
      'ooruku ponom',
      'village tour',
      'thiruvizha vlog',
      'kovil thiruvizha',
      'valaikappu',
      'seemantham',
      'kalyanam vlog',
      'marriage vlog',
      'wedding vlog',
      'baby shower vlog',

      // 3. Food, Cooking & Travel Hunts
      'street food',
      'village cooking',
      'traditional cooking',
      'taste test',
      'food hunt',
      'food hunter',
      'midnight food',
      'midnight biryani',
      'food review',
      'restaurant review',
      'biryani review',
      'eating challenge',
      'food challenge',
      'unlimited buffet',
      'secret spot',
      'hidden gem',
      'must try spot',
      'must visit',
      'food vlog',
      'eating 100',

      // 4. Consumer Reviews, Buying Guides & Testing
      'unboxing & review',
      'full review',
      'honest review',
      'ownership review',
      'mileage test',
      'camera test',
      'speed test',
      'battery drain test',
      'drop test',
      'which is best',
      'which one to buy',
      'best budget',
      'cheap and best',
      'cheap & best',
      "don't buy",
      'dont buy',
      'worth-a',
      'worth ah',
      'worthu',
      'worth ya',
      'waste-a',
      'waste ah',
      'waste ya',
      'scam exposed',
      'scam alert',
      'the truth about',
      'reality of',
      'watch before you buy',
      'shopping haul',
      'shopping vlog',
      'dress shopping',

      // 5. Entertainment Gossip, Movie Tracking & Theatre Responses
      'public review',
      'theatre review',
      'theater review',
      'theatre response',
      'theater response',
      'theatre reaction',
      'theater reaction',
      'audience response',
      'audience reaction',
      'fdfs review',
      'fdfs response',
      'fdfs celebration',
      'fans celebration',
      'theatre celebration',
      'box office report',
      'box office collection',
      'box office',
      'day 1 collection',
      'day 2 collection',
      'total collection',
      'movie review',
      'trailer review',
      'teaser review',
      'trailer reaction',
      'teaser reaction',
      'scene breakdown',
      'easter eggs',
      'hidden details',
      'story explained',
      'climax explained',
      'ending explained',
      'ott release date',
      'press meet',
      'success meet',
      'celebrity interview',
      'exclusive interview',
      'face to face interview',
      'round table interview',

      // 6. Instagram, Meme Pages, Skits & Reels Tropes
      'reels compilation',
      'reel compilation',
      'insta reels',
      'instagram reels',
      'trending reels',
      'viral reels',
      'reels video',
      'reel video',
      'reels shorts',
      'insta trend',
      'instagram trending',
      'meme compilation',
      'memes compilation',
      'troll compilation',
      'fun compilation',
      'mokka compilation',
      'comedy skit',
      'parody video',
      'spoof video',
      'relatable memes',
      'relatable meme',
      'expectations vs reality',
      'viral meme',
      'viral video',
      'funny reel',
      'funny reels',
      'comedy reel',
      'comedy reels',
      'guyskills',
      'kaathadi club',
    ];

    for (final pattern in creatorPatterns) {
      if (titleLower.contains(pattern)) {
        return true;
      }
    }

        // Character mashups / AMV edit titles (e.g. "BATMAN ft:- One Sun One Moon", "Spiderman x Song")
    if (RegExp(r'\b(batman|spiderman|superman|iron\s*man|anime|amv|goku|naruto|luffy)\b.*\b(ft\.?|x|vs\.?)\b', caseSensitive: false).hasMatch(rawTitle)) {
      return true;
    }

    // Trailing / multiple question mark clickbait (e.g. "Emotional Moment ???!", "What Happened ???")
    if (RegExp(r'(\?{2,}|(\?!|\!\?){1,})').hasMatch(rawTitle)) {
      return true;
    }

    return false;
  }

  /// Parses numeric view count from YouTubeVideo or formatted viewCount string.
  static int? _parseNumericViews(YouTubeVideo video) {
    if (video.rawViewCount != null) return video.rawViewCount;
    final viewStr = video.viewCount;
    if (viewStr.isEmpty) return null;
    final clean = viewStr.toLowerCase().replaceAll('views', '').replaceAll(',', '').trim();
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

  /// Checks if channel belongs to a verified music artist, composer, or official artist channel.
  static bool _isVerifiedMusicArtist(String channelLower) {
    if (_isOfficialMusicLabel(channelLower)) return true;
    final verifiedArtists = [
      'anirudh ravichander',
      'anirudh',
      'a.r. rahman',
      'ar rahman',
      'a. r. rahman',
      'dhanush',
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
      'armaan malik',
      'darshan raval',
      'diljit dosanjh',
      'satinder sartaaj',
      's. p. balasubrahmanyam',
      'spb',
      'k. j. yesudas',
      'chithra',
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
      'post malone',
      'bruno mars',
      'alan walker',
      'sanjay subrahmanyan',
    ];
    for (final artist in verifiedArtists) {
      if (channelLower == artist ||
          channelLower.startsWith('$artist ') ||
          channelLower.endsWith(' $artist') ||
          channelLower == '$artist official' ||
          channelLower.contains('$artist vevo')) {
        return true;
      }
    }
    return false;
  }

  /// Identifies whether channel is a known music label, distributor, or official artist channel.
  static bool _isOfficialMusicLabel(String channelLower) {
    // Exclude wrestling and sports entertainment channels even if name includes 'music' (e.g. WWE Music)
    if (channelLower.contains('wwe') ||
        channelLower.contains('wrestling') ||
        channelLower.contains('ufc') ||
        channelLower.contains('mma')) {
      return false;
    }

    if (channelLower.contains('wunderbar films') ||
        channelLower.contains('wunderbar') ||
        channelLower.contains('divo music') ||
        channelLower.contains('divomovies') ||
        channelLower.contains('lyca productions') ||
        channelLower.contains('raaj kamal') ||
        channelLower.contains('mythri movie makers') ||
        channelLower.contains('hombale films') ||
        channelLower.contains('dvv entertainment') ||
        channelLower.contains('geetha arts') ||
        channelLower.contains('sithara entertainments') ||
        channelLower.contains('dream warrior pictures') ||
        channelLower.contains('studio green') ||
        channelLower.contains('ags entertainment') ||
        channelLower.contains('red giant movies') ||
        channelLower.contains('yash raj films')) {
      return true;
    }
    if (channelLower.endsWith(' - topic') ||
        channelLower.contains('- topic') ||
        channelLower.contains('vevo') ||
        channelLower.contains('records') ||
        channelLower.contains('recordings') ||
        channelLower.contains('music') ||
        channelLower.contains('audio') ||
        channelLower.contains('sound') ||
        channelLower.contains('t-series') ||
        channelLower.contains('tseries') ||
        channelLower.contains('saregama') ||
        channelLower.contains('sony music') ||
        channelLower.contains('sonymusicsouth') ||
        channelLower.contains('zee music') ||
        channelLower.contains('aditya music') ||
        channelLower.contains('think music') ||
        channelLower.contains('speed records') ||
        channelLower.contains('lahari music') ||
        channelLower.contains('muzik247') ||
        channelLower.contains('tips official') ||
        channelLower.contains('satyam audios') ||
        channelLower.contains('manorama music') ||
        channelLower.contains('yrf') ||
        channelLower.contains('eros now') ||
        channelLower.contains('warner') ||
        channelLower.contains('universal music') ||
        channelLower.contains('atlantic') ||
        channelLower.contains('def jam') ||
        channelLower.contains('columbia') ||
        channelLower.contains('interscope') ||
        channelLower.contains('spinnin') ||
        channelLower.contains('monstercat') ||
        channelLower.contains('anjunabeats') ||
        channelLower.contains('ultra records') ||
        channelLower.contains('sun tv') ||
        channelLower.contains('sun pictures') ||
        channelLower.contains('sun gemini') ||
        channelLower.contains('sun nxt') ||
        channelLower.contains('kalaignar') ||
        channelLower.contains('vijay television') ||
        channelLower.contains('star vijay') ||
        channelLower.contains('star maa') ||
        channelLower.contains('zee tamil') ||
        channelLower.contains('zee telugu')) {
      return true;
    }
    return false;
  }

  /// Checks if video title contains explicit musical keywords.
  static bool _hasExplicitMusicKeyword(String titleLower) {
    // If it's a commentary on the music industry or music review, exclude the keyword match
    if (titleLower.contains('music industry') ||
        titleLower.contains('music review') ||
        titleLower.contains('about music') ||
        titleLower.contains('dark truth') ||
        titleLower.contains('truth of')) {
      return false;
    }

    return titleLower.contains('song') ||
        titleLower.contains('songs') ||
        titleLower.contains('audio') ||
        titleLower.contains('music video') ||
        titleLower.contains('official music') ||
        titleLower.contains('track') ||
        titleLower.contains('soundtrack') ||
        titleLower.contains('ost') ||
        titleLower.contains('theme') ||
        titleLower.contains('bgm') ||
        titleLower.contains('lyric') ||
        titleLower.contains('lyrical') ||
        titleLower.contains('remix') ||
        titleLower.contains('cover') ||
        titleLower.contains('acoustic') ||
        titleLower.contains('unplugged') ||
        titleLower.contains('instrumental') ||
        titleLower.contains('visualizer') ||
        titleLower.contains('orchestra') ||
        titleLower.contains('symphony') ||
        titleLower.contains('raga') ||
        titleLower.contains('album');
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
        titleLower.contains('slowed') ||
        titleLower.contains('theme') ||
        titleLower.contains('soundtrack') ||
        titleLower.contains('score') ||
        titleLower.contains('ost') ||
        titleLower.contains('bgm');
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
