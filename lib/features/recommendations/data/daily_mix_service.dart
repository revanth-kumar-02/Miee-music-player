import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../history/data/supabase_listening_history_repository.dart';
import '../../history/domain/listening_history_repository.dart';
import '../../library/data/favorites_repository.dart';
import '../../library/data/most_played_repository.dart';
import '../../library/data/recently_played_repository.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../profile/domain/user_profile.dart';
import '../../search/domain/search_deduplicator.dart';
import '../../youtube/data/youtube_repository.dart';
import '../domain/candidate_ranker.dart';
import '../domain/daily_mix.dart';
import '../domain/music_language_service.dart';
import '../domain/recommendation_diversity_filter.dart';
import '../domain/recommendation_scorer.dart';
import '../domain/user_taste_profile.dart';
import 'daily_mix_repository.dart';
import 'recommendation_service.dart';
import 'taste_profile_repository.dart';
import 'trending_music_service.dart';

/// Service generating and maintaining deterministic personalized Daily Mixes.
///
/// Produces 3 curated mixes with distinct listening characters:
/// 1. **Daily Mix 1: Your Favorites** (High familiarity, top affinity artists, loved & most-played tracks)
/// 2. **Daily Mix 2: In Rotation** (Balanced mix of familiar rotation and chart tracks)
/// 3. **Daily Mix 3: Fresh Discovery** (Low familiarity, related artists, verified new releases)
///
/// Guarantees:
/// - Truly Unique: Zero track or recording overlap between Daily Mix 1, 2, and 3 on the same day.
/// - Canonical Deduplication: Normalizes track IDs and computes canonical recording keys via [SearchDeduplicator].
/// - Daily Rotation: Tracks used in recent days are rotated out to prevent consecutive-day repetition.
/// - Small Library Resilient: Gracefully adapts to small libraries without starving mixes or creating fake tracks.
/// - Deterministic: Identical inputs produce identical outputs.
/// - Stable: Persisted per local calendar day ('YYYY-MM-DD'); does not regenerate on screen rebuilds.
/// - Isolated: Keyed strictly to authenticated user ID; never leaks cross-account data.
/// - Resilient: Failed refreshes preserve the previous valid snapshot.
class DailyMixService {
  final CandidateRanker candidateRanker;
  final RecommendationScorer _scorer;
  final DailyMixRepository _repository;
  final TasteProfileRepository? _tasteRepo;
  final ListeningHistoryRepository _historyRepo;
  final TrendingMusicService _trendingService;
  final ArtistRepository _artistRepo;
  final YouTubeRepository _youtubeRepo;
  final RecommendationService _recommendationService;
  final FavoritesRepository? _favoritesRepo;
  final MostPlayedRepository? _mostPlayedRepo;
  final RecentlyPlayedRepository? _recentlyPlayedRepo;
  final List<MusicItem> Function()? _getLocalSongs;

  /// Cooldown between manual forced refreshes to prevent API spam, tracked per user.
  static const Duration minManualRefreshInterval = Duration(seconds: 30);
  final Map<String, DateTime> _lastManualRefreshByUser = {};

