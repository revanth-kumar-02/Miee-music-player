import 'package:flutter/foundation.dart';
import '../../../shared/models/music_item.dart';
import '../../history/data/listening_history_repository.dart';
import '../../history/domain/listening_event.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../profile/domain/user_profile.dart';
import '../../youtube/domain/youtube_model.dart';
import '../../youtube/data/youtube_repository.dart';

class RecommendationSections {
  final List<ArtistSummary> favoriteArtists;
  final List<MusicItem> fromYourArtists;
  final List<ArtistModel> relatedArtists;
  final List<MusicItem> popularTracks;
  final List<MusicItem> discoverMore;
  final List<ListeningEvent> recentlyPlayed;
  final MusicItem? featuredTrack;

  const RecommendationSections({
    this.favoriteArtists = const [],
    this.fromYourArtists = const [],
    this.relatedArtists = const [],
    this.popularTracks = const [],
    this.discoverMore = const [],
    this.recentlyPlayed = const [],
    this.featuredTrack,
  });
}

class RecommendationService {
  final YouTubeRepository _youtubeRepo;
  final ArtistRepository _artistRepo;
  final ListeningHistoryRepository _historyRepo;

  RecommendationService({
    YouTubeRepository? youtubeRepo,
    ArtistRepository? artistRepo,
    ListeningHistoryRepository? historyRepo,
  })  : _youtubeRepo = youtubeRepo ?? YouTubeRepository(),
        _artistRepo = artistRepo ?? DeezerArtistRepository(),
        _historyRepo = historyRepo ?? FirestoreListeningHistoryRepository();

