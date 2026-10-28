import 'package:flutter/foundation.dart';
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
import '../../youtube/data/youtube_repository.dart';
import '../../search/domain/search_deduplicator.dart';
import 'trending_music_service.dart';

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

  RecommendationService({
    YouTubeRepository? youtubeRepo,
    ArtistRepository? artistRepo,
    ListeningHistoryRepository? historyRepo,
    TrendingMusicService? trendingService,
  })  : _youtubeRepo = youtubeRepo ?? YouTubeRepository(),
        _artistRepo = artistRepo ?? DeezerArtistRepository(),
        _historyRepo = historyRepo ?? SupabaseListeningHistoryRepository(),
        _trendingService = trendingService ?? TrendingMusicService();

  static String normalizeKey(String title, String artist) {
    final cleanT = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final cleanA = artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return '$cleanT|$cleanA';
  }

  /// Filters out playlists, multi-song compilations, jukeboxes, full movies, podcasts, and comedy sketches
  /// while strictly preserving genuine individual songs.
  static bool isLegitimateSong(YouTubeVideo video) {
    if (!MusicResultClassifier.isValidMusicTrack(video)) {
      return false;
    }
    final raw = video.rawTitle ?? video.title;
    final title = raw.toLowerCase();
    final durationSec = _parseDurationSeconds(video.duration);

    // 1. Spoken-word, interview, podcast, behind-the-scenes
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

    // 5. Long-form video heuristics
    if (durationSec >= 1500) {
      final isClassicalRecital = title.contains('raga') ||
          title.contains('alapana') ||
          title.contains('symphony') ||
          title.contains('carnatic') ||
          title.contains('kriti') ||
          title.contains('varnam');
      if (!isClassicalRecital) {
        return false;
      }
    }

    if (durationSec >= 900) {
      if (title.contains('hits') ||
          title.contains('songs') ||
          title.contains('album') ||
          title.contains('collection') ||
          title.contains('mix') ||
          title.contains('vol') ||
          title.contains('part 1 & 2') ||
          title.contains('medley')) {
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

  /// Fetches up to [limit] individual legitimate tracks for a specific [artist].
  Future<List<MusicItem>> getTracksForArtist(
    ArtistSummary artist, {
    int limit = 6,
  }) async {
    final tracks = <MusicItem>[];
    try {
      final rawVideos = await _youtubeRepo.search('${artist.name} songs');
      final deduplicated = SearchDeduplicator.deduplicateAndRank(
        rawVideos,
        query: artist.name,
      );
      final seenIds = <String>{};

      for (final v in deduplicated) {
        if (!isLegitimateSong(v)) continue;
        final track = v.toTrack(reliableArtist: artist.name);
        if (seenIds.add(track.id)) {
          tracks.add(track);
          if (tracks.length >= limit) break;
        }
      }
    } catch (e) {
      debugPrint('[RecommendationService] Fetch error for ${artist.name}: $e');
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
    final history = await _historyRepo.getRecentHistory(uid: uid, limit: 20);
    final historyKeys = history
        .map((e) => normalizeKey(e.title, e.artist))
        .toSet();

    final seenTrackKeys = <String>{...historyKeys};
    final seenTrackIds = <String>{};

    // ── 1. Trending & Popular Releases (Genuine Provider Chart Data) ──────────
    List<Track> trendingTracks = [];
    List<Track> recentReleases = [];

    try {
      final chartResult = await _trendingService.getTrendingAndRecentReleases();
      trendingTracks = chartResult.trendingTracks;
      recentReleases = chartResult.recentReleases;
    } catch (e) {
      debugPrint('[RecommendationService] Trending fetch error: $e');
    }

    // ── 2. From Your Artists (Multi-Artist Rotation & Depth) ──────────────────
    final fromYourArtists = <MusicItem>[];
    final selectedArtistsToQuery = effectiveArtists.take(4).toList();

    // Fetch tracks for each selected artist to guarantee variety across favorites
    final artistTrackBatches = <String, List<MusicItem>>{};
    for (final artist in selectedArtistsToQuery) {
      final tracks = await getTracksForArtist(artist, limit: 4);
      if (tracks.isNotEmpty) {
        artistTrackBatches[artist.name] = tracks;
      }
    }

    // Interleave tracks across selected artists (e.g. Artist 1 Track 1, Artist 2 Track 1...)
    bool moreTracks = true;
    int trackIndex = 0;
    while (moreTracks && fromYourArtists.length < 16) {
      moreTracks = false;
      for (final artist in selectedArtistsToQuery) {
        final batch = artistTrackBatches[artist.name] ?? [];
        if (trackIndex < batch.length) {
          final t = batch[trackIndex];
          final key = normalizeKey(t.title, t.artist);
          if (seenTrackIds.add(t.id) && !seenTrackKeys.contains(key)) {
            fromYourArtists.add(t);
            seenTrackKeys.add(key);
          }
          moreTracks = true;
        }
      }
      trackIndex++;
    }

    // ── 3. Discover New Artists (Outside User's Selected Artists) ────────────
    final relatedArtists = <ArtistModel>[];
    final selectedIds = effectiveArtists.map((a) => a.id).toSet();
    final selectedNames = effectiveArtists
        .map((a) => a.name.toLowerCase().trim())
        .toSet();

    if (hasUserSelected) {
      for (final artist in rawSelected.take(3)) {
        if (relatedArtists.length >= 8) break;
        try {
          final related = await _artistRepo.getRelatedArtists(artist.id);
          for (final r in related) {
            final rNameClean = r.name.toLowerCase().trim();
            if (!selectedIds.contains(r.id) &&
                !selectedNames.contains(rNameClean) &&
                !relatedArtists.any((a) => a.id == r.id || a.name.toLowerCase().trim() == rNameClean)) {
              relatedArtists.add(r);
              if (relatedArtists.length >= 8) break;
            }
          }
        } catch (e) {
          debugPrint('[RecommendationService] Related error for ${artist.name}: $e');
        }
      }
    }

    // If still need more to explore, add non-selected curated artists
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
        final videos = await _youtubeRepo.search('${rel.name} song');
        final valid = videos.where(isLegitimateSong).toList();
        valid.sort((a, b) => rankDiscoverCandidate(b).compareTo(rankDiscoverCandidate(a)));
        for (final v in valid.take(2)) {
          addCandidate(v.toTrack(reliableArtist: rel.name));
        }
      } catch (e) {
        debugPrint('[RecommendationService] Discover related candidate error for ${rel.name}: $e');
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

    // ── 5. Popular Tracks (Backwards Compatibility & Chart Depth) ────────────
    // If trendingTracks from provider has items, use them; otherwise fallback to search
    final popularTracks = trendingTracks.isNotEmpty
        ? trendingTracks
        : fromYourArtists.take(8).toList();

    // ── 6. Featured Track for Hero Banner ───────────────────────────────────
    final featuredTrack = trendingTracks.firstOrNull ??
        fromYourArtists.firstOrNull ??
        discoverMore.firstOrNull;

    return RecommendationSections(
      favoriteArtists: effectiveArtists,
      fromYourArtists: fromYourArtists,
      relatedArtists: relatedArtists.take(8).toList(),
      popularTracks: popularTracks,
      trendingTracks: trendingTracks,
      recentReleases: recentReleases,
      discoverMore: discoverMore,
      recentlyPlayed: history,
      featuredTrack: featuredTrack,
    );
  }

  /// Generates dynamic upcoming queue recommendations when the playback queue
  /// is running low or approaching exhaustion.
  ///
  /// Considers:
  /// - Current playing track and artist.
  /// - Real chart trends from [TrendingMusicService].
  /// - User's selected artists.
  /// - Deduplicates strictly against [currentQueue] and recent listening history.
  /// - Enforces artist diversity so the queue never loops through identical tracks.
  Future<List<MusicItem>> getUpcomingQueueRecommendations({
    required MusicItem currentTrack,
    required List<MusicItem> currentQueue,
    UserProfile? profile,
    int limit = 10,
  }) async {
    final upcoming = <MusicItem>[];
    final queueKeys = currentQueue
        .map((t) => normalizeKey(t.title, t.artist))
        .toSet();
    final queueIds = currentQueue.map((t) => t.id).toSet();

    // Also include currentTrack key and ID
    queueKeys.add(normalizeKey(currentTrack.title, currentTrack.artist));
    queueIds.add(currentTrack.id);

    // Track how many songs per artist are in the upcoming batch to guarantee variety
    final artistCount = <String, int>{};
    void addQueueTrack(MusicItem track) {
      if (upcoming.length >= limit) return;
      final key = normalizeKey(track.title, track.artist);
      final artistKey = track.artist.toLowerCase().trim();
      final count = artistCount[artistKey] ?? 0;

      // Max 2 songs per artist in an expansion batch to guarantee diversity
      if (count >= 2) return;

      if (track.isYoutube) {
        final rawT = (track is Track) ? (track.rawTitle ?? track.title) : track.title;
        final rawA = (track is Track) ? (track.rawArtist ?? track.artist) : track.artist;
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
        if (!isLegitimateSong(v)) return;
      }

      if (!queueKeys.contains(key) && !queueIds.contains(track.id)) {
        queueKeys.add(key);
        queueIds.add(track.id);
        artistCount[artistKey] = count + 1;
        upcoming.add(track);
      }
    }

    try {
      // 1. Fetch related tracks seeded by current track
      if (currentTrack.isYoutube) {
        final videoId = currentTrack.id.replaceFirst('youtube_', '');
        if (videoId.length == 11) {
          final seed = YouTubeVideo(
            id: videoId,
            title: currentTrack.title,
            channelTitle: currentTrack.artist,
            thumbnailUrl: currentTrack.imageUrl,
            duration: currentTrack.duration,
            viewCount: '',
          );
          final relatedVideos = await _youtubeRepo.getRelatedTracks(seed, limit: 8);
          for (final v in relatedVideos) {
            if (isLegitimateSong(v)) {
              addQueueTrack(v.toTrack());
            }
          }
        }
      }

      // If related videos didn't fill the quota, search for similar tracks
      if (upcoming.length < limit) {
        final searchRelated = await _youtubeRepo.search('${currentTrack.artist} song');
        for (final v in searchRelated) {
          if (isLegitimateSong(v)) {
            addQueueTrack(v.toTrack(reliableArtist: currentTrack.artist));
          }
        }
      }

      // 2. Blend genuine provider-backed trending tracks
      if (upcoming.length < limit) {
        final chartResult = await _trendingService.getTrendingAndRecentReleases();
        for (final chartTrack in chartResult.trendingTracks) {
          addQueueTrack(chartTrack);
          if (upcoming.length >= limit) break;
        }
      }

      // 3. Blend user's other selected artists
      if (upcoming.length < limit && profile != null && profile.selectedArtists.isNotEmpty) {
        for (final fav in profile.selectedArtists) {
          if (fav.name.toLowerCase().trim() == currentTrack.artist.toLowerCase().trim()) {
            continue;
          }
          final favTracks = await getTracksForArtist(fav, limit: 2);
          for (final t in favTracks) {
            addQueueTrack(t);
          }
          if (upcoming.length >= limit) break;
        }
      }

      // 4. Fallback to curated catalog
      if (upcoming.length < limit) {
        final curated = DeezerArtistRepository.staticCuratedArtists;
        for (final artist in curated) {
          final catalogTracks = await getTracksForArtist(artist.toSummary(), limit: 1);
          for (final t in catalogTracks) {
            addQueueTrack(t);
          }
          if (upcoming.length >= limit) break;
        }
      }
    } catch (e) {
      debugPrint('[RecommendationService] Upcoming queue expansion error: $e');
    }

    return upcoming;
  }
}
