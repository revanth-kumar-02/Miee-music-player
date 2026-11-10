import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/storage/adapters/history_entry.dart';
import 'package:Miee/core/storage/adapters/playback_history_entry.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/storage/adapters/queue_snapshot.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/sync/network_monitor.dart';
import 'package:Miee/features/home/presentation/home_page.dart';
import 'package:Miee/features/playlists/presentation/playlists_page.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/domain/media_repository.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/profile/domain/user_profile_repository.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/providers/recommendation_providers.dart';
import 'package:Miee/features/recommendations/domain/daily_mix.dart';
import 'package:Miee/features/recommendations/providers/daily_mix_providers.dart';

class TestNetworkMonitor implements NetworkMonitor {
  final _controller = StreamController<bool>.broadcast();
  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;
  @override
  Future<bool> get isConnected async => false;
}

class TestDailyMixNotifier extends DailyMixNotifier {
  @override
  Future<DailyMixSnapshot> build() async => DailyMixSnapshot.empty('guest');
}

class FakeUserProfileRepository implements UserProfileRepository {
  @override
  Future<void> clearCache(String uid) async {}
  @override
  Future<UserProfile?> getUserProfile(String uid) async => null;
  @override
  Future<void> saveUserProfile(UserProfile profile) async {}
  @override
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
    String? displayName,
    String? email,
  }) async => UserProfile.initial(uid: uid, email: email ?? '', displayName: displayName ?? '');
}

