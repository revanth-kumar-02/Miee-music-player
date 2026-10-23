import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/app/theme/app_colors.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/presentation/widgets/youtube_result_tile.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/mini_player.dart';

/// Test controller to simulate and test playback state transitions
class MockPlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  int playTrackCallCount = 0;
  MusicItem? lastTrackRequested;
  int _token = 0;

  MockPlayerController([PlaybackState? initial])
      : super(initial ?? PlaybackState.initial());

  @override
  Future<void> playTrack(MusicItem track, {String? playingFrom}) async {
    // 1. Debounce duplicate in-flight requests for the same track
    if (state.status == PlaybackStatus.loading &&
        state.loadingTrackId != null &&
        isSameTrackId(state.loadingTrackId, track.id)) {
      return;
    }

    final token = ++_token;
    playTrackCallCount++;
    lastTrackRequested = track;

    final isOnline = track.isYoutube;

    // Immediately update UI state with loading
    state = state.copyWith(
      status: PlaybackStatus.loading,
      currentTrack: track,
      loadingTrackId: isOnline ? track.id : null,
      clearLoadingTrackId: !isOnline,
      position: Duration.zero,
      playingFrom: playingFrom ?? state.playingFrom,
      clearErrorMessage: true,
    );
  }

  void simulateReady({bool isPlaying = true}) {
    state = state.copyWith(
      status: isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      clearLoadingTrackId: true,
      clearErrorMessage: true,
    );
  }

  void simulateError(String errorMsg, {int? token}) {
    if (token != null && token != _token) return; // Ignore stale request
    state = state.copyWith(
      status: PlaybackStatus.error,
      errorMessage: errorMsg,
      clearLoadingTrackId: true,
    );
  }

  void simulateStaleCompletion(int oldToken, MusicItem staleTrack) {
    if (oldToken != _token) return; // Stale protection
    state = state.copyWith(
      status: PlaybackStatus.playing,
      currentTrack: staleTrack,
      clearLoadingTrackId: true,
    );
  }

  int get currentToken => _token;

  @override
  Future<void> pause() async {
    state = state.copyWith(
      status: PlaybackStatus.paused,
      clearLoadingTrackId: true,
    );
  }

  @override
  Future<void> stop() async {
    state = state.copyWith(
      status: PlaybackStatus.idle,
      position: Duration.zero,
      clearLoadingTrackId: true,
    );
  }

  @override
  void selectTrack(MusicItem track, List<MusicItem> currentList,
      {String? playingFrom}) {
    playTrack(track, playingFrom: playingFrom);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('1. PlaybackState & ID Normalization Unit Tests', () {
    test('isSameTrackId handles raw and prefixed YouTube IDs correctly', () {
      expect(isSameTrackId('dQw4w9WgXcQ', 'youtube_dQw4w9WgXcQ'), isTrue);
      expect(isSameTrackId('youtube_dQw4w9WgXcQ', 'dQw4w9WgXcQ'), isTrue);
      expect(isSameTrackId('dQw4w9WgXcQ', 'dQw4w9WgXcQ'), isTrue);
      expect(isSameTrackId('youtube_abc', 'youtube_xyz'), isFalse);
      expect(isSameTrackId('local_123', 'local_123'), isTrue);
      expect(isSameTrackId('local_123', 'local_456'), isFalse);
      expect(isSameTrackId(null, 'dQw4w9WgXcQ'), isFalse);
      expect(isSameTrackId('dQw4w9WgXcQ', null), isFalse);
    });

    test('PlaybackState copyWith sets and clears loadingTrackId cleanly', () {
      final initial = PlaybackState.initial();
      expect(initial.loadingTrackId, isNull);

      final loadingState = initial.copyWith(
        status: PlaybackStatus.loading,
        loadingTrackId: 'youtube_abc123',
      );
      expect(loadingState.loadingTrackId, equals('youtube_abc123'));
      expect(loadingState.status, equals(PlaybackStatus.loading));

      // Clearing loading track id
      final clearedState = loadingState.copyWith(
        status: PlaybackStatus.playing,
        clearLoadingTrackId: true,
      );
      expect(clearedState.loadingTrackId, isNull);
      expect(clearedState.status, equals(PlaybackStatus.playing));
    });
  });

  group('2. Online Playback Loading Lifecycle & Debounce Tests', () {
    late MockPlayerController controller;

    setUp(() {
      controller = MockPlayerController();
    });

    test('Selecting an online track immediately sets loadingTrackId and status', () async {
      const onlineTrack = Track(
        id: 'youtube_video_1',
        title: 'Online Song 1',
        artist: 'Artist 1',
        imageUrl: '',
        duration: '3:30',
        filePath: 'https://youtube.com/watch?v=video_1',
      );

      await controller.playTrack(onlineTrack);

      expect(controller.state.status, equals(PlaybackStatus.loading));
      expect(controller.state.loadingTrackId, equals('youtube_video_1'));
      expect(controller.playTrackCallCount, equals(1));
    });

    test('Local track does NOT enter online-resolution loading state', () async {
      const localTrack = Track(
        id: 'local_track_1',
        title: 'Local Song 1',
        artist: 'Artist 1',
        imageUrl: '',
        duration: '3:30',
        filePath: '/storage/emulated/0/Music/song.mp3',
      );

      await controller.playTrack(localTrack);

      // Local tracks should not set loadingTrackId
      expect(controller.state.loadingTrackId, isNull);
    });

    test('Rapid taps for the same in-flight track do NOT create duplicate requests', () async {
      const onlineTrack = Track(
        id: 'youtube_video_rapid',
        title: 'Rapid Tap Song',
        artist: 'Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=video_rapid',
      );

      // Tap 1
      await controller.playTrack(onlineTrack);
      expect(controller.playTrackCallCount, equals(1));

      // Tap 2 (in-flight)
      await controller.playTrack(onlineTrack);
      expect(controller.playTrackCallCount, equals(1)); // Debounced!

      // Tap 3 with raw ID (without youtube_ prefix)
      const rawTrack = Track(
        id: 'video_rapid',
        title: 'Rapid Tap Song',
        artist: 'Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=video_rapid',
      );
      await controller.playTrack(rawTrack);
      expect(controller.playTrackCallCount, equals(1)); // Still debounced!
    });

    test('Selecting another track updates loadingTrackId immediately to new track', () async {
      const songA = Track(
        id: 'youtube_song_a',
        title: 'Song A',
        artist: 'Artist A',
        imageUrl: '',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=song_a',
      );
      const songB = Track(
        id: 'youtube_song_b',
        title: 'Song B',
        artist: 'Artist B',
        imageUrl: '',
        duration: '4:00',
        filePath: 'https://youtube.com/watch?v=song_b',
      );

      await controller.playTrack(songA);
      expect(controller.state.loadingTrackId, equals('youtube_song_a'));

      // Tap song B while song A is loading
      await controller.playTrack(songB);
      expect(controller.state.loadingTrackId, equals('youtube_song_b'));
      expect(controller.state.currentTrack?.id, equals('youtube_song_b'));
    });

    test('Stale request from earlier token cannot overwrite current track state', () async {
      const songA = Track(
        id: 'youtube_song_a',
        title: 'Song A',
        artist: 'Artist A',
        imageUrl: '',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=song_a',
      );
      const songB = Track(
        id: 'youtube_song_b',
        title: 'Song B',
        artist: 'Artist B',
        imageUrl: '',
        duration: '4:00',
        filePath: 'https://youtube.com/watch?v=song_b',
      );

      await controller.playTrack(songA);
      final tokenA = controller.currentToken;

      await controller.playTrack(songB);

      // Now song A completes late
      controller.simulateStaleCompletion(tokenA, songA);

      // Current track must still be song B, not superseded by song A
      expect(controller.state.currentTrack?.id, equals('youtube_song_b'));
      expect(controller.state.loadingTrackId, equals('youtube_song_b'));
    });

    test('Playback or resolution failure clears loadingTrackId and surfaces error', () async {
      const song = Track(
        id: 'youtube_failing_track',
        title: 'Broken Stream',
        artist: 'Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=failing_track',
      );

      await controller.playTrack(song);
      expect(controller.state.loadingTrackId, equals('youtube_failing_track'));

      // Error occurs
      controller.simulateError('Failed to extract audio stream');

      expect(controller.state.loadingTrackId, isNull);
      expect(controller.state.status, equals(PlaybackStatus.error));
      expect(controller.state.errorMessage, equals('Failed to extract audio stream'));
    });

    test('Player reaching ready state clears loadingTrackId and becomes playing', () async {
      const song = Track(
        id: 'youtube_success_track',
        title: 'Success Stream',
        artist: 'Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=success_track',
      );

      await controller.playTrack(song);
      expect(controller.state.loadingTrackId, equals('youtube_success_track'));

      controller.simulateReady(isPlaying: true);

      expect(controller.state.loadingTrackId, isNull);
      expect(controller.state.status, equals(PlaybackStatus.playing));
    });

    test('Stop or pause clears loadingTrackId', () async {
      const song = Track(
        id: 'youtube_track_stop',
        title: 'Stop Test',
        artist: 'Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: 'https://youtube.com/watch?v=stop_track',
      );

      await controller.playTrack(song);
      expect(controller.state.loadingTrackId, isNotNull);

      await controller.stop();
      expect(controller.state.loadingTrackId, isNull);
      expect(controller.state.status, equals(PlaybackStatus.idle));
    });
  });

  group('3. YouTubeResultTile Per-Track Loading Widget Tests', () {
    testWidgets('Only the selected track shows CircularProgressIndicator in play button',
        (tester) async {
      final videoA = YouTubeVideo(
        id: 'video_aaa',
        title: 'Song AAA',
        channelTitle: 'Channel A',
        duration: '3:20',
        viewCount: '1.2M',
        thumbnailUrl: '',
      );
      final videoB = YouTubeVideo(
        id: 'video_bbb',
        title: 'Song BBB',
        channelTitle: 'Channel B',
        duration: '4:10',
        viewCount: '500K',
        thumbnailUrl: '',
      );

      // State where videoA is resolving/loading
      final controller = MockPlayerController(
        PlaybackState.initial().copyWith(
          status: PlaybackStatus.loading,
          loadingTrackId: 'youtube_video_aaa',
          currentTrack: videoA.toTrack(),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  YouTubeResultTile(video: videoA),
                  YouTubeResultTile(video: videoB),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Exactly ONE CircularProgressIndicator should be visible (on videoA)
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // videoB should display the standard play icon
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    });

    testWidgets('Tapping a track in-flight does not trigger duplicate resolution',
        (tester) async {
      final video = YouTubeVideo(
        id: 'video_tap_test',
        title: 'Tap Song',
        channelTitle: 'Channel',
        duration: '3:00',
        viewCount: '250K',
        thumbnailUrl: '',
      );

      final controller = MockPlayerController(
        PlaybackState.initial().copyWith(
          status: PlaybackStatus.loading,
          loadingTrackId: 'youtube_video_tap_test',
          currentTrack: video.toTrack(),
        ),
      );

      int tapCallbackCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YouTubeResultTile(
                video: video,
                onTap: () {
                  tapCallbackCount++;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // The play IconButton should have onPressed == null while loading
      final iconButton = tester.widget<IconButton>(
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == 'Loading'),
      );
      expect(iconButton.onPressed, isNull);

      // Tap on the tile itself
      await tester.tap(find.byType(YouTubeResultTile));
      await tester.pump();

      // Tap callback was safely ignored because track is loading
      expect(tapCallbackCount, equals(0));
    });

    testWidgets('Spinner transitions to pause icon when playback begins',
        (tester) async {
      final video = YouTubeVideo(
        id: 'video_lifecycle',
        title: 'Lifecycle Song',
        channelTitle: 'Channel',
        duration: '3:00',
        viewCount: '780K',
        thumbnailUrl: '',
      );

      final controller = MockPlayerController(
        PlaybackState.initial().copyWith(
          status: PlaybackStatus.loading,
          loadingTrackId: 'youtube_video_lifecycle',
          currentTrack: video.toTrack(),
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: YouTubeResultTile(video: video),
            ),
          ),
        ),
      );

      await tester.pump();

      // Initially loading
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Player becomes ready and begins playing
      controller.simulateReady(isPlaying: true);
      await tester.pump();

      // Loading spinner gone, pause icon displayed
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);

      // Player pauses
      await controller.pause();
      await tester.pump();

      // Pause icon becomes play icon
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
    });
  });

  group('4. MiniPlayer Loading Widget Tests', () {
    testWidgets('MiniPlayer displays spinner when isLoading is true',
        (tester) async {
      const track = Track(
        id: 'youtube_mini_test',
        title: 'Mini Test Song',
        artist: 'Artist',
        imageUrl: '',
        duration: '3:00',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MiniPlayer(
              musicItem: track,
              progress: 0.0,
              isPlaying: false,
              isLoading: true,
              onPlayPauseTap: () {},
            ),
          ),
        ),
      );

      await tester.pump();

      // CircularProgressIndicator rendered inside FAB
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsNothing);
      expect(find.byIcon(Icons.pause), findsNothing);
    });
  });
}
