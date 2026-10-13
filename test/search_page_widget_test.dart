import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';

class MockPlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  MockPlayerController() : super(PlaybackState.initial());

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

    // Verify 'YouTube' section header is rendered
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text('1 FOUND'), findsOneWidget);

    // Verify song title and artist from YouTube result tile are rendered
    expect(find.text('Believer'), findsOneWidget);
    expect(find.text('Imagine Dragons · 2.5B views'), findsOneWidget);
  });

  testWidgets('SearchPage renders distinct error container when YouTube search fails', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
