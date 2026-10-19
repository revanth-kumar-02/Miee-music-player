import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/presentation/widgets/youtube_result_tile.dart';
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

void main() {
  testWidgets('SearchPage renders YouTube results when search returns items', (WidgetTester tester) async {
    const testVideo = YouTubeVideo(
      id: '7wtfhZwyrcc',
      title: 'Believer',
      channelTitle: 'Imagine Dragons',
      thumbnailUrl: 'https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg',
      duration: '3:24',
      viewCount: '2.5B views',
    );

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
                  query: 'Imagine Dragons Believer',
                  isYouTubeLoading: false,
                  youtubeResults: [testVideo],
                ),
              )),
        ],
        child: const MaterialApp(
          home: SearchPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify 'Songs' section header and count are rendered
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data == 'Songs' && (w.style?.fontSize ?? 0) >= 18,
      ),
      findsOneWidget,
    );
    expect(find.text('1 FOUND'), findsOneWidget);

    // Verify song title and artist from YouTube result tile are rendered
    expect(find.widgetWithText(YouTubeResultTile, 'Believer'), findsOneWidget);
    expect(find.text('Imagine Dragons · 2.5B views'), findsOneWidget);
  });

  testWidgets('SearchPage renders distinct error container when YouTube search fails', (WidgetTester tester) async {
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
                  query: 'Imagine Dragons Believer',
                  isYouTubeLoading: false,
                  errorMessage: 'No internet connection. Please check your network and try again.',
                ),
              )),
        ],
        child: const MaterialApp(
          home: SearchPage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify error state is rendered with error message and icon
    expect(find.text('No internet connection. Please check your network and try again.'), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_outlined), findsOneWidget);
  });
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