class FakeMediaRepository implements MediaRepository {
  @override
  Future<bool> checkAndRequestPermissions() async => true;
  @override
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async => [
    const MediaSong(
      id: 'local_1',
      title: 'Local Test Track',
      artist: 'Local Artist',
      album: 'Local Album',
      duration: '3:30',
      durationMs: 210000,
      artworkPath: '',
      filePath: '/storage/emulated/0/Music/track1.mp3',
    ),
  ];
  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async => [
    const MediaAlbum(
      id: 'album_1',
      title: 'Local Album',
      artist: 'Local Artist',
      trackCount: 1,
      artworkPath: '',
    ),
  ];
  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async => [
    const MediaArtist(
      id: 'artist_1',
      name: 'Local Artist',
      trackCount: 1,
      albumCount: 1,
    ),
  ];
  @override
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false}) async => [];
  @override
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false}) async => [];
  @override
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false}) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tempDir = await Directory.systemTemp.createTemp('miee_persisted_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TrackHiveModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(PlaylistHiveModelAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(HistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(PlaybackHistoryEntryAdapter());
    if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(QueueSnapshotAdapter());

    await Future.wait([
      Hive.openBox<TrackHiveModel>(HiveBoxes.favorites),
      Hive.openBox<PlaylistHiveModel>(HiveBoxes.playlists),
      Hive.openBox<HistoryEntry>(HiveBoxes.recentlyPlayed),
      Hive.openBox<int>(HiveBoxes.mostPlayed),
      Hive.openBox<PlaybackHistoryEntry>(HiveBoxes.playbackHistory),
      Hive.openBox<QueueSnapshot>(HiveBoxes.queueState),
      Hive.openBox<String>(HiveBoxes.searchHistory),
      Hive.openBox<dynamic>(HiveBoxes.preferences),
      Hive.openBox<dynamic>(HiveBoxes.profile),
      Hive.openBox<dynamic>(HiveBoxes.offlineQueue),
      Hive.openBox<dynamic>(HiveBoxes.dailyMixes),
      Hive.openBox<dynamic>(HiveBoxes.artworkCache),
    ]);

    // POPULATE WITH REALISTIC DATA FROM PREVIOUS SESSION
    final favBox = Hive.box<TrackHiveModel>(HiveBoxes.favorites);
    await favBox.put('fav_1', TrackHiveModel(
      id: 'fav_1',
      title: 'Favorite Song',
      artist: 'Favorite Artist',
      imageUrl: 'https://example.com/art.jpg',
      duration: '3:45',
      filePath: null,
    ));

    final playlistBox = Hive.box<PlaylistHiveModel>(HiveBoxes.playlists);
    await playlistBox.put('p_1', PlaylistHiveModel(
      id: 'p_1',
      name: 'Vibes Playlist',
      createdAt: DateTime.now().subtract(const Duration(days: 2)),
      lastModified: DateTime.now(),
      tracks: [
        TrackHiveModel(
          id: 't_p1',
          title: 'Playlist Track 1',
          artist: 'Playlist Artist',
          imageUrl: '',
          duration: '4:00',
        ),
      ],
      customCoverPath: null,
    ));

    final historyBox = Hive.box<HistoryEntry>(HiveBoxes.recentlyPlayed);
    await historyBox.add(HistoryEntry(
      track: TrackHiveModel(
        id: 'youtube_abc123',
        title: 'Recently Played Video Track',
        artist: 'YT Artist',
        imageUrl: '',
        duration: '3:15',
      ),
      playedAt: DateTime.now().subtract(const Duration(minutes: 10)),
    ));

    final playbackHistBox = Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory);
    await playbackHistBox.add(PlaybackHistoryEntry(
      track: TrackHiveModel(
        id: 'youtube_abc123',
        title: 'Recently Played Video Track',
        artist: 'YT Artist',
        imageUrl: 'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
        duration: '3:15',
      ),
      startTime: DateTime.now().subtract(const Duration(minutes: 10)),
      completionPercent: 0.95,
      userId: 'user_123',
    ));

    final profileBox = Hive.box<dynamic>(HiveBoxes.profile);
    await profileBox.put('active_profile', {
      'displayName': 'Test User',
      'username': 'testuser',
      'favoriteGenre': 'Pop',
      'favoriteArtist': 'Test Artist',
      'createdDate': DateTime.now().subtract(const Duration(days: 30)).toIso8601String(),
      'lastOpened': DateTime.now().toIso8601String(),
    });

    final prefBox = Hive.box<dynamic>(HiveBoxes.preferences);
    await prefBox.put('account_created_at', DateTime.now().subtract(const Duration(days: 30)).toIso8601String());
  });

  tearDown(() async {
    try {
      await Hive.close().timeout(const Duration(milliseconds: 500), onTimeout: () {});
    } catch (_) {}
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('PlaylistsPage renders successfully with populated persisted Hive data', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final originalOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = (details) {
      errors.add(details);
      // print to test stdout
      debugPrint('TEST CAUGHT ERROR: ${details.exceptionAsString()}');
      debugPrint('STACK: ${details.stack}');
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final container = ProviderContainer(
      overrides: [
        networkMonitorProvider.overrideWithValue(TestNetworkMonitor()),
        mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        userProfileRepositoryProvider.overrideWithValue(FakeUserProfileRepository()),
        currentAuthUserProvider.overrideWithValue(null),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PlaylistsPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(PlaylistsPage), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(errors, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('HomePage renders successfully with populated persisted Hive data', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final originalOnError = FlutterError.onError;
    final errors = <FlutterErrorDetails>[];
    FlutterError.onError = (details) {
      errors.add(details);
      debugPrint('TEST CAUGHT ERROR: ${details.exceptionAsString()}');
      debugPrint('STACK: ${details.stack}');
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    final webHandler = MieeAudioHandler();

    final container = ProviderContainer(
      overrides: [
        networkMonitorProvider.overrideWithValue(TestNetworkMonitor()),
        audioHandlerProvider.overrideWithValue(webHandler),
        mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        userProfileRepositoryProvider.overrideWithValue(FakeUserProfileRepository()),
        currentAuthUserProvider.overrideWithValue(null),
        dailyMixSnapshotProvider.overrideWith(() => TestDailyMixNotifier()),
        recommendationSectionsProvider.overrideWith((ref) => Future.value(
          const RecommendationSections(
            popularTracks: [],
            fromYourArtists: [],
            discoverMore: [],
            recentlyPlayed: [],
          ),
        )),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: HomePage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(HomePage), findsOneWidget);
    expect(errors, isEmpty);

    // Drain pending timers from background resolvers
    await tester.pumpAndSettle(const Duration(seconds: 10));

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
