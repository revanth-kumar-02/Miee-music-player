import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/queue/presentation/queue_page.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

/// Test Spy for PlayerController tracking calls to play, pause, togglePlayPause, and next.
class FakeQueuePlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  int playCallCount = 0;
  int pauseCallCount = 0;
  int togglePlayPauseCallCount = 0;
  int nextCallCount = 0;
  final QueueManager queueManager;

  FakeQueuePlayerController(this.queueManager, [PlaybackState? initialState])
      : super(initialState ?? PlaybackState.initial());

  @override
  Future<void> play() async {
    playCallCount++;
    state = state.copyWith(status: PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    state = state.copyWith(status: PlaybackStatus.paused);
  }

  @override
  Future<void> togglePlayPause() async {
    togglePlayPauseCallCount++;
    if (state.status == PlaybackStatus.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> next() async {
    nextCallCount++;
    final nextTrack = queueManager.next();
    if (nextTrack != null) {
      state = state.copyWith(
        currentTrack: nextTrack,
        status: PlaybackStatus.playing,
      );
    } else if (state.repeatMode == RepeatMode.all && queueManager.queue.isNotEmpty) {
      queueManager.setIndex(0);
      state = state.copyWith(
        currentTrack: queueManager.currentTrack,
        status: PlaybackStatus.playing,
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Queue Sheet Now Playing Controls — Unit & Logic Tests', () {
    late QueueManager queueManager;
    late List<Track> testTracks;

    setUp(() {
      queueManager = QueueManager();
      testTracks = List.generate(
        4,
        (i) => Track(
          id: 'track_$i',
          title: 'Track Title $i',
          artist: 'Artist $i',
          imageUrl: 'https://example.com/art_$i.jpg',
          duration: '3:3$i',
        ),
      );
      queueManager.setQueue(testTracks, startIndex: 0);
    });

    test('togglePlayPause pauses when actively playing', () async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.playing,
        ),
      );

      expect(controller.state.status, equals(PlaybackStatus.playing));
      await controller.togglePlayPause();

      expect(controller.togglePlayPauseCallCount, equals(1));
      expect(controller.pauseCallCount, equals(1));
      expect(controller.playCallCount, equals(0));
      expect(controller.state.status, equals(PlaybackStatus.paused));
    });

    test('togglePlayPause plays when paused or idle', () async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.paused,
        ),
      );

      expect(controller.state.status, equals(PlaybackStatus.paused));
      await controller.togglePlayPause();

      expect(controller.togglePlayPauseCallCount, equals(1));
      expect(controller.playCallCount, equals(1));
      expect(controller.pauseCallCount, equals(0));
      expect(controller.state.status, equals(PlaybackStatus.playing));
    });

    test('Control toggles cleanly across state changes', () async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.paused,
        ),
      );

      // 1. Paused -> Play
      await controller.togglePlayPause();
      expect(controller.state.status, equals(PlaybackStatus.playing));

      // 2. Playing -> Pause
      await controller.togglePlayPause();
      expect(controller.state.status, equals(PlaybackStatus.paused));

      // 3. Paused -> Play
      await controller.togglePlayPause();
      expect(controller.state.status, equals(PlaybackStatus.playing));

      expect(controller.togglePlayPauseCallCount, equals(3));
      expect(controller.playCallCount, equals(2));
      expect(controller.pauseCallCount, equals(1));
    });

    test('Next invokes queue-aware skip and updates active track', () async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.playing,
        ),
      );

      expect(controller.state.currentTrack?.id, equals('track_0'));
      expect(queueManager.currentIndex, equals(0));

      // Skip to next track
      await controller.next();

      expect(controller.nextCallCount, equals(1));
      expect(queueManager.currentIndex, equals(1));
      expect(controller.state.currentTrack?.id, equals('track_1'));

      // Skip to next track again
      await controller.next();

      expect(controller.nextCallCount, equals(2));
      expect(queueManager.currentIndex, equals(2));
      expect(controller.state.currentTrack?.id, equals('track_2'));
    });

    test('Next respects RepeatMode.all wrap-around at end of queue', () async {
      queueManager.setIndex(3); // Last track
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[3],
          status: PlaybackStatus.playing,
          repeatMode: RepeatMode.all,
        ),
      );

      await controller.next();

      expect(controller.nextCallCount, equals(1));
      expect(queueManager.currentIndex, equals(0));
      expect(controller.state.currentTrack?.id, equals('track_0'));
    });

    test('Empty queue handles next and play/pause safely without error', () async {
      final emptyQueueManager = QueueManager();
      final controller = FakeQueuePlayerController(
        emptyQueueManager,
        PlaybackState.initial(),
      );

      // Should not throw or crash
      await controller.next();
      expect(controller.nextCallCount, equals(1));
      expect(controller.state.currentTrack, isNull);

      await controller.togglePlayPause();
      expect(controller.togglePlayPauseCallCount, equals(1));
    });
  });

  group('Queue Sheet Now Playing Controls — Widget Integration', () {
    late QueueManager queueManager;
    late List<Track> testTracks;

    setUp(() {
      queueManager = QueueManager();
      testTracks = [
        const Track(
          id: 'track_alpha',
          title: 'Starboy',
          artist: 'The Weeknd',
          imageUrl: 'https://example.com/starboy.jpg',
          duration: '3:50',
        ),
        const Track(
          id: 'track_beta',
          title: 'Blinding Lights',
          artist: 'The Weeknd',
          imageUrl: 'https://example.com/blinding.jpg',
          duration: '3:20',
        ),
      ];
      queueManager.setQueue(testTracks, startIndex: 0);
    });

    testWidgets('Renders Now Playing card with play button when playing is false', (tester) async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.paused,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
            queueManagerProvider.overrideWithValue(queueManager),
          ],
          child: const MaterialApp(
            home: QueuePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Now Playing section header
      expect(find.text('Now Playing'), findsOneWidget);
      expect(find.text('Starboy'), findsWidgets);
      expect(find.text('The Weeknd'), findsWidgets);

      // Shows play icon when paused
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsNothing);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
    });

    testWidgets('Tapping play button triggers controller.togglePlayPause()', (tester) async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.paused,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
            queueManagerProvider.overrideWithValue(queueManager),
          ],
          child: const MaterialApp(
            home: QueuePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final playButton = find.byIcon(Icons.play_circle_fill_rounded);
      expect(playButton, findsOneWidget);

      await tester.tap(playButton);
      await tester.pumpAndSettle();

      expect(controller.togglePlayPauseCallCount, equals(1));
      expect(controller.playCallCount, equals(1));
    });

    testWidgets('Renders pause icon when actively playing and pauses on tap', (tester) async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.playing,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
            queueManagerProvider.overrideWithValue(queueManager),
          ],
          child: const MaterialApp(
            home: QueuePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Shows pause icon when actively playing
      final pauseButton = find.byIcon(Icons.pause_circle_filled_rounded);
      expect(pauseButton, findsOneWidget);

      await tester.tap(pauseButton);
      await tester.pumpAndSettle();

      expect(controller.togglePlayPauseCallCount, equals(1));
      expect(controller.pauseCallCount, equals(1));
    });

    testWidgets('Tapping next button triggers controller.next()', (tester) async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.playing,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
            queueManagerProvider.overrideWithValue(queueManager),
          ],
          child: const MaterialApp(
            home: QueuePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final nextButton = find.byIcon(Icons.skip_next_rounded);
      expect(nextButton, findsOneWidget);

      await tester.tap(nextButton);
      await tester.pumpAndSettle();

      expect(controller.nextCallCount, equals(1));
      expect(queueManager.currentIndex, equals(1));
    });

    testWidgets('Does not render Now Playing header when currentTrack is null', (tester) async {
      final emptyQueueManager = QueueManager();
      final controller = FakeQueuePlayerController(
        emptyQueueManager,
        PlaybackState.initial(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
            queueManagerProvider.overrideWithValue(emptyQueueManager),
          ],
          child: const MaterialApp(
            home: QueuePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Now Playing spotlight section header should not be present
      expect(find.text('Now Playing'), findsNothing);
      expect(find.byIcon(Icons.play_circle_fill_rounded), findsNothing);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsNothing);
    });

    testWidgets('Tapping Now Playing tile body navigates to player or pops modal', (tester) async {
      final controller = FakeQueuePlayerController(
        queueManager,
        PlaybackState.initial().copyWith(
          currentTrack: testTracks[0],
          status: PlaybackStatus.playing,
        ),
      );

      bool popped = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
            queueManagerProvider.overrideWithValue(queueManager),
          ],
          child: MaterialApp(
            home: Navigator(
              onPopPage: (route, result) {
                popped = true;
                return route.didPop(result);
              },
              pages: const [
                MaterialPage(child: Scaffold(body: Text('Previous Page'))),
                MaterialPage(child: QueuePage()),
              ],
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Find the Now Playing spotlight tile by Starboy title
      final starboyTile = find.text('Starboy');
      expect(starboyTile, findsWidgets);

      await tester.tap(starboyTile.first);
      await tester.pumpAndSettle();

      expect(popped, isTrue);
    });
  });
}
