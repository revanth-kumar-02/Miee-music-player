import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../history/data/supabase_listening_history_repository.dart';
import '../../history/domain/listening_history_repository.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../profile/domain/user_profile.dart';
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
/// 1. **Daily Mix 1: Your Favorites** (High familiarity, top affinity artists, loved tracks)
/// 2. **Daily Mix 2: In Rotation** (Balanced mix of familiar rotation and chart tracks)
/// 3. **Daily Mix 3: Fresh Discovery** (Low familiarity, related artists, verified new releases)
///
/// Guarantees:
/// - Reuses Phase 3 [CandidateRanker] and [RecommendationScorer] without formula duplication.
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
            );

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

  /// Internal generator executing candidate collection and multi-tier ranking.
  Future<DailyMixSnapshot> _generateDailyMixSnapshot({
    required String userId,
    required UserProfile? profile,
    required DateTime referenceTime,
    required String localDate,
  }) async {
    // 1. Fetch user taste profile and listening history
    final history = await _historyRepo.getRecentHistory(uid: userId, limit: 50);
    final tasteProfile = (userId.isNotEmpty && _tasteRepo != null)
        ? await _tasteRepo!.getProfile(userId)
        : UserTasteProfile.empty(userId);

    final preferredLanguages = MusicLanguageService.getPreferredLanguages(
      history: history,
      profile: profile,
    );

    // 2. Fetch provider charts for trending popularity scoring
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
      final cleanId = t.id.startsWith('youtube_') ? t.id.replaceFirst('youtube_', '') : t.id;
      chartRanks[cleanId] = rank;
      chartRanks['${t.title.toLowerCase().trim()}|${t.artist.toLowerCase().trim()}'] = rank;
    }

    // 3. User Artists pool (top affinity + profile selected artists)
    final topAffinityArtists = tasteProfile.topArtists(limit: 6);
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

    // 4. Fetch candidate tracks for favorite artists
    final favoriteCandidates = <MusicItem>[];
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
        favoriteCandidates.addAll(tracks);
      } catch (e) {
        debugPrint('[DailyMixService] Candidate fetch error for $artistName: $e');
      }
    }

    // Add recent history tracks as potential favorites
    for (final event in history) {
      favoriteCandidates.add(Track(
        id: event.trackId,
        title: event.title,
        artist: event.artist,
        imageUrl: event.imageUrl ?? '',
        duration: '3:00',
      ));
    }

    const targetMixCount = 25;

    // ── MIX 1: Your Favorites ──────────────────────────────────────────────
    // High familiarity target (0.90), strictly respecting 2 tracks per artist cap
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
      candidates: favoriteCandidates,
      tasteProfile: tasteProfile,
      preferredLanguages: preferredLanguages,
      chartRanks: chartRanks,
      recentHistory: history,
      limit: targetMixCount,
      now: referenceTime,
    );

    final mix1TrackIds = mix1Items.map((t) => t.id).toSet();
    final mix1RecordingKeys = mix1Items.map((t) => RecommendationService.normalizeKey(t.title, t.artist)).toSet();

    final dailyMix1 = DailyMix(
      id: 'favorites',
      title: 'Daily Mix 1',
      subtitle: favoriteArtistNames.isNotEmpty
          ? 'Featuring ${favoriteArtistNames.take(3).join(', ')} and more'
          : 'Your top artists and familiar favorites',
      tracks: mix1Items.map((m) => m is Track ? m : Track(
        id: m.id,
        title: m.title,
        artist: m.artist,
        imageUrl: m.imageUrl,
        duration: m.duration,
        filePath: m.filePath,
      )).toList(),
      primaryColorHex: '#FF3366',
      familiarRatio: 0.90,
      coverImageUrl: mix1Items.firstOrNull?.imageUrl,
    );

    // ── MIX 2: In Rotation ─────────────────────────────────────────────────
    // Balanced familiarity (0.60), combining rotation history with chart tracks
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

    final rotationCandidates = <MusicItem>[
      ...favoriteCandidates,
      ...trendingTracks,
    ];

    final mix2Items = mix2Ranker.rankCandidates(
      candidates: rotationCandidates,
      tasteProfile: tasteProfile,
      preferredLanguages: preferredLanguages,
      chartRanks: chartRanks,
      recentHistory: history,
      limit: targetMixCount,
      excludedTrackIds: mix1TrackIds,
      excludedRecordingKeys: mix1RecordingKeys,
      now: referenceTime,
    );

    final mix2TrackIds = {...mix1TrackIds, ...mix2Items.map((t) => t.id)};
    final mix2RecordingKeys = {...mix1RecordingKeys, ...mix2Items.map((t) => RecommendationService.normalizeKey(t.title, t.artist))};

    final dailyMix2 = DailyMix(
      id: 'rotation',
      title: 'Daily Mix 2',
      subtitle: 'Your active rotation with popular hits',
      tracks: mix2Items.map((m) => m is Track ? m : Track(
        id: m.id,
        title: m.title,
        artist: m.artist,
        imageUrl: m.imageUrl,
        duration: m.duration,
        filePath: m.filePath,
      )).toList(),
      primaryColorHex: '#6C5CE7',
      familiarRatio: 0.60,
      coverImageUrl: mix2Items.firstOrNull?.imageUrl,
    );

    // ── MIX 3: Fresh Discovery ─────────────────────────────────────────────
    // High discovery target (0.20 familiar / 0.80 discovery)
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

    // Fetch related artists outside the user's top favorites
    final relatedArtists = <ArtistModel>[];
    for (final artistName in favoriteArtistNames.take(3)) {
      if (relatedArtists.length >= 6) break;
      try {
        final rel = await _artistRepo.getRelatedArtists(artistName);
        relatedArtists.addAll(rel);
      } catch (_) {}
    }

    final discoveryCandidates = <MusicItem>[];

    // Source A: Tracks from related/discovered artists
    for (final rel in relatedArtists.take(4)) {
      try {
        final relVideos = await _youtubeRepo.search('${rel.name} song');
        for (final v in relVideos.take(3)) {
          discoveryCandidates.add(v.toTrack(reliableArtist: rel.name));
        }
      } catch (_) {}
    }

    // Source B: Verified recent releases & chart depth
    discoveryCandidates.addAll(recentReleases);
    discoveryCandidates.addAll(trendingTracks.skip(10));

    final mix3Items = mix3Ranker.rankCandidates(
      candidates: discoveryCandidates,
      tasteProfile: tasteProfile,
      preferredLanguages: preferredLanguages,
      chartRanks: chartRanks,
      recentHistory: history,
      limit: targetMixCount,
      excludedTrackIds: mix2TrackIds,
      excludedRecordingKeys: mix2RecordingKeys,
      now: referenceTime,
    );

    final dailyMix3 = DailyMix(
      id: 'discovery',
      title: 'Daily Mix 3',
      subtitle: 'New sounds and releases tailored to your taste',
      tracks: mix3Items.map((m) => m is Track ? m : Track(
        id: m.id,
        title: m.title,
        artist: m.artist,
        imageUrl: m.imageUrl,
        duration: m.duration,
        filePath: m.filePath,
      )).toList(),
      primaryColorHex: '#00CEC9',
      familiarRatio: 0.20,
      coverImageUrl: mix3Items.firstOrNull?.imageUrl,
    );

    return DailyMixSnapshot(
      userId: userId,
      localDate: localDate,
      generatedAt: referenceTime,
      mixes: [dailyMix1, dailyMix2, dailyMix3],
    );
  }
}
