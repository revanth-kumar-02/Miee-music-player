import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:Miee/core/network/network_request_coordinator.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/features/media/domain/media_repository.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/metadata/data/itunes_metadata_service.dart';
import 'package:Miee/features/metadata/data/musicbrainz_service.dart';
import 'package:Miee/features/metadata/domain/itunes_song.dart';
import 'package:Miee/features/metadata/domain/musicbrainz_models.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/search/data/search_repository.dart';
import 'package:Miee/features/search/domain/canonical_music_ranker.dart';
import 'package:Miee/features/search/domain/music_suggestion.dart';
import 'package:Miee/features/search/domain/online_playlist.dart';
import 'package:Miee/features/search/domain/query_relevance_evaluator.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';

class _StubYouTubeRepo extends YouTubeRepository {
  Map<String, List<YouTubeVideo>> searchResponses = {};
  Duration delay = Duration.zero;
  int calls = 0;

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
    NetworkPriority priority = NetworkPriority.userSearch,
  }) async {
    calls++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    return searchResponses[query] ??
        searchResponses[query.toLowerCase()] ??
        const [];
  }

  @override
  Future<List<OnlinePlaylist>> searchPlaylists(String query,
          {int limit = 10}) async =>
      const [];
}

class _StubArtistRepo implements ArtistRepository {
  List<ArtistModel> artists = const [];
  Map<String, List<ArtistAlbum>> albumsByArtistId = const {};

  @override
  Future<List<ArtistModel>> searchArtists(String query,
      {String? language}) async {
    return artists;
  }

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async {
    return albumsByArtistId[artistId] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubItunesService implements ItunesMetadataService {
  List<ItunesSong> songs = const [];
  List<ArtistModel> artists = const [];
  List<ArtistAlbum> albums = const [];
  Map<String, List<ItunesSong>> albumTracks = const {};

  @override
  Future<List<ItunesSong>> searchSongs(String term,
      {int limit = 10, bool forceRefresh = false}) async {
    return songs;
  }

  @override
  Future<List<ArtistModel>> searchArtists(String term, {int limit = 10}) async {
    return artists;
  }

  @override
  Future<List<ArtistAlbum>> searchAlbums(String term, {int limit = 10}) async {
    return albums;
  }

  @override
  Future<List<ItunesSong>> getAlbumTracks(String collectionId,
      {int limit = 50}) async {
    return albumTracks[collectionId] ?? const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubMusicBrainzService implements MusicBrainzService {
  List<MusicBrainzRecording> recordings = const [];
  List<ArtistModel> artists = const [];

  @override
  Future<List<MusicBrainzRecording>> searchRecordings(String query,
      {int limit = 10, bool forceRefresh = false}) async {
    return recordings;
  }

  @override
  Future<List<ArtistModel>> searchArtistsAsArtistModels(String query,
      {int limit = 10}) async {
    return artists;
  }

  @override
  Future<String?> resolveCoverArtUrl(MusicBrainzRecording recording) async =>
      null;

  @override
  void clearCache() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DummyMediaRepo implements MediaRepository {
  @override
  Future<bool> checkAndRequestPermissions() async => true;
  @override
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false}) async =>
      const [];
  @override
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false}) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Artist Relevance & Substring Protection', () {
    test('Rejects unrelated artists with substring or single-word collisions',
        () {
      expect(
        QueryRelevanceEvaluator.isArtistRelevant(
          'Rey Mysterio',
          query: 'Lana Del Rey',
        ),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isArtistRelevant(
          'Ariana Grande',
          query: 'Aria',
        ),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isArtistRelevant(
          'Lana Del Rey',
          query: 'Lana Del Rey',
        ),
        isTrue,
      );
    });

    test('Supports featured artists, multiple collaborators, and aliases', () {
      expect(
        QueryRelevanceEvaluator.matchesCreditedArtist(
          'Anirudh Ravichander, Jonita Gandhi feat. Sai Abhyankkar',
          'Sai Abhyankkar',
        ),
        isTrue,
      );
      expect(
        QueryRelevanceEvaluator.matchesCreditedArtist(
          'A. R. Rahman',
          'AR Rahman',
        ),
        isTrue,
      );
      expect(
        QueryRelevanceEvaluator.matchesCreditedArtist(
          'Sai Abhyankar',
          'Sai Abhyankkar',
        ),
        isTrue,
      );
      expect(
        QueryRelevanceEvaluator.matchesCreditedArtist(
          'Yuvan Shankar Raja',
          'YSR',
        ),
        isTrue,
      );
    });

    test(
        'Rejects matching song title when unrelated artist is returned for targeted artist query',
        () {
      const unrelatedUpload = YouTubeVideo(
        id: 'unrel123456',
        title: 'Anirudh Ravichander Tribute Song',
        channelTitle: 'Random Tribute DJ',
        canonicalTitle: 'Anirudh Ravichander Tribute Song',
        canonicalArtist: 'Random Tribute DJ',
        thumbnailUrl: '',
        duration: '3:10',
        viewCount: '5000',
      );
      const validSoundtrack = YouTubeVideo(
        id: 'valid123456',
        title: 'Hukum - Jailer | Music: Anirudh Ravichander',
        channelTitle: 'Sun TV',
        thumbnailUrl: '',
        duration: '3:27',
        viewCount: '50000000',
      );

      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(
          unrelatedUpload,
          query: 'Anirudh Ravichander',
          expectedArtist: 'Anirudh Ravichander',
        ),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(
          validSoundtrack,
          query: 'Anirudh Ravichander',
          expectedArtist: 'Anirudh Ravichander',
        ),
        isTrue,
      );
    });

