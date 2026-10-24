import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
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
  group('Header Clean Layout Tests — Unused Notification Bell Removed', () {
    testWidgets('MieeBrandHeader omits notification bell for clean minimalist profile header', (tester) async {
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
      expect(bellFinder, findsNothing);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    });

    testWidgets('AppHeader renders clean title and profile without notification bell clutter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            appBar: AppHeader(
              title: 'Settings',
            ),
            body: Center(child: Text('Settings Body')),
          ),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    });

    testWidgets('MainAppShell top bar displays avatar and search without notification bell', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => FakeShellPlayerController()),
            playlistControllerProvider.overrideWith((ref) => FakeShellPlaylistController()),
            profileProvider.overrideWith((ref) => FakeShellProfileController()),
            favoritesProvider.overrideWith((ref) => FakeShellFavoritesNotifier()),
          ],
          child: const MaterialApp(
            home: MainAppShell(
              child: Scaffold(body: Text('Home Feed')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
    });
  });
}
