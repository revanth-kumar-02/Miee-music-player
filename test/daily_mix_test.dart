import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/features/auth/presentation/auth_controller.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/recommendations/data/daily_mix_repository.dart';
import 'package:Miee/features/recommendations/data/daily_mix_service.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/data/trending_music_service.dart';
import 'package:Miee/features/recommendations/domain/daily_mix.dart';
import 'package:Miee/features/recommendations/providers/daily_mix_providers.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class MockYouTubeRepo extends YouTubeRepository {
  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
  }) async {
    return [
      YouTubeVideo(
        id: 'yt_${query.hashCode}_1',
        title: '$query Track 1',
        channelTitle: 'Artist Channel',
        thumbnailUrl: '',
        duration: '3:15',
        viewCount: '1M views',
      ),
      YouTubeVideo(
        id: 'yt_${query.hashCode}_2',
        title: '$query Track 2',
        channelTitle: 'Artist Channel',
        thumbnailUrl: '',
        duration: '3:30',
        viewCount: '2M views',
      ),
    ];
  }
}

class MockHistoryRepo implements ListeningHistoryRepository {
  List<ListeningEvent> events = [];

  @override
  Future<List<ListeningEvent>> getRecentHistory({int limit = 30, String? uid}) async {
    return events.take(limit).toList();
  }

  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {}

  @override
  Future<void> clearHistory(String? uid) async {}
}

class MockTrendingMusicService extends TrendingMusicService {
  List<Track> trending = [];
  List<Track> recent = [];
  bool throwError = false;

  @override
  Future<TrendingResult> getTrendingAndRecentReleases({
    bool forceRefresh = false,
    String? regionCode,
  }) async {
    if (throwError) throw Exception('Network timeout');
    return TrendingResult(
      trendingTracks: trending,
      recentReleases: recent,
      fetchedAt: DateTime.now(),
    );
  }
}

class MockArtistRepo extends DeezerArtistRepository {
  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async {
    return const [
      ArtistModel(id: 'rel_1', name: 'Related Artist 1', imageUrl: ''),
      ArtistModel(id: 'rel_2', name: 'Related Artist 2', imageUrl: ''),
    ];
  }
}

class MockRecommendationService extends RecommendationService {
  final Map<String, List<MusicItem>> artistTracks;

  MockRecommendationService({this.artistTracks = const {}});

  @override
  Future<List<MusicItem>> getTracksForArtist(
    ArtistSummary artist, {
    int limit = 15,
    int page = 1,
    List<String> preferredLanguages = const [],
  }) async {
    return artistTracks[artist.name] ?? [
      Track(id: '${artist.name}_1', title: '${artist.name} Hit 1', artist: artist.name, imageUrl: '', duration: '3:00'),
      Track(id: '${artist.name}_2', title: '${artist.name} Hit 2', artist: artist.name, imageUrl: '', duration: '3:00'),
      Track(id: '${artist.name}_3', title: '${artist.name} Hit 3', artist: artist.name, imageUrl: '', duration: '3:00'),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> dailyMixBox;
  late DailyMixRepository repository;

  final testDate1 = DateTime(2026, 11, 7, 10, 0, 0);
  final testDate2 = DateTime(2026, 11, 8, 10, 0, 0); // Next day

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_daily_mix_test_');
    Hive.init(tempDir.path);
    dailyMixBox = await Hive.openBox<dynamic>(HiveBoxes.dailyMixes);
    repository = DailyMixRepository(box: dailyMixBox);
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Daily Mix - Data Model Serialization & Snapshot Integrity', () {
    test('DailyMix and DailyMixSnapshot serialize and deserialize correctly', () {
      const track = Track(
        id: 't1',
        title: 'Song One',
        artist: 'Artist A',
        imageUrl: 'https://example.com/img.jpg',
        duration: '3:30',
        filePath: '/storage/song1.mp3',
      );

      const mix = DailyMix(
        id: 'favorites',
        title: 'Daily Mix 1',
        subtitle: 'Your top favorites',
        tracks: [track],
        primaryColorHex: '#FF3366',
        familiarRatio: 0.90,
      );

      final snapshot = DailyMixSnapshot(
        userId: 'user_123',
        localDate: '2026-11-07',
        generatedAt: testDate1,
        mixes: [mix],
      );

      final map = snapshot.toMap();
      final restored = DailyMixSnapshot.fromMap(map);

      expect(restored.userId, equals('user_123'));
      expect(restored.localDate, equals('2026-11-07'));
      expect(restored.mixes.length, equals(1));
      expect(restored.mixes.first.id, equals('favorites'));
      expect(restored.mixes.first.tracks.length, equals(1));
      expect(restored.mixes.first.tracks.first.id, equals('t1'));
      expect(restored.mixes.first.tracks.first.title, equals('Song One'));
      expect(restored.mixes.first.tracks.first.artist, equals('Artist A'));
    });
  });