  DailyMixService({
    CandidateRanker? candidateRanker,
    RecommendationScorer? scorer,
    DailyMixRepository? repository,
    TasteProfileRepository? tasteRepo,
    ListeningHistoryRepository? historyRepo,
    TrendingMusicService? trendingService,
    ArtistRepository? artistRepo,
    YouTubeRepository? youtubeRepo,
    RecommendationService? recommendationService,
    FavoritesRepository? favoritesRepo,
    MostPlayedRepository? mostPlayedRepo,
    RecentlyPlayedRepository? recentlyPlayedRepo,
    List<MusicItem> Function()? getLocalSongs,
  })  : candidateRanker = candidateRanker ?? const CandidateRanker(),
        _scorer = scorer ?? candidateRanker?.scorer ?? const RecommendationScorer(),
        _repository = repository ?? DailyMixRepository(),
        _tasteRepo = tasteRepo,
        _historyRepo = historyRepo ?? SupabaseListeningHistoryRepository(),
        _trendingService = trendingService ?? TrendingMusicService(),
        _artistRepo = artistRepo ?? DeezerArtistRepository(),
        _youtubeRepo = youtubeRepo ?? YouTubeRepository(),
        _recommendationService = recommendationService ??
            RecommendationService(
              youtubeRepo: youtubeRepo,
              artistRepo: artistRepo,
              historyRepo: historyRepo,
              trendingService: trendingService,
              tasteRepo: tasteRepo,
            ),
        _favoritesRepo = favoritesRepo,
        _mostPlayedRepo = mostPlayedRepo,
        _recentlyPlayedRepo = recentlyPlayedRepo,
        _getLocalSongs = getLocalSongs;

  /// Retrieves the Daily Mix snapshot for [userId].
  ///
  /// If a valid snapshot exists for today's local date, returns it immediately without regenerating.
  /// If [forceRefresh] is true or the date has changed, re-generates and persists a fresh snapshot.
  /// If generation fails, returns the previously saved snapshot safely.
  Future<DailyMixSnapshot> getDailyMixes({
    required String userId,
    UserProfile? profile,
    bool forceRefresh = false,
    DateTime? now,
  }) async {
    final referenceTime = now ?? DateTime.now();
    final todayLocalDate = DailyMixSnapshot.formatLocalDate(referenceTime);
    final cleanUid = userId.trim().isEmpty ? 'guest' : userId.trim();

    // 1. Check existing cached snapshot in Hive
    final cachedSnapshot = await _repository.getSnapshot(userId);

    // 2. Return cached snapshot if still valid for today and not forcing refresh
    if (!forceRefresh && _repository.isSnapshotValidForDate(cachedSnapshot, todayLocalDate)) {
      debugPrint('[DailyMixService] Using existing stable Daily Mix snapshot for $todayLocalDate (User: $userId)');
      return cachedSnapshot!;
    }

    // 3. Debounce manual forced refresh per user
    final lastRefresh = _lastManualRefreshByUser[cleanUid];
    if (forceRefresh && lastRefresh != null) {
      final elapsed = referenceTime.difference(lastRefresh);
      if (elapsed < minManualRefreshInterval && cachedSnapshot != null && cachedSnapshot.isNotEmpty) {
        debugPrint('[DailyMixService] Manual refresh debounced for $cleanUid (${elapsed.inSeconds}s < ${minManualRefreshInterval.inSeconds}s). Returning existing snapshot.');
        return cachedSnapshot;
      }
    }

    // 4. Generate fresh Daily Mixes
    try {
      if (forceRefresh) {
        _lastManualRefreshByUser[cleanUid] = referenceTime;
        _pruneOldCooldowns(referenceTime);
      }

      final snapshot = await _generateDailyMixSnapshot(
        userId: userId,
        profile: profile,
        referenceTime: referenceTime,
        localDate: todayLocalDate,
      );

      // Persist snapshot to Hive
      await _repository.saveSnapshot(snapshot);
      debugPrint('[DailyMixService] Successfully generated and persisted Daily Mixes for $todayLocalDate');
      return snapshot;
    } catch (e, st) {
      debugPrint('[DailyMixService] Failed to generate Daily Mixes: $e\n$st');
      // On failure, preserve previous snapshot if valid rather than destroying user data
      if (cachedSnapshot != null && cachedSnapshot.isNotEmpty) {
        debugPrint('[DailyMixService] Preserving previously saved Daily Mix snapshot following generation error.');
        return cachedSnapshot;
      }
      return DailyMixSnapshot.empty(userId);
    }
  }

