import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/widgets/miee_brand_header.dart';
import 'package:Miee/shared/widgets/app_header.dart';

void main() {
  group('MieeBrandHeader & Stitch Branding Tests', () {
    testWidgets('1. Renders MieeWordmarkDot (miee.) on root header (no title)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(showProfileAvatar: true),
            body: SizedBox.expand(),
          ),
        ),
      );

      // Verify the canonical Stitch wordmark is rendered
      expect(find.byType(MieeWordmarkDot), findsOneWidget);

      // Verify profile and notifications actions appear
      expect(find.byIcon(Icons.person), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);
    });

    testWidgets('2. Renders MieeWordmarkDot and screen title with hairline divider when title is specified', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(title: 'Search'),
            body: SizedBox.expand(),
          ),
        ),
      );

      expect(find.byType(MieeWordmarkDot), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
    });

    testWidgets('3. PreferredSize conforms to standard 56.0 logical pixels', (tester) async {
      const header = MieeBrandHeader(title: 'Playlists');
      expect(header.preferredSize.height, equals(56.0));
    });

    testWidgets('4. Custom action buttons are rendered properly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              title: 'Playlists',
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () {},
                ),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );

      expect(find.text('Playlists'), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    });

    testWidgets('5. AppHeader delegates cleanly to MieeBrandHeader', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: AppHeader(title: 'Settings'),
            body: SizedBox.expand(),
          ),
        ),
      );

      // Verify AppHeader mounts MieeBrandHeader and MieeWordmarkDot
      expect(find.byType(MieeBrandHeader), findsOneWidget);
      expect(find.byType(MieeWordmarkDot), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('6. Leading widget is respected when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              title: 'Artist',
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {},
              ),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
    });

    testWidgets('7. Tapping notification bell triggers default non-blocking SnackBar feedback', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(showProfileAvatar: true),
            body: SizedBox.expand(),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      await tester.tap(bellFinder);
      await tester.pump(); // Start SnackBar animation

      expect(find.text('No new notifications'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('8. Repeated taps on notification bell are debounced safely without stacking', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(showProfileAvatar: true),
            body: SizedBox.expand(),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      // Tap multiple times in rapid succession
      await tester.tap(bellFinder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(bellFinder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(bellFinder);
      await tester.pump();

      // Only one active SnackBar should be displayed (previous dismissed via hideCurrentSnackBar)
      expect(find.text('No new notifications'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('9. Custom onNotificationTap callback is invoked when provided', (tester) async {
      bool customTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              showProfileAvatar: true,
              onNotificationTap: () {
                customTapped = true;
              },
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      await tester.tap(bellFinder);
      await tester.pump();

      expect(customTapped, isTrue);
      // Default SnackBar should NOT be shown when custom callback handled it
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('10. AppHeader forwards onNotificationTap callback correctly', (tester) async {
      bool appHeaderBellTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppHeader(
              title: 'Library',
              onNotificationTap: () {
                appHeaderBellTapped = true;
              },
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      await tester.tap(bellFinder);
      await tester.pump();

      expect(appHeaderBellTapped, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}