    test('Rejects uploader name masquerading as recording artist', () {
      const uploaderMismatch = YouTubeVideo(
        id: 'upl12345678',
        title: 'Some Random Indie Song',
        channelTitle: 'Anirudh Fan Club Uploader',
        canonicalTitle: 'Some Random Indie Song',
        canonicalArtist: 'Indie Guy',
        thumbnailUrl: '',
        duration: '3:30',
        viewCount: '1000',
      );

      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(
          uploaderMismatch,
          query: 'Anirudh Ravichander',
          expectedArtist: 'Anirudh Ravichander',
        ),
        isFalse,
      );
    });
  });

  group('CanonicalMusicRanker Priorities & Penalties', () {
    test(
        'Prioritizes exact title + exact main artist and feat. collab over unrelated artist',
        () {
      const exactMain = YouTubeVideo(
        id: 'main1234567',
        title: 'Veezha Veera',
        channelTitle: 'Sai Abhyankkar - Topic',
        canonicalTitle: 'Veezha Veera',
        canonicalArtist: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '3:57',
        viewCount: '1000000',
        metadataProvider: 'itunes',
      );
      const collab = YouTubeVideo(
        id: 'col12345678',
        title: 'Veezha Veera',
        channelTitle: 'Tippu & Sai Abhyankkar',
        canonicalTitle: 'Veezha Veera',
        canonicalArtist: 'Tippu & Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '3:57',
        viewCount: '800000',
      );
      const unrelatedExactTitle = YouTubeVideo(
        id: 'bad12345678',
        title: 'Veezha Veera',
        channelTitle: 'Unrelated Cover Band',
        canonicalTitle: 'Veezha Veera',
        canonicalArtist: 'Unrelated Cover Band',
        thumbnailUrl: '',
        duration: '3:50',
        viewCount: '10000',
        metadataProvider: 'musicbrainz',
      );

      final ranked = CanonicalMusicRanker.rankVideos(
        [unrelatedExactTitle, collab, exactMain],
        query: 'Veezha Veera',
        canonicalArtist: 'Sai Abhyankkar',
      );

      expect(ranked.first.id, equals('main1234567'));
      expect(ranked[1].id, equals('col12345678'));
      expect(ranked.last.id, equals('bad12345678'));
    });

    test(
        'Preserves Tamil/Telugu variants, Remixes, and Live recordings when queried',
        () {
      const tamil = YouTubeVideo(
        id: 'tam12345678',
        title: 'Alaakaa Loova (Tamil)',
        channelTitle: 'Sai Abhyankkar - Topic',
        canonicalTitle: 'Alaakaa Loova (Tamil)',
        canonicalArtist: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '3:37',
        viewCount: '900000',
      );
      const telugu = YouTubeVideo(
        id: 'tel12345678',
        title: 'Alaakaa Loova (Telugu)',
        channelTitle: 'Sai Abhyankkar - Topic',
        canonicalTitle: 'Alaakaa Loova (Telugu)',
        canonicalArtist: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '3:38',
        viewCount: '800000',
      );
      const remix = YouTubeVideo(
        id: 'rmx12345678',
        title: 'Alaakaa Loova (Remix)',
        channelTitle: 'Sai Abhyankkar',
        canonicalTitle: 'Alaakaa Loova (Remix)',
        canonicalArtist: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '3:15',
        viewCount: '300000',
      );
      const live = YouTubeVideo(
        id: 'liv12345678',
        title: 'Alaakaa Loova (Live)',
        channelTitle: 'Sai Abhyankkar',
        canonicalTitle: 'Alaakaa Loova (Live)',
        canonicalArtist: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '4:05',
        viewCount: '250000',
      );

      final ranked = CanonicalMusicRanker.rankVideos(
        [tamil, telugu, remix, live],
        query: 'Alaakaa Loova',
        canonicalArtist: 'Sai Abhyankkar',
      );

      expect(ranked.length, equals(4));
    });
  });

  group('Multi-Provider Consistency, Compilation Bridging & Suggestions', () {
    test(
        'Artist search excludes unrelated compilation album tracks & merges MB/iTunes duplicates cleanly',
        () async {
      final ytRepo = _StubYouTubeRepo();
      final artistRepo = _StubArtistRepo()
        ..artists = const [
          ArtistModel(
            id: 'art_sai',
            name: 'Sai Abhyankkar',
            imageUrl: '',
            fanCount: 250000,
          ),
        ];
      final itunes = _StubItunesService()
        ..artists = const [
          ArtistModel(
            id: 'it_sai',
            name: 'Sai Abhyankkar',
            imageUrl: '',
            fanCount: 250000,
          ),
        ]
        ..albums = const [
          ArtistAlbum(
            id: 'itunes_comp1',
            title: 'Sai Abhyankkar Hits Collection',
            artistName: 'Various Artists',
            coverUrl: '',
            releaseDate: '2025-01-01',
          ),
        ]
        ..albumTracks = {
          'comp1': const [
            ItunesSong(
              trackId: 101,
              trackName: 'Genuine Sai Song',
              artistName: 'Sai Abhyankkar',
              collectionName: 'Sai Abhyankkar Hits Collection',
              artworkUrl100: 'https://img/1.jpg',
              trackTimeMillis: 210000,
            ),
            ItunesSong(
              trackId: 102,
              trackName: 'Unrelated Compilation Track',
              artistName: 'Completely Different Artist',
              collectionName: 'Sai Abhyankkar Hits Collection',
              artworkUrl100: 'https://img/2.jpg',
              trackTimeMillis: 200000,
            ),
          ],
        }
        ..songs = const [
          ItunesSong(
            trackId: 101,
            trackName: 'Genuine Sai Song',
            artistName: 'Sai Abhyankkar',
            collectionName: 'Single',
            artworkUrl100: 'https://img/1.jpg',
            trackTimeMillis: 210000,
          ),
        ];
      final mb = _StubMusicBrainzService()
        ..recordings = const [
          MusicBrainzRecording(
            mbid: 'mb-1',
            title: 'Genuine Sai Song',
            artistCredit: 'Sai Abhyankkar',
            primaryArtist: 'Sai Abhyankkar',
            durationMs: 210000,
            albumTitle: 'Single',
            releaseMbid: 'rel-1',
            score: 98,
          ),
          MusicBrainzRecording(
            mbid: 'mb-2',
            title: 'Sai Abhyankkar Medley Cover',
            artistCredit: 'Unrelated Tribute Act',
            primaryArtist: 'Unrelated Tribute Act',
            durationMs: 195000,
            score: 80,
          ),
        ];

      final repo = SearchRepository(
        youtubeRepository: ytRepo,
        artistRepository: artistRepo,
        itunesMetadataService: itunes,
        musicBrainzService: mb,
      );

      final results = await repo.searchYouTube('Sai Abhyankkar');

      expect(
        results.any(
            (v) => (v.canonicalArtist ?? v.channelTitle) == 'Sai Abhyankkar'),
        isTrue,
      );
      expect(
        results.any((v) =>
            (v.canonicalArtist ?? v.channelTitle) == 'Unrelated Tribute Act'),
        isFalse,
      );
      expect(
        results.any((v) =>
            (v.canonicalArtist ?? v.channelTitle) ==
            'Completely Different Artist'),
        isFalse,
      );
      expect(
        results
            .where((v) => (v.canonicalTitle ?? v.title) == 'Genuine Sai Song')
            .length,
        equals(1),
      );
    });

    test(
        'getLiveMusicSuggestions filters out unrelated artists and non-music clips and respects CancelToken',
        () async {
      final ytRepo = _StubYouTubeRepo()
        ..searchResponses = {
          'Anirudh': const [
            YouTubeVideo(
              id: 'validAni123',
              title: 'Hukum - Official Audio',
              channelTitle: 'Anirudh Ravichander - Topic',
              canonicalTitle: 'Hukum',
              canonicalArtist: 'Anirudh Ravichander',
              thumbnailUrl: '',
              duration: '3:27',
              viewCount: '1000000',
            ),
            YouTubeVideo(
              id: 'unrelAni123',
              title: 'Anirudh Interview Comedy Reaction',
              channelTitle: 'Troll Machi',
              canonicalTitle: 'Anirudh Interview Comedy Reaction',
              canonicalArtist: 'Troll Machi',
              thumbnailUrl: '',
              duration: '6:10',
              viewCount: '50000',
            ),
          ],
        };
      final artistRepo = _StubArtistRepo()
        ..artists = const [
          ArtistModel(
            id: 'art_ani',
            name: 'Anirudh Ravichander',
            imageUrl: '',
            fanCount: 5000000,
          ),
        ];

      final repo = SearchRepository(
        youtubeRepository: ytRepo,
        artistRepository: artistRepo,
        itunesMetadataService: _StubItunesService(),
        musicBrainzService: _StubMusicBrainzService(),
      );

      final suggestions = await repo.getLiveMusicSuggestions(query: 'Anirudh');
      final songSuggestions =
          suggestions.where((s) => s.type == SuggestionType.song).toList();
      expect(songSuggestions.length, equals(1));
      expect(songSuggestions.first.id, equals('validAni123'));

      final cancelled = CancelToken()..cancel('stale');
      final staleSuggestions = await repo.getLiveMusicSuggestions(
        query: 'Anirudh',
        cancelToken: cancelled,
      );
      expect(staleSuggestions, isEmpty);
    });
  });

  group('Rapid Query Changes & Stale Response Isolation', () {
    late Directory tempDir;

    setUp(() async {
      tempDir =
          await Directory.systemTemp.createTemp('miee_search_rel_reg_test_');
      Hive.init(tempDir.path);
      await Hive.openBox<dynamic>(HiveBoxes.preferences);
    });

    tearDown(() async {
      await Hive.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test(
        'SearchNotifier rapid searchNow drops slower stale query response in favor of latest query',
        () async {
      final ytRepo = _StubYouTubeRepo()
        ..delay = const Duration(milliseconds: 50)
        ..searchResponses = {
          'Anirudh': const [
            YouTubeVideo(
              id: 'stale123456',
              title: 'Anirudh Hit Song',
              channelTitle: 'Anirudh Ravichander - Topic',
              canonicalTitle: 'Anirudh Hit Song',
              canonicalArtist: 'Anirudh Ravichander',
              thumbnailUrl: '',
              duration: '3:00',
              viewCount: '100',
            ),
          ],
          'Rahman': const [
            YouTubeVideo(
              id: 'fresh123456',
              title: 'Rahman Classic Song',
              channelTitle: 'A. R. Rahman - Topic',
              canonicalTitle: 'Rahman Classic Song',
              canonicalArtist: 'A. R. Rahman',
              thumbnailUrl: '',
              duration: '3:15',
              viewCount: '2000',
            ),
          ],
        };
      final repo = SearchRepository(
        youtubeRepository: ytRepo,
        artistRepository: _StubArtistRepo(),
        itunesMetadataService: _StubItunesService(),
        musicBrainzService: _StubMusicBrainzService(),
      );

      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(repo),
          mediaLibraryServiceProvider
              .overrideWith((_) => MediaLibraryService(_DummyMediaRepo())),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchNotifierProvider.notifier);
      notifier.searchNow('Anirudh');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      notifier.searchNow('Rahman');

      await Future<void>.delayed(const Duration(milliseconds: 250));
      final state = container.read(searchNotifierProvider);
      expect(state.query, equals('Rahman'));
      expect(state.youtubeResults.any((v) => v.id == 'stale123456'), isFalse);
      expect(state.youtubeResults.any((v) => v.id == 'fresh123456'), isTrue);
    });
  });
}
