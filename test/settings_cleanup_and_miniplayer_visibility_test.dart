import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/features/settings/domain/settings_model.dart';
import 'package:Miee/features/settings/presentation/settings_controller.dart';
import 'package:Miee/features/settings/presentation/settings_page.dart';
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
    id: 'test_1',
    title: 'Vizhi Veekura',
    artist: 'Sai Abhyankkar',
    imageUrl: 'https://example.com/vizhi.jpg',
    duration: '3:45',
    filePath: 'https://youtube.com/watch?v=vizhi',
  );

  List<Override> buildStandardOverrides({
    pb.PlaybackState? playbackState,
    UserProfile? cloudProfile,
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
      currentUserProfileProvider.overrideWith((ref) => cloudProfile),
      currentAuthUserProvider.overrideWith((ref) => null),
      favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
      searchHistoryProvider.overrideWith((ref) => MockSearchHistoryNotifier()),
      playlistControllerProvider.overrideWith((ref) => FakePlaylistController()),
      settingsControllerProvider.overrideWith((ref) => FakeSettingsController()),
      mediaLibraryServiceProvider.overrideWith((ref) => FakeMediaLibraryService()),
    ];
  }

  group('Miee — Settings Cleaned 7 Categories Verification', () {
    testWidgets('Renders all seven required Settings categories', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Category 1: Account
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Manage Profile'), findsOneWidget);

      // Category 2: Personalization
      expect(find.text('Personalization'), findsOneWidget);
      expect(find.text('Favourite Artists'), findsOneWidget);
      expect(find.text('Preferred Playback Source'), findsOneWidget);

      // Category 3: Music Library
      expect(find.text('Music Library'), findsOneWidget);
      expect(find.text('Rescan Music Library'), findsOneWidget);
      expect(find.text('Refresh Metadata'), findsOneWidget);

      // Category 4: Playback & Notifications
      expect(find.text('Playback & Notifications'), findsOneWidget);
      expect(find.text('Background Playback'), findsOneWidget);
      expect(find.text('Media Notification'), findsOneWidget);
      expect(find.text('Lock Screen Controls'), findsOneWidget);
      expect(find.text('Resume Playback on Startup'), findsOneWidget);

      // Category 5: Storage & Cache
      expect(find.text('Storage & Cache'), findsOneWidget);
      expect(find.text('Clear Artwork Cache'), findsOneWidget);
      expect(find.text('Clear App Cache'), findsOneWidget);
      expect(find.text('Reset Library & Data'), findsOneWidget);

      // Category 6: Search History
      expect(find.text('Search History'), findsNWidgets(2)); // Header + Tile title
      expect(find.text('Clear Search History'), findsOneWidget);

      // Category 7: About Miee
      expect(find.text('About Miee'), findsWidgets);
      expect(find.text('Miee Version'), findsOneWidget);
      expect(find.text('Open Source Licenses'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
    });

    testWidgets('Removes redundant categories, duplicate controls, and placeholders', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Banned/Redundant categories and duplicates
      expect(find.text('Streaming Quality'), findsNothing);
      expect(find.text('Equalizer'), findsNothing);
      expect(find.text('Audio Effects'), findsNothing);
      expect(find.text('DJ Mode'), findsNothing);
      expect(find.text('Downloads'), findsNothing);
      expect(find.text('Default Shuffle'), findsNothing);
      expect(find.text('Default Repeat'), findsNothing);
      expect(find.text('Playback Speed'), findsNothing);
      expect(find.text('Developer Options'), findsNothing);
      expect(find.text('Music Folder Location'), findsNothing);
    });

    testWidgets('Destructive cache and library actions prompt confirmation dialogs', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: const MaterialApp(
            home: SettingsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Clear Artwork Cache confirmation
      final artworkCacheFinder = find.widgetWithText(ListTile, 'Clear Artwork Cache');
      await tester.ensureVisible(artworkCacheFinder);
      await tester.tap(artworkCacheFinder);
      await tester.pumpAndSettle();

      expect(find.text('Clear Artwork Cache?'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      // Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Clear Artwork Cache?'), findsNothing);

      // 2. Clear Search History confirmation
      final searchHistoryFinder = find.widgetWithText(ListTile, 'Clear Search History');
      await tester.ensureVisible(searchHistoryFinder);
      await tester.tap(searchHistoryFinder);
      await tester.pumpAndSettle();

      expect(find.text('Clear Search History?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Clear Search History?'), findsNothing);
    });
  });

  group('Miee — Compact Mini-Player Settings Route Visibility', () {
    GoRouter createTestRouter({required String initialLocation}) {
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
                path: '/settings',
                builder: (context, state) => const SettingsPage(),
              ),
              GoRoute(
                path: '/search',
                builder: (context, state) => const Scaffold(body: Text('Search Screen Content')),
              ),
            ],
          ),
        ],
      );
    }

    testWidgets('MiniPlayer is visible on /home when a track is active', (tester) async {
      tester.view.physicalSize = const Size(400, 800); // Mobile viewport
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
      expect(find.text('Vizhi Veekura'), findsOneWidget);
    });

    testWidgets('MiniPlayer is HIDDEN on /settings while audio continues playing in background', (tester) async {
      tester.view.physicalSize = const Size(400, 800); // Mobile viewport
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = createTestRouter(initialLocation: '/settings');

      await tester.pumpWidget(
        ProviderScope(
          overrides: buildStandardOverrides(),
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Settings screen content is rendered
      expect(find.text('Settings'), findsWidgets);
      expect(find.text('Account'), findsOneWidget);

      // MiniPlayer is completely HIDDEN
      expect(find.byType(MiniPlayer), findsNothing);
    });

    testWidgets('Navigating from /home to /settings hides MiniPlayer, navigating back restores it', (tester) async {
      tester.view.physicalSize = const Size(400, 800); // Mobile viewport
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

      // On /home: MiniPlayer is visible
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.text('Vizhi Veekura'), findsOneWidget);

      // Navigate to /settings
      router.go('/settings');
      await tester.pumpAndSettle();

      // On /settings: MiniPlayer is hidden
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.text('Settings'), findsWidgets);

      // Navigate back to /home
      router.go('/home');
      await tester.pumpAndSettle();

      // On /home again: MiniPlayer is restored with track preserved
      expect(find.byType(MiniPlayer), findsOneWidget);
      expect(find.text('Vizhi Veekura'), findsOneWidget);
    });
  });
}
