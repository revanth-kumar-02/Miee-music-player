import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/core/network/network_request_coordinator.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/queue/presentation/queue_page.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/data/trending_music_service.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class _StubPlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  _StubPlayerController(super.state);

  void emit(PlaybackState next) => state = next;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeYouTubeRepo extends YouTubeRepository {
  final List<YouTubeVideo> related;
  final Map<String, List<YouTubeVideo>> byArtist;

  _FakeYouTubeRepo({
    this.related = const [],
    this.byArtist = const {},
  });

  @override
  Future<List<YouTubeVideo>> getRelatedTracks(
    YouTubeVideo seed, {
    int limit = 15,
  }) async {
    return related.take(limit).toList();
  }

  @override
  Future<List<YouTubeVideo>> getArtistTracks(
    String artistName, {
    int page = 1,
    int limit = 15,
    List<String> preferredLanguages = const [],
    NetworkPriority priority = NetworkPriority.suggestionsAndEnrichment,
  }) async {
    return (byArtist[artistName] ?? const []).take(limit).toList();
  }

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
    NetworkPriority priority = NetworkPriority.userSearch,
  }) async {
    return const [];
  }
}

class _FakeArtistRepo extends DeezerArtistRepository {
  final List<ArtistModel> searched;
  final List<ArtistModel> related;

  _FakeArtistRepo({this.searched = const [], this.related = const []});

  @override
  Future<List<ArtistModel>> searchArtists(String query,
      {String? language}) async {
    return searched;
  }

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async {
    return related;
  }
}

class _FakeHistoryRepo implements ListeningHistoryRepository {
  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {}

  @override
  Future<List<ListeningEvent>> getRecentHistory(
      {required String? uid, int limit = 30}) async {
    return const [];
  }

  @override
  Future<void> clearHistory(String? uid) async {}
}

class _FakeTrendingService extends TrendingMusicService {
  @override
  Future<TrendingResult> getTrendingAndRecentReleases({
    bool forceRefresh = false,
    String? regionCode,
  }) async {
    return TrendingResult(
      trendingTracks: const [],
      recentReleases: const [],
      fetchedAt: DateTime(2026),
    );
  }
}

