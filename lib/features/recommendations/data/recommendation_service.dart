import 'package:flutter/foundation.dart';
import '../../../core/network/network_request_coordinator.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../history/data/supabase_listening_history_repository.dart';
import '../../history/domain/listening_history_repository.dart';
import '../../history/domain/listening_event.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../profile/domain/user_profile.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/domain/music_result_classifier.dart';
import '../../search/domain/search_deduplicator.dart';
import '../../youtube/data/youtube_repository.dart';
import '../../../core/audio/queue_diagnostics.dart';
import 'taste_profile_repository.dart';
import 'trending_music_service.dart';
import '../domain/candidate_ranker.dart';
import '../domain/music_language_service.dart';
import '../domain/user_taste_profile.dart';

class RecommendationSections {
  final List<ArtistSummary> favoriteArtists;
  final List<MusicItem> fromYourArtists;
  final List<ArtistModel> relatedArtists;
  final List<MusicItem> popularTracks;
  final List<MusicItem> trendingTracks;
  final List<MusicItem> recentReleases;
  final List<MusicItem> discoverMore;
  final List<ListeningEvent> recentlyPlayed;
  final MusicItem? featuredTrack;

  const RecommendationSections({
    this.favoriteArtists = const [],
    this.fromYourArtists = const [],
    this.relatedArtists = const [],
    this.popularTracks = const [],
    this.trendingTracks = const [],
    this.recentReleases = const [],
    this.discoverMore = const [],
    this.recentlyPlayed = const [],
    this.featuredTrack,
  });
}

class RecommendationService {
  final YouTubeRepository _youtubeRepo;
  final ArtistRepository _artistRepo;
  final ListeningHistoryRepository _historyRepo;
  final TrendingMusicService _trendingService;
  final TasteProfileRepository? _tasteRepo;
  final CandidateRanker _candidateRanker;

  RecommendationService({
    YouTubeRepository? youtubeRepo,
    ArtistRepository? artistRepo,
    ListeningHistoryRepository? historyRepo,
    TrendingMusicService? trendingService,
    TasteProfileRepository? tasteRepo,
    CandidateRanker? candidateRanker,
  })  : _youtubeRepo = youtubeRepo ?? YouTubeRepository(),
        _artistRepo = artistRepo ?? DeezerArtistRepository(),
        _historyRepo = historyRepo ?? SupabaseListeningHistoryRepository(),
        _trendingService = trendingService ?? TrendingMusicService(),
        _tasteRepo = tasteRepo,
        _candidateRanker = candidateRanker ?? const CandidateRanker();

  static String _normalizeTrackId(String id) {
    return id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;
  }

  static String normalizeKey(String title, String artist) {
    var cleanT = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    var cleanA = artist
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    if (cleanT.isEmpty) cleanT = title.toLowerCase().trim();
    if (cleanA.isEmpty) cleanA = artist.toLowerCase().trim();
    return '$cleanT|$cleanA';
  }

  /// Checks whether [track] is legitimately attributed to [targetArtist], either as
  /// the primary artist, a collaborating co-artist, or verified composer/creator.
  ///
  /// Prevents unrelated tracks from appearing in artist-specific spotlights
  /// while preserving legitimate collaborations.
  static bool isTrackAttributedToArtist(MusicItem track, String targetArtist) {
    if (targetArtist.trim().isEmpty) return false;
    final cleanTarget = targetArtist.trim().toLowerCase();

    // 1. Direct or alias match
    final aliases = getArtistAliases(cleanTarget);

    // 2. Check track.artist tokens
    final trackArtist = track.artist.toLowerCase().trim();
    if (trackArtist.isNotEmpty) {
      if (aliases.any((alias) => trackArtist == alias)) return true;
      final creditedArtists = trackArtist
          .split(RegExp(
              r'\s*(&|,|\bfeat\.?|\bft\.?|\bwith\b|\band\b|\bx\b|\bvs\.?|\/)\s*',
              caseSensitive: false))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      for (final credited in creditedArtists) {
        if (aliases.any((alias) => isArtistNameMatch(credited, alias))) {
          return true;
        }
      }
    }

    // 3. Check raw artist/channel if available
    final rawArtist =
        (track is Track ? (track.rawArtist ?? '') : '').toLowerCase().trim();
    if (rawArtist.isNotEmpty) {
      if (aliases.any((alias) => isArtistNameMatch(rawArtist, alias))) {
        return true;
      }
    }

    // 4. Check raw title or title for structured credit clauses:
    // e.g. "Song | Movie | A.R. Rahman | Singer...", "Music: A. R. Rahman", "Composed by Anirudh"
    final rawTitle =
        (track is Track ? (track.rawTitle ?? track.title) : track.title)
            .toLowerCase();
    for (final alias in aliases) {
      if (_hasStructuredArtistCredit(rawTitle, alias)) {
        return true;
      }
    }

    return false;
  }

