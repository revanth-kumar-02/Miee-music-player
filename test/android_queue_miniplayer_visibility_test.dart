import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/player/presentation/player_page.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/queue/presentation/queue_page.dart';
import 'package:Miee/features/rooms/providers/room_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/main_app_shell.dart';
import 'package:Miee/shared/widgets/mini_player.dart';

class TestPlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  int playCalls = 0;
  int pauseCalls = 0;
  int nextCalls = 0;
  int prevCalls = 0;

  TestPlayerController([pb.PlaybackState? initialState])
      : super(initialState ?? pb.PlaybackState.initial());

  void updateState(pb.PlaybackState newState) {
    state = newState;
  }

  @override
  Future<void> play() async {
    playCalls++;
    state = state.copyWith(status: pb.PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    state = state.copyWith(status: pb.PlaybackStatus.paused);
  }

  @override
  Future<void> next() async {
    nextCalls++;
  }

  @override
  Future<void> previous() async {
    prevCalls++;
  }

  @override
  void selectTrack(MusicItem track, List<MusicItem> currentList,
      {String? playingFrom}) {
    state = state.copyWith(currentTrack: track);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    // Select the track at index
  }

  @override
  void clearQueue() {
    state = state.copyWith(
      currentTrack: null,
      status: pb.PlaybackStatus.idle,
      position: Duration.zero,
      duration: Duration.zero,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFavoritesNotifier extends StateNotifier<List<Track>>
    implements FavoritesNotifier {
  FakeFavoritesNotifier() : super([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlaylistController extends StateNotifier<PlaylistsState>
    implements PlaylistController {
  FakePlaylistController() : super(const PlaylistsState(playlists: []));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileController extends StateNotifier<ProfileModel>
    implements ProfileController {
  FakeProfileController() : super(ProfileModel.defaultProfile());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleTrack = Track(
    id: 'track-101',
    title: 'Vaseegara',
    artist: 'Bombay Jayashri',
    imageUrl: 'https://example.com/minnalae.jpg',
    duration: '4:59',
  );

  const nextTrack = Track(
    id: 'track-102',
    title: 'Venmathi Venmathiye',
    artist: 'Roop Kumar Rathod',
    imageUrl: 'https://example.com/minnalae2.jpg',
    duration: '5:24',
  );

  GoRouter createTestRouter({String initialLocation = '/home'}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainAppShell(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const Scaffold(
                body: Center(child: Text('Home Screen Content')),
              ),
            ),
            GoRoute(
              path: '/player',
              builder: (context, state) => const PlayerPage(),
            ),
            GoRoute(
              path: '/queue',
              builder: (context, state) => const QueuePage(),
            ),
            GoRoute(
              path: '/search',
              builder: (context, state) => const Scaffold(
                body: Center(child: Text('Search Screen Content')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<Override> buildStandardOverrides({
    required TestPlayerController controller,
    required QueueManager queueManager,
  }) {
    return [
      playerControllerProvider.overrideWith((ref) => controller),
      queueManagerProvider.overrideWith((ref) => queueManager),
      favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
      allPlaylistsProvider.overrideWith((ref) => []),
      playlistControllerProvider.overrideWith((ref) => FakePlaylistController()),
      profileProvider.overrideWith((ref) => FakeProfileController()),
      activeRoomProvider.overrideWith((ref) => null),
    ];
  }

  Future<void> step(WidgetTester tester, [int millis = 500]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: millis));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('Miee Android — Compact Playback Visibility on Queue Screen', () {
    testWidgets(
        '1. Compact playback MiniPlayer is visible on /home when a track is active',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // Android mobile viewport
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: sampleTrack,
          duration: const Duration(minutes: 4, seconds: 59),
          position: const Duration(minutes: 1, seconds: 30),
        ),
      );

      final qm = QueueManager();
      qm.setQueue([sampleTrack, nextTrack], startIndex: 0);

      final router = createTestRouter(initialLocation: '/home');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(
            controller: controller,
            queueManager: qm,
          ),
          child: MaterialApp.router(
            theme: ThemeData(platform: TargetPlatform.android),
            routerConfig: router,
          ),
        ),
      );
      await step(tester);

      // Home content is visible
      expect(find.text('Home Screen Content'), findsOneWidget);

      // MiniPlayer is visible on /home
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Vaseegara')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Bombay Jayashri')),
        findsOneWidget,
      );
    });

    testWidgets(
        '2. Compact playback MiniPlayer is completely HIDDEN on /queue and leaves no blank space',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // Android mobile viewport
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: sampleTrack,
          duration: const Duration(minutes: 4, seconds: 59),
          position: const Duration(minutes: 1, seconds: 30),
        ),
      );

      final qm = QueueManager();
      qm.setQueue([sampleTrack, nextTrack], startIndex: 0);

      final router = createTestRouter(initialLocation: '/queue');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(
            controller: controller,
            queueManager: qm,
          ),
          child: MaterialApp.router(
            theme: ThemeData(platform: TargetPlatform.android),
            routerConfig: router,
          ),
        ),
      );
      await step(tester);

      // Queue page content is visible
      expect(find.text('Playing Queue'), findsOneWidget);
      expect(find.text('CLEAR QUEUE'), findsOneWidget);

      // MiniPlayer is strictly HIDDEN
      expect(find.byType(MiniPlayer), findsNothing);

      // Audio continues uninterrupted in state
      expect(controller.state.status, equals(pb.PlaybackStatus.playing));
      expect(controller.state.currentTrack?.title, equals('Vaseegara'));
      expect(controller.state.position, equals(const Duration(minutes: 1, seconds: 30)));
    });

    testWidgets(
        '3. Navigating from /home to /queue hides MiniPlayer, navigating back restores it without layout jumps',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // Android mobile viewport
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: sampleTrack,
          duration: const Duration(minutes: 4, seconds: 59),
          position: const Duration(minutes: 1, seconds: 30),
        ),
      );

      final qm = QueueManager();
      qm.setQueue([sampleTrack, nextTrack], startIndex: 0);

      final router = createTestRouter(initialLocation: '/home');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(
            controller: controller,
            queueManager: qm,
          ),
          child: MaterialApp.router(
            theme: ThemeData(platform: TargetPlatform.android),
            routerConfig: router,
          ),
        ),
      );
      await step(tester);

      // Step 1: On /home — MiniPlayer is visible
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Vaseegara')),
        findsOneWidget,
      );

      // Step 2: Navigate to /queue
      unawaited(router.push('/queue'));
      await step(tester);

      // Step 3: On /queue — MiniPlayer is completely hidden
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.text('Playing Queue'), findsOneWidget);
      expect(find.text('CLEAR QUEUE'), findsOneWidget);

      // Audio state remains playing
      expect(controller.state.status, equals(pb.PlaybackStatus.playing));

      // Step 4: Navigate back to /home
      router.pop();
      await step(tester);

      // Step 5: On /home — MiniPlayer is restored with all track info intact
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Vaseegara')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Bombay Jayashri')),
        findsOneWidget,
      );
    });

    testWidgets(
        '4. Navigating /home -> /player -> /queue -> /player -> /home correctly respects MiniPlayer visibility',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844); // Android mobile viewport
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: sampleTrack,
          duration: const Duration(minutes: 4, seconds: 59),
          position: const Duration(minutes: 1, seconds: 30),
        ),
      );

      final qm = QueueManager();
      qm.setQueue([sampleTrack, nextTrack], startIndex: 0);

      final router = createTestRouter(initialLocation: '/home');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(
            controller: controller,
            queueManager: qm,
          ),
          child: MaterialApp.router(
            theme: ThemeData(platform: TargetPlatform.android),
            routerConfig: router,
          ),
        ),
      );
      await step(tester);

      // 1. Home: MiniPlayer is visible
      expect(find.byType(MiniPlayer), findsOneWidget);

      // 2. Open Now Playing (/player)
      unawaited(router.push('/player'));
      await step(tester);

      // Now Playing: MiniPlayer is hidden (full screen player active)
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.text('PLAYING FROM'), findsOneWidget);

      // 3. Open Queue from Now Playing (/queue)
      unawaited(router.push('/queue'));
      await step(tester);

      // Queue: MiniPlayer is hidden
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.text('Playing Queue'), findsOneWidget);

      // 4. Pop from Queue back to Now Playing
      router.pop();
      await step(tester);

      // Now Playing: MiniPlayer is still hidden
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.text('PLAYING FROM'), findsOneWidget);

      // 5. Pop from Now Playing back to Home
      router.pop();
      await step(tester);

      // Home: MiniPlayer reappears cleanly
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Vaseegara')),
        findsOneWidget,
      );

      // 6. Repeat navigation to ensure no state degradation
      unawaited(router.push('/queue'));
      await step(tester);
      expect(find.byType(MiniPlayer), findsNothing);

      router.pop();
      await step(tester);
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Vaseegara')),
        findsOneWidget,
      );
    });

    testWidgets(
        '5. Audio playback state continues working seamlessly across queue navigation',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: sampleTrack,
          duration: const Duration(minutes: 4, seconds: 59),
          position: const Duration(minutes: 1, seconds: 30),
        ),
      );

      final qm = QueueManager();
      qm.setQueue([sampleTrack, nextTrack], startIndex: 0);

      final router = createTestRouter(initialLocation: '/home');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(
            controller: controller,
            queueManager: qm,
          ),
          child: MaterialApp.router(
            theme: ThemeData(platform: TargetPlatform.android),
            routerConfig: router,
          ),
        ),
      );
      await step(tester);

      // 1. Initial State on Home: Playing
      expect(controller.state.status, equals(pb.PlaybackStatus.playing));
      expect(controller.playCalls, equals(0));
      expect(controller.pauseCalls, equals(0));
      expect(find.byType(MiniPlayer), findsOneWidget);

      // 2. Navigate to /queue
      unawaited(router.push('/queue'));
      await step(tester);

      // Verify Queue screen is shown and MiniPlayer is hidden
      expect(find.text('Playing Queue'), findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);

      // Verify playback state is completely uninterrupted
      expect(controller.state.status, equals(pb.PlaybackStatus.playing));
      expect(controller.state.currentTrack?.title, equals('Vaseegara'));
      expect(controller.state.position, equals(const Duration(minutes: 1, seconds: 30)));
      expect(controller.pauseCalls, equals(0), reason: 'Audio must not be paused when entering queue');

      // 3. Pop back to /home
      router.pop();
      await step(tester);

      // MiniPlayer is restored on Home
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MiniPlayer), matching: find.text('Vaseegara')),
        findsOneWidget,
      );

      // Audio state remains uninterrupted
      expect(controller.state.status, equals(pb.PlaybackStatus.playing));
      expect(controller.state.currentTrack?.title, equals('Vaseegara'));
      expect(controller.pauseCalls, equals(0), reason: 'Audio must not be paused when leaving queue');
    });
  });
}
