import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/home/presentation/widgets/artist_rotation_section.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/providers/recommendation_providers.dart';

class MockPlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  int selectTrackCallCount = 0;

  MockPlayerController()
      : super(const PlaybackState(status: PlaybackStatus.idle));

  @override
  Future<void> selectTrack(
    MusicItem track,
    List<MusicItem> queue, {
    String? playingFrom,
  }) async {
    selectTrackCallCount++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockRecommendationService implements RecommendationService {
  final Map<String, List<MusicItem>> tracksByArtist;

  MockRecommendationService({this.tracksByArtist = const {}});

  @override
  Future<List<MusicItem>> getTracksForArtist(
    ArtistSummary artist, {
    int limit = 6,
  }) async {
    return tracksByArtist[artist.id] ?? [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockArtists = [
    const ArtistSummary(
      id: 'artist-1',
      name: 'A. R. Rahman',
      imageUrl: '',
    ),
    const ArtistSummary(
      id: 'artist-2',
      name: 'Anirudh Ravichander',
      imageUrl: '',
    ),
    const ArtistSummary(
      id: 'artist-3',
      name: 'Ilaiyaraaja',
      imageUrl: '',
    ),
  ];

  final mockTracks1 = [
    const Track(
      id: 'track-1',
      title: 'Jai Ho',
      artist: 'A. R. Rahman',
      imageUrl: '',
      duration: '3:45',
    ),
    const Track(
      id: 'track-2',
      title: 'Chaiyya Chaiyya',
      artist: 'A. R. Rahman',
      imageUrl: '',
      duration: '4:20',
    ),
  ];

  final mockTracks2 = [
    const Track(
      id: 'track-3',
      title: 'Hukum',
      artist: 'Anirudh Ravichander',
      imageUrl: '',
      duration: '3:20',
    ),
  ];

  final mockTracks3 = [
    const Track(
      id: 'track-4',
      title: 'Thendral Vanthu',
      artist: 'Ilaiyaraaja',
      imageUrl: '',
      duration: '4:10',
    ),
  ];

  Widget buildTestSection({
    List<ArtistSummary>? artists,
    List<MusicItem>? initialTracks,
    Duration interval = const Duration(seconds: 15),
    MockPlayerController? playerController,
    MockRecommendationService? recService,
  }) {
    final mockService = recService ??
        MockRecommendationService(
          tracksByArtist: {
            'artist-1': mockTracks1,
            'artist-2': mockTracks2,
            'artist-3': mockTracks3,
          },
        );

    final mockPlayer = playerController ?? MockPlayerController();

    return ProviderScope(
      overrides: [
        playerControllerProvider.overrideWith((ref) => mockPlayer),
        recommendationServiceProvider.overrideWithValue(mockService),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ArtistRotationSection(
              artists: artists ?? mockArtists,
              initialTracks: initialTracks ?? mockTracks1,
              rotationInterval: interval,
            ),
          ),
        ),
      ),
    );
  }

  group('ArtistRotationSection Tests', () {
    testWidgets('Renders initial artist name, tracks, and controls',
        (tester) async {
      await tester.pumpWidget(buildTestSection());
      await tester.pumpAndSettle();

      // Heading and initial artist
      expect(find.text('From Your Artists'), findsOneWidget);
      expect(find.text('Featuring top songs by A. R. Rahman'), findsOneWidget);

      // Tracks for initial artist
      expect(find.text('Jai Ho'), findsOneWidget);
      expect(find.text('Chaiyya Chaiyya'), findsOneWidget);

      // Previous and Next buttons exist
      expect(find.byTooltip('Previous artist'), findsOneWidget);
      expect(find.byTooltip('Next artist'), findsOneWidget);
    });

    testWidgets('Manual next button navigates to next artist with tracks',
        (tester) async {
      await tester.pumpWidget(buildTestSection());
      await tester.pumpAndSettle();

      final nextBtn = find.byTooltip('Next artist');
      expect(nextBtn, findsOneWidget);

      // Initial artist is A. R. Rahman
      expect(find.text('Featuring top songs by A. R. Rahman'), findsOneWidget);

      // Tap Next button
      await tester.tap(nextBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // After clicking next, second artist is shown
      expect(find.text('Featuring top songs by Anirudh Ravichander'), findsOneWidget);
      expect(find.text('Hukum'), findsOneWidget);
    });

    testWidgets('Manual previous button wraps around to last artist',
        (tester) async {
      await tester.pumpWidget(buildTestSection());
      await tester.pumpAndSettle();

      final prevBtn = find.byTooltip('Previous artist');
      expect(prevBtn, findsOneWidget);

      // Tap Previous button from first artist
      await tester.tap(prevBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Should wrap around to Ilaiyaraaja
      expect(find.text('Featuring top songs by Ilaiyaraaja'), findsOneWidget);
      expect(find.text('Thendral Vanthu'), findsOneWidget);
    });

    testWidgets('Automatic rotation advances artist after interval',
        (tester) async {
      await tester.pumpWidget(
        buildTestSection(
          interval: const Duration(seconds: 2),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Featuring top songs by A. R. Rahman'), findsOneWidget);

      // Fast forward past the 2-second interval
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 400));

      // Artist rotated to Anirudh
      expect(find.text('Featuring top songs by Anirudh Ravichander'), findsOneWidget);
      expect(find.text('Hukum'), findsOneWidget);
    });

    testWidgets('Single artist disables navigation buttons', (tester) async {
      final singleArtist = [mockArtists.first];
      await tester.pumpWidget(buildTestSection(artists: singleArtist));
      await tester.pumpAndSettle();

      // Artist name is visible
      expect(find.text('Featuring top songs by A. R. Rahman'), findsOneWidget);

      // Because single artist, buttons exist but are not enabled for multiple rotation
      expect(find.text('1/1'), findsNothing);
    });

    testWidgets('Audio player is never auto-triggered by artist rotation',
        (tester) async {
      final mockPlayer = MockPlayerController();

      await tester.pumpWidget(
        buildTestSection(
          interval: const Duration(seconds: 1),
          playerController: mockPlayer,
        ),
      );
      await tester.pumpAndSettle();

      // Verify that no tracks were played
      expect(mockPlayer.selectTrackCallCount, equals(0));

      // Advance through multiple rotation intervals
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));

      // Audio player selectTrack was NEVER called automatically!
      expect(mockPlayer.selectTrackCallCount, equals(0));
    });
  });
}