  /// Prunes stale cooldown timestamps older than 10 minutes to bound memory usage.
  void _pruneOldCooldowns(DateTime referenceTime) {
    if (_lastManualRefreshByUser.length > 50) {
      _lastManualRefreshByUser.removeWhere(
        (_, time) => referenceTime.difference(time) > const Duration(minutes: 10),
      );
    }
  }

  static String _normalizeTrackId(String id) {
    if (id.startsWith('youtube_')) return id.replaceFirst('youtube_', '');
    if (id.startsWith('wm_')) return id.replaceFirst('wm_', '');
    return id.trim();
  }

  /// Partitions [candidates] into fresh tracks (not used in recent daily mix generations)
  /// and previously used tracks. If fresh tracks meet [minFreshCount], prioritizes
  /// fresh tracks to prevent consecutive-day repetition while allowing graceful fallback.
  List<MusicItem> _rotateCandidates(
    List<MusicItem> candidates,
    Set<String> recentDayKeys, {
    int minFreshCount = 10,
  }) {
    if (recentDayKeys.isEmpty) return candidates;

    final fresh = <MusicItem>[];
    final recent = <MusicItem>[];
    final seen = <String>{};

    for (final t in candidates) {
      final id = _normalizeTrackId(t.id);
      final key = SearchDeduplicator.computeRecordingKey(t);
      if (seen.contains(id) || seen.contains(key)) continue;
      seen.add(id);
      seen.add(key);

      if (recentDayKeys.contains(id) || recentDayKeys.contains(key)) {
        recent.add(t);
      } else {
        fresh.add(t);
      }
    }

    if (fresh.length >= minFreshCount) {
      return [...fresh, ...recent];
    }
    return [...fresh, ...recent];
  }

