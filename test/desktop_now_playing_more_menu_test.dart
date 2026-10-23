import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/main_app_shell.dart';

class MockFavoritesNotifier extends StateNotifier<List<Track>>
    implements FavoritesNotifier {
  MockFavoritesNotifier([List<Track>? state]) : super(state ?? []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileController extends StateNotifier<ProfileModel>
    implements ProfileController {
  FakeProfileController() : super(ProfileModel.defaultProfile());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test spy for PlaylistController capturing addTrack calls.
class FakePlaylistController extends StateNotifier<PlaylistsState>
    implements PlaylistController {
  final List<Map<String, dynamic>> addTrackCalls = [];

  FakePlaylistController([List<PlaylistModel>? initialPlaylists])
      : super(PlaylistsState(playlists: initialPlaylists ?? []));

  @override
  Future<void> addTrack(String playlistId, MusicItem track) async {
    addTrackCalls.add({
      'playlistId': playlistId,
      'track': track,
    });
    final updated = state.playlists.map((pl) {
      if (pl.id == playlistId) {
        return PlaylistModel(
          id: pl.id,
          name: pl.name,
          tracks: [...pl.tracks, track],
          createdAt: pl.createdAt,
          lastModified: DateTime.now(),
        );
      }
      return pl;
    }).toList();
    state = state.copyWith(playlists: updated);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Test spy for PlayerController.
class FakePlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  int playCount = 0;
  int pauseCount = 0;
  int nextCount = 0;
  int previousCount = 0;
  int toggleShuffleCount = 0;
  int toggleRepeatCount = 0;

  FakePlayerController([pb.PlaybackState? initialState])
      : super(initialState ?? pb.PlaybackState.initial());

  void setPlaybackState(pb.PlaybackState newState) {
    state = newState;
  }

  @override
  Future<void> play() async {
    playCount++;
    state = state.copyWith(status: pb.PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    state = state.copyWith(status: pb.PlaybackStatus.paused);
  }

  @override
  Future<void> next() async {
    nextCount++;
  }

  @override
  Future<void> previous() async {
    previousCount++;
  }

  @override
  Future<void> toggleShuffle() async {
    toggleShuffleCount++;
    state = state.copyWith(isShuffleEnabled: !state.isShuffleEnabled);
  }

  @override
  Future<void> toggleRepeatMode() async {
    toggleRepeatCount++;
    final nextMode = state.repeatMode == pb.RepeatMode.off
        ? pb.RepeatMode.all
        : pb.RepeatMode.off;
    state = state.copyWith(repeatMode: nextMode);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final testTrackA = Track(
    id: 'track_a',
    title: 'Song Title Alpha',
    artist: 'Artist Alpha',
    imageUrl: 'https://example.com/art_a.jpg',
    duration: '3:30',
  );

  final testTrackB = Track(
    id: 'track_b',
    title: 'Song Title Beta',
    artist: 'Artist Beta',
    imageUrl: 'https://example.com/art_b.jpg',
    duration: '4:15',
  );

  final testPlaylist = PlaylistModel(
    id: 'pl_001',
    name: 'Chill Vibes',
    tracks: [],
    createdAt: DateTime(2025, 1, 1),
    lastModified: DateTime(2025, 1, 1),
  );

  group('Desktop Now Playing Panel & More Menu Tests', () {
    testWidgets('Renders track details and 3-dots More button when track is present', (tester) async {
      final playback = pb.PlaybackState.initial().copyWith(
        currentTrack: testTrackA,
        status: pb.PlaybackStatus.playing,
        position: const Duration(seconds: 45),
        duration: const Duration(minutes: 3, seconds: 30),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopNowPlayingPanel(
                playback: playback,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Song Title Alpha'), findsOneWidget);
      expect(find.text('Artist Alpha'), findsWidgets);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      expect(find.byTooltip('More options'), findsOneWidget);
    });

    testWidgets('Returns SizedBox.shrink() when currentTrack is null', (tester) async {
      final playback = pb.PlaybackState.initial();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopNowPlayingPanel(
                playback: playback,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Song Title Alpha'), findsNothing);
      expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
      expect(find.byTooltip('More options'), findsNothing);
    });

    testWidgets('Tapping More button opens Add to Playlist sheet and adds current track', (tester) async {
      final playback = pb.PlaybackState.initial().copyWith(
        currentTrack: testTrackA,
        status: pb.PlaybackStatus.playing,
      );

      final fakePlaylistController = FakePlaylistController([testPlaylist]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            playlistControllerProvider.overrideWith((ref) => fakePlaylistController),
            allPlaylistsProvider.overrideWithValue([testPlaylist]),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopNowPlayingPanel(
                playback: playback,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap 3-dots More options button
      final moreButton = find.byTooltip('More options');
      expect(moreButton, findsOneWidget);
      await tester.tap(moreButton);
      await tester.pumpAndSettle();

      // Verify the Add to Playlist sheet opened
      expect(find.text('Add to Playlist'), findsOneWidget);
      expect(find.text('Chill Vibes'), findsOneWidget);
      expect(find.text('New Playlist'), findsOneWidget);

      // Tap the playlist item
      await tester.tap(find.text('Chill Vibes'));
      await tester.pumpAndSettle();

      // Verify trackA was added to the playlist
      expect(fakePlaylistController.addTrackCalls.length, equals(1));
      expect(fakePlaylistController.addTrackCalls[0]['playlistId'], equals('pl_001'));
      expect(fakePlaylistController.addTrackCalls[0]['track'].id, equals('track_a'));
    });

    testWidgets('Changing playback passes updated track to Add to Playlist sheet', (tester) async {
      final fakePlaylistController = FakePlaylistController([testPlaylist]);

      var currentPlayback = pb.PlaybackState.initial().copyWith(
        currentTrack: testTrackA,
        status: pb.PlaybackStatus.playing,
      );

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return ProviderScope(
              overrides: [
                favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
                playlistControllerProvider.overrideWith((ref) => fakePlaylistController),
                allPlaylistsProvider.overrideWithValue([testPlaylist]),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: Column(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            currentPlayback = currentPlayback.copyWith(currentTrack: testTrackB);
                          });
                        },
                        child: const Text('Switch Track'),
                      ),
                      Expanded(
                        child: DesktopNowPlayingPanel(playback: currentPlayback),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );

      await tester.pumpAndSettle();

      // Verify initial track A
      expect(find.text('Song Title Alpha'), findsOneWidget);

      // Switch track to track B
      await tester.tap(find.text('Switch Track'));
      await tester.pumpAndSettle();

      // Verify updated track B
      expect(find.text('Song Title Beta'), findsOneWidget);

      // Tap More button
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();

      // Tap playlist
      await tester.tap(find.text('Chill Vibes'));
      await tester.pumpAndSettle();

      // Verify trackB was added
      expect(fakePlaylistController.addTrackCalls.length, equals(1));
      expect(fakePlaylistController.addTrackCalls[0]['playlistId'], equals('pl_001'));
      expect(fakePlaylistController.addTrackCalls[0]['track'].id, equals('track_b'));
    });

    testWidgets('Close chevron button invokes onClose callback', (tester) async {
      bool closed = false;
      final playback = pb.PlaybackState.initial().copyWith(
        currentTrack: testTrackA,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: DesktopNowPlayingPanel(
                playback: playback,
                onClose: () => closed = true,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final closeButton = find.byTooltip('Close panel');
      expect(closeButton, findsOneWidget);
      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(closed, isTrue);
    });

    testWidgets('MainAppShell on desktop displays right drawer with functional More menu', (tester) async {
      final fakePlayer = FakePlayerController(
        pb.PlaybackState.initial().copyWith(
          currentTrack: testTrackA,
          status: pb.PlaybackStatus.playing,
        ),
      );
      final fakePlaylist = FakePlaylistController([testPlaylist]);

      // Set screen size to desktop width (1200 x 800)
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            profileProvider.overrideWith((ref) => FakeProfileController()),
            playerControllerProvider.overrideWith((ref) => fakePlayer),
            playlistControllerProvider.overrideWith((ref) => fakePlaylist),
            allPlaylistsProvider.overrideWithValue([testPlaylist]),
          ],
          child: const MaterialApp(
            home: MainAppShell(
              initialDrawerOpen: true,
              child: Scaffold(
                body: Text('Main Content Area'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Desktop drawer should be visible with Now Playing panel
      expect(find.text('Main Content Area'), findsOneWidget);
      expect(find.byType(DesktopNowPlayingPanel), findsOneWidget);
      expect(find.text('Song Title Alpha'), findsWidgets);

      // Tap 3-dots More button
      final moreButtons = find.byTooltip('More options');
      expect(moreButtons, findsOneWidget);
      await tester.tap(moreButtons);
      await tester.pumpAndSettle();

      // Bottom sheet Add to Playlist appears
      expect(find.text('Add to Playlist'), findsOneWidget);
      expect(find.text('Chill Vibes'), findsWidgets);
    });

    testWidgets('MainAppShell on mobile viewport hides desktop drawer and uses mobile MiniPlayer', (tester) async {
      final fakePlayer = FakePlayerController(
        pb.PlaybackState.initial().copyWith(
          currentTrack: testTrackA,
          status: pb.PlaybackStatus.playing,
        ),
      );

      // Set screen size to mobile width (400 x 800)
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
            playerControllerProvider.overrideWith((ref) => fakePlayer),
          ],
          child: const MaterialApp(
            home: MainAppShell(
              initialDrawerOpen: true,
              child: Scaffold(
                body: Text('Mobile Main Content'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Mobile viewport must NOT render DesktopNowPlayingPanel
      expect(find.byType(DesktopNowPlayingPanel), findsNothing);
      expect(find.text('Mobile Main Content'), findsOneWidget);
    });
  });
}
