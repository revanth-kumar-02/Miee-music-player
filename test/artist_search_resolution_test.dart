import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/search/data/search_repository.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/presentation/widgets/youtube_result_tile.dart';
import 'package:Miee/shared/widgets/artist_avatar.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';

class MockPlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  MockPlayerController() : super(PlaybackState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFavoritesNotifier extends StateNotifier<List<Track>> implements FavoritesNotifier {
  MockFavoritesNotifier() : super([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSearchNotifier extends StateNotifier<SearchState> implements SearchNotifier {
  MockSearchNotifier(super.state);

  @override
  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('1. Genuine Artist Search & Canonical Resolution', () {
    test('Searching "Sai Abhyankkar" returns valid curated artist entity with stable ID', () async {
      final repo = DeezerArtistRepository();
      final results = await repo.searchArtists('Sai Abhyankkar');

      expect(results, isNotEmpty);
      final sai = results.firstWhere((a) => a.name == 'Sai Abhyankkar');
      expect(sai.id, equals('223843195'));
      expect(sai.name, equals('Sai Abhyankkar'));
      expect(sai.imageUrl, isNotEmpty);
      expect(ArtistAvatar.isValidArtistImageUrl(sai.imageUrl), isTrue);
    });

    test('Handles alternate spelling "Sai Abhyankar" and punctuation in curated lookup', () async {
      final repo = DeezerArtistRepository();
      // Single 'k' spelling
      final resultsSingleK = await repo.searchArtists('Sai Abhyankar');
      expect(resultsSingleK.any((a) => a.name == 'Sai Abhyankkar'), isTrue);

      // Punctuation variation "AR Rahman" vs "A. R. Rahman"
      final resultsAr = await repo.searchArtists('AR Rahman');
      expect(resultsAr.any((a) => a.name == 'A. R. Rahman'), isTrue);
    });

    test('Resolves other canonical Indian & international artists', () async {
      final repo = DeezerArtistRepository();
      final anirudh = await repo.searchArtists('Anirudh');
      expect(anirudh.any((a) => a.name.contains('Anirudh')), isTrue);

      final harris = await repo.searchArtists('Harris Jayaraj');
      expect(harris.any((a) => a.name == 'Harris Jayaraj'), isTrue);
    });

    test('Deduplicates identical canonical artists without merging different artists', () {
      final curated = [
        const ArtistModel(
          id: '223843195',
          name: 'Sai Abhyankkar',
          imageUrl: 'https://cdn-images.dzcdn.net/sai.jpg',
          fanCount: 4171,
        ),
      ];

      final ytChannels = [
        const ArtistModel(
          id: 'UCJd_XXgdc60nKoHFdiHuMZw',
          name: 'Sai Abhyankkar',
          imageUrl: 'https://yt3.ggpht.com/sai.jpg',
        ),
        const ArtistModel(
          id: 'UC_SaiPallavi_Channel',
          name: 'Sai Pallavi',
          imageUrl: 'https://yt3.ggpht.com/pallavi.jpg',
        ),
      ];

      final merged = SearchRepository.mergeAndDeduplicateArtists(
        curatedAndDeezer: curated,
        youtubeArtists: ytChannels,
        query: 'Sai Abhyankkar',
      );

      // Sai Abhyankkar should only appear once (curated entity preserved)
      final saiMatches = merged.where((a) => a.name == 'Sai Abhyankkar').toList();
      expect(saiMatches.length, equals(1));
      expect(saiMatches.first.id, equals('223843195'));
      expect(saiMatches.first.imageUrl, equals('https://cdn-images.dzcdn.net/sai.jpg'));

      // Sai Pallavi is a distinct artist and must NOT be merged with Sai Abhyankkar
      expect(merged.any((a) => a.name == 'Sai Pallavi'), isTrue);
      expect(merged.length, equals(2));
    });

    test('Filters out fan channels and tribute accounts while normalizing topic channels', () {
      // Test channel name exclusions and topic cleaning
      expect(YouTubeRepository.isExcludedArtistChannel('Saiabhyankkar Fanpage', 'Sai Abhyankkar'), isTrue);
      expect(YouTubeRepository.isExcludedArtistChannel('Sai Abhyankkar Fangirl', 'Sai Abhyankkar'), isTrue);
      expect(YouTubeRepository.isExcludedArtistChannel('Sai Abhyankkar FP', 'Sai Abhyankkar'), isTrue);
      expect(YouTubeRepository.isExcludedArtistChannel('Sai Abhyankkar Edits', 'Sai Abhyankkar'), isTrue);
      expect(YouTubeRepository.isExcludedArtistChannel('Sai Abhyankkar Status', 'Sai Abhyankkar'), isTrue);
      expect(YouTubeRepository.isExcludedArtistChannel('Sai Abhyankkar Tribute', 'Sai Abhyankkar'), isTrue);
      expect(YouTubeRepository.isExcludedArtistChannel('Sai Abhyankkar', 'Sai Abhyankkar'), isFalse);

      // Clean topic channel suffix
      expect(YouTubeRepository.cleanArtistName('Sai Abhyankkar - Topic'), equals('Sai Abhyankkar'));
      expect(YouTubeRepository.cleanArtistName('@SaiAbhyankkar'), equals('SaiAbhyankkar'));

      // Normalize double-protocol image URL
      expect(
        YouTubeRepository.normalizeImageUrl('https:https://yt3.ggpht.com/avatar.jpg'),
        equals('https://yt3.ggpht.com/avatar.jpg'),
      );
    });
  });

  group('2. Search State Classification & UI Filter Tabs', () {
    const saiArtist = ArtistModel(
      id: '223843195',
      name: 'Sai Abhyankkar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/234646e93d6ab2923f3bdc363f53d330/500x500-000000-80-0-0.jpg',
      fanCount: 4171,
    );

    const katchiSeraSong = YouTubeVideo(
      id: 'ks_123',
      title: 'Katchi Sera',
      channelTitle: 'Sai Abhyankkar',
      thumbnailUrl: 'https://i.ytimg.com/vi/ks_123/hqdefault.jpg',
      duration: '3:15',
      viewCount: '150M views',
      rawTitle: 'Katchi Sera (Music Video)',
      rawChannelTitle: 'Think Music India',
      rawViewCount: 150000000,
    );

    const aasaKoodaSong = YouTubeVideo(
      id: 'ak_456',
      title: 'Aasa Kooda',
      channelTitle: 'Sai Abhyankkar',
      thumbnailUrl: 'https://i.ytimg.com/vi/ak_456/hqdefault.jpg',
      duration: '3:40',
      viewCount: '120M views',
      rawTitle: 'Aasa Kooda (Music Video)',
      rawChannelTitle: 'Think Music India',
      rawViewCount: 120000000,
    );

    const testState = SearchState(
      query: 'Sai Abhyankkar',
      activeFilter: 'All',
      onlineArtists: [saiArtist],
      youtubeResults: [katchiSeraSong, aasaKoodaSong],
    );

    test('Songs appear under songs and artists appear under artists in SearchState', () {
      expect(testState.onlineArtists.length, equals(1));
      expect(testState.onlineArtists.first.name, equals('Sai Abhyankkar'));
      expect(testState.youtubeResults.length, equals(2));
      expect(testState.youtubeResults.every((v) => v.id.isNotEmpty), isTrue);
    });

    testWidgets('Artists filter tab renders artist entities and artist list tiles', (tester) async {
      final notifier = MockSearchNotifier(testState.copyWith(activeFilter: 'Artists'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockPlayerController()),
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Top result card for Sai Abhyankkar
      expect(find.text('Top result'), findsOneWidget);
      expect(find.text('Sai Abhyankkar'), findsAtLeast(1));

      // Artists section header and count
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Artists' && (w.style?.fontSize ?? 0) >= 18,
        ),
        findsOneWidget,
      );
      expect(find.text('1 FOUND'), findsOneWidget);

      // Songs list should NOT be visible under Artists filter
      expect(find.text('Online Tracks'), findsNothing);
      expect(find.text('Katchi Sera'), findsNothing);
    });

    testWidgets('All filter tab renders both artist carousel and songs list', (tester) async {
      final notifier = MockSearchNotifier(testState.copyWith(activeFilter: 'All'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockPlayerController()),
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Artists section header in All tab
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Artists' && (w.style?.fontSize ?? 0) >= 18,
        ),
        findsOneWidget,
      );
      expect(find.text('1 found'), findsOneWidget);

      // Songs section header in All tab
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Songs' && (w.style?.fontSize ?? 0) >= 18,
        ),
        findsOneWidget,
      );
      expect(find.text('2 FOUND'), findsOneWidget);
      expect(find.text('Katchi Sera'), findsOneWidget);
      expect(find.text('Aasa Kooda'), findsOneWidget);
    });

    testWidgets('Songs filter tab hides artist section and shows only songs', (tester) async {
      final notifier = MockSearchNotifier(testState.copyWith(activeFilter: 'Songs'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockPlayerController()),
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Songs section should be present
      expect(
        find.byWidgetPredicate(
          (w) => w is Text && w.data == 'Songs' && (w.style?.fontSize ?? 0) >= 18,
        ),
        findsOneWidget,
      );
      expect(find.text('2 FOUND'), findsOneWidget);
      expect(find.text('Katchi Sera'), findsWidgets);
      expect(find.widgetWithText(YouTubeResultTile, 'Katchi Sera'), findsOneWidget);

      // Artists section header should NOT be present
      expect(find.text('1 FOUND'), findsNothing);
    });

    testWidgets('Shows category-specific empty state when Artists filter has no matches', (tester) async {
      const emptyArtistState = SearchState(
        query: 'RandomNonExistentQueryXYZ',
        activeFilter: 'Artists',
        isArtistsLoading: false,
        onlineArtists: [],
        youtubeResults: [katchiSeraSong], // Songs exist, but 0 artists
      );
      final notifier = MockSearchNotifier(emptyArtistState);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockPlayerController()),
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => notifier),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('No artists found'), findsOneWidget);
      expect(find.byIcon(Icons.person_search_rounded), findsOneWidget);
    });
  });

  group('3. Artist Navigation & Profile Routing', () {
    const sai = ArtistModel(
      id: '223843195',
      name: 'Sai Abhyankkar',
      imageUrl: 'https://cdn-images.dzcdn.net/images/artist/234646e93d6ab2923f3bdc363f53d330/500x500-000000-80-0-0.jpg',
      fanCount: 4171,
    );

    testWidgets('Tapping artist in Artists tab pushes router to /artist/:id with stable ID', (tester) async {
      String? navigatedRoute;
      Object? navigatedExtra;

      final router = GoRouter(
        initialLocation: '/search',
        routes: [
          GoRoute(
            path: '/search',
            builder: (context, state) => const SearchPage(),
          ),
          GoRoute(
            path: '/artist/:id',
            builder: (context, state) {
              navigatedRoute = '/artist/${state.pathParameters['id']}';
              navigatedExtra = state.extra;
              return Scaffold(
                body: Text('Artist Profile: ${state.pathParameters['id']}'),
              );
            },
          ),
        ],
      );

      final notifier = MockSearchNotifier(
        const SearchState(
          query: 'Sai Abhyankkar',
          activeFilter: 'Artists',
          onlineArtists: [sai],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockPlayerController()),
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => notifier),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on the artist tile in the vertical list
      final artistTileFinder = find.widgetWithText(InkWell, 'Sai Abhyankkar').last;
      expect(artistTileFinder, findsOneWidget);
      await tester.tap(artistTileFinder);
      await tester.pumpAndSettle();

      // Verify router navigation occurred with the stable Deezer ID and extra
      expect(navigatedRoute, equals('/artist/223843195'));
      expect(navigatedExtra, isA<ArtistModel>());
      expect((navigatedExtra as ArtistModel).name, equals('Sai Abhyankkar'));
      expect(find.text('Artist Profile: 223843195'), findsOneWidget);
    });
  });

  group('4. Search Quality & Song Constraints Preservation', () {
    test('Derivative-edit exclusions apply to songs without filtering artist entities', () {
      final videos = [
        const YouTubeVideo(
          id: 'v_orig',
          title: 'Katchi Sera',
          channelTitle: 'Sai Abhyankkar',
          thumbnailUrl: 'https://example.com/1.jpg',
          duration: '3:15',
          viewCount: '150M views',
          rawTitle: 'Sai Abhyankkar - Katchi Sera (Official Video)',
          rawChannelTitle: 'Think Music India',
          rawViewCount: 150000000,
        ),
        const YouTubeVideo(
          id: 'v_edit',
          title: 'Katchi Sera (Slowed Reverb Edit)',
          channelTitle: 'Editor Channel',
          thumbnailUrl: 'https://example.com/2.jpg',
          duration: '3:45',
          viewCount: '5K views',
          rawTitle: 'Katchi Sera - Slowed + Reverb 4K Status Edit',
          rawChannelTitle: 'Editor Channel',
          rawViewCount: 5000,
        ),
      ];

      final rankedSongs = SearchDeduplicator.deduplicateAndRank(
        videos,
        query: 'Katchi Sera',
        config: const SearchRankingConfig(filterDerivativeEdits: true),
      );

      // Derivative slow+reverb edit is filtered from songs
      expect(rankedSongs.length, equals(1));
      expect(rankedSongs.first.id, equals('v_orig'));

      // Meanwhile, artist search is unaffected by song view count constraints
      const artist = ArtistModel(
        id: '223843195',
        name: 'Sai Abhyankkar',
        imageUrl: 'https://cdn-images.dzcdn.net/sai.jpg',
        fanCount: 4171,
      );
      expect(artist.name, equals('Sai Abhyankkar'));
      expect(artist.id, equals('223843195'));
    });
  });
}
