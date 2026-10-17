import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/player/presentation/player_page.dart';
import 'package:Miee/shared/widgets/waveform_widget.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';

class MockPlayerNotifier extends StateNotifier<PlaybackState> implements PlayerController {
  MockPlayerNotifier(super.state);

  Duration? lastSeekPosition;
  bool playCalled = false;
  bool pauseCalled = false;

  @override
  Future<void> seek(Duration position) async {
    lastSeekPosition = position;
  }

  @override
  Future<void> play() async {
    playCalled = true;
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFavoritesNotifier extends StateNotifier<List<Track>> implements FavoritesNotifier {
  MockFavoritesNotifier(super.state);

  String? lastRemovedId;
  Track? lastAddedTrack;

  @override
  Future<void> addFavorite(Track track) async {
    lastAddedTrack = track;
    state = [...state, track];
  }

  @override
  Future<void> removeFavorite(String trackId) async {
    lastRemovedId = trackId;
    state = state.where((t) => t.id != trackId).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const sampleTrack = Track(
    id: 'test-1',
    title: 'Young and Beautiful',
    artist: 'Lana Del Rey',
    imageUrl: 'https://example.com/artwork.jpg',
    duration: '3:58',
  );

  const longTitleTrack = Track(
    id: 'test-long',
    title: 'This is an Exceptionally Long Song Title That Extends Across Multiple Lines To Test Wrapping and Ellipsis Behaviors On Narrow Screens',
    artist: 'The Extremely Long Band Name That Also Needs Ellipsis Testing',
    imageUrl: 'https://example.com/artwork.jpg',
    duration: '5:12',
  );

  Widget createPlayerPage({
    required PlaybackState state,
    MockPlayerNotifier? playerNotifier,
    MockFavoritesNotifier? favoritesNotifier,
  }) {
    final mockCtrl = playerNotifier ?? MockPlayerNotifier(state);
    final mockFav = favoritesNotifier ?? MockFavoritesNotifier([]);

    return ProviderScope(
      overrides: [
        playerControllerProvider.overrideWith((ref) => mockCtrl),
        favoritesProvider.overrideWith((ref) => mockFav),
        allPlaylistsProvider.overrideWith((ref) => []),
      ],
      child: const MaterialApp(
        home: PlayerPage(),
      ),
    );
  }

  group('Issue 1: Title, Artist, Heart and Overflow Buttons Alignment', () {
    testWidgets('renders song title and artist with maxLines 2 and proper alignment', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = PlaybackState.initial().copyWith(
        currentTrack: sampleTrack,
        status: PlaybackStatus.playing,
      );

      await tester.pumpWidget(createPlayerPage(state: state));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final titleFinder = find.text('Young and Beautiful');
      final artistFinder = find.text('Lana Del Rey');

      expect(titleFinder, findsOneWidget);
      expect(artistFinder, findsOneWidget);

      final titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.maxLines, 2);
      expect(titleWidget.overflow, TextOverflow.ellipsis);
      expect(titleWidget.textAlign, TextAlign.center);

      final artistWidget = tester.widget<Text>(artistFinder);
      expect(artistWidget.maxLines, 1);
      expect(artistWidget.overflow, TextOverflow.ellipsis);
      expect(artistWidget.textAlign, TextAlign.center);
    });

    testWidgets('long song title wraps to 2 lines without throwing overflow errors', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = PlaybackState.initial().copyWith(
        currentTrack: longTitleTrack,
        status: PlaybackStatus.playing,
      );

      await tester.pumpWidget(createPlayerPage(state: state));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final titleFinder = find.text(longTitleTrack.title);
      expect(titleFinder, findsOneWidget);

      final titleWidget = tester.widget<Text>(titleFinder);
      expect(titleWidget.maxLines, 2);
      expect(titleWidget.overflow, TextOverflow.ellipsis);

      // Verify no Flutter layout overflow exceptions were caught
      expect(tester.takeException(), isNull);
    });

    testWidgets('heart button and overflow button are independently clickable', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = PlaybackState.initial().copyWith(
        currentTrack: sampleTrack,
        status: PlaybackStatus.playing,
      );
      final favNotifier = MockFavoritesNotifier([]);

      await tester.pumpWidget(createPlayerPage(state: state, favoritesNotifier: favNotifier));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final heartFinder = find.byIcon(Icons.favorite_border);
      expect(heartFinder, findsOneWidget);

      await tester.tap(heartFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(favNotifier.lastAddedTrack?.id, sampleTrack.id);

      final overflowFinder = find.byIcon(Icons.more_horiz);
      expect(overflowFinder, findsOneWidget);

      final overflowButtonFinder = find.widgetWithIcon(IconButton, Icons.more_horiz);
      expect(overflowButtonFinder, findsOneWidget);
      final overflowButton = tester.widget<IconButton>(overflowButtonFinder);
      expect(overflowButton.onPressed, isNotNull);
    });
  });

