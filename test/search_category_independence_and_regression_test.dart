import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/domain/online_playlist.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/metadata/domain/musicbrainz_models.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/shared/models/track.dart';
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

class TestSearchNotifier extends StateNotifier<SearchState> implements SearchNotifier {
  TestSearchNotifier(super.state);

  @override
  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  @override
  void updateQuery(String query) {
    state = state.copyWith(query: query);
  }

  @override
  void searchNow(String query) {}

  @override
  Future<void> addHistory(String query) async {}

  @override
  Future<void> removeHistory(String query) async {}

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> enrichArtistsFromSongsForTesting(String query, List<YouTubeVideo> youtube) async {}
}

void main() {
  const sheAndHimSong = YouTubeVideo(
    id: 'mb_d0bc88a3-1cdd-49e3-aa4d-ca8d13bb2950',
    title: 'I Thought I Saw Your Face Today',
    channelTitle: 'She & Him',
    thumbnailUrl: '',
    duration: '2:50',
    viewCount: 'MusicBrainz Verified',
    canonicalTitle: 'I Thought I Saw Your Face Today',
    canonicalArtist: 'She & Him',
    metadataProvider: 'musicbrainz',
    metadataIdentifier: 'd0bc88a3-1cdd-49e3-aa4d-ca8d13bb2950',
  );

  final samplePlaylists = List.generate(
    18,
    (i) => OnlinePlaylist(
      id: 'PL$i',
      title: 'Playlist #$i: Indie Classics',
      author: 'Curator $i',
      thumbnailUrl: '',
      trackCount: 25,
    ),
  );

  List<Override> commonOverrides(SearchState state) => [
        playerControllerProvider.overrideWith((ref) => MockPlayerController()),
        favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
        songsProvider.overrideWith((ref) => []),
        artistsProvider.overrideWith((ref) => []),
        albumsProvider.overrideWith((ref) => []),
        searchNotifierProvider.overrideWith((ref) => TestSearchNotifier(state)),
        resolvedArtworkProvider.overrideWith((ref, query) async {
          return ResolvedArtwork(
            imageUrl: query.fallbackThumbnailUrl ?? '',
            source: ArtworkSource.neutralFallback,
            confidence: 0.5,
            resolvedAt: DateTime.now(),
          );
        }),
      ];

  group('Miee — Critical Search Regression: Category Independence Tests', () {
    testWidgets('1. All tab displays Songs skeleton and does NOT hide songs when playlists arrive first', (tester) async {
      // Simulate the exact race: playlistsTask completed with 18 items, but ytTask is still loading
      final raceState = SearchState(
        query: 'I Thought I Saw Your Face Today',
        activeFilter: 'All',
        onlinePlaylists: samplePlaylists,
        isPlaylistsLoading: false,
        youtubeResults: const [],
        isYouTubeLoading: true,
        onlineArtists: const [],
        isArtistsLoading: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides(raceState),
          child: const MaterialApp(home: SearchPage()),
        ),
      );

      await tester.pump();

      // Songs section MUST be visible and indicate searching, NOT missing!
      expect(find.text('SEARCHING SONGS...'), findsOneWidget);

      // Playlists section is also visible with 18 found
      expect(find.text('Playlists'), findsWidgets);
      expect(find.text('18 found'), findsOneWidget);
    });

    testWidgets('2. All tab displays matching songs and playlists simultaneously when both loaded', (tester) async {
      final loadedState = SearchState(
        query: 'I Thought I Saw Your Face Today',
        activeFilter: 'All',
        onlinePlaylists: samplePlaylists,
        isPlaylistsLoading: false,
        youtubeResults: const [sheAndHimSong],
        isYouTubeLoading: false,
        onlineArtists: const [ArtistModel(id: 'she_and_him', name: 'She & Him', imageUrl: '')],
        isArtistsLoading: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides(loadedState),
          child: const MaterialApp(home: SearchPage()),
        ),
      );

      await tester.pump();

      // Both Songs and Playlists appear simultaneously
      expect(find.text('I Thought I Saw Your Face Today'), findsWidgets);
      expect(find.text('She & Him'), findsWidgets);
      expect(find.text('Playlists'), findsWidgets);
      expect(find.text('18 found'), findsOneWidget);
    });

    testWidgets('3. Songs tab displays loading skeleton when isYouTubeLoading is true and playlists finished', (tester) async {
      final raceState = SearchState(
        query: 'I Thought I Saw Your Face Today',
        activeFilter: 'Songs',
        onlinePlaylists: samplePlaylists,
        isPlaylistsLoading: false,
        youtubeResults: const [],
        isYouTubeLoading: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides(raceState),
          child: const MaterialApp(home: SearchPage()),
        ),
      );

      await tester.pump();

      // Songs tab displays Songs searching skeleton, never empty or blank!
      expect(find.text('SEARCHING SONGS...'), findsOneWidget);
      expect(find.text('No songs found'), findsNothing);
    });

    testWidgets('4. Songs tab displays matching songs independently of All tab', (tester) async {
      final songsTabState = SearchState(
        query: 'I Thought I Saw Your Face Today',
        activeFilter: 'Songs',
        onlinePlaylists: samplePlaylists,
        isPlaylistsLoading: false,
        youtubeResults: const [sheAndHimSong],
        isYouTubeLoading: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides(songsTabState),
          child: const MaterialApp(home: SearchPage()),
        ),
      );

      await tester.pump();

      expect(find.text('1 FOUND'), findsOneWidget);
      expect(find.text('I Thought I Saw Your Face Today'), findsWidgets);
      // Playlists section is NOT rendered in Songs tab
      expect(find.text('18 found'), findsNothing);
    });

    test('5. MusicBrainzRecording correctly maps to canonical YouTubeVideo with She & Him', () {
      final recording = MusicBrainzRecording(
        mbid: 'd0bc88a3-1cdd-49e3-aa4d-ca8d13bb2950',
        title: 'I Thought I Saw Your Face Today',
        artistCredit: 'She & Him',
        primaryArtist: 'She & Him',
        albumTitle: 'Volume One',
        durationMs: 170000,
        score: 100,
      );

      final video = YouTubeVideo.fromMusicBrainzRecording(recording);

      expect(video.metadataProvider, 'musicbrainz');
      expect(video.canonicalTitle, 'I Thought I Saw Your Face Today');
      expect(video.canonicalArtist, 'She & Him');
      expect(video.duration, '2:50');
      expect(video.albumName, 'Volume One');
      expect(video.id, 'mb_d0bc88a3-1cdd-49e3-aa4d-ca8d13bb2950');
    });

    test('6. SearchState category independence: results from one category cannot overwrite another', () {
      var state = const SearchState(query: 'test');

      // Populate playlists first
      state = state.copyWith(onlinePlaylists: samplePlaylists, isPlaylistsLoading: false);
      expect(state.onlinePlaylists.length, 18);
      expect(state.youtubeResults.isEmpty, isTrue);

      // Populate songs second
      state = state.copyWith(youtubeResults: [sheAndHimSong], isYouTubeLoading: false);
      expect(state.onlinePlaylists.length, 18);
      expect(state.youtubeResults.length, 1);
      expect(state.totalSongsCount, 1);
      expect(state.totalPlaylistsCount, 18);
    });

    test('7. Artist candidate extraction preserves full band names like "She & Him"', () {
      const video = sheAndHimSong;
      final candidateNames = <String>[];
      final artistName = (video.canonicalArtist ?? video.channelTitle).trim();

      if (!candidateNames.contains(artistName)) {
        candidateNames.add(artistName);
      }
      final parts = artistName.split(
        RegExp(r'\s*(&|,|\bft\.?\b|\bfeat\.?\b)\s*', caseSensitive: false),
      );
      for (final part in parts) {
        final p = part.trim();
        if (p.isNotEmpty && !candidateNames.contains(p)) {
          candidateNames.add(p);
        }
      }

      // First candidate MUST be the full band name "She & Him"
      expect(candidateNames.first, 'She & Him');
      expect(candidateNames.contains('She'), isTrue);
      expect(candidateNames.contains('Him'), isTrue);
    });
  });
}
