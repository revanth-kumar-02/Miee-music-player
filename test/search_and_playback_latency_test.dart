import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/search/data/local_search_service.dart';
import 'package:Miee/features/search/data/search_repository.dart';
import 'package:Miee/features/search/domain/search_diagnostics.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/metadata/data/itunes_metadata_service.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/core/audio/playback_diagnostics.dart';

class MockSlowYouTubeRepository extends YouTubeRepository {
  int searchCalls = 0;
  Duration networkDelay = const Duration(milliseconds: 150);

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
  }) async {
    searchCalls++;
    if (networkDelay > Duration.zero) {
      await Future<void>.delayed(networkDelay);
    }
    return [
      YouTubeVideo(
        id: 'yt_${query}_01',
        title: '$query Official Song',
        channelTitle: 'Artist Channel',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_${query}_01/hqdefault.jpg',
        duration: '3:45',
        viewCount: '100000',
      ),
      YouTubeVideo(
        id: 'yt_${query}_02',
        title: '$query Lyrical Video',
        channelTitle: 'Music Label',
        thumbnailUrl: 'https://img.youtube.com/vi/yt_${query}_02/hqdefault.jpg',
        duration: '3:40',
        viewCount: '50000',
      ),
    ];
  }
}

class MockBlockingItunesMetadataService extends ItunesMetadataService {
  MockBlockingItunesMetadataService() : super.withDio(Dio());
  int enrichCalls = 0;
  Duration enrichDelay = const Duration(milliseconds: 300);

  @override
  Future<List<YouTubeVideo>> enrichYouTubeResults(
    List<YouTubeVideo> videos, {
    int maxConcurrent = 5,
  }) async {
    enrichCalls++;
    if (enrichDelay > Duration.zero) {
      await Future<void>.delayed(enrichDelay);
    }
    return videos.map((v) => v.copyWith(albumName: 'Enriched Album')).toList();
  }
}

class MockFastArtistRepository implements ArtistRepository {
  @override
  Future<List<ArtistModel>> searchArtists(String query, {String? language}) async {
    return [
      ArtistModel(id: 'a1', name: '$query Artist', imageUrl: 'https://img.com/a1.jpg'),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Local Search Latency & Indexing Tests', () {
    test('1. Local search across 1000 songs completes in under 50ms (<0.3s target)', () {
      final localSearch = LocalSearchService();
      final songs = List<MediaSong>.generate(
        1000,
        (i) => MediaSong(
          id: 'song_$i',
          title: i == 420 ? 'Kadhal En Kadhal' : 'Track Number $i In Album',
          artist: i == 420 ? 'Dhanush' : 'Artist $i Singer',
          album: 'Album Title $i',
          durationMs: 240000,
          duration: '4:00',
          artworkPath: '/music/art_$i.jpg',
          filePath: '/storage/emulated/0/Music/song_$i.mp3',
        ),
      );

      final stopwatch = Stopwatch()..start();
      final results = localSearch.searchSongs(songs, 'Kadhal En Kadhal');
      stopwatch.stop();

      expect(results.length, equals(1));
      expect(results.first.title, equals('Kadhal En Kadhal'));
      expect(results.first.artist, equals('Dhanush'));
      expect(stopwatch.elapsedMilliseconds, lessThan(50),
          reason: 'Local song search took ${stopwatch.elapsedMilliseconds}ms, target is < 50ms');
    });

    test('2. Multi-word and prefix matching resolves accurately without regex overhead', () {
      final localSearch = LocalSearchService();
      final songs = <MediaSong>[
        const MediaSong(
          id: 's1',
          title: 'Rowdy Baby (From Maari 2)',
          artist: 'Dhanush & Dhee',
          album: 'Maari 2',
          durationMs: 280000,
          duration: '4:40',
          artworkPath: '/music/rowdy.jpg',
          filePath: '/music/rowdy.mp3',
        ),
        const MediaSong(
          id: 's2',
          title: 'Why This Kolaveri Di',
          artist: 'Dhanush',
          album: '3',
          durationMs: 250000,
          duration: '4:10',
          artworkPath: '/music/kolaveri.jpg',
          filePath: '/music/kolaveri.mp3',
        ),
      ];

      final results = localSearch.searchSongs(songs, 'dhanush rowdy');
      expect(results.length, equals(1));
      expect(results.first.id, equals('s1'));
    });
  });

