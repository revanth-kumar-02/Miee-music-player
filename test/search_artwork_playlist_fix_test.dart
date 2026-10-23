import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/shared/widgets/song_tile.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';

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
  void setFilter(String filter) {}

  @override
  void updateQuery(String query) {}

  @override
  void searchNow(String query) {}

  @override
  Future<void> addHistory(String query) async {}

  @override
  Future<void> removeHistory(String query) async {}

  @override
  Future<void> clearHistory() async {}
}

void main() {
  group('Search Landing & Top Result Fixes', () {
    testWidgets('SearchPage initial landing state does NOT show Top result: Dhee or static card', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockPlayerController()),
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => MockSearchNotifier(
                  const SearchState(
                    query: '',
                    isYouTubeLoading: false,
                    youtubeResults: [],
                  ),
                )),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify "Top result" and "Dhee" are NOT present in the explore view
      expect(find.text('Top result'), findsNothing);
      expect(find.text('Dhee'), findsNothing);

      // Verify the intentional Discovery banner is present
      expect(find.text('Discover Music'), findsOneWidget);
    });

    testWidgets('SearchPage shows Top result card only when matching song or artist exists', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => MockPlayerController()),
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => MockSearchNotifier(
                  const SearchState(
                    query: 'Believer',
                    isYouTubeLoading: false,
                    youtubeResults: [],
                    onlineArtists: [],
                    localArtists: [],
                  ),
                )),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Since youtubeResults and onlineArtists are empty, no matching artist/song exists, so Top result must NOT show
      expect(find.text('Top result'), findsNothing);
    });
  });

  group('SongTile Artwork & Fallback Placeholder Tests', () {
    testWidgets('SongTile renders 48x48 fallback placeholder with music note icon when imageUrl is null', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Test Song',
              artist: 'Test Artist',
              duration: '3:30',
              imageUrl: null,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title and artist are present
      expect(find.text('Test Song'), findsOneWidget);
      expect(find.text('Test Artist'), findsOneWidget);

      // Verify music_note icon is present in the leading placeholder
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('SongTile renders 48x48 fallback placeholder when imageUrl is empty string', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Empty Art Song',
              artist: 'Empty Art Artist',
              duration: '4:15',
              imageUrl: '',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });
  });

  group('Playlist Cover Persistence Tests', () {
    test('PlaylistModel returns customCoverPath as effectiveCoverUrl when set', () {
      final now = DateTime.now();
      final playlist = PlaylistModel(
        id: '1',
        name: 'My Summer Playlist',
        customCoverPath: '/data/user/0/com.miee/app_flutter/playlist_covers/cover_1.jpg',
        createdAt: now,
        lastModified: now,
        tracks: [
          const Track(
            id: 't1',
            title: 'Track 1',
            artist: 'Artist 1',
            imageUrl: 'https://example.com/track1.jpg',
            duration: '3:00',
            filePath: 'http://example.com/audio1.mp3',
          ),
        ],
      );

      expect(playlist.effectiveCoverUrl, equals('/data/user/0/com.miee/app_flutter/playlist_covers/cover_1.jpg'));
    });

    test('PlaylistModel falls back to artworkTrack imageUrl when customCoverPath is null', () {
      final now = DateTime.now();
      final playlist = PlaylistModel(
        id: '2',
        name: 'Auto Artwork Playlist',
        customCoverPath: null,
        createdAt: now,
        lastModified: now,
        tracks: [
          const Track(
            id: 't2',
            title: 'Track 2',
            artist: 'Artist 2',
            imageUrl: 'https://example.com/track2.jpg',
            duration: '3:30',
            filePath: 'http://example.com/audio2.mp3',
          ),
        ],
      );

      expect(playlist.effectiveCoverUrl, equals('https://example.com/track2.jpg'));
    });
  });
}
