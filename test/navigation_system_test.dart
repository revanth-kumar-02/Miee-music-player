import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/shared/widgets/miee_brand_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Navigation System Specification Tests', () {
    testWidgets('1. MieeBrandHeader on home screen does not show back button by default', (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: MieeBrandHeader(
                  automaticallyImplyLeading: true,
                ),
              ),
              body: Text('Home Content'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MieeWordmarkDot), findsOneWidget);
      // On home screen, no back arrow button is rendered
      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('2. MieeBrandHeader on secondary screen with title displays back button', (tester) async {
      final router = GoRouter(
        initialLocation: '/settings',
        routes: [
          GoRoute(
            path: '/settings',
            builder: (context, state) => const Scaffold(
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: MieeBrandHeader(
                  title: 'Settings',
                  automaticallyImplyLeading: true,
                ),
              ),
              body: Text('Settings Content'),
            ),
          ),
          GoRoute(
            path: '/home',
            builder: (context, state) => const Scaffold(
              body: Text('Home Screen'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      // Secondary screen must render back arrow button
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Tap back button with empty stack -> navigates safely to /home fallback
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('3. Stack-based navigation pops to previous route or falls back to /home', (tester) async {
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) => Scaffold(
              appBar: const PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: MieeBrandHeader(),
              ),
              body: ElevatedButton(
                onPressed: () => context.push('/liked-songs'),
                child: const Text('Go to Liked'),
              ),
            ),
          ),
          GoRoute(
            path: '/liked-songs',
            builder: (context, state) => Scaffold(
              appBar: const PreferredSize(
                preferredSize: Size.fromHeight(60),
                child: MieeBrandHeader(
                  title: 'Liked Songs',
                  automaticallyImplyLeading: true,
                ),
              ),
              body: const Text('Liked Songs Content'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
        ),
      );
      await tester.pumpAndSettle();

      // Push /liked-songs onto stack
      await tester.tap(find.text('Go to Liked'));
      await tester.pumpAndSettle();

      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);

      // Tap back -> pops stack and returns to /home
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Go to Liked'), findsOneWidget);
    });
  });
}
