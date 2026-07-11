// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/features/splash/presentation/splash_page.dart';

void main() {
  testWidgets('SplashPage title smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: SplashPage(),
        ),
      ),
    );

    // Verify that our Splash screen is displayed with the title 'Miee'.
    expect(find.text('Miee'), findsOneWidget);

    // Let the SplashPage navigation timer complete to satisfy test invariants.
    await tester.pump(const Duration(seconds: 3));
  });
}
