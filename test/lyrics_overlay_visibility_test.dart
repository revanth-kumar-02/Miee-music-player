import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/lyrics/presentation/widgets/lyrics_overlay.dart';
import 'package:Miee/features/lyrics/providers/lyrics_providers.dart';
import 'package:Miee/features/lyrics/domain/lyrics_model.dart';
import 'package:Miee/shared/models/track.dart';

class MockPlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  MockPlayerController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Lyrics unavailable empty state renders high-contrast card and invokes onClose', (tester) async {
    const track = Track(
      id: 'test_track_1',
      title: 'Who is this Dude?',
      artist: 'Sai Abhyankkar',
      albumName: 'Dude - Side A',
      duration: '0:43',
      imageUrl: 'https://example.com/art.jpg',
    );

    bool closed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerControllerProvider.overrideWith(
            (ref) => MockPlayerController(PlaybackState.initial().copyWith(currentTrack: track)),
          ),
          lyricsProvider(track).overrideWith((ref) => Future.value(LyricsData.empty)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: LyricsOverlay(
              track: track,
              onClose: () => closed = true,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Heading
    expect(find.text('No lyrics available for this song'), findsOneWidget);

    // Verify Description
    expect(find.text('We checked multiple title variants and providers.'), findsOneWidget);

    // Verify Champagne Lyrics Icon
    expect(find.byIcon(Icons.lyrics_outlined), findsOneWidget);

    // Verify Back to Player button
    final backBtn = find.text('Back to Player');
    expect(backBtn, findsOneWidget);

    // Tap Back to Player
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    expect(closed, isTrue);
  });
}
