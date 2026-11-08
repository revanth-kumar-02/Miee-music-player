import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:Miee/app/router/app_router.dart';
import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/player/presentation/player_page.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';
import 'package:Miee/features/playlists/presentation/playlist_detail_page.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/features/recommendations/domain/daily_mix.dart';
import 'package:Miee/features/recommendations/providers/daily_mix_providers.dart';
import 'package:Miee/features/rooms/providers/room_providers.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/mini_player.dart';

class TestPlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  TestPlayerController([pb.PlaybackState? initialState])
      : super(initialState ?? pb.PlaybackState.initial());

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
  FakePlaylistController(Track track)
      : super(PlaylistsState(playlists: [
          PlaylistModel(
            id: 'pl-1',
            name: 'Chill Vibes',
            tracks: [track],
            createdAt: DateTime.now(),
            lastModified: DateTime.now(),
          ),
        ]));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileController extends StateNotifier<ProfileModel>
    implements ProfileController {
  FakeProfileController() : super(ProfileModel.defaultProfile());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDailyMixSnapshotNotifier extends DailyMixNotifier {
  @override
  Future<DailyMixSnapshot> build() async => DailyMixSnapshot(
        userId: 'test_user',
        localDate: '2026-11-08',
        generatedAt: DateTime.now(),
        mixes: const [],
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleTrack = Track(
    id: 'track-101',
    title: 'Kaadhalai Solla Mudiyaadha',
    artist: 'A. R. Rahman',
    imageUrl: 'https://example.com/art.jpg',
    duration: '4:50',
  );

  Future<void> step(WidgetTester tester, [int millis = 300]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: millis));
  }

  group('Miee MiniPlayer Navigation Verification', () {
    testWidgets('1. Tapping MiniPlayer on /home opens PlayerPage without BottomNavigation', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: sampleTrack,
          duration: const Duration(minutes: 4, seconds: 50),
          position: const Duration(seconds: 33),
        ),
      );

      final qm = QueueManager();
      qm.setQueue([sampleTrack], startIndex: 0);

      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith((ref) => controller),
          queueManagerProvider.overrideWith((ref) => qm),
          favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
          allPlaylistsProvider.overrideWith((ref) => []),
          playlistControllerProvider.overrideWith((ref) => FakePlaylistController(sampleTrack)),
          profileProvider.overrideWith((ref) => FakeProfileController()),
          activeRoomProvider.overrideWith((ref) => null),
          guestModeProvider.overrideWith((ref) => true),
          dailyMixSnapshotProvider.overrideWith(() => FakeDailyMixSnapshotNotifier()),
        ],
      );

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      // Let splash timer resolve
      await tester.pump(const Duration(milliseconds: 2600));
      await step(tester);

      // Navigate to /home
      router.go('/home');
      await step(tester);

      // Verify MiniPlayer is present on /home
      expect(find.byType(MiniPlayer), findsOneWidget);

      // Tap the MiniPlayer body
      await tester.tap(find.byType(MiniPlayer));
      await step(tester, 500);

      // Verify PlayerPage is opened
      expect(find.byType(PlayerPage), findsOneWidget);

      // Verify playback state was NOT altered by navigation
      expect(controller.state.status, equals(pb.PlaybackStatus.playing));
      expect(controller.state.currentTrack?.id, equals('track-101'));
      expect(controller.state.position.inSeconds, equals(33));

      // Pop back from PlayerPage to /home
      router.pop();
      await step(tester, 500);

      // Verify returned to /home and MiniPlayer is restored
      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(MiniPlayer), findsOneWidget);
    });

    testWidgets('2. Tapping MiniPlayer on Playlist Detail (/playlist/pl-1) opens PlayerPage', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: sampleTrack,
          duration: const Duration(minutes: 4, seconds: 50),
          position: const Duration(seconds: 33),
        ),
      );

      final qm = QueueManager();
      qm.setQueue([sampleTrack], startIndex: 0);

      final container = ProviderContainer(
        overrides: [
          playerControllerProvider.overrideWith((ref) => controller),
          queueManagerProvider.overrideWith((ref) => qm),
          favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
          allPlaylistsProvider.overrideWith((ref) => []),
          playlistControllerProvider.overrideWith((ref) => FakePlaylistController(sampleTrack)),
          profileProvider.overrideWith((ref) => FakeProfileController()),
          activeRoomProvider.overrideWith((ref) => null),
          guestModeProvider.overrideWith((ref) => true),
          dailyMixSnapshotProvider.overrideWith(() => FakeDailyMixSnapshotNotifier()),
        ],
      );

      final router = container.read(appRouterProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      // Let splash timer resolve
      await tester.pump(const Duration(milliseconds: 2600));
      await step(tester);

      // Navigate to playlist detail
      router.go('/playlist/pl-1');
      await step(tester);

      // Verify PlaylistDetailPage is active and MiniPlayer is visible
      expect(find.byType(PlaylistDetailPage), findsOneWidget);
      expect(find.byType(MiniPlayer), findsOneWidget);

      // Tap MiniPlayer from playlist detail
      await tester.tap(find.byType(MiniPlayer));
      await step(tester, 500);

      // Verify PlayerPage is opened
      expect(find.byType(PlayerPage), findsOneWidget);

      // Navigate back
      router.pop();
      await step(tester, 500);

      // Returned to PlaylistDetailPage and MiniPlayer still present
      expect(find.byType(PlayerPage), findsNothing);
      expect(find.byType(PlaylistDetailPage), findsOneWidget);
      expect(find.byType(MiniPlayer), findsOneWidget);
    });
  });
}
