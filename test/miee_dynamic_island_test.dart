import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/player/presentation/widgets/miee_dynamic_island.dart';
import 'package:Miee/shared/models/track.dart';

class MockAudioHandlerForTest extends MieeAudioHandler {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Dynamic Island Widget Tests', () {
    testWidgets('Renders nothing when no track is active', (tester) async {
      final mockHandler = MockAudioHandlerForTest();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWithValue(mockHandler),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: MieeDynamicIsland(),
            ),
          ),
        ),
      );

      expect(find.byType(MieeDynamicIsland), findsOneWidget);
      expect(find.byKey(const ValueKey('collapsed_island')), findsNothing);
    });

    testWidgets('Renders collapsed pill with rotating album art & title when song is playing', (tester) async {
      final mockHandler = MockAudioHandlerForTest();
      final container = ProviderContainer(
        overrides: [
          audioHandlerProvider.overrideWithValue(mockHandler),
        ],
      );
      
      const testTrack = Track(
        id: 'youtube_track_island',
        title: 'Starboy',
        artist: 'The Weeknd',
        imageUrl: '',
        duration: '03:50',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: MieeDynamicIsland(),
            ),
          ),
        ),
      );

      // Simulate playing track
      container.read(playerControllerProvider.notifier).state = const PlaybackState(
        currentTrack: testTrack,
        status: PlaybackStatus.playing,
        position: Duration(seconds: 45),
        duration: Duration(seconds: 230),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('collapsed_island')), findsOneWidget);
      expect(find.text('Starboy'), findsOneWidget);

      // Test long press expansion
      await tester.longPress(find.byKey(const ValueKey('collapsed_island')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byKey(const ValueKey('expanded_island')), findsOneWidget);
      expect(find.text('The Weeknd'), findsOneWidget);
      expect(find.byIcon(Icons.skip_next_rounded), findsOneWidget);
      expect(find.byIcon(Icons.skip_previous_rounded), findsOneWidget);

      container.dispose();
    });
  });
}