  group('Issue 2: Waveform Width and Timer Alignment', () {
    testWidgets('waveform widget fills available container width and matches timer boundary', (tester) async {
      tester.view.physicalSize = const Size(400, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final state = PlaybackState.initial().copyWith(
        currentTrack: sampleTrack,
        position: const Duration(minutes: 1, seconds: 30),
        duration: const Duration(minutes: 3, seconds: 58),
        status: PlaybackStatus.playing,
      );

      await tester.pumpWidget(createPlayerPage(state: state));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Timestamps
      final elapsedFinder = find.text('1:30');
      final totalFinder = find.text('3:58');
      expect(elapsedFinder, findsOneWidget);
      expect(totalFinder, findsOneWidget);

      final waveformFinder = find.byType(WaveformWidget);
      expect(waveformFinder, findsOneWidget);

      final waveformRect = tester.getRect(waveformFinder);
      final elapsedRect = tester.getRect(elapsedFinder);
      final totalRect = tester.getRect(totalFinder);

      // Waveform is medium size (~270px wide, +12.5% modest increase from 240px)
      expect(waveformRect.width, inInclusiveRange(200.0, 280.0));

      // Elapsed time starts at the left boundary of the progress container
      expect(elapsedRect.left, closeTo(waveformRect.left, 2.0));
      // Total duration aligns with the right boundary of the progress container
      expect(totalRect.right, closeTo(waveformRect.right, 2.0));
    });

    testWidgets('waveform scrubbing calculates correct seek position across width', (tester) async {
      double? scrubbedFraction;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360.0,
                child: WaveformWidget(
                  isPlaying: false,
                  activeProgress: 0.25,
                  onScrub: (fraction) {
                    scrubbedFraction = fraction;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final waveformFinder = find.byType(WaveformWidget);
      final topLeft = tester.getTopLeft(waveformFinder);

      // Tap near the beginning (x = 5)
      await tester.tapAt(topLeft + const Offset(5.0, 10.0));
      await tester.pump();
      expect(scrubbedFraction, isNotNull);
      expect(scrubbedFraction!, closeTo(0.01, 0.05));

      // Tap near the middle (x = 180)
      await tester.tapAt(topLeft + const Offset(180.0, 10.0));
      await tester.pump();
      expect(scrubbedFraction!, closeTo(0.5, 0.05));

      // Tap near the end (x = 355)
      await tester.tapAt(topLeft + const Offset(355.0, 10.0));
      await tester.pump();
      expect(scrubbedFraction!, closeTo(0.98, 0.05));
    });
  });

  group('Issue 3: Waveform Animation Speed & Lifecycle', () {
    testWidgets('animation controller duration is 2400ms (50% speed)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300.0,
              child: WaveformWidget(
                isPlaying: true,
                activeProgress: 0.5,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final state = tester.state(find.byType(WaveformWidget));
      final dynamic dynamicState = state;
      final AnimationController controller = dynamicState.animationController as AnimationController;

      expect(controller.duration, const Duration(milliseconds: 2400));
      expect(controller.isAnimating, isTrue);

      // Stop when paused
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300.0,
              child: WaveformWidget(
                isPlaying: false,
                activeProgress: 0.5,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(controller.isAnimating, isFalse);
    });
  });
}
