import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/app/theme/midnight_velvet_tokens.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/features/desktop/presentation/desktop_shell.dart';
import 'package:Miee/features/desktop/presentation/widgets/desktop_sidebar.dart';
import 'package:Miee/features/desktop/presentation/widgets/desktop_floating_player.dart';
import 'package:Miee/features/desktop/presentation/widgets/left_console_rail.dart';
import 'package:Miee/features/desktop/presentation/widgets/top_telemetry_header.dart';
import 'package:Miee/features/desktop/presentation/widgets/master_transport_deck.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/shared/models/track.dart';

class FakePlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  FakePlayerController([PlaybackState? state])
      : super(state ?? const PlaybackState(status: PlaybackStatus.idle));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFavoritesNotifier extends StateNotifier<List<Track>> implements FavoritesNotifier {
  FakeFavoritesNotifier([List<Track>? initial]) : super(initial ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlaylistsNotifier extends StateNotifier<List<PlaylistHiveModel>> implements PlaylistsNotifier {
  FakePlaylistsNotifier([List<PlaylistHiveModel>? initial]) : super(initial ?? const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase D3 — Desktop Midnight Velvet Layout & Tokens Tests', () {
    test('1. Midnight Velvet design tokens match spec constants', () {
      expect(MidnightVelvetTokens.canvasBase, equals(const Color(0xFF121114)));
      expect(MidnightVelvetTokens.primaryEmber, equals(const Color(0xFFFF385C)));
      expect(MidnightVelvetTokens.amberChampagne, equals(const Color(0xFFF59E0B)));
      expect(MidnightVelvetTokens.consoleRailWidth, equals(260.0));
      expect(MidnightVelvetTokens.telemetryHeaderHeight, equals(68.0));
      expect(MidnightVelvetTokens.masterDeckHeight, equals(88.0));
    });

    testWidgets('2. LeftConsoleRail renders brand header, sections, and DAC telemetry', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      DesktopNavSection active = DesktopNavSection.nowSpinning;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            userPlaylistsProvider.overrideWith((ref) => FakePlaylistsNotifier()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: LeftConsoleRail(
                activeSection: active,
                onSectionChanged: (s) => active = s,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('miee.'), findsOneWidget);
      expect(find.text('STUDIO'), findsOneWidget);
      expect(find.text('Now Spinning'), findsOneWidget);
      expect(find.text('Crates & Mixes'), findsOneWidget);
      expect(find.text('Studio Catalog'), findsOneWidget);
      expect(find.text('AUDIO ENGINE: ACTIVE'), findsOneWidget);
      expect(find.text('Direct Output • 48.0 kHz'), findsOneWidget);
    });

    testWidgets('3. TopTelemetryHeader renders search input, shortcuts, and telemetry badge', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(status: PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: TopTelemetryHeader(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('⌘K'), findsOneWidget);
      expect(find.text('Search artists, tracks, or soundscapes...'), findsOneWidget);
      expect(find.text('DAC STANDBY • 44.1 KHZ'), findsOneWidget);
    });

    testWidgets('4. DesktopShell mounts compact sidebar, floating player, and stage child', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            userPlaylistsProvider.overrideWith((ref) => FakePlaylistsNotifier()),
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(status: PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: DesktopShell(
              child: Center(
                child: Text('MIEE STUDIO MASTER CONSOLE'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DesktopSidebar), findsOneWidget);
      expect(find.byType(DesktopFloatingPlayer), findsOneWidget);
      expect(find.text('MIEE STUDIO MASTER CONSOLE'), findsOneWidget);
    });

    testWidgets('5. DesktopDashboardView renders authentic reference headers and cards', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            userPlaylistsProvider.overrideWith((ref) => FakePlaylistsNotifier()),
            currentUserProfileProvider.overrideWithValue(null),
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(const PlaybackState(status: PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DesktopShell(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FEATURED SPOTLIGHT'), findsOneWidget);
      expect(find.text('Kannukulla'), findsAtLeast(1));
      expect(find.text('Play Now'), findsOneWidget);
      expect(find.text('Continue Listening'), findsOneWidget);
      expect(find.text('Popular Artists'), findsOneWidget);
      expect(find.text('Sai Abhyankkar'), findsAtLeast(1));
      expect(find.text('A. R. Rahman'), findsOneWidget);
      expect(find.text('Anirudh Ravichander'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('On Repeat'), findsOneWidget);
      expect(find.text('Daily Mixes'), findsOneWidget);
      expect(find.text('Daily Mix 1'), findsOneWidget);
      expect(find.text('Daily Mix 2'), findsOneWidget);
      expect(find.byType(DesktopFloatingPlayer), findsOneWidget);
    });
  });
}
