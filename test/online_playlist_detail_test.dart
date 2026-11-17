import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/playlists/presentation/online_playlist_detail_page.dart';
import 'package:Miee/features/search/domain/online_playlist.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/providers/youtube_providers.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';

class MockPlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  MockPlayerController() : super(PlaybackState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockYouTubeRepository extends YouTubeRepository {
  final List<YouTubeVideo> playlistVideos;

  MockYouTubeRepository({this.playlistVideos = const []});

  @override
  Future<List<YouTubeVideo>> getPlaylistVideos(String playlistId, {int limit = 50}) async {
    return playlistVideos;
  }
}

void main() {
  const samplePlaylist = OnlinePlaylist(
    id: 'PLVht12Lpqfkg',
    title: 'OM All Songs Tamil',
    author: 'Sai Abhyankkar',
    thumbnailUrl: 'https://i.ytimg.com/vi/sample/hqdefault.jpg',
    trackCount: 3,
  );

  final sampleVideos = [
    const YouTubeVideo(
      id: 'vid1',
      title: 'Alaakaa Loova',
      channelTitle: 'Sai Abhyankkar',
      thumbnailUrl: 'https://i.ytimg.com/vi/vid1/hqdefault.jpg',
      duration: '3:37',
      viewCount: '1M',
    ),
    const YouTubeVideo(
      id: 'vid2',
      title: 'Veezha Veera',
      channelTitle: 'Divo Music',
      thumbnailUrl: 'https://i.ytimg.com/vi/vid2/hqdefault.jpg',
      duration: '3:59',
      viewCount: '2M',
    ),
    const YouTubeVideo(
      id: 'vid3',
      title: 'FA FA FA',
      channelTitle: 'Sai Abhyankkar',
      thumbnailUrl: 'https://i.ytimg.com/vi/vid3/hqdefault.jpg',
      duration: '3:05',
      viewCount: '500K',
    ),
  ];

  testWidgets('OnlinePlaylistDetailPage renders playlist header and tracks accurately', (tester) async {
    final mockRepo = MockYouTubeRepository(playlistVideos: sampleVideos);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          youtubeRepositoryProvider.overrideWithValue(mockRepo),
          playerControllerProvider.overrideWith((ref) => MockPlayerController()),
        ],
        child: const MaterialApp(
          home: OnlinePlaylistDetailPage(
            playlistId: 'PLVht12Lpqfkg',
            initialPlaylist: samplePlaylist,
          ),
        ),
      ),
    );

    // Initial pump
    await tester.pump();
    // Finish async loading
    await tester.pumpAndSettle();

    // Verify header metadata
    expect(find.text('OM All Songs Tamil'), findsOneWidget);
    expect(find.text('Sai Abhyankkar'), findsNWidgets(3));
    expect(find.text(' · 3 tracks'), findsOneWidget);

    // Verify action buttons
    expect(find.text('Play All'), findsOneWidget);
    expect(find.text('Shuffle'), findsOneWidget);

    // Verify tracks list
    expect(find.text('Alaakaa Loova'), findsOneWidget);
    expect(find.text('Veezha Veera'), findsOneWidget);
    expect(find.text('FA FA FA'), findsOneWidget);
    expect(find.text('3:37'), findsOneWidget);
    expect(find.text('3:59'), findsOneWidget);
    expect(find.text('3:05'), findsOneWidget);
  });
}
