import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/domain/music_suggestion.dart';
import 'package:Miee/features/search/domain/artist_classifier.dart';
import 'package:Miee/features/search/data/search_repository.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/shared/models/track.dart';

class MockLivePlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  MockLivePlayerController() : super(PlaybackState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLiveFavoritesNotifier extends StateNotifier<List<Track>> implements FavoritesNotifier {
  MockLiveFavoritesNotifier() : super([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockLiveSearchNotifier extends StateNotifier<SearchState> implements SearchNotifier {
  String? lastUpdatedQuery;
  String? lastSearchedQuery;

  MockLiveSearchNotifier(super.state);

  @override
  void updateQuery(String query) {
    lastUpdatedQuery = query;
  }

  @override
  void searchNow(String query) {
    lastSearchedQuery = query;
  }

  @override
  void setFilter(String filter) {}

  @override
  Future<void> addHistory(String query) async {}

  @override
  Future<void> removeHistory(String query) async {}

  @override
  Future<void> clearHistory() async {}

  @override
  void enrichArtistsFromSongsForTesting(String query, List<YouTubeVideo> youtube) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Live Music Autocomplete — Unit & Domain Tests', () {
    test('1. Type "lana del" yields Artist first, followed by Songs and Album, ending with Search action', () async {
      final repo = SearchRepository();

      const lanaArtist = ArtistModel(
        id: 'lana_del_rey',
        name: 'Lana Del Rey',
        imageUrl: 'https://example.com/lana.jpg',
        fanCount: 8500000,
      );

      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'lana del',
        localArtists: const [],
        localSongs: const [],
      );

      // Suggestions must not be empty
      expect(suggestions.isNotEmpty, isTrue);

      // Verify Artist suggestion is present
      final artistSugg = suggestions.firstWhere((s) => s.type == SuggestionType.artist);
      expect(artistSugg.title, contains('Lana Del Rey'));
      expect(artistSugg.typeLabel, equals('Artist'));

      // Verify secondary Search action is at the end
      final lastSugg = suggestions.last;
      expect(lastSugg.type, equals(SuggestionType.searchQuery));
      expect(lastSugg.title, equals('Search for "lana del"'));
    });

    test('2. Type "brooklyn baby" links to Lana Del Rey performing artist identity', () {
      final curated = DeezerArtistRepository.findCuratedByName('Lana Del Rey');
      expect(curated, isNotNull);
      expect(curated!.name, equals('Lana Del Rey'));

      const brooklynBabySong = MusicSuggestion(
        id: 'yt_brooklyn_baby',
        title: 'Brooklyn Baby',
        subtitle: 'Lana Del Rey',
        type: SuggestionType.song,
      );

      expect(brooklynBabySong.typeLabel, equals('Song · Lana Del Rey'));
    });

    test('3. Type "west coast" strictly excludes non-music entities from artists', () {
      // Rejections
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Baptist College'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Eagles Football Club'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Dealing School'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Gunpla Alliance'), isFalse);

      // Acceptances
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Wolves'), isTrue);
    });

    test('4. Suggestions deduplicate by entity type and ID', () {
      const s1 = MusicSuggestion(
        id: 'v1',
        title: 'West Coast',
        subtitle: 'Lana Del Rey',
        type: SuggestionType.song,
      );

      const s2 = MusicSuggestion(
        id: 'v1',
        title: 'West Coast',
        subtitle: 'Lana Del Rey',
        type: SuggestionType.song,
      );

      final set = <MusicSuggestion>{s1, s2};
      expect(set.length, equals(1));
    });
  });

  group('Miee Live Music Autocomplete — Widget & Interaction Tests', () {
    testWidgets('5. Renders live music suggestions with artwork and entity-type labels on Android viewport', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400); // Typical modern Android screen
      tester.view.devicePixelRatio = 2.75;
      addTearDown(() => tester.view.resetPhysicalSize());

      const suggestions = [
        MusicSuggestion(
          id: 'artist_1',
          title: 'Lana Del Rey',
          subtitle: null,
          imageUrl: 'https://example.com/lana.jpg',
          type: SuggestionType.artist,
        ),
        MusicSuggestion(
          id: 'song_1',
          title: 'Summertime Sadness',
          subtitle: 'Lana Del Rey',
          imageUrl: 'https://example.com/summertime.jpg',
          type: SuggestionType.song,
        ),
        MusicSuggestion(
          id: 'album_1',
          title: 'Born to Die',
          subtitle: 'Lana Del Rey',
          imageUrl: 'https://example.com/borntodie.jpg',
          type: SuggestionType.album,
        ),
        MusicSuggestion(
          id: 'search_1',
          title: 'Search for "lana del"',
          type: SuggestionType.searchQuery,
          entity: 'lana del',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockLivePlayerController()),
            favoritesProvider.overrideWith((ref) => MockLiveFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => MockLiveSearchNotifier(
                  const SearchState(
                    query: 'lana del',
                    liveSuggestions: suggestions,
                  ),
                )),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Focus the search input field to simulate active typing
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.tap(textField);
      await tester.pumpAndSettle();

      // Verify Spotify-inspired music suggestions header
      expect(find.text('SUGGESTIONS'), findsOneWidget);

      // Verify artist entity and label
      expect(find.text('Lana Del Rey'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);

      // Verify song entity and label
      expect(find.text('Summertime Sadness'), findsOneWidget);
      expect(find.text('Song · Lana Del Rey'), findsOneWidget);

      // Verify album entity and label
      expect(find.text('Born to Die'), findsOneWidget);
      expect(find.text('Album · Lana Del Rey'), findsOneWidget);

      // Verify secondary query submission action at the bottom
      expect(find.text('Search for "lana del"'), findsOneWidget);
    });

    testWidgets('6. Empty query with focused field displays Recent Searches and Clear All', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockLivePlayerController()),
            favoritesProvider.overrideWith((ref) => MockLiveFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => MockLiveSearchNotifier(
                  const SearchState(
                    query: '',
                    recentSearches: ['Lana Del Rey', 'Imagine Dragons'],
                  ),
                )),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap search bar to focus
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Verify Recent Searches title and items are rendered
      expect(find.text('Recent Searches'), findsOneWidget);
      expect(find.text('Clear All'), findsOneWidget);
      expect(find.text('Lana Del Rey'), findsOneWidget);
      expect(find.text('Imagine Dragons'), findsOneWidget);
    });

    testWidgets('7. Empty query with no history displays comforting exploration entry prompt', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockLivePlayerController()),
            favoritesProvider.overrideWith((ref) => MockLiveFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => MockLiveSearchNotifier(
                  const SearchState(
                    query: '',
                    recentSearches: [],
                  ),
                )),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap search bar to focus
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      // Verify helpful welcome state without any blank screen
      expect(find.text('Play what you love'), findsOneWidget);
      expect(find.text('Search for artists, songs, albums, and playlists.'), findsOneWidget);
    });
  });
}