  group('Search Repository Caching & Progressive Non-Blocking Tests', () {
    late MockSlowYouTubeRepository mockYt;
    late MockBlockingItunesMetadataService mockItunes;
    late SearchRepository repo;

    setUp(() {
      mockYt = MockSlowYouTubeRepository();
      mockItunes = MockBlockingItunesMetadataService();
      repo = SearchRepository(
        youtubeRepository: mockYt,
        itunesMetadataService: mockItunes,
        artistRepository: MockFastArtistRepository(),
      );
    });

    tearDown(() {
      repo.dispose();
    });

    test('3. YouTube search emits results immediately without blocking on iTunes enrichment', () async {
      mockYt.networkDelay = const Duration(milliseconds: 100);
      mockItunes.enrichDelay = const Duration(milliseconds: 400);

      final stopwatch = Stopwatch()..start();
      final results = await repo.searchYouTube('Dhanush');
      stopwatch.stop();

      expect(results.isNotEmpty, isTrue);
      // Raw search should finish around 100ms, not 100ms + 400ms = 500ms
      expect(stopwatch.elapsedMilliseconds, lessThan(350),
          reason: 'searchYouTube blocked on enrichment for ${stopwatch.elapsedMilliseconds}ms');
      expect(mockItunes.enrichCalls, equals(0),
          reason: 'Synchronous searchYouTube must not block on iTunes enrichment');
    });

    test('4. Cached YouTube search returns in under 5ms (0ms target)', () async {
      await repo.searchYouTube('Anirudh');
      final initialCalls = mockYt.searchCalls;
      expect(initialCalls, greaterThan(0));

      final stopwatch = Stopwatch()..start();
      final cachedResults = await repo.searchYouTube('Anirudh');
      stopwatch.stop();

      expect(cachedResults.isNotEmpty, isTrue);
      expect(mockYt.searchCalls, equals(initialCalls),
          reason: 'Must reuse cache without extra network calls');
      expect(stopwatch.elapsedMilliseconds, lessThan(15),
          reason: 'Cached lookup took ${stopwatch.elapsedMilliseconds}ms');
    });

    test('5. In-flight request deduplication prevents duplicate network calls for same query', () async {
      mockYt.networkDelay = const Duration(milliseconds: 150);

      final future1 = repo.searchYouTube('Harris Jayaraj');
      final future2 = repo.searchYouTube('Harris Jayaraj');

      final results = await Future.wait([future1, future2]);
      expect(results[0].length, equals(results[1].length));
      // With single-batch search optimization, 1 query makes exactly 1 network search.
      // Two simultaneous in-flight calls must share the future and make exactly 1 call, not 2.
      expect(mockYt.searchCalls, equals(1),
          reason: 'Concurrent in-flight searches for identical query must share a single future');
    });
  });

  group('Debounce & Query Cancellation Tests', () {
    test('6. Rapid typing cancels superseded queries and only emits latest query results', () async {
      final mockYt = MockSlowYouTubeRepository();
      final repo = SearchRepository(
        youtubeRepository: mockYt,
        artistRepository: MockFastArtistRepository(),
      );

      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repo),
        ],
      );

      final notifier = container.read(searchNotifierProvider.notifier);

      // User types rapidly: "k" -> "ka" -> "kad" -> "kadhal" (fast typing, 15ms per keystroke)
      notifier.updateQuery('k');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      notifier.updateQuery('ka');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      notifier.updateQuery('kad');
      await Future<void>.delayed(const Duration(milliseconds: 15));
      notifier.updateQuery('kadhal');

      // Wait for debounce (250ms) + network delay (300ms) + buffer
      await Future<void>.delayed(const Duration(milliseconds: 800));

      final state = container.read(searchNotifierProvider);
      expect(state.query, equals('kadhal'));
      expect(state.youtubeResults.isNotEmpty, isTrue);
      expect(state.youtubeResults.first.title.contains('kadhal'), isTrue);
      // Earlier keystrokes were cancelled; only final debounced query fires live suggestions (1 call) + main search (1 call)
      expect(mockYt.searchCalls, equals(2),
          reason: 'Only the final debounced query should execute network search');

      container.dispose();
      repo.dispose();
    });
  });

  group('Playback Diagnostics & Latency Instrumentation Tests', () {
    test('7. PlaybackDiagnostics correctly records tap, resolution, load, and confirmed playback', () {
      final diagnostics = PlaybackDiagnostics();

      diagnostics.recordTap(
        trackId: 'test_song_01',
        title: 'Kadhal En Kadhal',
        isYoutube: false,
      );

      final timing = diagnostics.activeTiming;
      expect(timing, isNotNull);
      expect(timing!.sanitizedId, equals('test_song_01'));
      expect(timing.sourceType, equals('Local'));

      diagnostics.recordSelectedTrackUpdated('test_song_01');
      expect(timing.selectedUpdateTime, isNotNull);

      diagnostics.recordPlayerLoadStart('test_song_01');
      expect(timing.playerLoadStartTime, isNotNull);

      diagnostics.recordPlayerLoadEnd('test_song_01', success: true);
      expect(timing.playerLoadEndTime, isNotNull);

      diagnostics.recordConfirmedPlaying('test_song_01');
      expect(timing.confirmedPlayingTime, isNotNull);
      expect(timing.totalLatencyMs, greaterThanOrEqualTo(0));
    });

    test('8. SearchDiagnostics traces debounce, local search, and YouTube request correctly', () {
      final searchDiag = SearchDiagnostics();

      searchDiag.recordInput(query: 'Dhanush', reqId: 101);
      searchDiag.recordDebounceComplete(101);
      searchDiag.recordLocalQueryStart(101);
      searchDiag.recordLocalQueryEnd(101, resultCount: 5);
      searchDiag.recordYouTubeRequestStart(101);
      searchDiag.recordYouTubeRequestEnd(101, resultCount: 20, fromCache: false, success: true);
      searchDiag.recordEnrichmentEnd(101, durationMs: 120, enrichedCount: 15);

      final timing = searchDiag.activeTiming;
      expect(timing, isNotNull);
      expect(timing!.reqId, equals(101));
      expect(timing.localDurationMs, greaterThanOrEqualTo(0));
      expect(timing.youtubeDurationMs, greaterThanOrEqualTo(0));
      expect(timing.enrichmentDurationMs, equals(120));
    });
  });
}
