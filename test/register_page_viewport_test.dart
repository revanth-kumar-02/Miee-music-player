import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/auth/presentation/register_page.dart';
import 'package:Miee/features/auth/presentation/widgets/auth_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createTestWidget() {
    return const ProviderScope(
      child: MaterialApp(
        home: RegisterPage(),
      ),
    );
  }

  group('Registration Page Layout & Viewport Tests', () {
    testWidgets('Password visibility toggle functions correctly on registration page', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // Find visibility toggle button (single toggle for the sole password field)
      final visibilityIcon = find.byIcon(Icons.visibility_off_outlined);
      expect(visibilityIcon, findsOneWidget);

      // Tap password visibility toggle
      await tester.tap(visibilityIcon);
      await tester.pump();

      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    });

    testWidgets('Mobile viewport renders vinyl hero, exactly 3 fields and no confirm password', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      // 1. Vinyl hero image is present
      final vinylImage = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final asset = widget.image as AssetImage;
          return asset.assetName == 'assets/images/auth/register_vinyl.png';
        }
        return false;
      });
      expect(vinylImage, findsOneWidget);

      // 2. Heading & Subtitle
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('A home for all the music you love.'), findsOneWidget);

      // 3. Exactly 3 fields: Full Name, Email, Password
      expect(find.byType(AuthTextField), findsNWidgets(3));
      expect(find.text('Enter your full name'), findsOneWidget);
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Create a password'), findsOneWidget);
      expect(find.text('CONFIRM PASSWORD'), findsNothing);
      expect(find.text('Confirm your password'), findsNothing);

      // 4. Password validation requirement indicator
      expect(find.text('At least 8 characters with a letter and a number.'), findsOneWidget);

      // 5. Actions and legal links
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
    });

    testWidgets('Desktop viewport renders dual-pane layout with vinyl showcase', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Enter your full name'), findsOneWidget);
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Create a password'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
      expect(find.text('© 2024 miee audio systems inc.'), findsOneWidget);
    });
  });
}
