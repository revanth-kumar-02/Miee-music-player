import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/onboarding/providers/onboarding_providers.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/domain/user_profile_repository.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/features/settings/presentation/favourite_artists_page.dart';

class MockArtistRepository implements ArtistRepository {
  @override
  Future<List<ArtistModel>> getPopularArtists({String? language}) async {
    return [
      const ArtistModel(
        id: '1',
        name: 'A. R. Rahman',
        imageUrl: '',
        languages: ['Tamil', 'Hindi'],
      ),
      const ArtistModel(
        id: '2',
        name: 'Sai Abhyankkar',
        imageUrl: '',
        languages: ['Tamil'],
      ),
      const ArtistModel(
        id: '3',
        name: 'Jonita Gandhi',
        imageUrl: '',
        languages: ['Tamil', 'Hindi'],
      ),
      const ArtistModel(
        id: '4',
        name: 'Anirudh Ravichander',
        imageUrl: '',
        languages: ['Tamil'],
      ),
      const ArtistModel(
        id: '5',
        name: 'Yuvan Shankar Raja',
        imageUrl: '',
        languages: ['Tamil'],
      ),
    ];
  }

  @override
  Future<List<ArtistModel>> searchArtists(String query,
      {String? language}) async {
    final all = await getPopularArtists(language: language);
    return all
        .where((a) => a.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<ArtistModel?> getArtistDetails(String artistId) async => null;

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async => [];

  @override
  Future<List<ArtistTopTrack>> getArtistTopTracks(String artistId) async => [];

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async => [];

  @override
  List<String> getSupportedLanguages() =>
      ['All', 'Tamil', 'Hindi', 'English', 'Telugu'];
}

class MockUserProfileRepository implements UserProfileRepository {
  UserProfile? storedProfile;

  MockUserProfileRepository([this.storedProfile]);

  @override
  Future<UserProfile?> getUserProfile(String uid) async => storedProfile;

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    storedProfile = profile;
  }

  @override
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
    String? displayName,
    String? email,
  }) async {
    final now = DateTime.now();
    final p = UserProfile(
      uid: uid,
      displayName: displayName ?? 'Miee Listener',
      email: email ?? '',
      selectedArtists: artists,
      selectedArtistIds: artists.map((a) => a.id).toList(),
      onboardingCompleted: true,
      createdAt: now,
      updatedAt: now,
    );
    storedProfile = p;
    return p;
  }

  @override
  Future<void> clearCache(String uid) async {}
}

class MockUserProfileNotifier extends StateNotifier<UserProfileState>
    implements UserProfileNotifier {
  final MockUserProfileRepository repo;

  MockUserProfileNotifier(UserProfile profile, this.repo)
      : super(UserProfileState(profile: profile, isLoading: false));

  @override
  void updateProfileLocally(UserProfile profile) {
    state = UserProfileState(profile: profile, isLoading: false);
    repo.storedProfile = profile;
  }

  @override
  Future<void> saveProfile(UserProfile profile) async {
    state = UserProfileState(profile: profile, isLoading: false);
    repo.storedProfile = profile;
  }

  @override
  Future<void> clearCache(String uid) async {}

  @override
  Future<void> loadProfile(String uid) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'FavouriteArtistsPage renders pre-populated saved artists and handles toggles',
      (tester) async {
    const initialArtists = [
      ArtistSummary(
        id: '1',
        name: 'A. R. Rahman',
        imageUrl: '',
        languages: ['Tamil', 'Hindi'],
      ),
      ArtistSummary(
        id: '2',
        name: 'Sai Abhyankkar',
        imageUrl: '',
        languages: ['Tamil'],
      ),
    ];

    final profile = UserProfile(
      uid: 'user_123',
      displayName: 'Test User',
      email: 'test@example.com',
      selectedArtists: initialArtists,
      selectedArtistIds: const ['1', '2'],
      onboardingCompleted: true,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final mockRepo = MockUserProfileRepository(profile);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          artistRepositoryProvider.overrideWithValue(MockArtistRepository()),
          userProfileRepositoryProvider.overrideWithValue(mockRepo),
          userProfileNotifierProvider.overrideWith(
            (ref) => MockUserProfileNotifier(profile, mockRepo),
          ),
        ],
        child: const MaterialApp(
          home: FavouriteArtistsPage(),
        ),
      ),
    );

    // Initial pump
    await tester.pumpAndSettle();

    // Verify title and app header back button exist
    expect(find.text('Favourite Artists'), findsWidgets);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    // Verify selection tray text
    expect(find.text('Current Selection'), findsOneWidget);
    expect(find.text('2 of 5 selected'), findsOneWidget);

    // Verify chips for initial pre-populated artists exist in selection tray
    expect(find.text('A. R. Rahman'), findsWidgets);
    expect(find.text('Sai Abhyankkar'), findsWidgets);

    // Verify popular artists loaded
    expect(find.text('Jonita Gandhi'), findsOneWidget);
    expect(find.text('Anirudh Ravichander'), findsOneWidget);

    // Tap Jonita Gandhi to select (adding 3rd artist)
    await tester.tap(find.text('Jonita Gandhi'));
    await tester.pumpAndSettle();

    expect(find.text('3 of 5 selected'), findsOneWidget);

    // Tap Save Preferences button
    final saveButton = find.text('Save Preferences (3 of 5)');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    // Verify repository received the 3 artists
    expect(mockRepo.storedProfile?.selectedArtists.length, equals(3));
  });

  testWidgets(
      'Delete playlist dialog pops dialog with boolean result without affecting parent route',
      (tester) async {
    bool? dialogResult;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final res = await showDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    title: const Text('Delete Playlist?'),
                    content: const Text('Are you sure you want to delete "one piece"?\nThis cannot be undone.'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogCtx).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                dialogResult = res;
              },
              child: const Text('Show Delete Dialog'),
            ),
          ),
        ),
      ),
    );

    // Tap to open dialog
    await tester.tap(find.text('Show Delete Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Playlist?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Tap Cancel -> should dismiss dialog, returning false, button remains
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(dialogResult, equals(false));
    expect(find.text('Delete Playlist?'), findsNothing);
    expect(find.text('Show Delete Dialog'), findsOneWidget);

    // Tap to open dialog again
    await tester.tap(find.text('Show Delete Dialog'));
    await tester.pumpAndSettle();

    // Tap Delete -> should dismiss dialog, returning true
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(dialogResult, equals(true));
    expect(find.text('Delete Playlist?'), findsNothing);
    expect(find.text('Show Delete Dialog'), findsOneWidget);
  });
}
