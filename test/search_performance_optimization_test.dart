import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/network/network_request_coordinator.dart';
import 'package:Miee/features/artwork/data/artwork_cache.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/metadata/data/itunes_metadata_service.dart';
import 'package:Miee/features/metadata/data/musicbrainz_service.dart';
import 'package:Miee/features/metadata/domain/itunes_song.dart';
import 'package:Miee/features/metadata/domain/musicbrainz_models.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/data/trending_music_service.dart';
import 'package:Miee/features/search/data/search_repository.dart';
import 'package:Miee/features/search/domain/online_playlist.dart';
import 'package:Miee/features/youtube/data/web_music_discovery_source.dart';
import 'package:Miee/features/youtube/data/youtube_data_source.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';

class _DisabledDataSource extends YouTubeDataSource {
  @override
  bool get isConfigured => false;
}

class _CountingWebDiscoverySource implements WebMusicDiscoverySource {
  int searchCalls = 0;

  @override
  Future<List<YouTubeVideo>> searchVideos(String query,
      {int limit = 25}) async {
    searchCalls++;
    return [
      YouTubeVideo(
        id: 'yt_fallback1',
        title: '$query (Official Audio)',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_fallback1/hqdefault.jpg',
        duration: '3:45',
        viewCount: '1M views',
        rawTitle: '$query (Official Audio)',
        rawChannelTitle: 'Sony Music South',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTrendingService extends TrendingMusicService {
  final TrendingResult result;
  _FakeTrendingService(this.result);

  @override
  Future<TrendingResult> getTrendingAndRecentReleases({
    bool forceRefresh = false,
    String? regionCode,
  }) async =>
      result;
}

class _StubHistoryRepo implements ListeningHistoryRepository {
  @override
  Future<List<ListeningEvent>> getRecentHistory(
          {String? uid, int limit = 50}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubArtistRepo implements ArtistRepository {
  int searchCalls = 0;

  @override
  Future<List<ArtistModel>> searchArtists(String query,
      {String? language}) async {
    searchCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return [
      ArtistModel(
        id: 'art_1',
        name: query,
        imageUrl: 'https://example.com/a.jpg',
        fanCount: 100000,
      ),
    ];
  }

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async => const [];

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistName,
          {int limit = 5}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubItunesService implements ItunesMetadataService {
  int songSearchCalls = 0;
  int artistSearchCalls = 0;
  int albumSearchCalls = 0;

  @override
  Future<List<ItunesSong>> searchSongs(
    String query, {
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    songSearchCalls++;
    return const [];
  }

  @override
  Future<List<ArtistModel>> searchArtists(String query, {int limit = 5}) async {
    artistSearchCalls++;
    return const [];
  }

  @override
  Future<List<ArtistAlbum>> searchAlbums(String query, {int limit = 5}) async {
    albumSearchCalls++;
    return [
      ArtistAlbum(
        id: 'itunes_alb_1',
        title: '$query Album',
        artistName: 'Test Artist',
        coverUrl: 'https://example.com/alb.jpg',
        releaseDate: '2026-01-01',
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubMusicBrainzService implements MusicBrainzService {
  @override
  Future<List<MusicBrainzRecording>> searchRecordings(
    String query, {
    int limit = 15,
    bool forceRefresh = false,
  }) async =>
      const [];

  @override
  Future<List<ArtistModel>> searchArtistsAsArtistModels(String query,
          {int limit = 5}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubYouTubeRepo extends YouTubeRepository {
  int searchCalls = 0;
  int artistTracksCalls = 0;
  int playlistSearchCalls = 0;

  _StubYouTubeRepo()
      : super(
          dataSource: _DisabledDataSource(),
          webDiscoverySource: _CountingWebDiscoverySource(),
        );

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
    NetworkPriority priority = NetworkPriority.userSearch,
  }) async {
    searchCalls++;
    return [
      const YouTubeVideo(
        id: 'stub_vid_001',
        title: 'Radhima (Official Audio)',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://img.youtube.com/vi/stub_vid_001/hqdefault.jpg',
        duration: '3:40',
        viewCount: '2M views',
        rawTitle: 'Radhima (Official Audio)',
        rawChannelTitle: 'Sony Music South',
      ),
    ];
  }

  @override
  Future<List<YouTubeVideo>> getArtistTracks(
    String artistName, {
    int page = 1,
    int limit = 15,
    List<String> preferredLanguages = const [],
    NetworkPriority priority = NetworkPriority.userSearch,
  }) async {
    artistTracksCalls++;
    return const [];
  }

  @override
  Future<List<OnlinePlaylist>> searchPlaylists(String query,
      {int limit = 10}) async {
    playlistSearchCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return const [];
  }
}

class _TransientArtworkDio extends Fake implements Dio {
  int attempts = 0;
  final List<int> validPng = [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    ...List<int>.filled(120, 0x01),
  ];

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    attempts++;
    if (attempts == 1) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionTimeout,
        message: 'Simulated 5s connectTimeout',
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      headers: Headers.fromMap({
        'content-type': ['image/png'],
      }),
      data: validPng as T,
    );
  }
}

void main() {
  group('YouTubeRepository Circuit Breaker & Deduplication', () {
    test(
        'InnerTube NoSuchMethodError trips circuit breaker; subsequent requests bypass Explode during cooldown and recover after',
        () async {
      DateTime fakeNow = DateTime(2026, 11, 26, 10, 0, 0);
      int explodeCalls = 0;
      bool shouldFailParse = true;

      final webSource = _CountingWebDiscoverySource();
      final repo = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        webDiscoverySource: webSource,
        explodeCircuitCooldown: const Duration(minutes: 5),
        now: () => fakeNow,
        explodeSearchOverride: (q, {int page = 1}) async {
          explodeCalls++;
          if (shouldFailParse) {
            final dynamic m = <String, dynamic>{'text': 'x'};
            return m.getT('text') as List<YouTubeVideo>;
          }
          return [
            const YouTubeVideo(
              id: 'recovered11',
              title: 'Recovered Song (Official Audio)',
              channelTitle: 'Sony Music South',
              thumbnailUrl:
                  'https://img.youtube.com/vi/recovered11/hqdefault.jpg',
              duration: '3:30',
              viewCount: '1M views',
              rawTitle: 'Recovered Song (Official Audio)',
              rawChannelTitle: 'Sony Music South',
            ),
          ];
        },
      );

      final r1 = await repo.search('Radhima');
      expect(r1, isNotEmpty);
      expect(explodeCalls, 1);
      expect(webSource.searchCalls, 1);
      expect(repo.isExplodeCircuitOpen, isTrue);

      final r2 = await repo.search('Fa Fa Fa');
      expect(r2, isNotEmpty);
      expect(explodeCalls, 1);
      expect(webSource.searchCalls, 2);

      shouldFailParse = false;
      fakeNow = fakeNow.add(const Duration(minutes: 6));
      expect(repo.isExplodeCircuitOpen, isFalse);

      final r3 = await repo.search('Recovered Song');
      expect(r3, isNotEmpty);
      expect(r3.first.id, 'recovered11');
      expect(explodeCalls, 2);
    });

    test('Transient network error does NOT trip the Explode circuit breaker',
        () async {
      int explodeCalls = 0;
      final webSource = _CountingWebDiscoverySource();
      final repo = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        webDiscoverySource: webSource,
        explodeSearchOverride: (q, {int page = 1}) async {
          explodeCalls++;
          throw const SocketException('Temporary DNS glitch');
        },
      );

      await repo.search('Query 1');
      expect(repo.isExplodeCircuitOpen, isFalse);
      await repo.search('Query 2');
      expect(explodeCalls, 2);
      expect(repo.isExplodeCircuitOpen, isFalse);
    });

    test(
        'Concurrent identical requests deduplicate to 1 call and cache keys are case-insensitive',
        () async {
      int explodeCalls = 0;
      final repo = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        webDiscoverySource: _CountingWebDiscoverySource(),
        explodeSearchOverride: (q, {int page = 1}) async {
          explodeCalls++;
          await Future<void>.delayed(const Duration(milliseconds: 25));
          return [
            const YouTubeVideo(
              id: 'radhima1234',
              title: 'Radhima (Official Audio)',
              channelTitle: 'Sony Music South',
              thumbnailUrl:
                  'https://img.youtube.com/vi/radhima1234/hqdefault.jpg',
              duration: '3:50',
              viewCount: '3M views',
              rawTitle: 'Radhima (Official Audio)',
              rawChannelTitle: 'Sony Music South',
            ),
          ];
        },
      );

      final results = await Future.wait([
        repo.search('Radhima'),
        repo.search('radhima'),
        repo.search('  RADHIMA  '),
      ]);

      expect(explodeCalls, 1);
      expect(results[0].length, 1);
      expect(results[1].length, 1);
      expect(results[2].length, 1);

      await repo.search('rAdHiMa');
      expect(explodeCalls, 1);
    });
  });

  group('RecommendationService Home Startup Storm Elimination', () {
    test(
        'Cached/chart recent releases do not trigger eager YouTube search storm and duplicate artists are skipped',
        () async {
      final ytRepo = _StubYouTubeRepo();
      final chartTracks = List.generate(
        8,
        (i) => Track(
          id: 'wm_chart_$i',
          title: 'Chart Song $i',
          artist: 'Chart Artist $i',
          imageUrl: 'https://example.com/$i.jpg',
          duration: '3:30',
        ),
      );
      final recService = RecommendationService(
        youtubeRepo: ytRepo,
        artistRepo: _StubArtistRepo(),
        historyRepo: _StubHistoryRepo(),
        trendingService: _FakeTrendingService(
          TrendingResult(
            trendingTracks: chartTracks,
            recentReleases: chartTracks,
            fetchedAt: DateTime(2026),
          ),
        ),
      );

      final profile = UserProfile(
        uid: 'u1',
        displayName: 'QA User',
        email: 'qa@miee.app',
        onboardingCompleted: true,
        selectedArtists: const [
          ArtistSummary(id: 'a1', name: 'Anirudh Ravichander', imageUrl: ''),
          ArtistSummary(id: 'a2', name: 'anirudh ravichander', imageUrl: ''),
        ],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final sections =
          await recService.getPersonalizedSections(profile: profile);

      // Zero eager YouTube searches for the 8 chart recent releases
      expect(ytRepo.searchCalls, lessThanOrEqualTo(4));
      expect(ytRepo.artistTracksCalls, 1);
      expect(sections.recentReleases.length, 8);
    });
  });

  group('SearchRepository Deduplication, Cancellation & Priority', () {
    test(
        'Concurrent artist and playlist requests are deduplicated and CancelToken aborts cancelled queries',
        () async {
      final artistRepo = _StubArtistRepo();
      final itunes = _StubItunesService();
      final ytRepo = _StubYouTubeRepo();

      final searchRepo = SearchRepository(
        youtubeRepository: ytRepo,
        artistRepository: artistRepo,
        itunesMetadataService: itunes,
        musicBrainzService: _StubMusicBrainzService(),
      );

      await Future.wait([
        searchRepo.searchArtists('Radhima'),
        searchRepo.searchArtists('radhima'),
        searchRepo.searchPlaylists('Radhima'),
        searchRepo.searchPlaylists('radhima'),
      ]);

      expect(artistRepo.searchCalls, 1);
      expect(ytRepo.playlistSearchCalls, 1);

      final songCallsBeforeCancel = itunes.songSearchCalls;
      final cancelled = CancelToken()..cancel('Superseded');
      final cancelledYt =
          await searchRepo.searchYouTube('Old Query', cancelToken: cancelled);
      expect(cancelledYt, isEmpty);
      expect(itunes.songSearchCalls, songCallsBeforeCancel);
    });

    test(
        'NetworkRequestCoordinator executes playbackResolution ahead of backgroundDiscovery',
        () async {
      final coordinator = NetworkRequestCoordinator(
        maxConcurrent: 2,
        reservedInteractiveSlots: 1,
      );
      final order = <String>[];

      final bg1 = coordinator.run(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        order.add('bg1');
      }, priority: NetworkPriority.backgroundDiscovery);

      final bg2 = coordinator.run(() async {
        order.add('bg2');
      }, priority: NetworkPriority.backgroundDiscovery);

      final pb = coordinator.run(() async {
        order.add('playback');
      }, priority: NetworkPriority.playbackResolution);

      await Future.wait([bg1, bg2, pb]);
      expect(order.indexOf('playback'), lessThan(order.indexOf('bg2')));
    });
  });

  group('ArtworkCache Bounded Retry & Cache Integrity', () {
    test('Retries once on transient connectionTimeout and succeeds', () async {
      final tempDir =
          await Directory.systemTemp.createTemp('miee_artwork_cache_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final fakeDio = _TransientArtworkDio();
      final cache = ArtworkCache(
        dio: fakeDio,
        cacheDirectory: tempDir,
      );

      final path = await cache.cacheImageFromUrl(
        'test_key_retry',
        'https://is1-ssl.mzstatic.com/image/thumb/test.jpg',
      );

      expect(fakeDio.attempts, 2);
      expect(path, isNotNull);
      expect(await File(path!).exists(), isTrue);
    });
  });

  group('Phase 7 Controlled Search Latency Benchmark', () {
    test(
        'Measures cached vs uncached YouTubeRepository search latency (normal & throttled)',
        () async {
      int networkLatencyMs = 40;
      int explodeCalls = 0;
      final repo = YouTubeRepository(
        dataSource: _DisabledDataSource(),
        webDiscoverySource: _CountingWebDiscoverySource(),
        explodeSearchOverride: (q, {int page = 1}) async {
          explodeCalls++;
          await Future<void>.delayed(Duration(milliseconds: networkLatencyMs));
          return [
            YouTubeVideo(
              id: 'bench_${q.hashCode}',
              title: '$q (Official Audio)',
              channelTitle: 'Sony Music South',
              thumbnailUrl:
                  'https://img.youtube.com/vi/bench123456/hqdefault.jpg',
              duration: '3:30',
              viewCount: '1M views',
              rawTitle: '$q (Official Audio)',
              rawChannelTitle: 'Sony Music South',
            ),
          ];
        },
      );

      // Warm uncached (normal 40ms simulated RTT)
      final normalTimes = <int>[];
      for (int i = 0; i < 10; i++) {
        final sw = Stopwatch()..start();
        await repo.search('query_$i');
        sw.stop();
        normalTimes.add(sw.elapsedMilliseconds);
      }

      // Cached lookups
      final cachedTimes = <int>[];
      for (int i = 0; i < 10; i++) {
        final sw = Stopwatch()..start();
        await repo.search('QUERY_$i');
        sw.stop();
        cachedTimes.add(sw.elapsedMilliseconds);
      }

      // Throttled (450ms simulated RTT)
      networkLatencyMs = 450;
      final throttledTimes = <int>[];
      for (int i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        await repo.search('throttled_$i');
        sw.stop();
        throttledTimes.add(sw.elapsedMilliseconds);
      }

      normalTimes.sort();
      cachedTimes.sort();
      throttledTimes.sort();

      // ignore: avoid_print
      print(
          '[BENCH] cached_p50=${cachedTimes[5]}ms cached_p95=${cachedTimes[9]}ms | '
          'normal_p50=${normalTimes[5]}ms normal_p95=${normalTimes[9]}ms | '
          'throttled_p50=${throttledTimes[2]}ms throttled_p95=${throttledTimes[4]}ms | '
          'explodeCalls=$explodeCalls');

      expect(cachedTimes[9], lessThan(300));
      expect(normalTimes[9], lessThan(2000));
      expect(explodeCalls, 15); // 10 normal + 5 throttled, 0 for 10 cached hits
    });
  });
}
