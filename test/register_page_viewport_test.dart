import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/auth/presentation/register_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createTestWidget() {
    return const ProviderScope(
      child: MaterialApp(
        home: RegisterPage(),
      ),
    );
  }

  group('Registration Page Viewport Optimization Tests', () {
    final desktopResolutions = <String, Size>{
      '1920x1080': const Size(1920, 1080),
      '1686x864': const Size(1686, 864),
      '1440x900': const Size(1440, 900),
      '1366x768': const Size(1366, 768),
      '1280x720': const Size(1280, 720),
    };

    for (final entry in desktopResolutions.entries) {
      testWidgets('Fits within 100vh at ${entry.key} without vertical overflow or scrolling', (tester) async {
        tester.view.physicalSize = entry.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(createTestWidget());
        await tester.pump();

        // 1. Verify two-column layout is present
        expect(find.text('SOUND ARCHITECTURE'), findsOneWidget);
        expect(find.text('Create your account'), findsOneWidget);
        expect(find.text('Experience Sound in Its True Fidelity'), findsOneWidget);
        expect(find.text('DIRECT ACOUSTIC PIPELINE'), findsOneWidget);

        // 2. Verify all 4 input fields are visible
        expect(find.text('FULL NAME'), findsOneWidget);
        expect(find.text('EMAIL ADDRESS'), findsOneWidget);
        expect(find.text('PASSWORD'), findsOneWidget);
        expect(find.text('CONFIRM PASSWORD'), findsOneWidget);

        // 3. Verify primary button and footers are visible
        expect(find.text('Create account'), findsOneWidget);
        expect(find.text('Already have an account?'), findsOneWidget);
        expect(find.text('Continue as Guest'), findsOneWidget);
        expect(find.text('© 2024 miee audio systems inc.'), findsOneWidget);

        // 4. Verify that SingleChildScrollView has NO scrollable extent (fits within 100vh)
        final scrollableFinder = find.byType(Scrollable);
        expect(scrollableFinder, findsWidgets);

        final scrollableState = tester.state<ScrollableState>(scrollableFinder.first);
        final position = scrollableState.position;
        expect(
          position.maxScrollExtent,
          equals(0.0),
          reason: 'At ${entry.key}, the page exceeded 100vh and required scrolling by ${position.maxScrollExtent}px!',
        );
      });
    }

    testWidgets('Password visibility toggle functions correctly on registration page', (tester) async {
      tester.view.physicalSize = const Size(1366, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Find visibility toggle buttons
      final visibilityIcons = find.byIcon(Icons.visibility_off_outlined);
      expect(visibilityIcons, findsNWidgets(2)); // Password and Confirm Password

      // Tap password visibility toggle
      await tester.tap(visibilityIcons.first);
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('Mobile viewport renders gracefully with single-column layout', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // On mobile, the desktop category pill and right showcase should not appear
      expect(find.text('SOUND ARCHITECTURE'), findsNothing);
      expect(find.text('Experience Sound in Its True Fidelity'), findsNothing);

      // Mobile elements must be present
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('FULL NAME'), findsOneWidget);
      expect(find.text('EMAIL ADDRESS'), findsOneWidget);
      expect(find.text('PASSWORD'), findsOneWidget);
      expect(find.text('CONFIRM PASSWORD'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
    });
  });
}