  /// Filters out playlists, multi-song compilations, jukeboxes, full movies, and podcasts
  /// while strictly preserving genuine individual songs (including legitimate long individual songs
  /// and songs containing words like 'hits' or 'official video').
  static bool isLegitimateSong(YouTubeVideo video) {
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

    // 4. Multi-song collections: "Top 10", "Top 20", "Top 50", "Best of", "All Songs", "Full Playlist", "Full Album", etc.
    final compilationRegex = RegExp(
      r'(\btop\s*\d+\b|\bbest\s+of\b|\bhit\s+songs\s+collection\b|\ball\s+songs\b|\bfull\s+album\b|\bfull\s+playlist\b|\bplaylist\b|\bcompilation\b|\bsongs\s+collection\b)',
      caseSensitive: false,
    );
    if (compilationRegex.hasMatch(title)) {
      return false;
    }

    // 5. Long-form video heuristics:
    // - Over 25 minutes (1500 seconds, e.g. 29-minute playlist mix) is almost certainly a compilation/mix
    //   unless specifically marked as a solo classical raga/carnatic/symphony recital.
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

    // - Videos between 15-25 minutes (900-1499s) with multi-song/compilation indicators:
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

    // - Over 35 minutes (2100s) is strictly not an individual track
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

  /// Calculates a candidate quality and relevance score for ranking Discover More tracks.
  static int rankDiscoverCandidate(YouTubeVideo video) {
    int score = 100;
    final raw = (video.rawTitle ?? video.title).toLowerCase();
    final ch = (video.rawChannelTitle ?? video.channelTitle).toLowerCase();

    // High confidence source channels
    if (ch.contains('topic')) score += 30;
    if (ch.contains('vevo') || ch.contains('official')) score += 20;

    // Track type indicators
    if (raw.contains('official audio') ||
        raw.contains('official video') ||
        raw.contains('lyric video')) {
      score += 15;
    }

    // Penalize ambiguous terms
    if (raw.contains('hits')) score -= 10;
    if (raw.contains('remix')) score -= 15;

    return score;
  }

  /// Loads personalized sections tailored to [profile].
  Future<RecommendationSections> getPersonalizedSections({
    required UserProfile? profile,
  }) async {
    final rawSelected = profile?.selectedArtists ?? [];
    final hasUserSelected = rawSelected.isNotEmpty;

    // Use user-selected artists or genuine curated catalog artists if none selected yet
    final effectiveArtists = hasUserSelected
        ? rawSelected
        : DeezerArtistRepository.staticCuratedArtists
            .take(8)
            .map((a) => a.toSummary())
            .toList();

    final uid = profile?.uid;
    final history = await _historyRepo.getRecentHistory(uid: uid, limit: 15);
    final seenTrackIds = <String>{};

    // 1. From Your Artists: fetch top individual tracks for selected/curated artists
    final fromYourArtists = <MusicItem>[];
    for (final artist in effectiveArtists.take(3)) {
      try {
        final videos = await _youtubeRepo.search('${artist.name} song');
        for (final v in videos) {
          if (!isLegitimateSong(v)) continue;
          final track = v.toTrack(reliableArtist: artist.name);
          if (seenTrackIds.add(track.id)) {
            fromYourArtists.add(track);
            if (fromYourArtists.length >= 6) break;
          }
        }
      } catch (e) {
        debugPrint('[RecommendationService] Fetch error for ${artist.name}: $e');
      }
    }

    // 2. Related Artists / Artists to Explore:
    final relatedArtists = <ArtistModel>[];
    if (hasUserSelected) {
      final primaryArtist = rawSelected.first;
      try {
        final related = await _artistRepo.getRelatedArtists(primaryArtist.id);
        final selectedIds = rawSelected.map((a) => a.id).toSet();
        for (final r in related) {
          if (!selectedIds.contains(r.id)) {
            relatedArtists.add(r);
          }
        }
      } catch (e) {
        debugPrint('[RecommendationService] Related artists error: $e');
      }
    }

    if (relatedArtists.isEmpty) {
      final selectedIds = effectiveArtists.map((a) => a.id).toSet();
      final curated = DeezerArtistRepository.staticCuratedArtists
          .where((a) => !selectedIds.contains(a.id))
          .take(8)
          .toList();
      relatedArtists.addAll(curated);
    }

    // 3. Popular Tracks:
    final popularTracks = <MusicItem>[];
    try {
      final popQuery = effectiveArtists.isNotEmpty
          ? '${effectiveArtists.first.name} song'
          : 'top hits song';
      final popVideos = await _youtubeRepo.search(popQuery);
      for (final v in popVideos) {
        if (!isLegitimateSong(v)) continue;
        final track = v.toTrack();
        if (seenTrackIds.add(track.id)) {
          popularTracks.add(track);
          if (popularTracks.length >= 8) break;
        }
      }
    } catch (e) {
      debugPrint('[RecommendationService] Popular tracks error: $e');
    }

    // Fallback: If popularTracks is still empty, search 'top songs'
    if (popularTracks.isEmpty) {
      try {
        final generalVideos = await _youtubeRepo.search('top songs');
        for (final v in generalVideos) {
          if (!isLegitimateSong(v)) continue;
          final track = v.toTrack();
          if (seenTrackIds.add(track.id)) {
            popularTracks.add(track);
            if (popularTracks.length >= 8) break;
          }
        }
      } catch (e) {
        debugPrint('[RecommendationService] General popular fallback error: $e');
      }
    }

    // 4. Discover More:
    final discoverMore = <MusicItem>[];
    const targetDiscoverCount = 10;
    const minDiscoverCount = 6;

    Future<void> addRankedCandidates(
      List<YouTubeVideo> videos, {
      String? reliableArtist,
    }) async {
      final valid = videos.where(isLegitimateSong).toList();
      valid.sort((a, b) => rankDiscoverCandidate(b).compareTo(rankDiscoverCandidate(a)));

      for (final v in valid) {
        if (discoverMore.length >= targetDiscoverCount) break;
        final track = v.toTrack(reliableArtist: reliableArtist);
        if (seenTrackIds.add(track.id)) {
          discoverMore.add(track);
        }
      }
    }

    // Priority 1: Individual tracks by top artists
    if (effectiveArtists.isNotEmpty) {
      for (final fav in effectiveArtists.take(3)) {
        if (discoverMore.length >= targetDiscoverCount) break;
        try {
          final videos = await _youtubeRepo.search('${fav.name} song');
          await addRankedCandidates(videos, reliableArtist: fav.name);
        } catch (e) {
          debugPrint('[RecommendationService] Discover artist error for ${fav.name}: $e');
        }
      }
    }

    // Priority 2: Individual tracks from verified related artists
    if (relatedArtists.isNotEmpty) {
      for (final rel in relatedArtists.take(4)) {
        if (discoverMore.length >= targetDiscoverCount) break;
        try {
          final videos = await _youtubeRepo.search('${rel.name} song');
          await addRankedCandidates(videos, reliableArtist: rel.name);
        } catch (e) {
          debugPrint('[RecommendationService] Discover related artist error for ${rel.name}: $e');
        }
      }
    }

    // Priority 3: Fallback fetching from curated catalog
    if (discoverMore.length < minDiscoverCount) {
      final curatedCatalog = DeezerArtistRepository.staticCuratedArtists;
      final existingNames = <String>{
        ...effectiveArtists.map((a) => a.name.toLowerCase()),
        ...relatedArtists.map((a) => a.name.toLowerCase()),
      };
      final fallbackCurated = curatedCatalog
          .where((a) => !existingNames.contains(a.name.toLowerCase()))
          .toList();

      for (final artist in fallbackCurated) {
        if (discoverMore.length >= minDiscoverCount) break;
        try {
          final videos = await _youtubeRepo.search('${artist.name} song');
          await addRankedCandidates(videos, reliableArtist: artist.name);
        } catch (e) {
          debugPrint('[RecommendationService] Discover catalog fallback error for ${artist.name}: $e');
        }
      }
    }

    // 5. Featured Track for Hero Banner:
    final featuredTrack = popularTracks.firstOrNull ??
        fromYourArtists.firstOrNull ??
        discoverMore.firstOrNull;

    return RecommendationSections(
      favoriteArtists: effectiveArtists,
      fromYourArtists: fromYourArtists,
      relatedArtists: relatedArtists.take(8).toList(),
      popularTracks: popularTracks,
      discoverMore: discoverMore,
      recentlyPlayed: history,
      featuredTrack: featuredTrack,
    );
  }
}
