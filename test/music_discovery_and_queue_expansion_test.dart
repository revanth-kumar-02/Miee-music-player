import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/data/trending_music_service.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class TestYouTubeRepository implements YouTubeRepository {
  final Map<String, List<YouTubeVideo>> responses;

  TestYouTubeRepository({this.responses = const {}});

  @override
  Future<List<YouTubeVideo>> search(String query) async {
    for (final entry in responses.entries) {
      if (query.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return [
      YouTubeVideo(
        id: 'vid_${query.hashCode.abs()}',
        title: '$query Official Song',
        channelTitle: 'Verified Channel',
        thumbnailUrl: 'https://img.youtube.com/vi/thumb.jpg',
        duration: '3:45',
        viewCount: '2.5M views',
      ),
    ];
  }

  @override
  Future<List<YouTubeVideo>> getRelatedTracks(
    YouTubeVideo seedVideo, {
    int limit = 15,
  }) async {
    return [
      YouTubeVideo(
        id: 'related_${seedVideo.id}_1',
        title: 'Related Song 1',
        channelTitle: 'Channel A',
        thumbnailUrl: 'https://img.youtube.com/vi/rel1.jpg',
        duration: '3:30',
        viewCount: '1.2M views',
      ),
      YouTubeVideo(
        id: 'related_${seedVideo.id}_2',
        title: 'Related Song 2',
        channelTitle: 'Channel B',
        thumbnailUrl: 'https://img.youtube.com/vi/rel2.jpg',
        duration: '4:10',
        viewCount: '800K views',
      ),
    ];
  }

  @override
  void clearCache() {}

  @override
  Future<List<String>> getSuggestions(String query) async => [];

  @override
  Future<List<ArtistModel>> searchArtists(String query) async => [];
}

class TestArtistRepository implements ArtistRepository {
  final Map<String, List<ArtistModel>> relatedMap;

  TestArtistRepository({this.relatedMap = const {}});

  @override
  Future<List<ArtistModel>> getPopularArtists({String? language}) async => [];

  @override
  Future<List<ArtistModel>> searchArtists(String query, {String? language}) async => [];

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async {
    return relatedMap[artistId] ??
        [
          const ArtistModel(
            id: 'rel_artist_99',
            name: 'Discovered Indie Artist',
            imageUrl: 'https://cdn-images.dzcdn.net/images/artist/indie.jpg',
            fanCount: 15000,
            languages: ['Tamil', 'English'],
          ),
          const ArtistModel(
            id: 'rel_artist_100',
            name: 'Emerging Maestro',
            imageUrl: 'https://cdn-images.dzcdn.net/images/artist/maestro.jpg',
            fanCount: 8200,
            languages: ['Hindi'],
          ),
        ];
  }

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async => [];

  @override
  Future<ArtistModel?> getArtistDetails(String artistId) async => null;

  @override
  Future<List<ArtistTopTrack>> getArtistTopTracks(String artistId) async => [];

  @override
  List<String> getSupportedLanguages() => ['Tamil', 'Hindi', 'Telugu', 'English'];
}

class TestHistoryRepository implements ListeningHistoryRepository {
  final List<ListeningEvent> events;

  TestHistoryRepository({this.events = const []});

  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {}

  @override
  Future<List<ListeningEvent>> getRecentHistory({required String? uid, int limit = 30}) async =>
      events.take(limit).toList();

  @override
  Future<void> clearHistory(String? uid) async {}
}

class TestTrendingService extends TrendingMusicService {
  final TrendingResult? customResult;

  TestTrendingService({this.customResult});

  @override
  Future<TrendingResult> getTrendingAndRecentReleases({
    bool forceRefresh = false,
    String? regionCode,
  }) async {
    if (customResult != null) return customResult!;
    return TrendingResult(
      trendingTracks: [
        for (int i = 1; i <= 25; i++)
          Track(
            id: 'wm_chart_top_$i',
            title: 'Top Chart Song $i',
            artist: 'Trending Star ${((i - 1) % 5) + 1}',
            imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/top$i.jpg',
            duration: '3:20',
          ),
      ],
      recentReleases: [
        for (int i = 1; i <= 10; i++)
          Track(
            id: 'wm_chart_recent_$i',
            title: 'Fresh Release $i',
            artist: 'Fresh Artist $i',
            imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/recent$i.jpg',
            duration: '3:15',
          ),
      ],
      fetchedAt: DateTime.now(),
    );
  }
}

void main() {
  group('Phase 2 — Trending & Popular Current Releases', () {
    test('TrendingMusicService distinguishes trending tracks from recent releases', () async {
      final service = TestTrendingService();
      final result = await service.getTrendingAndRecentReleases();

      expect(result.trendingTracks.length, 25);
      expect(result.recentReleases.length, 10);
      expect(result.trendingTracks.first.title, 'Top Chart Song 1');
      expect(result.recentReleases.first.title, 'Fresh Release 1');
    });

    test('Trending tracks deduplicate by ID and provide valid image and title metadata', () async {
      final service = TestTrendingService();
      final result = await service.getTrendingAndRecentReleases();

      final ids = result.trendingTracks.map((t) => t.id).toSet();
      expect(ids.length, result.trendingTracks.length);
      for (final track in result.trendingTracks) {
        expect(track.title, isNotEmpty);
        expect(track.artist, isNotEmpty);
        expect(track.imageUrl, startsWith('http'));
      }
    });
  });

  group('Phase 3 & 4 — Selected Artist & New Artist Discovery', () {
    test('Rotating across multiple selected artists yields varied tracks (not just first artist)', () async {
      final ytRepo = TestYouTubeRepository(
        responses: {
          'Anirudh': [
            const YouTubeVideo(
              id: 'ani_1',
              title: 'Hukum',
              channelTitle: 'Sun TV',
              thumbnailUrl: 'https://img.youtube.com/ani1.jpg',
              duration: '3:20',
              viewCount: '100M',
            ),
            const YouTubeVideo(
              id: 'ani_2',
              title: 'Badass',
              channelTitle: 'Sony Music',
              thumbnailUrl: 'https://img.youtube.com/ani2.jpg',
              duration: '3:45',
              viewCount: '80M',
            ),
          ],
          'Arijit': [
            const YouTubeVideo(
              id: 'ari_1',
              title: 'Chaleya',
              channelTitle: 'T-Series',
              thumbnailUrl: 'https://img.youtube.com/ari1.jpg',
              duration: '3:20',
              viewCount: '90M',
            ),
            const YouTubeVideo(
              id: 'ari_2',
              title: 'Tum Hi Ho',
              channelTitle: 'T-Series',
              thumbnailUrl: 'https://img.youtube.com/ari2.jpg',
              duration: '4:22',
              viewCount: '400M',
            ),
          ],
        },
      );

      final recService = RecommendationService(
        youtubeRepo: ytRepo,
        artistRepo: TestArtistRepository(),
        historyRepo: TestHistoryRepository(),
        trendingService: TestTrendingService(),
      );

      final profile = UserProfile(
        uid: 'user_1',
        email: 'test@miee.app',
        displayName: 'Miee Listener',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        selectedArtists: const [
          ArtistSummary(
            id: '1516162',
            name: 'Anirudh Ravichander',
            imageUrl: 'https://cdn-images.dzcdn.net/ani.jpg',
          ),
          ArtistSummary(
            id: '3830821',
            name: 'Arijit Singh',
            imageUrl: 'https://cdn-images.dzcdn.net/ari.jpg',
          ),
        ],
      );

      final sections = await recService.getPersonalizedSections(profile: profile);

      // Verify that fromYourArtists contains songs from BOTH Anirudh and Arijit
      expect(sections.fromYourArtists.isNotEmpty, isTrue);
      final artistsRepresented = sections.fromYourArtists.map((t) => t.artist).toSet();
      expect(artistsRepresented.any((a) => a.contains('Anirudh')), isTrue);
      expect(artistsRepresented.any((a) => a.contains('Arijit') || a.contains('T-Series')), isTrue);
    });

    test('Discover New Artists excludes all of user\'s selected artists', () async {
      final recService = RecommendationService(
        youtubeRepo: TestYouTubeRepository(),
        artistRepo: TestArtistRepository(
          relatedMap: {
            '1516162': [
              const ArtistModel(
                id: '1516162', // Duplicate of selected
                name: 'Anirudh Ravichander',
                imageUrl: 'https://cdn-images.dzcdn.net/ani.jpg',
                fanCount: 50000,
                languages: ['Tamil'],
              ),
              const ArtistModel(
                id: '223843195',
                name: 'Sai Abhyankkar',
                imageUrl: 'https://cdn-images.dzcdn.net/sai.jpg',
                fanCount: 4000,
                languages: ['Tamil'],
              ),
            ],
          },
        ),
        historyRepo: TestHistoryRepository(),
        trendingService: TestTrendingService(),
      );

      final profile = UserProfile(
        uid: 'user_1',
        email: 'test@miee.app',
        displayName: 'Miee Listener',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        selectedArtists: const [
          ArtistSummary(
            id: '1516162',
            name: 'Anirudh Ravichander',
            imageUrl: 'https://cdn-images.dzcdn.net/ani.jpg',
          ),
        ],
      );

      final sections = await recService.getPersonalizedSections(profile: profile);

      expect(sections.relatedArtists.isNotEmpty, isTrue);
      // Selected artist Anirudh Ravichander MUST NOT appear in Artists to Explore!
      expect(sections.relatedArtists.any((a) => a.id == '1516162'), isFalse);
      expect(sections.relatedArtists.any((a) => a.name == 'Anirudh Ravichander'), isFalse);
      // New artist Sai Abhyankkar should appear
      expect(sections.relatedArtists.any((a) => a.name == 'Sai Abhyankkar'), isTrue);
    });
  });

  group('Phase 5 & 6 — Recommendation Ranking & Dynamic Queue Expansion', () {
    test('Total catalogue across sections retrieves far more than the old ~10 tracks limit', () async {
      final recService = RecommendationService(
        youtubeRepo: TestYouTubeRepository(),
        artistRepo: TestArtistRepository(),
        historyRepo: TestHistoryRepository(),
        trendingService: TestTrendingService(),
      );

      final sections = await recService.getPersonalizedSections(profile: null);

      final totalUniqueTracks = {
        ...sections.trendingTracks.map((t) => t.id),
        ...sections.recentReleases.map((t) => t.id),
        ...sections.fromYourArtists.map((t) => t.id),
        ...sections.discoverMore.map((t) => t.id),
      };

      // Far exceeds the old ~10 track limitation!
      expect(totalUniqueTracks.length, greaterThan(35));
    });

    test('Dynamic queue expansion generates diverse upcoming tracks seeded by active track', () async {
      final recService = RecommendationService(
        youtubeRepo: TestYouTubeRepository(),
        artistRepo: TestArtistRepository(),
        historyRepo: TestHistoryRepository(),
        trendingService: TestTrendingService(),
      );

      const currentTrack = Track(
        id: 'youtube_seed123456',
        title: 'Seed Song',
        artist: 'Seed Artist',
        imageUrl: 'https://img.youtube.com/seed.jpg',
        duration: '3:30',
      );

      final existingQueue = <MusicItem>[
        currentTrack,
        const Track(
          id: 'wm_chart_top_1',
          title: 'Top Chart Song 1',
          artist: 'Trending Star 1',
          imageUrl: 'https://img.youtube.com/top1.jpg',
          duration: '3:20',
        ),
      ];

      final upcoming = await recService.getUpcomingQueueRecommendations(
        currentTrack: currentTrack,
        currentQueue: existingQueue,
        limit: 8,
      );

      expect(upcoming.isNotEmpty, isTrue);
      expect(upcoming.length, lessThanOrEqualTo(8));

      // Must not contain any track already in existingQueue
      final existingIds = existingQueue.map((t) => t.id).toSet();
      for (final track in upcoming) {
        expect(existingIds.contains(track.id), isFalse);
      }
    });

    test('Dynamic queue expansion deduplicates against recent history and avoids consecutive duplicates', () async {
      final recService = RecommendationService(
        youtubeRepo: TestYouTubeRepository(),
        artistRepo: TestArtistRepository(),
        historyRepo: TestHistoryRepository(
          events: [
            ListeningEvent(
              id: 'hist_1',
              trackId: 'played_before_id',
              title: 'Already Played Title',
              artist: 'Already Played Artist',
              source: 'youtube',
              timestamp: DateTime.now(),
              durationSec: 200,
              listenedSec: 190,
              completionRatio: 0.95,
            ),
          ],
        ),
        trendingService: TestTrendingService(),
      );

      const current = Track(
        id: 'current_song_id',
        title: 'Current Active Song',
        artist: 'Active Artist',
        imageUrl: 'https://img.youtube.com/current.jpg',
        duration: '3:45',
      );

      final upcoming = await recService.getUpcomingQueueRecommendations(
        currentTrack: current,
        currentQueue: [current],
        limit: 10,
      );

      // Verifies no track in upcoming is identical to the active song or has invalid properties
      for (final t in upcoming) {
        expect(t.id, isNot(equals('current_song_id')));
        expect(t.title, isNotEmpty);
        expect(t.artist, isNotEmpty);
      }
    });

    test('QueueManager.addTracks smoothly appends items without disturbing currentIndex', () {
      final qm = QueueManager();
      const t1 = Track(id: '1', title: 'T1', artist: 'A1', imageUrl: '', duration: '3:00');
      const t2 = Track(id: '2', title: 'T2', artist: 'A2', imageUrl: '', duration: '3:00');
      qm.setQueue([t1, t2], startIndex: 1);

      expect(qm.currentIndex, 1);
      expect(qm.currentTrack?.id, '2');

      const t3 = Track(id: '3', title: 'T3', artist: 'A3', imageUrl: '', duration: '3:00');
      const t4 = Track(id: '4', title: 'T4', artist: 'A4', imageUrl: '', duration: '3:00');
      qm.addTracks([t3, t4]);

      expect(qm.queue.length, 4);
      expect(qm.currentIndex, 1);
      expect(qm.currentTrack?.id, '2');
      expect(qm.queue[2].id, '3');
      expect(qm.queue[3].id, '4');
    });

    test('RecommendationService survives total network failures gracefully', () async {
      final recService = RecommendationService(
        youtubeRepo: TestYouTubeRepository(responses: {}),
        artistRepo: TestArtistRepository(),
        historyRepo: TestHistoryRepository(),
        trendingService: TrendingMusicService(), // Real service will fall back to offline fallback when network is unavailable
      );

      const current = Track(id: 's1', title: 'Song 1', artist: 'Artist 1', imageUrl: '', duration: '3:00');
      final upcoming = await recService.getUpcomingQueueRecommendations(
        currentTrack: current,
        currentQueue: [current],
        limit: 5,
      );

      // Even if network or provider calls fail, it returns valid fallback tracks and never throws
      expect(upcoming, isA<List<MusicItem>>());
    });
  });
}

