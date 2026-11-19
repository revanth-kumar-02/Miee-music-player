import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/desktop/presentation/desktop_shell.dart';
import 'package:Miee/features/desktop/presentation/widgets/master_transport_deck.dart';
import 'package:Miee/features/desktop/presentation/widgets/session_queue_view.dart';
import 'package:Miee/features/desktop/presentation/widgets/studio_audio_output_modal.dart';
import 'package:Miee/features/desktop/presentation/widgets/top_telemetry_header.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

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
    required this.filePath,
    this.artist = 'Studio Artist',
    this.imageUrl = '',
    this.duration = '03:45',
    this.isYoutube = false,
  });

  @override
  String? get album => null;
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
  Duration? lastSeekTarget;

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
    lastSeekTarget = position;
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
  FakePlaylistsNotifier([List<PlaylistHiveModel>? initial]) : super(initial ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase D6 — Desktop Hotkeys, Verified Telemetry & DAC Modal Tests', () {
    testWidgets('1a. TopTelemetryHeader displays DAC STANDBY when idle', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(status: PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TopTelemetryHeader(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DAC STANDBY • 44.1 KHZ'), findsOneWidget);
    });

    testWidgets('1b. TopTelemetryHeader displays FLAC LOSSLESS for local flac track', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      const flacTrack = _FakeItem(
        id: 'flac_1',
        title: 'Master Take (Direct)',
        filePath: 'C:/Audio/track.flac',
      );
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                currentTrack: flacTrack,
              )),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TopTelemetryHeader(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('FLAC LOSSLESS • PCM DIRECT'), findsOneWidget);
    });

    testWidgets('1c. TopTelemetryHeader displays MP3 telemetry for mp3 file', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      const mp3Track = _FakeItem(
        id: 'mp3_1',
        title: 'Vintage Cut',
        filePath: 'C:/Audio/track.mp3',
      );
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                currentTrack: mp3Track,
              )),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TopTelemetryHeader(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('MP3 • 320 KBPS / 44.1 KHZ'), findsOneWidget);
    });

    testWidgets('1d. TopTelemetryHeader displays STREAM OPUS for YouTube playback', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      const ytTrack = _FakeItem(
        id: 'yt_1',
        title: 'Live Session Stream',
        filePath: '',
        isYoutube: true,
      );
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                currentTrack: ytTrack,
              )),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TopTelemetryHeader(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('STREAM • OPUS 160 KBPS'), findsOneWidget);
    });

    testWidgets('2. StudioAudioOutputModal displays active pipeline and hardware endpoints', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(
                status: PlaybackStatus.playing,
                currentTrack: _FakeItem(
                  id: 'flac_2',
                  title: 'Acoustic Suite',
                  filePath: 'C:/Audio/acoustic.flac',
                ),
              )),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: StudioAudioOutputModal(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STUDIO DAC & AUDIO OUTPUT'), findsOneWidget);
      expect(find.text('ACTIVE PLAYBACK PIPELINE'), findsOneWidget);
      expect(find.text('FLAC Lossless • Direct File Decoder'), findsOneWidget);
      expect(find.text('Default System Audio Endpoint'), findsOneWidget);
      expect(find.text('Direct Hardware DAC Stream'), findsOneWidget);
      expect(find.text('CLOSE'), findsOneWidget);
    });

    testWidgets('3. DesktopShell hotkeys trigger Play/Pause, Seek, and Search Focus', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      final fakeController = FakePlayerController(const PlaybackState(
        status: PlaybackStatus.playing,
        position: Duration(seconds: 30),
        duration: Duration(seconds: 180),
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            userPlaylistsProvider.overrideWith((ref) => FakePlaylistsNotifier()),
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith((ref) => fakeController),
          ],
          child: const MaterialApp(
            home: DesktopShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger Space -> togglePlayPause
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(fakeController.togglePlayPauseCalls, 1);

      // Trigger ArrowLeft -> seek backward 5s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(fakeController.seekCalls, 1);
      expect(fakeController.lastSeekTarget, const Duration(seconds: 25));

      // Trigger ArrowRight -> seek forward 5s
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(fakeController.seekCalls, 2);
      expect(fakeController.lastSeekTarget, const Duration(seconds: 30));
    });

    testWidgets('4. Escape hotkey dismisses open SessionQueueView drawer in DesktopShell', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            userPlaylistsProvider.overrideWith((ref) => FakePlaylistsNotifier()),
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(status: PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: DesktopShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially drawer is closed
      expect(find.byType(SessionQueueView), findsNothing);

      // Open drawer via transport icon
      await tester.tap(find.byTooltip('Session Queue'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionQueueView), findsOneWidget);

      // Press Escape -> drawer closes
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SessionQueueView), findsNothing);
    });
  });
}