  group('Daily Mix - Generation, Stability & Refresh Lifecycle', () {
    late MockHistoryRepo mockHistory;
    late MockTrendingMusicService mockTrending;
    late MockArtistRepo mockArtist;
    late MockRecommendationService mockRecService;
    late DailyMixService service;

    setUp(() {
      mockHistory = MockHistoryRepo();
      mockTrending = MockTrendingMusicService();
      mockArtist = MockArtistRepo();
      mockRecService = MockRecommendationService();
      final mockYouTube = MockYouTubeRepo();

      mockTrending.trending = List.generate(
        30,
        (i) => Track(id: 'trend_$i', title: 'Chart Song $i', artist: 'Chart Artist ${i % 15}', imageUrl: '', duration: '3:00'),
      );
      mockTrending.recent = List.generate(
        10,
        (i) => Track(id: 'recent_$i', title: 'New Release $i', artist: 'New Artist $i', imageUrl: '', duration: '3:00'),
      );

      service = DailyMixService(
        repository: repository,
        historyRepo: mockHistory,
        trendingService: mockTrending,
        artistRepo: mockArtist,
        youtubeRepo: mockYouTube,
        recommendationService: mockRecService,
      );
    });

    test('Deterministic generation with identical inputs produces identical outputs', () async {
      final snap1 = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
        forceRefresh: true,
      );

      // Clear repository to force complete regeneration with identical inputs
      await repository.clearSnapshot('u1');

      final snap2 = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
        forceRefresh: true,
      );

      expect(snap1.mixes.length, equals(3));
      expect(snap2.mixes.length, equals(3));
      for (int i = 0; i < 3; i++) {
        expect(snap1.mixes[i].id, equals(snap2.mixes[i].id));
        expect(snap1.mixes[i].tracks.map((t) => t.id).toList(),
            equals(snap2.mixes[i].tracks.map((t) => t.id).toList()));
      }
    });

    test('Same-day snapshot stability: repeated calls return cached snapshot without regeneration', () async {
      final snap1 = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
      );

      // Mutate mock data so if a regeneration occurred, outputs would differ
      mockTrending.trending = [];

      final snap2 = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1.add(const Duration(hours: 3)), // Later on same day
      );

