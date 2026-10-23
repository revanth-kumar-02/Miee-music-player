import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/widgets/waveform_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WaveformWidget Performance & Rendering', () {
    testWidgets('WaveformWidget wraps CustomPaint in a RepaintBoundary', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 270,
                height: 48,
                child: WaveformWidget(
                  isPlaying: true,
                  activeProgress: 0.35,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 50));

      // Must have RepaintBoundary ancestor to isolate vsync repaints from surrounding tree
      final repaintBoundaries = find.descendant(
        of: find.byType(WaveformWidget),
        matching: find.byType(RepaintBoundary),
      );
      expect(repaintBoundaries, findsOneWidget);

      final customPaints = find.descendant(
        of: find.byType(WaveformWidget),
        matching: find.byType(CustomPaint),
      );
      expect(customPaints, findsOneWidget);
    });

    testWidgets('Scrubbing across waveform fires onScrub callback with clamped value', (tester) async {
      double? scrubbedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 270,
                height: 48,
                child: WaveformWidget(
                  isPlaying: false,
                  activeProgress: 0.1,
                  onScrub: (val) {
                    scrubbedValue = val;
                  },
                ),
              ),
            ),
          ),
        ),
      );

      final waveformFinder = find.byType(WaveformWidget);
      expect(waveformFinder, findsOneWidget);

      // Tap in the middle (50% progress)
      await tester.tap(waveformFinder);
      await tester.pump();

      expect(scrubbedValue, isNotNull);
      expect(scrubbedValue! >= 0.0 && scrubbedValue! <= 1.0, isTrue);
    });

    testWidgets('Toggling isPlaying starts and stops animation cleanly without errors', (tester) async {
      bool isPlaying = true;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    WaveformWidget(
                      isPlaying: isPlaying,
                      activeProgress: 0.5,
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          isPlaying = !isPlaying;
                        });
                      },
                      child: const Text('Toggle'),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );

      // Animate for a few frames while playing
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Toggle to pause
      await tester.tap(find.text('Toggle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Toggle back to play
      await tester.tap(find.text('Toggle'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify widget is still healthy and rendered
      expect(find.byType(WaveformWidget), findsOneWidget);
    });

    testWidgets('WaveformWidget handles activeProgress boundary values (0.0, 1.0, and out-of-range)', (tester) async {
      for (final progress in [-0.5, 0.0, 0.5, 1.0, 1.5]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WaveformWidget(
                isPlaying: false,
                activeProgress: progress,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(WaveformWidget), findsOneWidget);
      }
    });
  });
}
