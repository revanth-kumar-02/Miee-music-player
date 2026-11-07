import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/home/presentation/widgets/daily_mixes_section.dart';
import 'package:Miee/features/recommendations/domain/daily_mix.dart';
import 'package:Miee/features/recommendations/providers/daily_mix_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

/// Test implementation of [PlayerController] to record calls without invoking audio hardware.
class FakePlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  FakePlayerController()
      : super(
          const pb.PlaybackState(
            status: pb.PlaybackStatus.idle,
            currentTrack: null,
          ),
        );

  List<MusicItem>? lastSetQueueTracks;
  int? lastSetQueueStartIndex;
  String? lastSetQueuePlayingFrom;

  @override
  void setQueue(
    List<MusicItem> tracks, {
    int startIndex = 0,
    String? playingFrom,
  }) {
    lastSetQueueTracks = tracks;
    lastSetQueueStartIndex = startIndex;
    lastSetQueuePlayingFrom = playingFrom;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake notifier allowing precise control over [DailyMixSnapshot] emission and tracking of refreshes.
class TestDailyMixNotifier extends DailyMixNotifier {
  final AsyncValue<DailyMixSnapshot> initialValue;
  int refreshCallCount = 0;

  TestDailyMixNotifier(this.initialValue);

  @override
  Future<DailyMixSnapshot> build() async {
    return initialValue.value!;
  }

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testTrack1 = Track(
    id: 't1',
    title: 'Nenjame Nenjame',
    artist: 'Anirudh Ravichander',
    imageUrl: 'https://example.com/1.jpg',
    duration: '3:45',
  );
  const testTrack2 = Track(
    id: 't2',
    title: 'Hukum',
    artist: 'Anirudh Ravichander',
    imageUrl: 'https://example.com/2.jpg',
    duration: '3:20',
  );
  const testTrack3 = Track(
    id: 't3',
    title: 'Pachchai Nirame',
    artist: 'A.R. Rahman',
    imageUrl: 'https://example.com/3.jpg',
    duration: '5:10',
  );

  const testMix1 = DailyMix(
    id: 'mix_1',
    title: 'Daily Mix 1',
    subtitle: 'Anirudh Ravichander, A.R. Rahman and more',
    tracks: [testTrack1, testTrack2],
  );

  const testMix2 = DailyMix(
    id: 'mix_2',
    title: 'Daily Mix 2',
    subtitle: 'Sid Sriram, Harris Jayaraj and more',
    tracks: [testTrack3],
  );

  const testMix3 = DailyMix(
    id: 'mix_3',
    title: 'Daily Mix 3',
    subtitle: 'Fresh Tamil & Indie releases',
    tracks: [testTrack1, testTrack3],
  );

  final testSnapshot = DailyMixSnapshot(
    userId: 'user_test_1',
    localDate: '2026-11-07',
    generatedAt: DateTime(2026, 11, 7, 6, 0),
    mixes: [testMix1, testMix2, testMix3],
    version: 1,
  );

  group('Daily Mixes Home UI Integration Tests', () {
    testWidgets('1. Renders all 3 Daily Mixes with titles, subtitles, and track counts',
        (tester) async {
      final fakePlayerController = FakePlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(
              () => TestDailyMixNotifier(AsyncValue.data(testSnapshot)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('Daily Mixes'), findsOneWidget);
      expect(find.text('Tuned to your taste and listening habits'), findsOneWidget);

      // Verify All 3 Mixes are present
      expect(find.text('Daily Mix 1'), findsOneWidget);
      expect(find.text('Daily Mix 2'), findsOneWidget);
      expect(find.text('Daily Mix 3'), findsOneWidget);

      // Verify Subtitles & Track Counts
      expect(find.text('Anirudh Ravichander, A.R. Rahman and more'), findsOneWidget);
      expect(find.text('Sid Sriram, Harris Jayaraj and more'), findsOneWidget);
      expect(find.text('Fresh Tamil & Indie releases'), findsOneWidget);

      expect(find.text('2 tracks'), findsNWidgets(2)); // Mix 1 and Mix 3 have 2 tracks
      expect(find.text('1 tracks'), findsOneWidget); // Mix 2 has 1 track
    });

    testWidgets('2. Tapping play button triggers playerController.playDailyMix with correct queue',
        (tester) async {
      final fakePlayerController = FakePlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(
              () => TestDailyMixNotifier(AsyncValue.data(testSnapshot)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the play button on Daily Mix 1
      final playButtons = find.byIcon(Icons.play_arrow_rounded);
      expect(playButtons, findsNWidgets(3));

      await tester.tap(playButtons.first);
      await tester.pumpAndSettle();

      // Verify playback helper was called and correctly populated queue
      expect(fakePlayerController.lastSetQueueStartIndex, equals(0));
      expect(fakePlayerController.lastSetQueueTracks, equals(testMix1.tracks));
      expect(fakePlayerController.lastSetQueuePlayingFrom, equals('Daily Mix: Daily Mix 1'));
    });

    testWidgets('3. Tapping card body triggers playback of that specific mix',
        (tester) async {
      final fakePlayerController = FakePlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(
              () => TestDailyMixNotifier(AsyncValue.data(testSnapshot)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on Daily Mix 2 title text
      await tester.tap(find.text('Daily Mix 2'));
      await tester.pumpAndSettle();

      expect(fakePlayerController.lastSetQueueStartIndex, equals(0));
      expect(fakePlayerController.lastSetQueueTracks, equals(testMix2.tracks));
      expect(fakePlayerController.lastSetQueuePlayingFrom, equals('Daily Mix: Daily Mix 2'));
    });

    testWidgets('4. Loading state renders skeleton placeholders without crashing',
        (tester) async {
      final fakePlayerController = FakePlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(
              () => _StaticLoadingNotifier(),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      // Loading state renders skeleton
      expect(find.byType(DailyMixesSection), findsOneWidget);
      expect(find.text('Daily Mix 1'), findsNothing);
      expect(fakePlayerController.lastSetQueueTracks, isNull);
    });

    testWidgets('5. Error state renders retry container and tapping retry invokes refresh',
        (tester) async {
      final fakePlayerController = FakePlayerController();
      final errorNotifier = _StaticErrorNotifier();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(() => errorNotifier),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Daily Mixes temporarily unavailable'), findsOneWidget);
      final retryButton = find.text('Retry');
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(errorNotifier.refreshCallCount, equals(1));
    });

    testWidgets('6. Empty snapshot collapses cleanly without visual clutter',
        (tester) async {
      final fakePlayerController = FakePlayerController();
      final emptySnapshot = DailyMixSnapshot.empty('user_test_1');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(
              () => TestDailyMixNotifier(AsyncValue.data(emptySnapshot)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Daily Mixes'), findsNothing);
      expect(find.text('Daily Mix 1'), findsNothing);
    });

    testWidgets('7. Widget rebuild does not alter playback queue or trigger audio',
        (tester) async {
      final fakePlayerController = FakePlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(
              () => TestDailyMixNotifier(AsyncValue.data(testSnapshot)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Trigger re-render
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayerController),
            dailyMixSnapshotProvider.overrideWith(
              () => TestDailyMixNotifier(AsyncValue.data(testSnapshot)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: DailyMixesSection(),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Ensure no playback was called automatically
      expect(fakePlayerController.lastSetQueueTracks, isNull);
    });
  });
}

class _StaticLoadingNotifier extends DailyMixNotifier {
  final Completer<DailyMixSnapshot> _completer = Completer<DailyMixSnapshot>();

  @override
  Future<DailyMixSnapshot> build() {
    return _completer.future;
  }
}

class _StaticErrorNotifier extends DailyMixNotifier {
  int refreshCallCount = 0;

  @override
  Future<DailyMixSnapshot> build() async {
    throw Exception('Simulated network failure');
  }

  @override
  Future<void> refresh() async {
    refreshCallCount++;
  }
}