void main() {
  group('Q-01: Reactive Queue State & Loading UI', () {
    test(
        'PlaybackState copyWith updates queueVersion and queueGenerationStatus',
        () {
      final initial = PlaybackState.initial();
      expect(initial.queueVersion, equals(0));
      expect(initial.queueGenerationStatus, equals(QueueGenerationStatus.idle));

      final loading = initial.copyWith(
        queueVersion: 1,
        queueGenerationStatus: QueueGenerationStatus.loading,
      );
      expect(loading.queueVersion, equals(1));
      expect(
          loading.queueGenerationStatus, equals(QueueGenerationStatus.loading));

      final ready = loading.copyWith(
        queueVersion: 2,
        queueGenerationStatus: QueueGenerationStatus.ready,
        clearQueueGenerationError: true,
      );
      expect(ready.queueVersion, equals(2));
      expect(ready.queueGenerationStatus, equals(QueueGenerationStatus.ready));
      expect(ready.queueGenerationError, isNull);
    });

    testWidgets(
        'QueuePage displays loading indicator while generating and updates reactively on queueVersion change',
        (tester) async {
      const seedTrack = Track(
        id: 'youtube_seed1234567',
        title: 'Alaakaa Loova (Telugu)',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:38',
      );
      const nextTrack = Track(
        id: 'youtube_next1234567',
        title: 'Veezha Veera',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:57',
      );

      final queueManager = QueueManager()..setQueue([seedTrack], startIndex: 0);
      final stubController = _StubPlayerController(
        const PlaybackState(
          status: PlaybackStatus.playing,
          currentTrack: seedTrack,
          queueVersion: 1,
          queueGenerationStatus: QueueGenerationStatus.loading,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queueManagerProvider.overrideWithValue(queueManager),
            playerControllerProvider.overrideWith((_) => stubController),
            resolvedArtworkProvider.overrideWith(
              (ref, query) async => ResolvedArtwork.neutralFallback(),
            ),
          ],
          child: const MaterialApp(home: QueuePage()),
        ),
      );
      await tester.pump();
      expect(find.text('Playing Queue'), findsOneWidget);
      expect(find.text('Finding related tracks...'), findsOneWidget);
      expect(find.text('Veezha Veera'), findsNothing);

      // Mutate queue and bump queueVersion WITHOUT changing currentTrack
      queueManager.addTracks([nextTrack]);
      stubController.emit(
        stubController.state.copyWith(
          queueVersion: 2,
          queueGenerationStatus: QueueGenerationStatus.ready,
        ),
      );
      await tester.pump();

      expect(find.text('Finding related tracks...'), findsNothing);
      expect(find.text('Veezha Veera'), findsOneWidget);
    });
  });

  group('Q-02: Non-Music & Editorial Storytelling Filtering', () {
    test(
        'Rejects short editorial/storytelling clip on music label channel ("Lyricist Rokesh shares the...")',
        () {
      final editorialClip = YouTubeVideo(
        id: 'rokesh12345',
        title: 'Lyricist Rokesh shares the making experience of OM',
        channelTitle: 'Divo Music',
        thumbnailUrl: 'https://i.ytimg.com/vi/rokesh12345/hqdefault.jpg',
        duration: '0:44',
        viewCount: '25000',
      );

      expect(
          MusicResultClassifier.isValidIndividualSong(editorialClip), isFalse);
      expect(RecommendationService.isLegitimateSong(editorialClip), isFalse);
    });

    test('Rejects interview, talks about, sneak peek clips', () {
      final interview = YouTubeVideo(
        id: 'inter123456',
        title: 'Sai Abhyankkar talks about his musical journey',
        channelTitle: 'Think Music India',
        thumbnailUrl: 'https://i.ytimg.com/vi/inter123456/hqdefault.jpg',
        duration: '1:15',
        viewCount: '18000',
      );
      final sneakPeek = YouTubeVideo(
        id: 'sneak123456',
        title: 'OM Special Glimpse | Sneak Peek',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://i.ytimg.com/vi/sneak123456/hqdefault.jpg',
        duration: '0:50',
        viewCount: '90000',
      );

      expect(RecommendationService.isLegitimateSong(interview), isFalse);
      expect(RecommendationService.isLegitimateSong(sneakPeek), isFalse);
    });

    test(
        'Preserves legitimate official audio, lyrical video, remix, live, and short musical intro',
        () {
      final officialAudio = YouTubeVideo(
        id: 'off12345678',
        title: 'Veezha Veera (From "O.M") - Official Audio',
        channelTitle: 'Sai Abhyankkar - Topic',
        thumbnailUrl: 'https://i.ytimg.com/vi/off12345678/hqdefault.jpg',
        duration: '3:57',
        viewCount: '1200000',
      );
      final shortIntro = YouTubeVideo(
        id: 'intro123456',
        title: 'O.M Intro Theme (Audio)',
        channelTitle: 'Sai Abhyankkar - Topic',
        thumbnailUrl: 'https://i.ytimg.com/vi/intro123456/hqdefault.jpg',
        duration: '0:45',
        viewCount: '150000',
      );
      final remix = YouTubeVideo(
        id: 'remix123456',
        title: 'Katchi Sera (Remix)',
        channelTitle: 'Think Music India',
        thumbnailUrl: 'https://i.ytimg.com/vi/remix123456/hqdefault.jpg',
        duration: '3:12',
        viewCount: '450000',
      );

      expect(RecommendationService.isLegitimateSong(officialAudio), isTrue);
      expect(RecommendationService.isLegitimateSong(shortIntro), isTrue);
      expect(RecommendationService.isLegitimateSong(remix), isTrue);
    });
  });

  group('Q-03: Recording Identity & Language-Aware Queue Filtering', () {
    test(
        'computeLanguageAgnosticRecordingKey collapses Telugu and Tamil variants of same song while keeping Remix/Live distinct',
        () {
      const telugu = Track(
        id: 'youtube_tel12345678',
        title: 'Alaakaa Loova (Telugu)',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:38',
      );
      const tamil = Track(
        id: 'youtube_tam12345678',
        title: 'Alaakaa Loova Lyrical (Tamil)',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:37',
      );
      const remix = Track(
        id: 'youtube_rmx12345678',
        title: 'Alaakaa Loova (Remix)',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:15',
      );

      // Existing computeRecordingKey keeps them separate for search
      expect(
        SearchDeduplicator.computeRecordingKey(telugu),
        isNot(equals(SearchDeduplicator.computeRecordingKey(tamil))),
      );

      // Language-agnostic key collapses Telugu & Tamil variants of same song
      expect(
        SearchDeduplicator.computeLanguageAgnosticRecordingKey(telugu),
        equals(SearchDeduplicator.computeLanguageAgnosticRecordingKey(tamil)),
      );

      // Remix remains distinct
      expect(
        SearchDeduplicator.computeLanguageAgnosticRecordingKey(telugu),
        isNot(
          equals(SearchDeduplicator.computeLanguageAgnosticRecordingKey(remix)),
        ),
      );
    });

    test(
        'getUpcomingQueueRecommendations excludes other-language duplicate and prioritizes seed language',
        () async {
      const seedTrack = Track(
        id: 'youtube_tel12345678',
        title: 'Alaakaa Loova (Telugu)',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:38',
      );

      final ytRepo = _FakeYouTubeRepo(
        related: [
          YouTubeVideo(
            id: 'tam12345678',
            title: 'Alaakaa Loova Lyrical (Tamil)',
            channelTitle: 'Sai Abhyankkar',
            thumbnailUrl: 'https://i.ytimg.com/vi/tam12345678/hqdefault.jpg',
            duration: '3:37',
            viewCount: '900000',
          ),
          YouTubeVideo(
            id: 'tel22345678',
            title: 'Butta Bomma (Telugu) - Official Audio',
            channelTitle: 'Armaan Malik',
            thumbnailUrl: 'https://i.ytimg.com/vi/tel22345678/hqdefault.jpg',
            duration: '3:18',
            viewCount: '2000000',
          ),
          YouTubeVideo(
            id: 'hin12345678',
            title: 'Kesariya (Hindi) - Official Audio',
            channelTitle: 'Arijit Singh',
            thumbnailUrl: 'https://i.ytimg.com/vi/hin12345678/hqdefault.jpg',
            duration: '4:28',
            viewCount: '3000000',
          ),
        ],
      );

      final service = RecommendationService(
        youtubeRepo: ytRepo,
        artistRepo: _FakeArtistRepo(),
        historyRepo: _FakeHistoryRepo(),
        trendingService: _FakeTrendingService(),
      );

      final upcoming = await service.getUpcomingQueueRecommendations(
        currentTrack: seedTrack,
        currentQueue: const [seedTrack],
        limit: 5,
      );

      expect(upcoming.any((t) => t.id.contains('tam12345678')), isFalse);
      expect(upcoming.first.id, contains('tel22345678'));
    });
  });

  group('Q-04: Strict Artist Diversity Enforcement', () {
    test(
        'Enforces maxTracksPerArtist = 2 without backfilling deferred same-artist tracks',
        () async {
      const seedTrack = Track(
        id: 'youtube_seed9999999',
        title: 'Karuppa Kooda Va',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:40',
      );

      final ytRepo = _FakeYouTubeRepo(
        related: List.generate(
          6,
          (i) => YouTubeVideo(
            id: 'sai0000000$i',
            title: 'Sai Song $i (Official Audio)',
            channelTitle: 'Sai Abhyankkar',
            thumbnailUrl: 'https://i.ytimg.com/vi/sai0000000$i/hqdefault.jpg',
            duration: '3:30',
            viewCount: '500000',
          ),
        ),
        byArtist: {
          'Anirudh Ravichander': [
            YouTubeVideo(
              id: 'ani00000001',
              title: 'Hukum - Official Audio',
              channelTitle: 'Anirudh Ravichander',
              thumbnailUrl: 'https://i.ytimg.com/vi/ani00000001/hqdefault.jpg',
              duration: '3:27',
              viewCount: '1000000',
            ),
          ],
        },
      );

      final service = RecommendationService(
        youtubeRepo: ytRepo,
        artistRepo: _FakeArtistRepo(
          searched: const [
            ArtistModel(id: 'art_sai', name: 'Sai Abhyankkar', imageUrl: ''),
          ],
          related: const [
            ArtistModel(
                id: 'art_ani', name: 'Anirudh Ravichander', imageUrl: ''),
          ],
        ),
        historyRepo: _FakeHistoryRepo(),
        trendingService: _FakeTrendingService(),
      );

      final upcoming = await service.getUpcomingQueueRecommendations(
        currentTrack: seedTrack,
        currentQueue: const [seedTrack],
        limit: 8,
      );

      final saiCount = upcoming
          .where((t) =>
              SearchDeduplicator.normalizeArtist(t.artist) == 'sai abhyankkar')
          .length;
      expect(saiCount, lessThanOrEqualTo(2));
      expect(
        upcoming.any((t) =>
            SearchDeduplicator.normalizeArtist(t.artist) ==
            'anirudh ravichander'),
        isTrue,
      );
    });
  });

  group('Q-05: Unified Artwork Propagation', () {
    test(
        'ArtworkQuery.fromMusicItem preserves resolvedArtworkUrl without promoting YouTube thumbnail to albumArtworkUrl',
        () {
      const trackWithResolvedArt = Track(
        id: 'youtube_art12345678',
        title: 'Veezha Veera',
        artist: 'Sai Abhyankkar',
        imageUrl: '',
        duration: '3:57',
        resolvedArtworkUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/art/600x600bb.jpg',
        youtubeThumbnailUrl: 'https://i.ytimg.com/vi/art12345678/hqdefault.jpg',
      );

      final q1 = ArtworkQuery.fromMusicItem(trackWithResolvedArt);
      expect(
        q1.albumArtworkUrl,
        equals('https://is1-ssl.mzstatic.com/image/thumb/art/600x600bb.jpg'),
      );
      expect(
        q1.fallbackThumbnailUrl,
        equals('https://i.ytimg.com/vi/art12345678/hqdefault.jpg'),
      );

      const trackWithThumbOnly = Track(
        id: 'youtube_thb12345678',
        title: 'Salambala - Full',
        artist: 'Karthik',
        imageUrl: '',
        duration: '3:50',
        youtubeThumbnailUrl: 'https://i.ytimg.com/vi/thb12345678/hqdefault.jpg',
      );

      final q2 = ArtworkQuery.fromMusicItem(trackWithThumbOnly);
      expect(q2.albumArtworkUrl, isNull);
      expect(
        q2.fallbackThumbnailUrl,
        equals('https://i.ytimg.com/vi/thb12345678/hqdefault.jpg'),
      );
    });
  });

  group('Q-06: Playback Source & Recording Identity Consistency', () {
    test(
        'PlaybackSourceResolver rejects duration/title/artist mismatches and preserves intended recording',
        () {
      final resolver = PlaybackSourceResolver();
      final wrongDurationCandidate = YouTubeVideo(
        id: 'wrongDur123',
        title: 'Alaakaa Loova (Official Audio)',
        channelTitle: 'Sai Abhyankkar - Topic',
        thumbnailUrl: 'https://i.ytimg.com/vi/wrongDur123/hqdefault.jpg',
        duration: '0:25',
        viewCount: '10000',
      );
      final wrongTitleCandidate = YouTubeVideo(
        id: 'wrongTit123',
        title: 'Completely Different Song',
        channelTitle: 'Sai Abhyankkar - Topic',
        thumbnailUrl: 'https://i.ytimg.com/vi/wrongTit123/hqdefault.jpg',
        duration: '3:38',
        viewCount: '100000',
      );

      expect(
        resolver.selectBestCandidate(
          [wrongDurationCandidate, wrongTitleCandidate],
          title: 'Alaakaa Loova',
          artist: 'Sai Abhyankkar',
          durationStr: '3:38',
        ),
        isNull,
      );
    });
  });
}
