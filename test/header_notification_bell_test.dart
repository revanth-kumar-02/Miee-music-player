import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/app_header.dart';
import 'package:Miee/shared/widgets/main_app_shell.dart';
import 'package:Miee/shared/widgets/miee_brand_header.dart';

class FakeShellPlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  FakeShellPlayerController([pb.PlaybackState? initialState])
      : super(initialState ?? pb.PlaybackState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Header Notification Bell Interaction Tests', () {
    testWidgets('Tapping notification bell in MieeBrandHeader displays non-blocking SnackBar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              title: 'Explore',
              showProfileAvatar: true,
            ),
            body: Center(child: Text('Content')),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      await tester.tap(bellFinder);
      await tester.pump();

      expect(find.text('No new notifications'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('Rapid taps on notification bell clear previous SnackBar safely', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              showProfileAvatar: true,
            ),
            body: Center(child: Text('Content')),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      // Perform three rapid taps
      await tester.tap(bellFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(bellFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(bellFinder);
      await tester.pump();

      // Exactly one SnackBar is visible on screen
      expect(find.text('No new notifications'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('Custom onNotificationTap callback overrides default SnackBar behavior', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              showProfileAvatar: true,
              onNotificationTap: () {
                tapCount++;
              },
            ),
            body: const Center(child: Text('Content')),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      await tester.tap(bellFinder);
      await tester.pump();

      expect(tapCount, equals(1));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('AppHeader properly connects onNotificationTap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppHeader(
              title: 'Playlists',
              onNotificationTap: () {
                tapped = true;
              },
            ),
            body: const Center(child: Text('Content')),
          ),
        ),
      );

      final bellFinder = find.byTooltip('Notifications');
      expect(bellFinder, findsOneWidget);

      await tester.tap(bellFinder);
      await tester.pump();

      expect(tapped, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('Desktop MainAppShell top bar notification bell triggers truthful feedback', (tester) async {
      final fakePlayer = FakeShellPlayerController(
        pb.PlaybackState.initial().copyWith(
          currentTrack: Track(
            id: 'trk_1',
            title: 'Sample Track',
            artist: 'Sample Artist',
            imageUrl: '',
            duration: '3:00',
          ),
        ),
      );

      // Desktop viewport size
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => fakePlayer),
          ],
          child: const MaterialApp(
            home: MainAppShell(
              child: Scaffold(
                body: Text('Desktop Content Area'),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final bellFinder = find.byIcon(Icons.notifications_none_rounded);
      expect(bellFinder, findsOneWidget);

      await tester.tap(bellFinder);
      await tester.pump();

      expect(find.text('No new notifications'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('MieeBrandHeader preserves brand logo, back navigation, and profile avatar', (tester) async {
      bool logoTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: MieeBrandHeader(
              showProfileAvatar: true,
              onLogoTap: () {
                logoTapped = true;
              },
            ),
            body: const Center(child: Text('Content')),
          ),
        ),
      );

      // Verify wordmark is present
      expect(find.byType(MieeWordmarkDot), findsOneWidget);

      // Verify profile avatar is present
      expect(find.byIcon(Icons.person), findsOneWidget);

      // Verify notification bell is present
      expect(find.byIcon(Icons.notifications_none_rounded), findsOneWidget);

      // Tap logo
      await tester.tap(find.byType(MieeWordmarkDot));
      expect(logoTapped, isTrue);
    });
  });
}
