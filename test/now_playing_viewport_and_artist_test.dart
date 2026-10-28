import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/player/presentation/player_page.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/rooms/providers/room_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/desktop_waveform_scrubber.dart';
import 'package:Miee/shared/widgets/main_app_shell.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:go_router/go_router.dart';

class FakeShellProfileController extends StateNotifier<ProfileModel> implements ProfileController {
  FakeShellProfileController() : super(ProfileModel.defaultProfile());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFavoritesNotifier extends StateNotifier<List<Track>> implements FavoritesNotifier {
  MockFavoritesNotifier([List<Track>? state]) : super(state ?? []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlaylistController extends StateNotifier<PlaylistsState> implements PlaylistController {
  FakePlaylistController() : super(const PlaylistsState(playlists: []));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestPlayerController extends StateNotifier<pb.PlaybackState> implements PlayerController {
  int playCalls = 0;
  int pauseCalls = 0;
  int nextCalls = 0;
  int prevCalls = 0;
  int shuffleCalls = 0;
  int repeatCalls = 0;
  Duration? seekPos;

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
  Future<void> toggleShuffle() async {
    shuffleCalls++;
    state = state.copyWith(isShuffleEnabled: !state.isShuffleEnabled);
  }

  @override
  Future<void> toggleRepeatMode() async {
    repeatCalls++;
    final nextMode = state.repeatMode == pb.RepeatMode.off
        ? pb.RepeatMode.all
        : (state.repeatMode == pb.RepeatMode.all ? pb.RepeatMode.one : pb.RepeatMode.off);
    state = state.copyWith(repeatMode: nextMode);
  }

  @override
  Future<void> seek(Duration position) async {
    seekPos = position;
    state = state.copyWith(position: position);
  }

  @override
  void selectTrack(MusicItem track, List<MusicItem> currentList, {String? playingFrom}) {
    state = state.copyWith(currentTrack: track);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget buildTestablePlayer({
  required TestPlayerController controller,
  QueueManager? queueManager,
}) {
  return ProviderScope(
    overrides: [
      playerControllerProvider.overrideWith((ref) => controller),
      favoritesProvider.overrideWith((ref) => MockFavoritesNotifier([])),
      allPlaylistsProvider.overrideWith((ref) => []),
      playlistControllerProvider.overrideWith((ref) => FakePlaylistController()),
      activeRoomProvider.overrideWith((ref) => null),
      if (queueManager != null)
        queueManagerProvider.overrideWith((ref) => queueManager),
    ],
    child: const MaterialApp(
      home: PlayerPage(),
    ),
  );
}

Widget buildTestablePlayerInShell({
  required TestPlayerController controller,
  QueueManager? queueManager,
}) {
  final router = GoRouter(
    initialLocation: '/player',
    routes: [
      ShellRoute(
        builder: (context, state, child) => MainAppShell(child: child),
        routes: [
          GoRoute(
            path: '/player',
            builder: (context, state) => const PlayerPage(),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const SizedBox(),
          ),
          GoRoute(
            path: '/queue',
            builder: (context, state) => const SizedBox(),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      playerControllerProvider.overrideWith((ref) => controller),
      favoritesProvider.overrideWith((ref) => MockFavoritesNotifier([])),
      allPlaylistsProvider.overrideWith((ref) => []),
      playlistControllerProvider.overrideWith((ref) => FakePlaylistController()),
      profileProvider.overrideWith((ref) => FakeShellProfileController()),
      activeRoomProvider.overrideWith((ref) => null),
      if (queueManager != null)
        queueManagerProvider.overrideWith((ref) => queueManager),
    ],
    child: MaterialApp.router(
      routerConfig: router,
    ),
  );
}

void main() {
  final rahmanTrack = Track(
    id: 'track-arr-1',
    title: 'Kannukkul Kannai',
    artist: 'A. R. Rahman',
    imageUrl: 'https://example.com/vinnaithaandi.jpg',
    duration: '3:53',
  );

  final anirudhTrack = Track(
    id: 'track-ani-1',
    title: 'Hukum',
    artist: 'Anirudh Ravichander',
    imageUrl: 'https://example.com/jailer.jpg',
    duration: '3:27',
  );

  final unknownTrack = Track(
    id: 'track-unknown-1',
    title: 'Mysterious Soundscape',
    artist: 'Unknown Indie Musician',
    imageUrl: '',
    duration: '2:15',
  );

  group('Part A — Header Refinement ("Hi-Fi Direct Stream" Removal)', () {
    testWidgets('Header removes "Hi-Fi Direct Stream" and preserves back arrow and "NOW PLAYING"', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: rahmanTrack,
          duration: const Duration(minutes: 3, seconds: 53),
          position: const Duration(minutes: 1, seconds: 15),
          playingFrom: 'Hi-Fi Direct Stream',
        ),
      );

      await tester.pumpWidget(buildTestablePlayer(controller: controller));
      await tester.pumpAndSettle();

      // 1. "Hi-Fi Direct Stream" must be removed
      expect(find.text('Hi-Fi Direct Stream'), findsNothing);

      // 2. "NOW PLAYING" label must be present
      expect(find.text('NOW PLAYING'), findsOneWidget);

      // 3. Back arrow button must be present
      expect(find.byTooltip('Back'), findsOneWidget);

      // 4. "DIRECT MASTER" badge on artwork must remain intact
      expect(find.text('DIRECT MASTER'), findsOneWidget);
    });
  });

  group('Part B — Viewport Optimization Across Target Resolutions', () {
    const desktopViewports = [
      Size(1920, 1080),
      Size(1686, 864),
      Size(1440, 900),
      Size(1366, 768),
      Size(1280, 720),
    ];

    for (final size in desktopViewports) {
      testWidgets('Fits completely within viewport height ${size.width.toInt()}x${size.height.toInt()} with all controls visible', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final controller = TestPlayerController(
          pb.PlaybackState.initial().copyWith(
            status: pb.PlaybackStatus.playing,
            currentTrack: rahmanTrack,
            duration: const Duration(minutes: 3, seconds: 53),
            position: const Duration(minutes: 1, seconds: 15),
          ),
        );

        final qm = QueueManager();
        qm.setQueue([
          rahmanTrack,
          Track(
            id: 'track-arr-2',
            title: 'Nallai Allai',
            artist: 'A. R. Rahman',
            imageUrl: 'https://example.com/kaatru.jpg',
            duration: '3:59',
          ),
        ], startIndex: 0);

        await tester.pumpWidget(buildTestablePlayer(controller: controller, queueManager: qm));
        await tester.pumpAndSettle();

        // Verify Essential Left Column elements
        expect(find.text('Kannukkul Kannai'), findsOneWidget);
        expect(find.byTooltip('Previous'), findsOneWidget);
        expect(find.byTooltip('Next'), findsOneWidget);
        expect(find.byTooltip('Shuffle'), findsOneWidget);
        expect(find.byTooltip('Repeat'), findsOneWidget);
        expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

        // Verify Essential Right Column elements
        expect(find.text('Up Next'), findsOneWidget);
        expect(find.text('About the Artist'), findsOneWidget);

        // Verify that play button is rendered within viewport bounds
        final playBtnFinder = find.byIcon(Icons.pause_rounded);
        final playBtnBottom = tester.getBottomRight(playBtnFinder).dy;
        expect(playBtnBottom, lessThan(size.height));

        // Verify play button is prominent
        final playMaterialFinder = find.byWidgetPredicate((w) => w is Material && w.shape is CircleBorder);
        expect(playMaterialFinder, findsOneWidget);
        final playBtnDimensions = tester.getSize(playMaterialFinder);
        expect(playBtnDimensions.width, greaterThanOrEqualTo(58.0));

        // Verify that About the Artist is rendered within viewport bounds
        final aboutArtistFinder = find.text('About the Artist');
        final aboutArtistTop = tester.getTopLeft(aboutArtistFinder).dy;
        expect(aboutArtistTop, lessThan(size.height));

        // Verify album artwork size matches suggested target ranges
        final artworkClip = find.byWidgetPredicate(
          (w) => w is ClipRRect && w.child is SizedBox && (w.child as SizedBox).child != null,
        ).first;
        final artworkDimensions = tester.getSize(artworkClip);
        expect(artworkDimensions.width, equals(artworkDimensions.height), reason: 'Artwork must be square');

        if (size == const Size(1280, 720)) {
          expect(artworkDimensions.width, inInclusiveRange(300.0, 330.0));
        } else if (size == const Size(1366, 768)) {
          expect(artworkDimensions.width, inInclusiveRange(330.0, 360.0));
        } else if (size == const Size(1440, 900)) {
          expect(artworkDimensions.width, inInclusiveRange(380.0, 420.0));
        } else if (size == const Size(1686, 864)) {
          expect(artworkDimensions.width, inInclusiveRange(380.0, 420.0));
        } else if (size == const Size(1920, 1080)) {
          expect(artworkDimensions.width, inInclusiveRange(400.0, 440.0));
        }

        // Verify waveform expands across the playback column (wider than or equal to artwork)
        final waveformFinder = find.byType(DiscreteWaveformScrubber);
        expect(waveformFinder, findsOneWidget);
        final waveformWidth = tester.getSize(waveformFinder).width;
        expect(waveformWidth, greaterThanOrEqualTo(artworkDimensions.width));

        // Verify artwork is centered horizontally within the playback column
        final artworkCenter = tester.getCenter(artworkClip).dx;
        final waveformCenter = tester.getCenter(waveformFinder).dx;
        expect((artworkCenter - waveformCenter).abs(), lessThan(1.0), reason: 'Artwork must be centered in playback column');

        // Verify track title and waveform align to playback column left edge
        final titleLeft = tester.getTopLeft(find.text('Kannukkul Kannai')).dx;
        final waveformLeft = tester.getTopLeft(waveformFinder).dx;
        expect(titleLeft, equals(waveformLeft), reason: 'Track title and waveform must align to playback column left edge');

        // Verify horizontal baseline alignment: Up Next card aligns with Album Artwork top
        final artworkTop = tester.getTopLeft(artworkClip).dy;
        final upNextHeaderTop = tester.getTopLeft(find.text('Up Next')).dy;
        expect((upNextHeaderTop - artworkTop).abs(), lessThan(40.0), reason: 'Up Next card must align with artwork top baseline');
      });
    }
  });

  group('Part C — About Artist Section and Dynamic Metadata', () {
    testWidgets('Displays curated artist info for A. R. Rahman with bio and verified badge', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: rahmanTrack,
          duration: const Duration(minutes: 3, seconds: 53),
        ),
      );

      await tester.pumpWidget(buildTestablePlayer(controller: controller));
      await tester.pumpAndSettle();

      // Verify About Artist Card is rendered
      expect(find.text('About the Artist'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('A. R. Rahman'), findsWidgets); // on track info and artist card
      expect(find.text('View Profile'), findsOneWidget);
      expect(find.textContaining('284K monthly listeners'), findsOneWidget);
      expect(find.textContaining('Academy and Grammy Award-winning'), findsOneWidget);
    });

    testWidgets('Dynamically updates artist information when current track changes', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: rahmanTrack,
          duration: const Duration(minutes: 3, seconds: 53),
        ),
      );

      await tester.pumpWidget(buildTestablePlayer(controller: controller));
      await tester.pumpAndSettle();

      expect(find.textContaining('Academy and Grammy Award-winning'), findsOneWidget);

      // Now switch currentTrack to Anirudh Ravichander
      controller.updateState(
        controller.state.copyWith(currentTrack: anirudhTrack),
      );
      await tester.pumpAndSettle();

      // Should now display Anirudh's bio and stats
      expect(find.text('Anirudh Ravichander'), findsWidgets);
      expect(find.textContaining('54K monthly listeners'), findsOneWidget);
      expect(find.textContaining('viral music producer'), findsOneWidget);
      expect(find.textContaining('Academy and Grammy'), findsNothing);
    });

    testWidgets('Gracefully renders fallback state when artist details are unavailable', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: unknownTrack,
          duration: const Duration(minutes: 2, seconds: 15),
        ),
      );

      await tester.pumpWidget(buildTestablePlayer(controller: controller));
      await tester.pumpAndSettle();

      expect(find.text('About the Artist'), findsOneWidget);
      expect(find.text('Unknown Indie Musician'), findsWidgets);
      expect(find.text('Featured artist on Miee.'), findsOneWidget);
    });
  });

  group('Part D — Preserves Audio Transport Interactions', () {
    testWidgets('Tapping play/pause and navigation buttons triggers controller', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TestPlayerController(
        pb.PlaybackState.initial().copyWith(
          status: pb.PlaybackStatus.playing,
          currentTrack: rahmanTrack,
          duration: const Duration(minutes: 3, seconds: 53),
        ),
      );

      await tester.pumpWidget(buildTestablePlayer(controller: controller));
      await tester.pumpAndSettle();

      // Tap Pause
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pumpAndSettle();
      expect(controller.pauseCalls, equals(1));

      // Tap Next
      await tester.tap(find.byTooltip('Next'));
      await tester.pumpAndSettle();
      expect(controller.nextCalls, equals(1));

      // Tap Previous
      await tester.tap(find.byTooltip('Previous'));
      await tester.pumpAndSettle();
      expect(controller.prevCalls, equals(1));

      // Tap Shuffle
      await tester.tap(find.byTooltip('Shuffle'));
      await tester.pumpAndSettle();
      expect(controller.shuffleCalls, equals(1));

      // Tap Repeat
      await tester.tap(find.byTooltip('Repeat'));
      await tester.pumpAndSettle();
      expect(controller.repeatCalls, equals(1));
    });
  });

  group('Part E — Verification inside Desktop MainAppShell Across Target Resolutions', () {
    const desktopViewports = [
      Size(1920, 1080),
      Size(1686, 864),
      Size(1440, 900),
      Size(1366, 768),
      Size(1280, 720),
    ];

    for (final size in desktopViewports) {
      testWidgets('MainAppShell: Fits cleanly at ${size.width.toInt()}x${size.height.toInt()} with prominent artwork and no bottom void', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final controller = TestPlayerController(
          pb.PlaybackState.initial().copyWith(
            status: pb.PlaybackStatus.playing,
            currentTrack: rahmanTrack,
            duration: const Duration(minutes: 3, seconds: 53),
            position: const Duration(minutes: 1, seconds: 15),
          ),
        );

        final qm = QueueManager();
        qm.setQueue([
          rahmanTrack,
          Track(
            id: 'track-arr-2',
            title: 'Nallai Allai',
            artist: 'A. R. Rahman',
            imageUrl: 'https://example.com/kaatru.jpg',
            duration: '3:59',
          ),
        ], startIndex: 0);

        await tester.pumpWidget(buildTestablePlayerInShell(controller: controller, queueManager: qm));
        await tester.pumpAndSettle();

        // 1. Controls are rendered and visible
        expect(find.text('Kannukkul Kannai'), findsOneWidget);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.text('NOW PLAYING'), findsOneWidget);
        expect(find.text('Hi-Fi Direct Stream'), findsNothing);
        expect(find.text('DIRECT MASTER'), findsOneWidget);
        expect(find.text('Up Next'), findsOneWidget);
        expect(find.text('About the Artist'), findsOneWidget);

        // 2. Artwork dimensions match responsive expectations
        final artworkClip = find.byWidgetPredicate(
          (w) => w is ClipRRect && w.child is SizedBox && (w.child as SizedBox).child != null,
        ).first;
        final artworkDimensions = tester.getSize(artworkClip);
        expect(artworkDimensions.width, equals(artworkDimensions.height), reason: 'Artwork must be square');

        if (size == const Size(1686, 864)) {
          expect(artworkDimensions.width, inInclusiveRange(380.0, 420.0), reason: 'Target at 1686x864 is 380-420px');
        } else if (size == const Size(1440, 900)) {
          expect(artworkDimensions.width, inInclusiveRange(380.0, 420.0));
        } else if (size == const Size(1920, 1080)) {
          expect(artworkDimensions.width, inInclusiveRange(400.0, 440.0));
        } else if (size == const Size(1366, 768)) {
          expect(artworkDimensions.width, inInclusiveRange(300.0, 360.0));
        } else if (size == const Size(1280, 720)) {
          expect(artworkDimensions.width, inInclusiveRange(300.0, 330.0));
        }

        // 3. Waveform scrubber expands across the playback column
        final waveformFinder = find.byType(DiscreteWaveformScrubber);
        expect(waveformFinder, findsOneWidget);
        final waveformWidth = tester.getSize(waveformFinder).width;
        expect(waveformWidth, greaterThanOrEqualTo(artworkDimensions.width));

        // 4. Artwork is horizontally centered in the playback column
        final artworkCenter = tester.getCenter(artworkClip).dx;
        final waveformCenter = tester.getCenter(waveformFinder).dx;
        expect((artworkCenter - waveformCenter).abs(), lessThan(1.0));

        // 5. Play button is prominent (>= 58px) and rendered within bounds
        final playMaterialFinder = find.byWidgetPredicate((w) => w is Material && w.shape is CircleBorder);
        expect(playMaterialFinder, findsOneWidget);
        final playBtnDimensions = tester.getSize(playMaterialFinder);
        expect(playBtnDimensions.width, greaterThanOrEqualTo(58.0));

        final playBtnFinder = find.byIcon(Icons.pause_rounded);
        final playBtnBottom = tester.getBottomRight(playBtnFinder).dy;
        expect(playBtnBottom, lessThan(size.height));

        // 6. Up Next & About the Artist cards are within bounds
        final aboutArtistFinder = find.text('About the Artist');
        final aboutArtistTop = tester.getTopLeft(aboutArtistFinder).dy;
        expect(aboutArtistTop, lessThan(size.height));
      });
    }
  });
}
