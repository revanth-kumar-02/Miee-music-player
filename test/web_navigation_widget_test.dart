import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/shared/providers/web_navigation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestHeader({
    required WebNavigationState state,
    VoidCallback? onBack,
    VoidCallback? onForward,
  }) {
    final canGoBack = state.canGoBack;
    final canGoForward = state.canGoForward;

    return MaterialApp(
      home: Scaffold(
        body: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: canGoBack ? 'Go back' : '',
              child: IconButton(
                icon: const Icon(Icons.chevron_left_rounded),
                onPressed: canGoBack ? onBack : null,
              ),
            ),
            Tooltip(
              message: canGoForward ? 'Go forward' : '',
              child: IconButton(
                icon: const Icon(Icons.chevron_right_rounded),
                onPressed: canGoForward ? onForward : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  group('Web Navigation Widget Tests', () {
    testWidgets('Initial state has both Back and Forward disabled', (tester) async {
      final state = const WebNavigationState();
      await tester.pumpWidget(buildTestHeader(state: state));
      await tester.pumpAndSettle();

      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
      );
      final forwardButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );

      expect(backButton.onPressed, isNull);
      expect(forwardButton.onPressed, isNull);
    });

    testWidgets('Single route has Back and Forward disabled', (tester) async {
      final state = const WebNavigationState(
        history: ['/home'],
        currentIndex: 0,
      );
      await tester.pumpWidget(buildTestHeader(state: state));
      await tester.pumpAndSettle();

      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
      );
      final forwardButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );

      expect(backButton.onPressed, isNull);
      expect(forwardButton.onPressed, isNull);
    });

    testWidgets('Multiple routes at end enables Back and disables Forward', (tester) async {
      bool backPressed = false;

      final state = const WebNavigationState(
        history: ['/home', '/search', '/playlists'],
        currentIndex: 2,
      );
      await tester.pumpWidget(
        buildTestHeader(
          state: state,
          onBack: () => backPressed = true,
        ),
      );
      await tester.pumpAndSettle();

      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
      );
      final forwardButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );

      expect(backButton.onPressed, isNotNull);
      expect(forwardButton.onPressed, isNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
      expect(backPressed, isTrue);
    });

    testWidgets('In middle of history enables both Back and Forward', (tester) async {
      bool backPressed = false;
      bool forwardPressed = false;

      final state = const WebNavigationState(
        history: ['/home', '/search', '/playlists'],
        currentIndex: 1,
      );
      await tester.pumpWidget(
        buildTestHeader(
          state: state,
          onBack: () => backPressed = true,
          onForward: () => forwardPressed = true,
        ),
      );
      await tester.pumpAndSettle();

      final backButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
      );
      final forwardButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );

      expect(backButton.onPressed, isNotNull);
      expect(forwardButton.onPressed, isNotNull);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_left_rounded));
      expect(backPressed, isTrue);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right_rounded));
      expect(forwardPressed, isTrue);
    });
  });
}