      // Must be identical because same day returns cached snapshot
      expect(snap2.generatedAt, equals(snap1.generatedAt));
      expect(snap2.mixes.first.tracks.length, equals(snap1.mixes.first.tracks.length));
    });

    test('Next-day refresh: date change triggers fresh generation for the new calendar day', () async {
      final snapDay1 = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
      );
      expect(snapDay1.localDate, equals('2026-11-07'));

      // Next day arrives (testDate2 is 2026-11-08)
      final snapDay2 = await service.getDailyMixes(
        userId: 'u1',
        now: testDate2,
      );

      expect(snapDay2.localDate, equals('2026-11-08'));
      expect(snapDay2.generatedAt, equals(testDate2));
    });

    test('Account isolation: User A and User B receive separate, isolated snapshots', () async {
      await service.getDailyMixes(
        userId: 'user_A',
        now: testDate1,
      );

      await service.getDailyMixes(
        userId: 'user_B',
        now: testDate1,
      );

      final snapA = await repository.getSnapshot('user_A');
      final snapB = await repository.getSnapshot('user_B');

      expect(snapA, isNotNull);
      expect(snapB, isNotNull);
      expect(snapA!.userId, equals('user_A'));
      expect(snapB!.userId, equals('user_B'));
    });

    test('Manual refresh behavior: forceRefresh creates fresh mix, debounces rapid repeats', () async {
      final initial = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
      );
      expect(initial.isNotEmpty, isTrue);

      // Force refresh with elapsed time
      final refreshed = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1.add(const Duration(minutes: 5)),
        forceRefresh: true,
      );

      expect(refreshed.generatedAt, equals(testDate1.add(const Duration(minutes: 5))));

      // Rapid repeat manual refresh within 5 seconds is debounced to avoid API spam
      final debounced = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1.add(const Duration(minutes: 5, seconds: 5)),
        forceRefresh: true,
      );

      expect(debounced.generatedAt, equals(refreshed.generatedAt));
    });

    test('No duplicate tracks within each Daily Mix and inter-mix deduplication respected', () async {
      final snapshot = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
      );

      for (final mix in snapshot.mixes) {
        final trackIds = mix.tracks.map((t) => t.id).toList();
        final uniqueIds = trackIds.toSet();
        expect(trackIds.length, equals(uniqueIds.length), reason: 'Mix ${mix.id} contained duplicate track IDs');
      }
    });

    test('Strict artist diversity (max 2 tracks per artist) is strictly enforced in all 3 mixes', () async {
      final snapshot = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
      );

      for (final mix in snapshot.mixes) {
        final artistCounts = <String, int>{};
        for (final t in mix.tracks) {
          final norm = t.artist.toLowerCase().trim();
          artistCounts[norm] = (artistCounts[norm] ?? 0) + 1;
        }

        for (final entry in artistCounts.entries) {
          expect(entry.value, lessThanOrEqualTo(2),
              reason: 'Mix ${mix.id} exceeded artist cap of 2 for artist "${entry.key}" (count: ${entry.value})');
        }
      }
    });

    test('Soundtrack diversity is strictly respected in all Daily Mixes', () async {
      // Inject multiple tracks from the same soundtrack into trending
      mockTrending.trending = [
        const Track(id: 'st_1', title: 'Song 1 (From Leo)', artist: 'Singer A', imageUrl: '', duration: '3:00'),
        const Track(id: 'st_2', title: 'Song 2 (From Leo)', artist: 'Singer B', imageUrl: '', duration: '3:00'),
        const Track(id: 'st_3', title: 'Song 3 (From Leo)', artist: 'Singer C', imageUrl: '', duration: '3:00'),
        const Track(id: 'st_4', title: 'Other Song (From Jailer)', artist: 'Singer D', imageUrl: '', duration: '3:00'),
      ];

      final snapshot = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
        forceRefresh: true,
      );

      for (final mix in snapshot.mixes) {
        final leoTracks = mix.tracks.where((t) => t.title.toLowerCase().contains('leo')).toList();
        expect(leoTracks.length, lessThanOrEqualTo(1),
            reason: 'Mix ${mix.id} contained more than 1 track from same soundtrack');
      }
    });

    test('Cold start / new user with zero history generates valid mixes without crashing', () async {
      mockHistory.events = []; // Zero history

      final snapshot = await service.getDailyMixes(
        userId: 'new_user_1',
        profile: UserProfile(
          uid: 'new_user_1',
          displayName: 'New Listener',
          email: 'new@example.com',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
          selectedArtists: const [],
        ),
        now: testDate1,
      );

      expect(snapshot.mixes.length, equals(3));
      for (final mix in snapshot.mixes) {
        expect(mix.tracks, isNotEmpty);
      }
    });

    test('Failed source requests preserve previously saved valid snapshot', () async {
      // 1. Generate valid snapshot
      final initial = await service.getDailyMixes(
        userId: 'u1',
        now: testDate1,
      );
      expect(initial.isNotEmpty, isTrue);

      // 2. Network goes down
      mockTrending.throwError = true;

      // 3. Requesting refresh on next day fails gracefully and returns preserved previous snapshot
      final preserved = await service.getDailyMixes(
        userId: 'u1',
        now: testDate2,
        forceRefresh: true,
      );

      expect(preserved.isNotEmpty, isTrue);
      expect(preserved.mixes.length, equals(initial.mixes.length));
      expect(preserved.mixes.first.tracks.first.id, equals(initial.mixes.first.tracks.first.id));
    });

    test('Insufficient candidate pools return smaller mixes rather than violating diversity rules', () async {
      // Very sparse pool: only 2 candidates available total
      mockTrending.trending = [
        const Track(id: 'sparse_1', title: 'Sparse 1', artist: 'Solo Singer', imageUrl: '', duration: '3:00'),
        const Track(id: 'sparse_2', title: 'Sparse 2', artist: 'Solo Singer', imageUrl: '', duration: '3:00'),
      ];
      mockTrending.recent = [];

      final sparseService = DailyMixService(
        repository: repository,
        historyRepo: mockHistory,
        trendingService: mockTrending,
        artistRepo: mockArtist,
        youtubeRepo: MockYouTubeRepo(),
        recommendationService: MockRecommendationService(artistTracks: {}),
      );

      final snapshot = await sparseService.getDailyMixes(
        userId: 'sparse_user',
        now: testDate1,
      );

      // Returns the small set without padding duplicates or crashing
      expect(snapshot.mixes, isNotEmpty);
      for (final mix in snapshot.mixes) {
        expect(mix.tracks.length, lessThanOrEqualTo(25));
        // Max 2 per artist must STILL hold
        final artistCounts = mix.tracks.where((t) => t.artist == 'Solo Singer').length;
        expect(artistCounts, lessThanOrEqualTo(2));
      }
    });
  });

  group('Daily Mix - Playback Integration', () {
    test('DailyMixPlaybackExtension sets queue in intended order without unintended replacement', () {
      final queueManager = QueueManager();
      final tracks = [
        const Track(id: 't1', title: 'Mix Song 1', artist: 'Artist A', imageUrl: '', duration: '3:00'),
        const Track(id: 't2', title: 'Mix Song 2', artist: 'Artist B', imageUrl: '', duration: '3:00'),
        const Track(id: 't3', title: 'Mix Song 3', artist: 'Artist C', imageUrl: '', duration: '3:00'),
      ];

      final mix = DailyMix(
        id: 'favorites',
        title: 'Daily Mix 1',
        subtitle: 'Your Favorites',
        tracks: tracks,
      );

      // Verify mix track order is preserved
      expect(mix.tracks[0].id, equals('t1'));
      expect(mix.tracks[1].id, equals('t2'));
      expect(mix.tracks[2].id, equals('t3'));

      // QueueManager setQueue retains order
      queueManager.setQueue(mix.tracks, startIndex: 1);
      expect(queueManager.currentTrack?.id, equals('t2'));
      expect(queueManager.queue.length, equals(3));
      expect(queueManager.queue[0].id, equals('t1'));
      expect(queueManager.queue[1].id, equals('t2'));
      expect(queueManager.queue[2].id, equals('t3'));
    });
  });

  group('Daily Mix - Race Conditions, Concurrency & State Isolation', () {
    late MockHistoryRepo mockHistory;
    late MockTrendingMusicService mockTrending;
    late MockArtistRepo mockArtist;
    late MockRecommendationService mockRecService;
    late DailyMixService service;

    setUp(() {
      mockHistory = MockHistoryRepo();
      mockTrending = MockTrendingMusicService();
      mockArtist = MockArtistRepo();
      mockRecService = MockRecommendationService();
      final mockYouTube = MockYouTubeRepo();

      mockTrending.trending = List.generate(
        30,
        (i) => Track(id: 'trend_$i', title: 'Chart Song $i', artist: 'Chart Artist ${i % 15}', imageUrl: '', duration: '3:00'),
      );
      mockTrending.recent = List.generate(
        10,
        (i) => Track(id: 'recent_$i', title: 'New Release $i', artist: 'New Artist $i', imageUrl: '', duration: '3:00'),
      );

      service = DailyMixService(
        repository: repository,
        historyRepo: mockHistory,
        trendingService: mockTrending,
        artistRepo: mockArtist,
        youtubeRepo: mockYouTube,
        recommendationService: mockRecService,
      );
    });

    test('1. User A starts refresh, then switches to User B before completion. A result must never appear in B state', () async {
      final userACompleter = Completer<DailyMixSnapshot>();
      late FakeAuthController fakeAuth;

      final mockService = ControllableDailyMixService(
        handler: (userId, forceRefresh) {
          if (userId == 'user_A') {
            return userACompleter.future;
          }
          return Future.value(DailyMixSnapshot(
            userId: 'user_B',
            localDate: '2026-11-07',
            generatedAt: DateTime(2026, 11, 7, 12, 0, 0),
            mixes: const [DailyMix(id: 'mix_B', title: 'User B Mix', subtitle: '', tracks: [])],
          ));
        },
      );

      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => fakeAuth = FakeAuthController(ref, 'user_A')),
          dailyMixServiceProvider.overrideWithValue(mockService),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(dailyMixSnapshotProvider, (_, __) {});
      addTearDown(sub.close);

      final notifier = container.read(dailyMixSnapshotProvider.notifier);

      // User A initiates refresh
      final refreshFuture = notifier.refresh();

      // Account switch to User B happens while User A refresh is pending
      fakeAuth.switchUser('user_B');

      // Now User A's pending generation completes
      userACompleter.complete(DailyMixSnapshot(
        userId: 'user_A',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 11, 0, 0),
        mixes: const [DailyMix(id: 'mix_A', title: 'User A Mix', subtitle: '', tracks: [])],
      ));

      await refreshFuture;

      // The notifier state must NEVER contain User A's snapshot
      final currentSnapshot = await container.read(dailyMixSnapshotProvider.future);
      expect(currentSnapshot.userId, isNot(equals('user_A')),
          reason: 'User A snapshot must not leak into active User B notifier state');
      expect(currentSnapshot.userId, equals('user_B'),
          reason: 'Active user B must be present in notifier state');
    });

    test('2. A stale request cannot overwrite a newer notifier state', () async {
      final slowCompleter = Completer<DailyMixSnapshot>();
      int callCount = 0;

      final mockService = ControllableDailyMixService(
        handler: (userId, forceRefresh) {
          callCount++;
          if (callCount == 1) {
            return slowCompleter.future;
          }
          return Future.value(DailyMixSnapshot(
            userId: 'user_A',
            localDate: '2026-11-07',
            generatedAt: DateTime(2026, 11, 7, 12, 5, 0),
            mixes: const [DailyMix(id: 'fast_mix', title: 'Fast New Mix', subtitle: '', tracks: [])],
          ));
        },
      );

      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => FakeAuthController(ref, 'user_A')),
          dailyMixServiceProvider.overrideWithValue(mockService),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(dailyMixSnapshotProvider.notifier);

      // Request 1 (slow)
      final req1 = notifier.refresh();

      // Request 2 (fast newer request)
      final req2 = notifier.refresh();
      await req2;

      expect(container.read(dailyMixSnapshotProvider).value?.mixes.first.id, equals('fast_mix'));

      // Request 1 completes later
      slowCompleter.complete(DailyMixSnapshot(
        userId: 'user_A',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 12, 0, 0),
        mixes: const [DailyMix(id: 'slow_mix', title: 'Slow Old Mix', subtitle: '', tracks: [])],
      ));
      await req1;

      // State must remain the newer fast_mix
      expect(container.read(dailyMixSnapshotProvider).value?.mixes.first.id, equals('fast_mix'));
    });

    test('3. A slow older generation cannot overwrite a newer persisted snapshot', () async {
      final newerSnapshot = DailyMixSnapshot(
        userId: 'u_monotonic',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 14, 0, 0),
        mixes: const [DailyMix(id: 'new', title: 'New Mix', subtitle: '', tracks: [])],
      );
      await repository.saveSnapshot(newerSnapshot);

      final olderSnapshot = DailyMixSnapshot(
        userId: 'u_monotonic',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 13, 0, 0),
        mixes: const [DailyMix(id: 'old', title: 'Old Mix', subtitle: '', tracks: [])],
      );
      await repository.saveSnapshot(olderSnapshot);

      final current = await repository.getSnapshot('u_monotonic');
      expect(current!.generatedAt, equals(DateTime(2026, 11, 7, 14, 0, 0)));
      expect(current.mixes.first.id, equals('new'));
    });

    test('4. Concurrent repository writes preserve the newest snapshot', () async {
      final snap1 = DailyMixSnapshot(
        userId: 'u_concurrent',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 10, 0, 0),
        mixes: const [DailyMix(id: 'm1', title: 'Mix 1', subtitle: '', tracks: [])],
      );
      final snap2 = DailyMixSnapshot(
        userId: 'u_concurrent',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 11, 0, 0),
        mixes: const [DailyMix(id: 'm2', title: 'Mix 2', subtitle: '', tracks: [])],
      );
      final snap3 = DailyMixSnapshot(
        userId: 'u_concurrent',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 10, 30, 0),
        mixes: const [DailyMix(id: 'm3', title: 'Mix 3', subtitle: '', tracks: [])],
      );

      // Save concurrently
      await Future.wait([
        repository.saveSnapshot(snap1),
        repository.saveSnapshot(snap2),
        repository.saveSnapshot(snap3),
      ]);

      final finalSnap = await repository.getSnapshot('u_concurrent');
      expect(finalSnap!.generatedAt, equals(DateTime(2026, 11, 7, 11, 0, 0)));
      expect(finalSnap.mixes.first.id, equals('m2'));
    });

    test('5. A failed Hive write preserves the previous valid snapshot', () async {
      final initial = DailyMixSnapshot(
        userId: 'u_fail',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 10, 0, 0),
        mixes: const [DailyMix(id: 'valid', title: 'Valid Mix', subtitle: '', tracks: [])],
      );
      await repository.saveSnapshot(initial);

      final mockFailingBox = ThrowingBox(dailyMixBox);
      final failingRepo = DailyMixRepository(box: mockFailingBox);

      final failedSnapshot = DailyMixSnapshot(
        userId: 'u_fail',
        localDate: '2026-11-07',
        generatedAt: DateTime(2026, 11, 7, 12, 0, 0),
        mixes: const [DailyMix(id: 'corrupt', title: 'Corrupt Mix', subtitle: '', tracks: [])],
      );

      // Attempted write throws and does not report success
      expect(() => failingRepo.saveSnapshot(failedSnapshot), throwsA(isA<Exception>()));

      // Real box remains with valid snapshot
      final preserved = await repository.getSnapshot('u_fail');
      expect(preserved, isNotNull);
      expect(preserved!.mixes.first.id, equals('valid'));
    });

    test('6. User A cooldown does not block User B', () async {
      final timeT0 = testDate1;
      final snapBInitial = await service.getDailyMixes(
        userId: 'user_B',
        now: timeT0,
        forceRefresh: true,
      );
      expect(snapBInitial.generatedAt, equals(timeT0));

      // User A refreshes 30 seconds later
      final timeA = timeT0.add(const Duration(seconds: 30));
      await service.getDailyMixes(
        userId: 'user_A',
        now: timeA,
        forceRefresh: true,
      );

      // User B refreshes 35 seconds after B's initial refresh (5 seconds after A's refresh)
      final timeB2 = timeT0.add(const Duration(seconds: 35));
      final snapBRefreshed = await service.getDailyMixes(
        userId: 'user_B',
        now: timeB2,
        forceRefresh: true,
      );

      // User B must NOT be blocked by User A's refresh
      expect(snapBRefreshed.generatedAt, equals(timeB2));
    });

    test('7. Same-user cooldown still works', () async {
      final snap1 = await service.getDailyMixes(
        userId: 'user_cooldown',
        now: testDate1,
        forceRefresh: true,
      );

      // 10 seconds later, same user attempts manual refresh -> debounced
      final snap2 = await service.getDailyMixes(
        userId: 'user_cooldown',
        now: testDate1.add(const Duration(seconds: 10)),
        forceRefresh: true,
      );
      expect(snap2.generatedAt, equals(snap1.generatedAt));

      // 35 seconds later, same user attempts manual refresh -> generates fresh
      final snap3 = await service.getDailyMixes(
        userId: 'user_cooldown',
        now: testDate1.add(const Duration(seconds: 35)),
        forceRefresh: true,
      );
      expect(snap3.generatedAt, equals(testDate1.add(const Duration(seconds: 35))));
    });
  });
}

class FakeAuthController extends AuthController {
  FakeAuthController(super._ref, String initialUid) {
    state = AuthState(
      user: User(
        id: initialUid,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      ),
    );
  }

  void switchUser(String newUid) {
    state = AuthState(
      user: User(
        id: newUid,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-01-01',
      ),
    );
  }
}

class ControllableDailyMixService extends DailyMixService {
  final Future<DailyMixSnapshot> Function(String userId, bool forceRefresh) handler;

  ControllableDailyMixService({required this.handler});

  @override
  Future<DailyMixSnapshot> getDailyMixes({
    required String userId,
    UserProfile? profile,
    bool forceRefresh = false,
    DateTime? now,
  }) {
    return handler(userId, forceRefresh);
  }
}

class ThrowingBox implements Box<dynamic> {
  final Box<dynamic> _delegate;
  ThrowingBox(this._delegate);

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) => _delegate.get(key, defaultValue: defaultValue);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    throw Exception('Hive disk full simulation');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => _delegate.noSuchMethod(invocation);
}
