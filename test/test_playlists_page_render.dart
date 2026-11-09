import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/core/storage/adapters/history_entry.dart';
import 'package:Miee/core/storage/adapters/playback_history_entry.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/storage/adapters/queue_snapshot.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/sync/network_monitor.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/domain/media_repository.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/playlists/presentation/playlists_page.dart';
import 'package:Miee/features/home/presentation/home_page.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/wrapped/providers/wrapped_providers.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/providers/recommendation_providers.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/features/profile/domain/user_profile_repository.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
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
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async => [];
  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async => [];
  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async => [];
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
    tempDir = await Directory.systemTemp.createTemp('miee_render_test_');
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
  });

  tearDown(() async {
    try {
      await Hive.close().timeout(const Duration(milliseconds: 500), onTimeout: () {});
    } catch (_) {}
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('PlaylistsPage renders without throwing exceptions', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        networkMonitorProvider.overrideWithValue(TestNetworkMonitor()),
        mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        userProfileRepositoryProvider.overrideWithValue(FakeUserProfileRepository()),
        currentAuthUserProvider.overrideWithValue(null),
        playbackHistoryWatcherProvider.overrideWith((ref) => const Stream.empty()),
        recentlyPlayedProvider.overrideWith((ref) => const Stream.empty()),
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

    expect(find.byType(PlaylistsPage), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('HomePage renders without throwing exceptions', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final webHandler = MieeAudioHandler();

    final container = ProviderContainer(
      overrides: [
        networkMonitorProvider.overrideWithValue(TestNetworkMonitor()),
        audioHandlerProvider.overrideWithValue(webHandler),
        mediaRepositoryProvider.overrideWithValue(FakeMediaRepository()),
        userProfileRepositoryProvider.overrideWithValue(FakeUserProfileRepository()),
        currentAuthUserProvider.overrideWithValue(null),
        dailyMixSnapshotProvider.overrideWith(() => TestDailyMixNotifier()),
        playbackHistoryWatcherProvider.overrideWith((ref) => const Stream.empty()),
        recentlyPlayedProvider.overrideWith((ref) => const Stream.empty()),
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

    expect(find.byType(HomePage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
}
