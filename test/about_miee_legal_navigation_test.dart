import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/features/settings/domain/settings_model.dart';
import 'package:Miee/features/settings/presentation/settings_controller.dart';
import 'package:Miee/features/settings/presentation/settings_page.dart';
import 'package:Miee/features/legal/presentation/legal_document_page.dart';
import 'package:Miee/features/about/presentation/miee_dedication_page.dart';
import 'package:Miee/shared/models/track.dart';

class MockFavoritesNotifier extends StateNotifier<List<Track>>
    implements FavoritesNotifier {
  MockFavoritesNotifier() : super([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSearchHistoryNotifier extends StateNotifier<List<String>>
    implements SearchHistoryNotifier {
  MockSearchHistoryNotifier() : super([]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileController extends StateNotifier<ProfileModel>
    implements ProfileController {
  FakeProfileController() : super(ProfileModel.defaultProfile());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlaylistController extends StateNotifier<PlaylistsState>
    implements PlaylistController {
  FakePlaylistController() : super(const PlaylistsState(playlists: []));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSettingsController extends StateNotifier<SettingsModel>
    implements SettingsController {
  FakeSettingsController() : super(const SettingsModel());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeMediaLibraryService extends StateNotifier<MediaLibraryState>
    implements MediaLibraryService {
  FakeMediaLibraryService() : super(MediaLibraryState.initial());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  FakePlayerController(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget createSettingsScreen() {
  return ProviderScope(
    overrides: [
      playerControllerProvider.overrideWith(
        (ref) => FakePlayerController(const pb.PlaybackState(status: pb.PlaybackStatus.idle)),
      ),
      favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
      searchHistoryProvider.overrideWith((ref) => MockSearchHistoryNotifier()),
      profileProvider.overrideWith((ref) => FakeProfileController()),
      playlistControllerProvider.overrideWith((ref) => FakePlaylistController()),
      settingsControllerProvider.overrideWith((ref) => FakeSettingsController()),
      mediaLibraryServiceProvider.overrideWith((ref) => FakeMediaLibraryService()),
      currentUserProfileProvider.overrideWith((ref) => null),
      currentAuthUserProvider.overrideWith((ref) => null),
    ],
    child: const MaterialApp(
      home: SettingsPage(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SettingsPage renders About Miee with Version 2.0.0 and all legal entries',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSettingsScreen());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Contact Support'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Verify About Miee header & understated note tile
    expect(find.text('About Miee'), findsNWidgets(2));
    expect(find.text('A quiet note on how this space came to be'), findsOneWidget);

    // Verify Version 2.0.0
    expect(find.text('Miee Version'), findsOneWidget);
    expect(find.text('v2.0.0 (Build 2) • Production Release'), findsOneWidget);

    // Verify Open Source Licenses tile
    expect(find.text('Open Source Licenses'), findsOneWidget);
    expect(find.text('Review third-party library notices and license terms'), findsOneWidget);

    // Verify Privacy Policy tile
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Review data handling, cloud sync, and user rights'), findsOneWidget);

    // Verify Terms of Service tile
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Review conditions of usage, content rights, and disclaimers'), findsOneWidget);

    // Verify Contact Support tile
    expect(find.text('Contact Support'), findsOneWidget);
    expect(find.text('imposterz.rev02@gmail.com'), findsOneWidget);
  });

  testWidgets('Tapping Privacy Policy opens full in-app LegalDocumentPage', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSettingsScreen());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Privacy Policy'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tap Privacy Policy
    await tester.tap(find.text('Privacy Policy'));
    await tester.pumpAndSettle();

    // Verify LegalDocumentPage is pushed
    expect(find.byType(LegalDocumentPage), findsOneWidget);
    expect(find.text('Legal & Release Info'), findsOneWidget);
    expect(find.text('1. Introduction & Local-First Scope'), findsOneWidget);
    expect(find.text('6. Zero Analytics & Zero Advertising'), findsOneWidget);

    // Pop back
    final backBtn = find.byTooltip('Back');
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();
  });

  testWidgets('Tapping Terms of Service opens full in-app LegalDocumentPage', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSettingsScreen());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Terms of Service'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tap Terms of Service
    await tester.tap(find.text('Terms of Service'));
    await tester.pumpAndSettle();

    // Verify LegalDocumentPage is pushed with Terms tab
    expect(find.byType(LegalDocumentPage), findsOneWidget);
    expect(find.text('1. Acceptance of Terms'), findsOneWidget);
    expect(find.text('3. User Responsibilities & Acceptable Use'), findsOneWidget);

    // Pop back
    final backBtn = find.byTooltip('Back');
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();
  });

  testWidgets('Tapping Open Source Licenses opens full in-app LegalDocumentPage with search',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSettingsScreen());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Open Source Licenses'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tap Open Source Licenses
    await tester.tap(find.text('Open Source Licenses'));
    await tester.pumpAndSettle();

    // Verify LegalDocumentPage is pushed with Licenses tab
    expect(find.byType(LegalDocumentPage), findsOneWidget);
    expect(find.text('Direct (19)'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // Pop back
    final backBtn = find.byTooltip('Back');
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();
  });

  testWidgets('Tapping Miee Version opens full in-app LegalDocumentPage with About tab',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSettingsScreen());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Miee Version'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tap Miee Version
    await tester.tap(find.text('Miee Version'));
    await tester.pumpAndSettle();

    // Verify LegalDocumentPage is pushed with About tab
    expect(find.byType(LegalDocumentPage), findsOneWidget);
    expect(find.text('Version 2.0.0 (Build 2) • Production Release'), findsOneWidget);
    expect(find.text('Version Overview'), findsOneWidget);
  });

  testWidgets('Tapping About Miee note opens dedicated MieeDedicationPage with exact copy and back navigation',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(createSettingsScreen());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('A quiet note on how this space came to be'),
      200.0,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Tap the understated note tile
    await tester.tap(find.text('A quiet note on how this space came to be'));
    await tester.pumpAndSettle();

    // Verify MieeDedicationPage is pushed full-screen
    expect(find.byType(MieeDedicationPage), findsOneWidget);

    // Verify opening headline
    expect(find.text('Some names are more than names.'), findsOneWidget);

    // Verify exact pacing and body copy
    expect(
      find.text('Somewhere between a memory and a feeling, a little name found its way into something bigger.'),
      findsOneWidget,
    );
    expect(
      find.text('And that is how Miee came to be.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'This little space was created in memory of someone who will always be my favorite — someone whose place in my story doesn\'t need to be explained to the world.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Maybe time changes things. Maybe life takes people in different directions. But some feelings leave behind something beautiful.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('For me, that something became Miee.'),
      findsOneWidget,
    );

    // Verify callout box line
    expect(
      find.text('A little piece of a memory, made to live on in music.'),
      findsOneWidget,
    );

    // Verify closing whisper line
    expect(
      find.text('Some things are better kept in the heart than explained in words.'),
      findsOneWidget,
    );

    // Verify Android / App bar back navigation returns cleanly
    final backBtn = find.byTooltip('Back');
    expect(backBtn, findsOneWidget);
    await tester.tap(backBtn);
    await tester.pumpAndSettle();

    // Back on SettingsPage
    expect(find.byType(MieeDedicationPage), findsNothing);
    expect(find.byType(SettingsPage), findsOneWidget);
  });
}
