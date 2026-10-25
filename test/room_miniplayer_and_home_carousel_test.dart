import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/home/presentation/home_page.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/providers/recommendation_providers.dart';
import 'package:Miee/features/rooms/presentation/room_landing_page.dart';
import 'package:Miee/features/rooms/presentation/create_room_page.dart';
import 'package:Miee/features/rooms/presentation/join_room_page.dart';
import 'package:Miee/features/rooms/providers/room_providers.dart';
import 'package:Miee/features/settings/domain/settings_model.dart';
import 'package:Miee/features/settings/presentation/settings_controller.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/main_app_shell.dart';
import 'package:Miee/shared/widgets/mini_player.dart';

class MockFavoritesNotifier extends StateNotifier<List<Track>>
    implements FavoritesNotifier {
  MockFavoritesNotifier() : super([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSearchHistoryNotifier extends StateNotifier<List<String>>
    implements SearchHistoryNotifier {
  MockSearchHistoryNotifier() : super(['A.R. Rahman', 'Anirudh']);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileController extends StateNotifier<ProfileModel>
    implements ProfileController {
  FakeProfileController() : super(ProfileModel.defaultProfile());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlaylistController extends StateNotifier<PlaylistsState>
    implements PlaylistController {
  FakePlaylistController() : super(const PlaylistsState(playlists: []));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsController extends StateNotifier<SettingsModel>
    implements SettingsController {
  FakeSettingsController() : super(const SettingsModel());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaLibraryService extends StateNotifier<MediaLibraryState>
    implements MediaLibraryService {
  FakeMediaLibraryService() : super(MediaLibraryState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  FakePlayerController(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testTrack = Track(
    id: 'test_track_1',
    title: 'Kaadhalai Solla Mudiyatha',
    artist: 'Yazin Nizar',
    imageUrl: 'https://example.com/art.jpg',
    duration: '4:51',
    filePath: 'https://youtube.com/watch?v=123',
  );

  List<Override> buildStandardOverrides({
    pb.PlaybackState? playbackState,
  }) {
    final effectivePlayback = playbackState ??
        const pb.PlaybackState(
          status: pb.PlaybackStatus.playing,
          currentTrack: testTrack,
          position: Duration(seconds: 45),
        );

    return [
      playerControllerProvider.overrideWith((ref) => FakePlayerController(effectivePlayback)),
      profileProvider.overrideWith((ref) => FakeProfileController()),
      currentUserProfileProvider.overrideWith((ref) => null),
      currentAuthUserProvider.overrideWith((ref) => null),
      favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
      searchHistoryProvider.overrideWith((ref) => MockSearchHistoryNotifier()),
      playlistControllerProvider.overrideWith((ref) => FakePlaylistController()),
      settingsControllerProvider.overrideWith((ref) => FakeSettingsController()),
      mediaLibraryServiceProvider.overrideWith((ref) => FakeMediaLibraryService()),
      allPlaylistsProvider.overrideWith((ref) => <PlaylistModel>[]),
      songsProvider.overrideWith((ref) => []),
      albumsProvider.overrideWith((ref) => []),
      recommendationSectionsProvider.overrideWith((ref) async => const RecommendationSections()),
      recentlyPlayedProvider.overrideWith((ref) => Stream.value([])),
    ];
  }

  GoRouter createTestRouter({String initialLocation = '/home'}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          builder: (context, state, child) => MainAppShell(child: child),
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const Scaffold(body: Text('Home Screen Content')),
            ),
            GoRoute(
              path: '/search',
              builder: (context, state) => const Scaffold(body: Text('Search Screen Content')),
            ),
            GoRoute(
              path: '/playlists',
              builder: (context, state) => const Scaffold(body: Text('Playlists Screen Content')),
            ),
            GoRoute(
              path: '/rooms',
              builder: (context, state) => const Scaffold(body: Text('Rooms Landing Content')),
            ),
            GoRoute(
              path: '/rooms/create',
              builder: (context, state) => const Scaffold(body: Text('Create Room Content')),
            ),
            GoRoute(
              path: '/rooms/join',
              builder: (context, state) => const Scaffold(body: Text('Join Room Content')),
            ),
          ],
        ),
      ],
    );
  }

  group('Task 1: Compact Player Visibility on Room Entrance Screens', () {
    testWidgets('MiniPlayer is visible on /home when a track is active', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = createTestRouter(initialLocation: '/home');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Screen Content'), findsOneWidget);
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.text('Kaadhalai Solla Mudiyatha'), findsOneWidget);
    });

    testWidgets('MiniPlayer is HIDDEN on /rooms entrance screen while music keeps playing', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = createTestRouter(initialLocation: '/rooms');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rooms Landing Content'), findsOneWidget);
      // MiniPlayer is strictly HIDDEN
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('MiniPlayer is HIDDEN on /rooms/create screen', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = createTestRouter(initialLocation: '/rooms/create');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Room Content'), findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('MiniPlayer is HIDDEN on /rooms/join screen', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = createTestRouter(initialLocation: '/rooms/join');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Join Room Content'), findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('Navigating from /home to /rooms/create hides MiniPlayer, navigating back restores it', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = createTestRouter(initialLocation: '/home');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // On /home: visible
      expect(find.byType(MiniPlayer), findsOneWidget);

      // Navigate to /rooms/create
      router.go('/rooms/create');
      await tester.pumpAndSettle();
      expect(find.byType(MiniPlayer), findsNothing);

      // Navigate back to /home
      router.go('/home');
      await tester.pumpAndSettle();
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.text('Kaadhalai Solla Mudiyatha'), findsOneWidget);
    });
  });

  group('Task 2: Home Promotional Carousel Features & Artwork', () {
    testWidgets('Renders editorial hero banner with artwork, left text, and controls', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: const MaterialApp(
            home: HomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Greeting and first headline
      expect(find.text('Music for\na calmer you.'), findsOneWidget);
      expect(find.text('Play now'), findsOneWidget);

      // Chevron buttons
      expect(find.byIcon(Icons.chevron_left_rounded).first, findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded).first, findsOneWidget);

      // Right-side Image.asset is present
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('Carousel advances slides with chevron buttons and cycles through all 3 slides', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: const MaterialApp(
            home: HomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Slide 0: Discover Music
      expect(find.text('Music for\na calmer you.'), findsOneWidget);

      // Tap Next (>)
      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pumpAndSettle();

      // Slide 1: Your Music
      expect(find.text('Discover sound\nwithout noise.'), findsOneWidget);

      // Tap Next (>)
      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pumpAndSettle();

      // Slide 2: Listen Together
      expect(find.text('Your sanctuary\nof rhythm.'), findsOneWidget);

      // Tap Next (>) to wrap around to Slide 0
      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Music for\na calmer you.'), findsOneWidget);
    });

    testWidgets('Manual swiping left advances slide, swiping right goes to previous slide', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: const MaterialApp(
            home: HomePage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Slide 0
      expect(find.text('Music for\na calmer you.'), findsOneWidget);

      // Swipe left on banner
      await tester.fling(find.text('Music for\na calmer you.'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      // Now Slide 1
      expect(find.text('Discover sound\nwithout noise.'), findsOneWidget);

      // Swipe right on banner
      await tester.fling(find.text('Discover sound\nwithout noise.'), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();

      // Returns to Slide 0
      expect(find.text('Music for\na calmer you.'), findsOneWidget);
    });

    testWidgets('Tapping Slide 0 navigates to /search, Slide 1 to /playlists, Slide 2 to /rooms', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomePage()),
          GoRoute(path: '/search', builder: (_, __) => const Scaffold(body: Text('Navigated to Search'))),
          GoRoute(path: '/playlists', builder: (_, __) => const Scaffold(body: Text('Navigated to Playlists'))),
          GoRoute(path: '/rooms', builder: (_, __) => const Scaffold(body: Text('Navigated to Rooms'))),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // Slide 0: Tap banner text area
      await tester.tap(find.text('Music for\na calmer you.'));
      await tester.pumpAndSettle();
      expect(find.text('Navigated to Search'), findsOneWidget);

      // Go back to home
      router.go('/home');
      await tester.pumpAndSettle();

      // Move to Slide 1
      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Discover sound\nwithout noise.'), findsOneWidget);

      // Tap banner on Slide 1
      await tester.tap(find.text('Discover sound\nwithout noise.'));
      await tester.pumpAndSettle();
      expect(find.text('Navigated to Playlists'), findsOneWidget);

      // Go back to home
      router.go('/home');
      await tester.pumpAndSettle();

      // Move to Slide 2
      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Discover sound\nwithout noise.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('Your sanctuary\nof rhythm.'), findsOneWidget);

      // Tap banner on Slide 2
      await tester.tap(find.text('Your sanctuary\nof rhythm.'));
      await tester.pumpAndSettle();
      expect(find.text('Navigated to Rooms'), findsOneWidget);
    });
  });
}
