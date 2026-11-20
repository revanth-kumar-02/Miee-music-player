import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/features/desktop/presentation/desktop_shell.dart';
import 'package:Miee/features/desktop/presentation/views/desktop_dashboard_view.dart';
import 'package:Miee/features/desktop/presentation/views/desktop_local_library_view.dart';
import 'package:Miee/features/desktop/presentation/views/studio_now_spinning_view.dart';
import 'package:Miee/features/desktop/presentation/widgets/left_console_rail.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/lyrics/domain/lyrics_model.dart';
import 'package:Miee/features/lyrics/providers/lyrics_providers.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/desktop_waveform_scrubber.dart';

class _FakeItem implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String imageUrl;
  @override
  final String duration;
  @override
  final String filePath;
  @override
  final bool isYoutube;

  const _FakeItem({
    required this.id,
    required this.title,
    required this.artist,
    this.filePath = '',
    this.imageUrl = '',
    this.duration = '03:45',
    this.isYoutube = false,
  });

  @override
  String? get album => 'Neon Noir';
  @override
  String get displayTitle => title;
  @override
  String get effectiveArtworkUrl => imageUrl;
}

class FakePlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  FakePlayerController([PlaybackState? initial])
      : super(initial ?? const PlaybackState(status: PlaybackStatus.idle));

  int togglePlayPauseCalls = 0;
  int seekCalls = 0;

  @override
  Future<void> togglePlayPause() async {
    togglePlayPauseCalls++;
    if (state.status == PlaybackStatus.playing) {
      state = state.copyWith(status: PlaybackStatus.paused);
    } else {
      state = state.copyWith(status: PlaybackStatus.playing);
    }
  }

  @override
  Future<void> seek(Duration position) async {
    seekCalls++;
    state = state.copyWith(position: position);
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

class FakePlaylistsNotifier extends StateNotifier<List<PlaylistHiveModel>>
    implements PlaylistsNotifier {
  FakePlaylistsNotifier() : super(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testTrack = _FakeItem(
    id: 'afterglow_1',
    title: 'AFTERGLOW',
    artist: 'CYBER NOIR',
  );

  group('Studio Now Spinning View Tests', () {
    testWidgets('1. Renders steady ambient rim, floating sleeve, and clean title/artist without extra badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                position: Duration(seconds: 84), // 01:24
                duration: Duration(seconds: 225), // 03:45
                currentTrack: testTrack,
              )),
            ),
          ],
          child: const MaterialApp(
            home: StudioNowSpinningView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Title and Artist
      expect(find.text('AFTERGLOW'), findsOneWidget);
      expect(find.text('CYBER NOIR'), findsOneWidget);

      // Verify NO badge text below artist name (user requested removal)
      expect(find.text('FLAC LOSSLESS • 24-BIT / 96 KHZ'), findsNothing);

      // Verify Top action headers
      expect(find.text('STUDIO CATALOG'), findsOneWidget);
      expect(find.text('STUDIO TUNER'), findsOneWidget);
    });

    testWidgets('2. Renders medium-width discrete waveform scrubber with dual timecodes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                position: Duration(seconds: 84),
                duration: Duration(seconds: 225),
                currentTrack: testTrack,
              )),
            ),
          ],
          child: const MaterialApp(
            home: StudioNowSpinningView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify dual timecodes
      expect(find.text('1:24'), findsOneWidget);
      expect(find.text('3:45'), findsOneWidget);

      // Verify waveform widget exists
      expect(find.byType(DiscreteWaveformScrubber), findsOneWidget);
    });

    testWidgets('3. Renders cardless floating transport controls and toggles lyrics mode', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      final fakeController = FakePlayerController(const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 84),
        duration: Duration(seconds: 225),
        currentTrack: testTrack,
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith((ref) => fakeController),
            lyricsProvider(testTrack).overrideWith((ref) async => const LyricsData(
                  lines: [
                    LyricLine(time: Duration(seconds: 10), text: 'Neon lights reflecting through the dark'),
                    LyricLine(time: Duration(seconds: 80), text: 'I feel the afterglow in my heart'),
                  ],
                  isSynced: true,
                )),
          ],
          child: const MaterialApp(
            home: StudioNowSpinningView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Floating Play/Pause Key
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.pause_rounded));
      await tester.pumpAndSettle();
      expect(fakeController.togglePlayPauseCalls, 1);

      // Dedicated Lyrics Button exists
      expect(find.text('Lyrics'), findsOneWidget);

      // Tap Lyrics -> switches to Synced Lyrics Stage
      await tester.tap(find.text('Lyrics'));
      await tester.pumpAndSettle();

      expect(find.text('Sleeve'), findsOneWidget);
      expect(find.text('I feel the afterglow in my heart'), findsOneWidget);

      // Tap Sleeve -> returns to Album Art
      await tester.tap(find.text('Sleeve'));
      await tester.pumpAndSettle();
      expect(find.text('Lyrics'), findsOneWidget);
    });

    testWidgets('4. Opening Studio Tuner reveals lighting controls, thickness slider, and color chips', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                currentTrack: testTrack,
              )),
            ),
          ],
          child: const MaterialApp(
            home: StudioNowSpinningView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially Tuner is closed
      expect(find.text('STUDIO LIGHTING & TUNER'), findsNothing);

      // Open Tuner drawer
      await tester.tap(find.text('STUDIO TUNER'));
      await tester.pumpAndSettle();

      // Verify Drawer content
      expect(find.text('STUDIO LIGHTING & TUNER'), findsOneWidget);
      expect(find.text('AUDIO ENGINE STATUS'), findsOneWidget);
      expect(find.text('Ember Red'), findsOneWidget);
      expect(find.text('Champagne Gold'), findsOneWidget);
      expect(find.text('Neon Cyan'), findsOneWidget);

      // Tap Neon Cyan preset
      await tester.tap(find.text('Neon Cyan'));
      await tester.pumpAndSettle();

      // Close Tuner
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('STUDIO LIGHTING & TUNER'), findsNothing);
    });

    testWidgets('5. DesktopShell default stage is DesktopDashboardView and switches with sidebar', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            userPlaylistsProvider.overrideWith((ref) => FakePlaylistsNotifier()),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                currentTrack: testTrack,
              )),
            ),
          ],
          child: const MaterialApp(
            home: DesktopShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Default stage is DesktopDashboardView matching the Reference Design
      expect(find.byType(DesktopDashboardView), findsOneWidget);

      // Click Studio Now Spinning in sidebar
      await tester.tap(find.byTooltip('Studio Now Spinning'));
      await tester.pumpAndSettle();

      // StudioNowSpinningView is mounted
      expect(find.byType(StudioNowSpinningView), findsOneWidget);
      expect(find.descendant(of: find.byType(StudioNowSpinningView), matching: find.text('AFTERGLOW')), findsOneWidget);

      // Click Studio Catalog in sidebar
      await tester.tap(find.byTooltip('Studio Catalog'));
      await tester.pumpAndSettle();

      // Studio Local Library is mounted
      expect(find.byType(DesktopLocalLibraryView), findsOneWidget);

      // Click Dashboard in sidebar to return
      await tester.tap(find.byTooltip('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.byType(DesktopDashboardView), findsOneWidget);
    });
  });
}
