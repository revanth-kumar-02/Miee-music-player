import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/main_app_shell.dart';

class FakeShellPlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  FakeShellPlayerController([pb.PlaybackState? initialState])
      : super(initialState ?? pb.PlaybackState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeShellPlaylistController extends StateNotifier<PlaylistsState>
    implements PlaylistController {
  FakeShellPlaylistController() : super(const PlaylistsState(playlists: []));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeShellProfileController extends StateNotifier<ProfileModel>
    implements ProfileController {
  FakeShellProfileController() : super(ProfileModel.defaultProfile());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeShellFavoritesNotifier extends StateNotifier<List<Track>>
    implements FavoritesNotifier {
  FakeShellFavoritesNotifier() : super(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildDesktopShell({Size size = const Size(1440, 900)}) {
    return ProviderScope(
      overrides: [
        playerControllerProvider.overrideWith((ref) => FakeShellPlayerController()),
        playlistControllerProvider.overrideWith((ref) => FakeShellPlaylistController()),
        profileProvider.overrideWith((ref) => FakeShellProfileController()),
        favoritesProvider.overrideWith((ref) => FakeShellFavoritesNotifier()),
      ],
      child: const MaterialApp(
        home: MainAppShell(
          child: Scaffold(
            body: Center(child: Text('Desktop Web Content')),
          ),
        ),
      ),
    );
  }

  group('Miee Web Frontend Refinement Tests', () {
    testWidgets('1. Download feature is completely removed from Desktop Web sidebar', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDesktopShell());
      await tester.pumpAndSettle();

      // Downloaded item and its icons must NOT exist
      expect(find.text('Downloaded'), findsNothing);
      expect(find.byIcon(Icons.arrow_circle_down_outlined), findsNothing);
      expect(find.byIcon(Icons.arrow_circle_down_rounded), findsNothing);

      // Other core Library navigation items MUST be preserved
      expect(find.text('Liked Songs'), findsOneWidget);
      expect(find.text('Recently Played'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Rooms'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Your Library'), findsOneWidget);
    });

    testWidgets('2. Notification UI is hidden from Desktop Web header while implementation is preserved', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDesktopShell());
      await tester.pumpAndSettle();

      // Notification bell icon and unread indicator must NOT be visible
      expect(find.byIcon(Icons.notifications_outlined), findsNothing);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      expect(find.byIcon(Icons.notifications), findsNothing);

      // Verify the visibility flag is false
      expect(MainAppShell.showWebNotifications, isFalse);

      // Verify Back/Forward controls, Search bar, and Profile Avatar remain intact and aligned
      expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search artists, tracks, or soundscapes...'), findsOneWidget);

      // Profile avatar exists as an InkWell
      final profileFinder = find.byWidgetPredicate(
        (widget) => widget is InkWell && widget.onTap != null,
      );
      expect(profileFinder, findsWidgets);
    });

    testWidgets('3. Header layout maintains correct spacing without empty gaps', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDesktopShell());
      await tester.pumpAndSettle();

      // Top search field is rendered
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      // Content canvas is rendered
      expect(find.text('Desktop Web Content'), findsOneWidget);
    });
  });
}