  /// Returns known aliases and spelling variations for [artistName].
  static List<String> getArtistAliases(String artistName) {
    final clean = artistName.trim().toLowerCase();
    final normalized = clean
        .replaceAll(RegExp(r'[\.\,\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final aliases = <String>{clean, normalized};

    // Specific well-known aliases and variations
    if (clean.contains('rahman') ||
        clean == 'a. r. rahman' ||
        clean == 'ar rahman') {
      aliases.addAll([
        'a. r. rahman',
        'a.r. rahman',
        'ar rahman',
        'a r rahman',
        'rahman',
        'arrahman',
        'a r rehman',
        'ar rehman'
      ]);
    } else if (clean.contains('anirudh')) {
      aliases.addAll(['anirudh ravichander', 'anirudh', 'anirudhravichander']);
    } else if (clean.contains('yuvan')) {
      aliases.addAll(['yuvan shankar raja', 'yuvan', 'ysr', 'yuvanshankar']);
    } else if (clean.contains('harris')) {
      aliases.addAll(['harris jayaraj', 'harris']);
    } else if (clean.contains('ilaiyaraaja') || clean.contains('ilayaraja')) {
      aliases.addAll(['ilaiyaraaja', 'ilaiyaraja', 'ilayaraja', 'raaja']);
    } else if (clean.contains('balasubrahmanyam') || clean == 'spb') {
      aliases.addAll([
        's. p. balasubrahmanyam',
        'sp balasubrahmanyam',
        'spb',
        's p balasubrahmanyam',
        'balasubrahmanyam'
      ]);
    } else if (clean.contains('chithra')) {
      aliases.addAll(['k. s. chithra', 'ks chithra', 'chithra']);
    } else if (clean.contains('arijit')) {
      aliases.addAll(['arijit singh', 'arijit']);
    } else if (clean.contains('shreya')) {
      aliases.addAll(['shreya ghoshal', 'shreya']);
    } else if (clean.contains('sid sriram')) {
      aliases.addAll(['sid sriram']);
    } else if (clean.contains('santhosh narayanan')) {
      aliases.addAll(['santhosh narayanan', 'sana']);
    } else if (clean.contains('sai abhyankkar')) {
      aliases.addAll(['sai abhyankkar', 'sai abhyankar']);
    } else if (clean.contains('jonita')) {
      aliases.addAll(['jonita gandhi', 'jonita']);
    }

    return aliases.toList();
  }

  static bool isArtistNameMatch(String credited, String alias) {
    final cleanCredited = credited.trim().toLowerCase();
    final cleanAlias = alias.trim().toLowerCase();
    if (cleanCredited == cleanAlias) return true;

    final normCredited = cleanCredited
        .replaceAll(RegExp(r'[\.\,\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final normAlias = cleanAlias
        .replaceAll(RegExp(r'[\.\,\-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normCredited == normAlias) return true;

    if (cleanAlias.length >= 4) {
      final pattern = RegExp(r'\b' + RegExp.escape(cleanAlias) + r'\b');
      if (pattern.hasMatch(cleanCredited)) return true;
    }

    return false;
  }

  static bool _hasStructuredArtistCredit(String title, String alias) {
    if (alias.length < 3) return false;
    final lowerTitle = title.toLowerCase();

    final prefixes = [
      'music:',
      'music by',
      'composed by',
      'composer:',
      'singer:',
      'singers:',
      'ft.',
      'feat.',
      'featuring'
    ];
    for (final prefix in prefixes) {
      final idx = lowerTitle.indexOf(prefix);
      if (idx != -1) {
        final after = lowerTitle.substring(idx + prefix.length).trim();
        if (after.startsWith(alias) ||
            isArtistNameMatch(
                after.split(RegExp(r'[\|\,\-\•]')).first.trim(), alias)) {
          return true;
        }
      }
    }

    final clauses = lowerTitle.split(RegExp(r'\s*(\||•|\/\/)\s*'));
    for (final clause in clauses) {
      final cleanClause = clause.trim();
      if (isArtistNameMatch(cleanClause, alias)) {
        return true;
      }
    }

    final dashes = lowerTitle.split(RegExp(r'\s*[\-\–\—]\s*'));
    if (dashes.length >= 2) {
      for (final part in dashes) {
        if (isArtistNameMatch(part.trim(), alias)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Filters out playlists, multi-song compilations, jukeboxes, full movies, podcasts, and comedy sketches
  /// while strictly preserving genuine individual songs.
  static bool isLegitimateSong(YouTubeVideo video) {
    if (!MusicResultClassifier.isValidIndividualSong(video)) {
      return false;
    }
    final raw = video.rawTitle ?? video.title;
    final title = raw.toLowerCase();
    final durationSec = _parseDurationSeconds(video.duration);

    // 1. Spoken-word, interview, podcast, behind-the-scenes, editorial storytelling
    final editorialClipRegex = RegExp(
      r'\b(shares\s+the|shares\s+his|shares\s+her|talks\s+about|speaks\s+about|'
      r'opens\s+up|reveals\b.*\bstory|story\s+behind|creator\s+commentary|'
      r'artist\s+discussion|sneak\s+peek|special\s+glimpse|first\s+glimpse)\b',
      caseSensitive: false,
    );
    if (title.contains('podcast') ||
        title.contains('episode #') ||
        title.contains('interview with') ||
        title.contains('exclusive interview') ||
        title.contains('press meet') ||
        title.contains('trailer') ||
        title.contains('teaser') ||
        title.contains('audio launch') ||
        title.contains('making of') ||
        title.contains('behind the scenes') ||
        title.contains('audio commentary') ||
        editorialClipRegex.hasMatch(raw) ||
        RegExp(r'\bep\.?\s*\d+\b', caseSensitive: false).hasMatch(title)) {
      return false;
    }

    // 2. Full movie / comedy scenes / movie scene compilations
    if (title.contains('full movie') ||
        title.contains('tamil movie') ||
        title.contains('telugu movie') ||
        title.contains('hindi movie') ||
        title.contains('malayalam movie') ||
        title.contains('kannada movie') ||
        title.contains('comedy scene') ||
        title.contains('best scenes') ||
        title.contains('movie scenes') ||
        title.contains('scene collection')) {
      return false;
    }

    // 3. Jukeboxes, continuous mixes, back to back
    if (title.contains('jukebox') ||
        title.contains('continuous mix') ||
        title.contains('non stop') ||
        title.contains('nonstop') ||
        title.contains('mashup mix') ||
        title.contains('mega mix') ||
        title.contains('megamix') ||
        title.contains('audio jukebox') ||
        title.contains('video jukebox') ||
        title.contains('all songs jukebox') ||
        title.contains('back to back') ||
        title.contains('b2b songs') ||
        title.contains('songs jukebox')) {
      return false;
    }

    // 4. Multi-song collections: "Top 10", "Top 20", "Top 50", "Best of", "All Songs", etc.
    final compilationRegex = RegExp(
      r'(\btop\s*\d+\b|\bbest\s+of\b|\bhit\s+songs\s+collection\b|\ball\s+songs\b|\bfull\s+album\b|\bfull\s+playlist\b|\bplaylist\b|\bcompilation\b|\bsongs\s+collection\b)',
      caseSensitive: false,
    );
    if (compilationRegex.hasMatch(title)) {
      return false;
    }

    // 4b. Milestone views / promotional celebration teasers
    final milestonePromoRegex = RegExp(
      r'(\b\d+\s*[mbk]\+?\s*views\b|\bcelebration\s*video\b|\bsuccess\s*meet\b|\bthanks\s*meet\b)',
      caseSensitive: false,
    );
    if (milestonePromoRegex.hasMatch(raw)) {
      return false;
    }

    // 4c. Implausibly short clips (< 20s) and ambiguous short clips (< 65s) without explicit music evidence
    final isShortForm = title.contains('intro') ||
        title.contains('interlude') ||
        title.contains('skit') ||
        title.contains('prelude') ||
        title.contains('outro') ||
        title.contains('theme');
    if (durationSec > 0 && durationSec < 20 && !isShortForm) {
      return false;
    }
    if (durationSec > 0 && durationSec < 65) {
      final channelLower =
          (video.rawChannelTitle ?? video.channelTitle).toLowerCase();
      final hasMusicalEvidence = isShortForm ||
          channelLower.endsWith('- topic') ||
          title.contains('song') ||
          title.contains('audio') ||
          title.contains('lyrical') ||
          title.contains('ost') ||
          title.contains('bgm') ||
          title.contains('acoustic') ||
          title.contains('live') ||
          title.contains('remix') ||
          title.contains('instrumental');
      if (!hasMusicalEvidence) {
        return false;
      }
    }

    // 5. Long-form video heuristics: require legitimate musical genre indicators
    if (durationSec >= 480) {
      final isLegitimateLongMusic = title.contains('raga') ||
          title.contains('alapana') ||
          title.contains('symphony') ||
          title.contains('carnatic') ||
          title.contains('kriti') ||
          title.contains('varnam') ||
          title.contains('soundtrack') ||
          title.contains('ost') ||
          title.contains('concert') ||
          title.contains('live at') ||
          title.contains('live in') ||
          title.contains('orchestra') ||
          title.contains('extended mix') ||
          title.contains('dj mix');
      if (!isLegitimateLongMusic) {
        return false;
      }
    }

    if (durationSec > 2100) {
      return false;
    }

    return true;
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

  static int rankDiscoverCandidate(YouTubeVideo video) {
    int score = 100;
    final raw = (video.rawTitle ?? video.title).toLowerCase();
    final ch = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();

    if (ch.contains('topic')) score += 30;
    if (ch.contains('vevo') || ch.contains('official')) score += 20;

    if (raw.contains('official audio') ||
        raw.contains('official video') ||
        raw.contains('lyric video')) {
      score += 15;
    }

    if (raw.contains('hits')) score -= 10;
    if (raw.contains('remix')) score -= 15;

    return score;
  }

  /// Fetches up to [limit] individual legitimate tracks for a specific [artist],
  /// prioritizing songs in [preferredLanguages] if specified, with support for progressive [page] pagination.
  Future<List<MusicItem>> getTracksForArtist(
    ArtistSummary artist, {
    int limit = 15,
    int page = 1,
    List<String> preferredLanguages = const [],
  }) async {
    final tracks = <MusicItem>[];
    try {
      final rawVideos = await _youtubeRepo.getArtistTracks(
        artist.name,
        page: page,
        limit: limit,
        preferredLanguages: preferredLanguages,
        priority: NetworkPriority.backgroundDiscovery,
      );

      final seenIds = <String>{};
      final candidateTracks = <MusicItem>[];

      for (final v in rawVideos) {
        if (!isLegitimateSong(v)) continue;
        final track = v.toTrack(reliableArtist: artist.name);
        if (!isTrackAttributedToArtist(track, artist.name)) {
          debugPrint(
              '[RecommendationService] Track "${track.title}" by "${track.artist}" excluded: not attributed to "${artist.name}"');
          continue;
        }
        if (seenIds.add(track.id)) {
          candidateTracks.add(track);
        }
      }

      // Rank candidates according to user's preferred languages
      return MusicLanguageService.rankAndDeduplicate(
        candidateTracks,
        preferredLanguages,
        limit: limit,
      );
    } catch (e) {
      debugPrint(
          '[RecommendationService] Fetch error for ${artist.name} (page $page): $e');
    }
    return tracks;
  }

  /// Loads personalized sections tailored to [profile] backed by genuine
  /// provider charts, multi-artist rotation, new artist discovery, and deterministic ranking.
  Future<RecommendationSections> getPersonalizedSections({
    required UserProfile? profile,
  }) async {
    final rawSelected = profile?.selectedArtists ?? [];
    final hasUserSelected = rawSelected.isNotEmpty;

    final effectiveArtists = hasUserSelected
        ? rawSelected
        : DeezerArtistRepository.staticCuratedArtists
            .take(8)
            .map((a) => a.toSummary())
            .toList();

    final uid = profile?.uid;
    final history = await _historyRepo.getRecentHistory(uid: uid, limit: 30);
    final tasteProfile = (uid != null && uid.isNotEmpty && _tasteRepo != null)
        ? await _tasteRepo!.getProfile(uid)
        : UserTasteProfile.empty(uid ?? '');

    final preferredLanguages = MusicLanguageService.getPreferredLanguages(
      history: history,
      profile: profile,
    );
    final historyKeys =
        history.map((e) => normalizeKey(e.title, e.artist)).toSet();

    final seenTrackKeys = <String>{...historyKeys};
    final seenTrackIds = <String>{};

    // ── 1. Trending & Popular Releases (Genuine Provider Chart Data) ──────────
    List<Track> trendingTracks = [];
    List<Track> recentReleases = [];

    try {
      final chartResult = await _trendingService.getTrendingAndRecentReleases();
      trendingTracks = chartResult.trendingTracks;
      recentReleases =
          await _verifyAndResolveRecentReleases(chartResult.recentReleases);
    } catch (e) {
      debugPrint('[RecommendationService] Trending fetch error: $e');
    }

    // ── 2. From Your Artists (Multi-Artist Rotation & Depth - Parallel) ──────
    final fromYourArtists = <MusicItem>[];
    // Deduplicate selectedArtists by normalized name within one recommendation session
    final seenSelectedNames = <String>{};
    final selectedArtistsToQuery = <ArtistSummary>[];
    for (final artist in effectiveArtists) {
      final normName = artist.name.trim().toLowerCase();
      if (normName.isEmpty || !seenSelectedNames.add(normName)) continue;
      selectedArtistsToQuery.add(artist);
      if (selectedArtistsToQuery.length >= 4) break;
    }

    // Fetch tracks for each selected artist concurrently to avoid slow sequential waterfalls
    final artistTrackBatches = <String, List<MusicItem>>{};
    try {
      final futures = selectedArtistsToQuery.map((artist) async {
        try {
          final tracks = await getTracksForArtist(
            artist,
            limit: 4,
            preferredLanguages: preferredLanguages,
          ).timeout(
            const Duration(seconds: 4),
            onTimeout: () => <MusicItem>[],
          );
          return MapEntry(artist.name, tracks);
        } catch (_) {
          return MapEntry(artist.name, <MusicItem>[]);
        }
      });
      final results = await Future.wait(futures);
      for (final entry in results) {
        if (entry.value.isNotEmpty) {
          artistTrackBatches[entry.key] = entry.value;
        }
      }
    } catch (e) {
      debugPrint(
          '[RecommendationService] Artist tracks concurrent fetch error: $e');
    }

    // Populate fromYourArtists strictly with the verified tracks for the initial spotlighted artist
    if (effectiveArtists.isNotEmpty) {
      final initialArtist = effectiveArtists.first;
      final initialBatch = artistTrackBatches[initialArtist.name] ?? const [];
      for (final t in initialBatch) {
        final key = normalizeKey(t.title, t.artist);
        if (seenTrackIds.add(t.id) && !seenTrackKeys.contains(key)) {
          fromYourArtists.add(t);
          seenTrackKeys.add(key);
        }
      }
    }

    // ── 3. Discover New Artists (Outside User's Selected Artists - Parallel) ────
    final relatedArtists = <ArtistModel>[];
    final selectedIds = effectiveArtists.map((a) => a.id).toSet();
    final selectedNames =
        effectiveArtists.map((a) => a.name.toLowerCase().trim()).toSet();

    if (hasUserSelected) {
      try {
        final relatedFutures = rawSelected.take(3).map((artist) async {
          try {
            return await _artistRepo.getRelatedArtists(artist.id).timeout(
                  const Duration(seconds: 3),
                  onTimeout: () => <ArtistModel>[],
                );
          } catch (_) {
            return <ArtistModel>[];
          }
        });
        final allRelated = await Future.wait(relatedFutures);
        for (final relatedList in allRelated) {
          for (final r in relatedList) {
            final rNameClean = r.name.toLowerCase().trim();
            if (!selectedIds.contains(r.id) &&
                !selectedNames.contains(rNameClean) &&
                !relatedArtists.any((a) =>
                    a.id == r.id ||
                    a.name.toLowerCase().trim() == rNameClean)) {
              relatedArtists.add(r);
              if (relatedArtists.length >= 8) break;
            }
          }
          if (relatedArtists.length >= 8) break;
        }
      } catch (e) {
        debugPrint(
            '[RecommendationService] Related concurrent fetch error: $e');
      }
    }

    // If still need more to explore, derive artists from live trending/recent releases
    // before falling back to curated artists
    if (relatedArtists.length < 8) {
      for (final t in [...trendingTracks, ...recentReleases]) {
        final name = t.artist.trim();
        final lower = name.toLowerCase();
        if (name.isEmpty ||
            lower == 'unknown artist' ||
            selectedNames.contains(lower) ||
            relatedArtists.any((r) => r.name.toLowerCase().trim() == lower)) {
          continue;
        }
        relatedArtists.add(
          ArtistModel(
            id: 'trend_${lower.hashCode}',
            name: name,
            imageUrl: t.imageUrl,
          ),
        );
        if (relatedArtists.length >= 8) break;
      }
    }

    if (relatedArtists.length < 8) {
      final curated = DeezerArtistRepository.staticCuratedArtists
          .where((a) =>
              !selectedIds.contains(a.id) &&
              !selectedNames.contains(a.name.toLowerCase().trim()) &&
              !relatedArtists.any((r) => r.id == a.id))
          .take(8 - relatedArtists.length)
          .toList();
      relatedArtists.addAll(curated);
    }

    // ── 4. Discover More (Personalized, Diverse & Ranked) ─────────────────────
    final discoverMore = <MusicItem>[];
    const targetDiscoverCount = 18;

    // REC-01 FIX: Capture exclusions from prior shelves BEFORE collecting discoverMore candidates.
    // Candidates intended for discoverMore must not exclude themselves from ranking.
    final priorShelfTrackIds = Set<String>.from(seenTrackIds);
    final priorShelfTrackKeys = Set<String>.from(seenTrackKeys);

    // Helper to evaluate and add candidates with deterministic quality scoring
    void addCandidate(MusicItem track) {
      if (discoverMore.length >= targetDiscoverCount) return;
      final key = normalizeKey(track.title, track.artist);
      if (seenTrackIds.add(track.id) && seenTrackKeys.add(key)) {
        discoverMore.add(track);
      }
    }

    // Source A: Playable tracks from discovered/related artists
    for (final rel in relatedArtists.take(4)) {
      if (discoverMore.length >= targetDiscoverCount) break;
      try {
        final rawRelVideos = <YouTubeVideo>[];
        final topLang =
            preferredLanguages.isNotEmpty ? preferredLanguages.first : null;
        if (topLang != null &&
            MusicLanguageService.isArtistMultilingualInLang(
                rel.name, topLang)) {
          final langVideos =
              await _youtubeRepo.search('${rel.name} $topLang song');
          rawRelVideos.addAll(langVideos);
        }
        final generalVideos = await _youtubeRepo.search('${rel.name} song');
        rawRelVideos.addAll(generalVideos);

        final valid = rawRelVideos.where(isLegitimateSong).toList();
        valid.sort((a, b) =>
            rankDiscoverCandidate(b).compareTo(rankDiscoverCandidate(a)));
        for (final v in valid.take(2)) {
          addCandidate(v.toTrack(reliableArtist: rel.name));
        }
      } catch (e) {
        debugPrint(
            '[RecommendationService] Discover related candidate error for ${rel.name}: $e');
      }
    }

    // Source B: Provider-backed trending tracks (ranked after top tier)
    for (final chartTrack in trendingTracks.skip(6)) {
      if (discoverMore.length >= targetDiscoverCount) break;
      addCandidate(chartTrack);
    }

    // Source C: Verified recent releases
    for (final releaseTrack in recentReleases) {
      if (discoverMore.length >= targetDiscoverCount) break;
      addCandidate(releaseTrack);
    }

    // Build chart rank map for deterministic scoring
    final chartRanks = <String, int>{};
    for (int i = 0; i < trendingTracks.length; i++) {
      final rank = i + 1;
      final t = trendingTracks[i];
      final cleanId = _normalizeTrackId(t.id);
      chartRanks[cleanId] = rank;
      chartRanks[t.id] = rank;
      chartRanks[
              '${t.title.toLowerCase().trim()}|${t.artist.toLowerCase().trim()}'] =
          rank;
    }

    // ── 5. Popular Tracks (Backwards Compatibility & Chart Depth) ────────────
    // If trendingTracks from provider has items, use them; otherwise fallback to search
    final popularTracks = trendingTracks.isNotEmpty
        ? trendingTracks
        : fromYourArtists.take(8).toList();

    // ── 6. Featured Track for Hero Banner ───────────────────────────────────
    final featuredTrack = trendingTracks.firstOrNull ??
        fromYourArtists.firstOrNull ??
        discoverMore.firstOrNull;

    final rankedDiscoverMore = _candidateRanker.rankCandidates(
      candidates: discoverMore,
      tasteProfile: tasteProfile,
      preferredLanguages: preferredLanguages,
      chartRanks: chartRanks,
      recentHistory: history,
      limit: targetDiscoverCount,
      excludedTrackIds: priorShelfTrackIds,
      excludedRecordingKeys: priorShelfTrackKeys,
    );

    // Fall back gracefully to original candidates if filtered set is empty
    final finalDiscoverMore = rankedDiscoverMore.isNotEmpty
        ? rankedDiscoverMore
        : MusicLanguageService.rankAndDeduplicate(
            discoverMore,
            preferredLanguages,
            limit: targetDiscoverCount,
          );

    final sections = RecommendationSections(
      favoriteArtists: effectiveArtists,
      fromYourArtists: fromYourArtists,
      relatedArtists: relatedArtists.take(8).toList(),
      popularTracks: popularTracks,
      trendingTracks: trendingTracks,
      recentReleases: recentReleases,
      discoverMore: finalDiscoverMore,
      recentlyPlayed: history,
      featuredTrack: featuredTrack,
    );
    _cachedSections = sections;
    return sections;
  }

  RecommendationSections? _cachedSections;
  RecommendationSections? get cachedSections => _cachedSections;

  /// Verifies candidate recent releases, ensuring each item corresponds to a verified,
  /// playable YouTube music track before presenting it in the Recent Releases section.
  /// Candidates that cannot be verified are excluded.
  Future<List<Track>> _verifyAndResolveRecentReleases(
      List<Track> rawReleases) async {
    if (rawReleases.isEmpty) return const [];
    final verified = <Track>[];
    for (final track in rawReleases) {
      if (verified.length >= 8) break;
      final rawT = track.rawTitle ?? track.title;
      final rawA = track.rawArtist ?? track.artist;

      final cleanId = track.id.replaceFirst('youtube_', '');
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(cleanId)) {
        final candidate = YouTubeVideo(
          id: cleanId,
          title: track.title,
          channelTitle: track.artist,
          thumbnailUrl: track.imageUrl,
          duration: track.duration,
          viewCount: '',
          rawTitle: rawT,
          rawChannelTitle: rawA,
        );
        if (MusicResultClassifier.isValidIndividualSong(candidate)) {
          verified.add(track);
        }
        continue;
      }

      // Defer YouTube video-ID resolution until playback is actually requested
      // for chart/metadata tracks (wm_chart_..., itunes_...) that already have
      // verified title and artist metadata. This eliminates the Home startup search storm.
      if (track.title.trim().isNotEmpty && track.artist.trim().isNotEmpty) {
        verified.add(track);
      }
    }
    return verified;
  }

  /// Generates dynamic upcoming queue recommendations when the playback queue
  /// Evaluates and generates truly related upcoming track recommendations for the playing queue.
  ///
  /// Strict Rules:
  /// - Prioritizes the same artist, same album, or verified musical relationships.
  /// - Excludes derivative edits (karaoke, covers, fan edits, compilation mixes, live recordings).
  /// - Strictly NEVER falls back to unrelated regional trending songs or arbitrary curated artists.
  /// - If no reliable recommendation is available, returns an empty list leaving the queue untouched.
  Future<List<MusicItem>> getUpcomingQueueRecommendations({
    required MusicItem currentTrack,
    required List<MusicItem> currentQueue,
    UserProfile? profile,
    int limit = 10,
  }) async {
    final upcoming = <MusicItem>[];
    final queueKeys = currentQueue
        .map((t) => SearchDeduplicator.computeRecordingKey(t))
        .toSet();
    final queueBaseKeys = currentQueue
        .map((t) => SearchDeduplicator.computeLanguageAgnosticRecordingKey(t))
        .toSet();
    final queueIds = currentQueue.map((t) => _normalizeTrackId(t.id)).toSet();

    // Include currentTrack key and ID to prevent immediate duplicate
    queueKeys.add(SearchDeduplicator.computeRecordingKey(currentTrack));
    queueBaseKeys.add(
        SearchDeduplicator.computeLanguageAgnosticRecordingKey(currentTrack));
    queueIds.add(_normalizeTrackId(currentTrack.id));

    final currentRawTitle =
        (currentTrack is Track && currentTrack.rawTitle != null)
            ? currentTrack.rawTitle!
            : currentTrack.title;
    final seedLanguage = MusicLanguageService.detectLanguage(
      currentRawTitle,
      artist: currentTrack.artist,
    );

    final currentArtist = currentTrack.artist.trim();
    final currentArtistNorm = SearchDeduplicator.normalizeArtist(currentArtist);

    final currentBaseTitle = SearchDeduplicator.normalizeBaseTitle(
      currentTrack.title,
      rawTitle:
          (currentTrack is Track) ? currentTrack.rawTitle : currentTrack.title,
      artist: currentTrack.artist,
    ).toLowerCase().trim();

    final preferredLanguages = profile?.preferredLanguages ?? const <String>[];
    final onboardingArtistsNorm = (profile?.selectedArtists ?? const [])
        .map((a) => SearchDeduplicator.normalizeArtist(a.name))
        .where((a) => a.isNotEmpty)
        .toSet();

    final scoredPool =
        <({MusicItem track, double score, String artistNorm, String reason})>[];
    final seenPoolIds = <String>{};
    final seenPoolKeys = <String>{};
    final seenPoolBaseKeys = <String>{};

    bool isValidCandidate(MusicItem track) {
      final key = SearchDeduplicator.computeRecordingKey(track);
      final baseKey =
          SearchDeduplicator.computeLanguageAgnosticRecordingKey(track);
      final normId = _normalizeTrackId(track.id);

      if (queueKeys.contains(key) ||
          queueBaseKeys.contains(baseKey) ||
          queueIds.contains(normId) ||
          seenPoolKeys.contains(key) ||
          seenPoolBaseKeys.contains(baseKey) ||
          seenPoolIds.contains(normId)) {
        QueueDiagnostics.logDuplicateRejected(
          track: track,
          duplicateReason: 'Track already present in queue ($normId)',
        );
        return false;
      }

      // Reject different artists' tracks merely sharing the current track's title
      final candidateBaseTitle = SearchDeduplicator.normalizeBaseTitle(
        track.title,
        rawTitle: (track is Track) ? track.rawTitle : track.title,
        artist: track.artist,
      ).toLowerCase().trim();
      final candidateArtistNorm =
          SearchDeduplicator.normalizeArtist(track.artist);

      if (currentBaseTitle.isNotEmpty &&
          candidateBaseTitle == currentBaseTitle &&
          candidateArtistNorm != currentArtistNorm) {
        return false;
      }

      if (track.isYoutube) {
        final rawT =
            (track is Track) ? (track.rawTitle ?? track.title) : track.title;
        final rawA =
            (track is Track) ? (track.rawArtist ?? track.artist) : track.artist;
        final v = YouTubeVideo(
          id: track.id.replaceFirst('youtube_', ''),
          title: track.title,
          channelTitle: track.artist,
          thumbnailUrl: track.imageUrl,
          duration: track.duration,
          viewCount: '',
          rawTitle: rawT,
          rawChannelTitle: rawA,
        );
        if (!isLegitimateSong(v)) return false;

        // Exclude derivative edits (covers, karaoke, fan edits, status clips, etc.)
        final intent = QueryIntent.fromQuery(currentArtist);
        final editType = SearchDeduplicator.detectEditType(v, intent);
        if (editType == EditType.coverSong ||
            editType == EditType.karaokeVersion ||
            editType == EditType.fanEdit ||
            editType == EditType.livePerformance ||
            editType == EditType.compilationMix ||
            editType == EditType.mashupRemake ||
            editType == EditType.nonMusicEntertainment) {
          return false;
        }
      }

      return true;
    }

    void collectCandidate(
      MusicItem track, {
      required double baseRelevanceScore,
      required String sourceReason,
    }) {
      if (!isValidCandidate(track)) return;

      final key = SearchDeduplicator.computeRecordingKey(track);
      final baseKey =
          SearchDeduplicator.computeLanguageAgnosticRecordingKey(track);
      final normId = _normalizeTrackId(track.id);
      seenPoolKeys.add(key);
      seenPoolBaseKeys.add(baseKey);
      seenPoolIds.add(normId);

      final candArtistNorm = SearchDeduplicator.normalizeArtist(track.artist);
      double score = baseRelevanceScore;

      // Track-anchored affinity: modest boost for seed artist, never dominating diversity.
      if (currentArtistNorm.isNotEmpty && candArtistNorm == currentArtistNorm) {
        score += 15.0;
      }

      // Seed-track language alignment: prefer matching language, penalize conflicting language.
      final candRawTitle = (track is Track && track.rawTitle != null)
          ? track.rawTitle!
          : track.title;
      final candLang = MusicLanguageService.detectLanguage(
        candRawTitle,
        artist: track.artist,
      );
      if (seedLanguage != 'Unknown' && candLang != 'Unknown') {
        if (candLang.toLowerCase() == seedLanguage.toLowerCase()) {
          score += 25.0;
        } else {
          score -= 35.0;
        }
      }

      // Secondary language tie-breaker from user profile.
      if (preferredLanguages.isNotEmpty && candLang != 'Unknown') {
        final langIdx = preferredLanguages
            .indexWhere((l) => l.toLowerCase() == candLang.toLowerCase());
        if (langIdx == 0) {
          score += 10.0;
        } else if (langIdx > 0) {
          score += 5.0;
        }
      }

      // Onboarding artist preference is a light secondary signal, not a filter.
      if (onboardingArtistsNorm.contains(candArtistNorm)) {
        score += 10.0;
      }

      scoredPool.add((
        track: track,
        score: score,
        artistNorm: candArtistNorm,
        reason: sourceReason,
      ));
    }

    try {
      // 1. Track-Anchored Primary: YouTube related tracks (supports 11-char IDs,
      // Track.sourceId, and discovery IDs resolved via YouTube search).
      String seedVideoId = currentTrack.id.replaceFirst('youtube_', '');
      if (seedVideoId.length != 11 &&
          currentTrack is Track &&
          currentTrack.sourceId != null &&
          currentTrack.sourceId!.trim().length == 11) {
        seedVideoId = currentTrack.sourceId!.trim();
      }
      if (seedVideoId.length != 11 && currentTrack.title.trim().isNotEmpty) {
        final lookupQuery =
            currentArtist.isNotEmpty && currentArtist.toLowerCase() != 'unknown'
                ? '${currentTrack.title} $currentArtist'
                : currentTrack.title;
        final resolved = await _youtubeRepo.search(lookupQuery);
        final bestSeed = resolved
            .where((v) => isLegitimateSong(v) && v.id.length == 11)
            .firstOrNull;
        if (bestSeed != null) {
          seedVideoId = bestSeed.id;
        }
      }

      if (seedVideoId.length == 11) {
        final seed = YouTubeVideo(
          id: seedVideoId,
          title: currentTrack.title,
          channelTitle: currentTrack.artist,
          thumbnailUrl: currentTrack.imageUrl,
          duration: currentTrack.duration,
          viewCount: '',
        );
        final relatedVideos =
            await _youtubeRepo.getRelatedTracks(seed, limit: limit * 2);
        for (final v in relatedVideos) {
          if (isLegitimateSong(v)) {
            collectCandidate(
              v.toTrack(),
              baseRelevanceScore: 100.0,
              sourceReason: 'Related to "${currentTrack.title}"',
            );
          }
        }
      }

      // 2. Secondary: Same-artist catalog (capped contribution so one artist never dominates)
      if (currentArtist.isNotEmpty &&
          currentArtist.toLowerCase() != 'unknown' &&
          currentArtist.toLowerCase() != 'various artists') {
        final artistTracks = await _youtubeRepo.getArtistTracks(
          currentArtist,
          page: 1,
          limit: 5,
          preferredLanguages: preferredLanguages,
        );
        for (final v in artistTracks) {
          if (isLegitimateSong(v)) {
            collectCandidate(
              v.toTrack(reliableArtist: currentArtist),
              baseRelevanceScore: 70.0,
              sourceReason: 'Same artist catalog: "$currentArtist"',
            );
          }
        }
      }

      // 3. Tertiary: Same album tracks when album metadata is available
      if (currentTrack is Track &&
          currentTrack.albumName != null &&
          currentTrack.albumName!.isNotEmpty) {
        final albumTracks = await _youtubeRepo.search(
          '${currentTrack.artist} ${currentTrack.albumName}',
        );
        for (final v in albumTracks) {
          if (isLegitimateSong(v)) {
            collectCandidate(
              v.toTrack(reliableArtist: currentTrack.artist),
              baseRelevanceScore: 85.0,
              sourceReason: 'Same album: "${currentTrack.albumName}"',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[RecommendationService] Upcoming queue expansion error: $e');
    }

    if (scoredPool.isEmpty) return const [];

    // Sort deterministically by relevance score descending
    scoredPool.sort((a, b) => b.score.compareTo(a.score));

    // Apply strict per-artist diversity cap (max 2 per normalized artist).
    // Never backfill same-artist deferred candidates beyond this cap.
    const int maxTracksPerArtist = 2;
    final artistCounts = <String, int>{};

    for (final entry in scoredPool) {
      if (upcoming.length >= limit) break;
      final count = artistCounts[entry.artistNorm] ?? 0;
      if (entry.artistNorm.isEmpty || count < maxTracksPerArtist) {
        artistCounts[entry.artistNorm] = count + 1;
        upcoming.add(entry.track);
      }
    }

    // If diverse candidates didn't reach [limit], perform bounded related-artist
    // discovery (max 2 related artists) instead of repeating the same artist.
    if (upcoming.length < limit &&
        currentArtist.isNotEmpty &&
        currentArtist.toLowerCase() != 'unknown' &&
        currentArtist.toLowerCase() != 'various artists') {
      try {
        final matchedArtists = await _artistRepo
            .searchArtists(currentArtist,
                language: seedLanguage != 'Unknown' ? seedLanguage : null)
            .timeout(const Duration(seconds: 3), onTimeout: () => const []);
        final primaryArtist = matchedArtists.firstOrNull;
        if (primaryArtist != null) {
          final related = await _artistRepo
              .getRelatedArtists(primaryArtist.id)
              .timeout(const Duration(seconds: 3), onTimeout: () => const []);
          final relatedCandidates = related
              .where((a) =>
                  SearchDeduplicator.normalizeArtist(a.name) !=
                  currentArtistNorm)
              .take(2)
              .toList();
          if (relatedCandidates.isNotEmpty) {
            final relatedBatches = await Future.wait(
              relatedCandidates.map((rel) => _youtubeRepo
                  .getArtistTracks(
                    rel.name,
                    page: 1,
                    limit: 4,
                    preferredLanguages: preferredLanguages,
                  )
                  .catchError((_) => <YouTubeVideo>[])),
            );
            final relatedPool = <({
              MusicItem track,
              double score,
              String artistNorm,
            })>[];
            for (var idx = 0; idx < relatedCandidates.length; idx++) {
              final rel = relatedCandidates[idx];
              for (final v in relatedBatches[idx]) {
                if (!isLegitimateSong(v)) continue;
                final track = v.toTrack(reliableArtist: rel.name);
                if (!isValidCandidate(track)) continue;
                final key = SearchDeduplicator.computeRecordingKey(track);
                final baseKey =
                    SearchDeduplicator.computeLanguageAgnosticRecordingKey(
                        track);
                final normId = _normalizeTrackId(track.id);
                seenPoolKeys.add(key);
                seenPoolBaseKeys.add(baseKey);
                seenPoolIds.add(normId);
                relatedPool.add((
                  track: track,
                  score: 60.0,
                  artistNorm: SearchDeduplicator.normalizeArtist(track.artist),
                ));
              }
            }
            for (final entry in relatedPool) {
              if (upcoming.length >= limit) break;
              final count = artistCounts[entry.artistNorm] ?? 0;
              if (entry.artistNorm.isEmpty || count < maxTracksPerArtist) {
                artistCounts[entry.artistNorm] = count + 1;
                upcoming.add(entry.track);
              }
            }
          }
        }
      } catch (e) {
        debugPrint(
            '[RecommendationService] Related-artist diversity expansion failed: $e');
      }
    }

    // STRICT POLICY: Never fallback to unrelated trending chart songs or arbitrary curated artists!
    // If no genuinely related tracks are available, return empty list leaving queue untouched.
    if (upcoming.isEmpty) return const [];

    return upcoming;
  }
}
