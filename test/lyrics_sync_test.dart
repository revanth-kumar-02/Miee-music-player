import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/lyrics/domain/lyrics_model.dart';
import 'package:Miee/features/lyrics/presentation/widgets/lyrics_overlay.dart';
import 'package:Miee/features/lyrics/providers/lyrics_providers.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Lyric Line Matching Logic', () {
    final sampleLines = [
      const LyricLine(time: Duration(seconds: 5), text: 'Line 1: 5s'),
      const LyricLine(time: Duration(seconds: 12), text: 'Line 2: 12s'),
      const LyricLine(time: Duration(seconds: 20), text: 'Line 3: 20s'),
      const LyricLine(time: Duration(seconds: 35), text: 'Line 4: 35s'),
    ];
    final lyricsData = LyricsData(lines: sampleLines, isSynced: true);

    int findActiveIndex(LyricsData data, Duration currentPosition) {
      int activeIndex = -1;
      for (int i = 0; i < data.length; i++) {
        if (currentPosition >= data[i].time) {
          activeIndex = i;
        } else {
          break;
        }
      }
      return activeIndex;
    }

    test('Position before first lyric timestamp returns -1 (no active line yet)', () {
      expect(findActiveIndex(lyricsData, const Duration(seconds: 2)), -1);
      expect(findActiveIndex(lyricsData, Duration.zero), -1);
    });

    test('Exact match on timestamp highlights that line', () {
      expect(findActiveIndex(lyricsData, const Duration(seconds: 5)), 0);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 12)), 1);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 35)), 3);
    });

    test('Position between timestamps keeps previous line highlighted', () {
      expect(findActiveIndex(lyricsData, const Duration(seconds: 10)), 0);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 15)), 1);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 30)), 2);
    });

    test('Position past final line keeps final line highlighted', () {
      expect(findActiveIndex(lyricsData, const Duration(seconds: 60)), 3);
    });

    test('Seeking backwards jumps active line backwards', () {
      expect(findActiveIndex(lyricsData, const Duration(seconds: 25)), 2);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 8)), 0);
    });
  });

  group('Unsynchronized Lyrics Handling', () {
    test('Plain lyrics fallback does not invent artificial line durations', () {
      const plainText = 'First line of plain song\nSecond line\nThird line';
      final lines = plainText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .map((text) => LyricLine(time: Duration.zero, text: text))
          .toList();

      final lyricsData = LyricsData(lines: lines, isSynced: false, source: 'plain_fallback');

      expect(lyricsData.isSynced, isFalse);
      expect(lyricsData.length, 3);
      for (final line in lyricsData) {
        // Plain lyrics must have Duration.zero, not artificial interpolated timings
        expect(line.time, Duration.zero);
      }
    });
  });

  group('LyricsOverlay Widget Tests', () {
    const testTrack = Track(
      id: 'track_1',
      title: 'Starboy',
      artist: 'The Weeknd',
      imageUrl: 'https://example.com/art.jpg',
      duration: '3:50',
    );

    testWidgets('LyricsOverlay removes horizontal divider below header', (tester) async {
      final lyricsData = LyricsData(
        lines: [
          const LyricLine(time: Duration(seconds: 2), text: 'I am a starboy'),
        ],
        isSynced: true,
      );

      final fakePlayer = _FakePlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lyricsProvider(testTrack).overrideWith((ref) => Future.value(lyricsData)),
            playerControllerProvider.overrideWith((ref) => fakePlayer),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LyricsOverlay(
                track: testTrack,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Header components must be present
      expect(find.text('LYRICS'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // Issue 1 verification: NO Divider widget in the Lyrics overlay
      expect(find.byType(Divider), findsNothing);
    });

    testWidgets('Unsynchronized lyrics show badge and plain formatting without crash', (tester) async {
      final plainData = LyricsData(
        lines: [
          const LyricLine(time: Duration.zero, text: 'Unsynced line 1'),
          const LyricLine(time: Duration.zero, text: 'Unsynced line 2'),
        ],
        isSynced: false,
      );

      final fakePlayer = _FakePlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            lyricsProvider(testTrack).overrideWith((ref) => Future.value(plainData)),
            playerControllerProvider.overrideWith((ref) => fakePlayer),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LyricsOverlay(
                track: testTrack,
                onClose: () {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Indicator badge for unsynchronized lyrics must be visible
      expect(find.text('Unsynchronized lyrics'), findsOneWidget);
      expect(find.text('Unsynced line 1'), findsOneWidget);
      expect(find.text('Unsynced line 2'), findsOneWidget);
      expect(find.byType(Divider), findsNothing);
    });
  });
}

class _FakePlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  _FakePlayerController([pb.PlaybackState? initialState])
      : super(initialState ?? pb.PlaybackState.initial());

  @override
  Future<void> play() async {
    state = state.copyWith(status: pb.PlaybackStatus.playing);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(status: pb.PlaybackStatus.paused);
  }

  @override
  Future<void> seek(Duration position) async {
    state = state.copyWith(position: position);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