  /// Internal generator executing candidate collection, daily rotation, and multi-tier ranking.
  Future<DailyMixSnapshot> _generateDailyMixSnapshot({
    required String userId,
    required UserProfile? profile,
    required DateTime referenceTime,
    required String localDate,
  }) async {
    // 1. Fetch user taste profile, listening history, and user preferences
    final history = await _historyRepo.getRecentHistory(uid: userId, limit: 100);
    final tasteProfile = (userId.isNotEmpty && _tasteRepo != null)
        ? await _tasteRepo!.getProfile(userId)
        : UserTasteProfile.empty(userId);

    final preferredLanguages = MusicLanguageService.getPreferredLanguages(
      history: history,
      profile: profile,
    );

    // 2. Fetch user library sources (Liked songs, Most played, Recently played, Local library)
    final likedSongs = _favoritesRepo?.getFavorites() ?? const [];
    final mostPlayedEntries = _mostPlayedRepo?.getMostPlayed(limit: 50) ?? const [];
    final mostPlayedIds = mostPlayedEntries.map((e) => _normalizeTrackId(e.key)).toSet();
    final recentlyPlayed = _recentlyPlayedRepo?.getRecentTracks() ?? const [];
    final localSongs = _getLocalSongs?.call() ?? const [];

    // 3. Fetch provider charts for trending popularity scoring
    List<Track> trendingTracks = [];
    List<Track> recentReleases = [];
    try {
      final chartResult = await _trendingService.getTrendingAndRecentReleases();
      trendingTracks = chartResult.trendingTracks;
      recentReleases = chartResult.recentReleases;
    } catch (e) {
      debugPrint('[DailyMixService] Warning: Chart fetch error: $e');
    }

    // Build chart rank map
    final chartRanks = <String, int>{};
    for (int i = 0; i < trendingTracks.length; i++) {
      final rank = i + 1;
      final t = trendingTracks[i];
      chartRanks[t.id] = rank;
      final cleanId = _normalizeTrackId(t.id);
      chartRanks[cleanId] = rank;
      chartRanks['${t.title.toLowerCase().trim()}|${t.artist.toLowerCase().trim()}'] = rank;
    }

    // 4. User Artists pool (top affinity + profile selected artists)
    final topAffinityArtists = tasteProfile.topArtists(limit: 8);
    final profileArtists = (profile?.selectedArtists ?? const [])
        .map((a) => a.name)
        .where((n) => n.trim().isNotEmpty)
        .toList();

    final favoriteArtistNames = <String>{
      ...topAffinityArtists,
      ...profileArtists,
    }.take(8).toList();

    // Fallback to static curated artists if cold start
    if (favoriteArtistNames.isEmpty) {
      favoriteArtistNames.addAll(
        DeezerArtistRepository.staticCuratedArtists
            .take(6)
            .map((a) => a.name),
      );
    }

    // 5. Query recent daily mix history for cross-day rotation (consecutive-day avoidance)
    final recentDayKeys = await _repository.getRecentlyUsedRecordingKeys(
      userId,
      days: 2,
      excludeDate: localDate,
    );

    // 6. Fetch candidate tracks for favorite artists
    final onlineFavoriteCandidates = <MusicItem>[];
    for (final artistName in favoriteArtistNames.take(5)) {
      try {
        final artistSummary = ArtistSummary(
          id: artistName.toLowerCase().replaceAll(' ', '_'),
          name: artistName,
          imageUrl: '',
        );
        final tracks = await _recommendationService.getTracksForArtist(
          artistSummary,
          limit: 8,
          preferredLanguages: preferredLanguages,
        );
        onlineFavoriteCandidates.addAll(tracks);
      } catch (e) {
        debugPrint('[DailyMixService] Candidate fetch error for $artistName: $e');
      }
    }

    const targetMixCount = 25;
    final assignedTrackIds = <String>{};
    final assignedRecordingKeys = <String>{};

    // ── MIX 1: Your Favorites ──────────────────────────────────────────────
    // High familiarity target (0.90), strictly respecting 2 tracks per artist cap.
    // Built from: Liked songs, Most played, History, and Favorite artist catalog.
    final pool1 = <MusicItem>[];

    // Priority 1A: Liked Songs
    pool1.addAll(likedSongs);

    // Priority 1B: Most Played tracks (from history or local library)
    for (final event in history) {
      final normId = _normalizeTrackId(event.trackId);
      if (mostPlayedIds.contains(normId)) {
        pool1.add(Track(
          id: event.trackId,
          title: event.title,
          artist: event.artist,
          imageUrl: event.imageUrl ?? '',
          duration: '3:00',
        ));
      }
    }

    // Priority 1C: History tracks
    for (final event in history) {
      pool1.add(Track(
        id: event.trackId,
        title: event.title,
        artist: event.artist,
        imageUrl: event.imageUrl ?? '',
        duration: '3:00',
      ));
    }

    // Priority 1D: Favorite artists online tracks
    pool1.addAll(onlineFavoriteCandidates);

    // Priority 1E: Local songs matching favorite artists
    final favoriteArtistsLower = favoriteArtistNames.map((a) => a.toLowerCase().trim()).toSet();
    for (final local in localSongs) {
      if (favoriteArtistsLower.contains(local.artist.toLowerCase().trim())) {
        pool1.add(local);
      }
    }

    // Apply cross-day rotation to avoid yesterday's repetition
    final rotatedPool1 = _rotateCandidates(pool1, recentDayKeys);

    final mix1Ranker = CandidateRanker(
      scorer: _scorer,
      diversityFilter: const RecommendationDiversityFilter(
        config: DiversityConfig(
          maxTracksPerArtist: 2,
          targetFamiliarRatio: 0.90,
          familiarAffinityThreshold: 0.50,
        ),
      ),
    );

    final mix1Items = mix1Ranker.rankCandidates(
      candidates: rotatedPool1,
      tasteProfile: tasteProfile,
      preferredLanguages: preferredLanguages,
      chartRanks: chartRanks,
      recentHistory: history,
      limit: targetMixCount,
      excludedTrackIds: assignedTrackIds,
      excludedRecordingKeys: assignedRecordingKeys,
      now: referenceTime,
    );

    final finalMix1Tracks = <Track>[];
    for (final m in mix1Items) {
      final t = m is Track ? m : Track(
        id: m.id,
        title: m.title,
        artist: m.artist,
        imageUrl: m.imageUrl,
        duration: m.duration,
        filePath: m.filePath,
      );
      final id = _normalizeTrackId(t.id);
      final key = SearchDeduplicator.computeRecordingKey(t);
      if (assignedTrackIds.contains(id) || assignedRecordingKeys.contains(key)) continue;
      assignedTrackIds.add(id);
      assignedRecordingKeys.add(key);
      finalMix1Tracks.add(t);
    }

    final dailyMix1 = DailyMix(
      id: 'favorites',
      title: 'Daily Mix 1',
      subtitle: favoriteArtistNames.isNotEmpty
          ? 'Featuring ${favoriteArtistNames.take(3).join(', ')} and more'
          : 'Your top artists and familiar favorites',
      tracks: finalMix1Tracks,
      primaryColorHex: '#FF3366',
      familiarRatio: 0.90,
      coverImageUrl: finalMix1Tracks.firstOrNull?.imageUrl,
    );

    // ── MIX 2: In Rotation ─────────────────────────────────────────────────
    // Balanced familiarity (0.60), combining rotation history with chart tracks.
    // Must contain DISTINCT tracks: zero overlap with Daily Mix 1!
    final pool2 = <MusicItem>[];

    // Priority 2A: Active rotation & recently played
    pool2.addAll(recentlyPlayed);
    pool2.addAll(onlineFavoriteCandidates);
    pool2.addAll(localSongs);

    // Priority 2B: Trending chart tracks in preferred languages
    pool2.addAll(trendingTracks);

    // Filter out anything assigned to Mix 1 before candidate ranking
    final unassignedPool2 = pool2.where((t) {
      final id = _normalizeTrackId(t.id);
      final key = SearchDeduplicator.computeRecordingKey(t);
      return !assignedTrackIds.contains(id) && !assignedRecordingKeys.contains(key);
    }).toList();

    // Apply cross-day rotation
    final rotatedPool2 = _rotateCandidates(unassignedPool2, recentDayKeys);

    final mix2Ranker = CandidateRanker(
      scorer: _scorer,
      diversityFilter: const RecommendationDiversityFilter(
        config: DiversityConfig(
          maxTracksPerArtist: 2,
          targetFamiliarRatio: 0.60,
          familiarAffinityThreshold: 0.52,
        ),
      ),
    );

    final mix2Items = mix2Ranker.rankCandidates(
      candidates: rotatedPool2,
      tasteProfile: tasteProfile,
      preferredLanguages: preferredLanguages,
      chartRanks: chartRanks,
      recentHistory: history,
      limit: targetMixCount,
      excludedTrackIds: assignedTrackIds,
      excludedRecordingKeys: assignedRecordingKeys,
      now: referenceTime,
    );

    final finalMix2Tracks = <Track>[];
    for (final m in mix2Items) {
      final t = m is Track ? m : Track(
        id: m.id,
        title: m.title,
        artist: m.artist,
        imageUrl: m.imageUrl,
        duration: m.duration,
        filePath: m.filePath,
      );
      final id = _normalizeTrackId(t.id);
      final key = SearchDeduplicator.computeRecordingKey(t);
      if (assignedTrackIds.contains(id) || assignedRecordingKeys.contains(key)) continue;
      assignedTrackIds.add(id);
      assignedRecordingKeys.add(key);
      finalMix2Tracks.add(t);
    }

    final dailyMix2 = DailyMix(
      id: 'rotation',
      title: 'Daily Mix 2',
      subtitle: 'Your active rotation with popular hits',
      tracks: finalMix2Tracks,
      primaryColorHex: '#6C5CE7',
      familiarRatio: 0.60,
      coverImageUrl: finalMix2Tracks.firstOrNull?.imageUrl,
    );

    // ── MIX 3: Fresh Discovery ─────────────────────────────────────────────
    // High discovery target (0.20 familiar / 0.80 discovery).
    // Must contain DISTINCT tracks: zero overlap with Daily Mix 1 and Daily Mix 2!
    final relatedArtists = <ArtistModel>[];
    for (final artistName in favoriteArtistNames.take(3)) {
      if (relatedArtists.length >= 6) break;
      try {
        final rel = await _artistRepo.getRelatedArtists(artistName);
        relatedArtists.addAll(rel);
      } catch (_) {}
    }

    final pool3 = <MusicItem>[];

    // Source 3A: Tracks from related/discovered artists
    for (final rel in relatedArtists.take(4)) {
      try {
        final relVideos = await _youtubeRepo.search('${rel.name} song');
        for (final v in relVideos.take(3)) {
          pool3.add(v.toTrack(reliableArtist: rel.name));
        }
      } catch (_) {}
    }

    // Source 3B: Verified recent releases & chart depth
    pool3.addAll(recentReleases);
    pool3.addAll(trendingTracks.skip(10));

    // Filter out anything assigned to Mix 1 or Mix 2
    final unassignedPool3 = pool3.where((t) {
      final id = _normalizeTrackId(t.id);
      final key = SearchDeduplicator.computeRecordingKey(t);
      return !assignedTrackIds.contains(id) && !assignedRecordingKeys.contains(key);
    }).toList();

    // Apply cross-day rotation
    final rotatedPool3 = _rotateCandidates(unassignedPool3, recentDayKeys);

    final mix3Ranker = CandidateRanker(
      scorer: _scorer,
      diversityFilter: const RecommendationDiversityFilter(
        config: DiversityConfig(
          maxTracksPerArtist: 2,
          targetFamiliarRatio: 0.20,
          familiarAffinityThreshold: 0.52,
        ),
      ),
    );

    final mix3Items = mix3Ranker.rankCandidates(
      candidates: rotatedPool3,
      tasteProfile: tasteProfile,
      preferredLanguages: preferredLanguages,
      chartRanks: chartRanks,
      recentHistory: history,
      limit: targetMixCount,
      excludedTrackIds: assignedTrackIds,
      excludedRecordingKeys: assignedRecordingKeys,
      now: referenceTime,
    );

    final finalMix3Tracks = <Track>[];
    for (final m in mix3Items) {
      final t = m is Track ? m : Track(
        id: m.id,
        title: m.title,
        artist: m.artist,
        imageUrl: m.imageUrl,
        duration: m.duration,
        filePath: m.filePath,
      );
      final id = _normalizeTrackId(t.id);
      final key = SearchDeduplicator.computeRecordingKey(t);
      if (assignedTrackIds.contains(id) || assignedRecordingKeys.contains(key)) continue;
      assignedTrackIds.add(id);
      assignedRecordingKeys.add(key);
      finalMix3Tracks.add(t);
    }

    final dailyMix3 = DailyMix(
      id: 'discovery',
      title: 'Daily Mix 3',
      subtitle: 'New sounds and releases tailored to your taste',
      tracks: finalMix3Tracks,
      primaryColorHex: '#00CEC9',
      familiarRatio: 0.20,
      coverImageUrl: finalMix3Tracks.firstOrNull?.imageUrl,
    );

    // 7. Record today's generated canonical keys in the rolling rotation ledger
    await _repository.recordGenerationHistory(
      userId,
      localDate,
      assignedRecordingKeys.toList(),
    );

    return DailyMixSnapshot(
      userId: userId,
      localDate: localDate,
      generatedAt: referenceTime,
      mixes: [dailyMix1, dailyMix2, dailyMix3],
    );
  }
}
