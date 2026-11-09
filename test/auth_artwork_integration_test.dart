import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/auth/presentation/login_page.dart';
import 'package:Miee/features/auth/presentation/register_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auth Artwork Integration Tests', () {
    testWidgets('RegisterPage renders register_vinyl.png hero image', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: RegisterPage(),
          ),
        ),
      );
      await tester.pump();

      // Find the register hero image widget
      final registerImageFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final assetImage = widget.image as AssetImage;
          return assetImage.assetName == 'assets/images/auth/register_vinyl.png';
        }
        return false;
      });

      expect(registerImageFinder, findsOneWidget);

      // Verify no login collage is rendered on RegisterPage
      final loginImageFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final assetImage = widget.image as AssetImage;
          return assetImage.assetName == 'assets/images/auth/login_collage.png';
        }
        return false;
      });
      expect(loginImageFinder, findsNothing);
    });

    testWidgets('LoginPage renders login_collage.png on desktop viewport', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginPage(),
          ),
        ),
      );
      await tester.pump();

      // Find the login collage image widget
      final loginImageFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final assetImage = widget.image as AssetImage;
          return assetImage.assetName == 'assets/images/auth/login_collage.png';
        }
        return false;
      });

      expect(loginImageFinder, findsOneWidget);

      // Verify no register vinyl is rendered on LoginPage
      final registerImageFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final assetImage = widget.image as AssetImage;
          return assetImage.assetName == 'assets/images/auth/register_vinyl.png';
        }
        return false;
      });
      expect(registerImageFinder, findsNothing);

      // Verify form elements on desktop
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(find.text('Remember me'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('Continue as Guest'), findsOneWidget);
    });

    testWidgets('LoginPage on mobile renders login_collage.png hero image', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginPage(),
          ),
        ),
      );
      await tester.pump();

      // Hero image should appear on mobile
      final loginImageFinder = find.byWidgetPredicate((widget) {
        if (widget is Image && widget.image is AssetImage) {
          final assetImage = widget.image as AssetImage;
          return assetImage.assetName == 'assets/images/auth/login_collage.png';
        }
        return false;
      });
      expect(loginImageFinder, findsOneWidget);

      // Form remains functional on mobile
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Enter your email'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(find.text('Log in'), findsOneWidget);
    });
  });
}
