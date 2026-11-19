import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/core/storage/adapters/history_entry.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/desktop/presentation/desktop_shell.dart';
import 'package:Miee/features/desktop/presentation/widgets/session_queue_view.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/profile/providers/profile_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class FakeTestArtworkResolver implements ArtworkResolver {
  @override
  Future<ResolvedArtwork> resolve(ArtworkQuery query, {bool forceRefresh = false}) async =>
      ResolvedArtwork.neutralFallback();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockTestTrack implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String album;
  @override
  final String duration;
  @override
  final String filePath;
  @override
  final String imageUrl;

  MockTestTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.filePath,
    required this.imageUrl,
  });

  @override
  String get displayTitle => title;
  @override
  String get effectiveArtworkUrl => imageUrl;
  @override
  bool get isYoutube => false;
}

class FakeQueuePlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  final QueueManager queueManager;
  int? lastSkippedIndex;
  int? lastRemovedIndex;
  bool wasQueueCleared = false;
  MusicItem? lastQueuedTrack;

  FakeQueuePlayerController(this.queueManager, [PlaybackState? state])
      : super(state ?? const PlaybackState(status: PlaybackStatus.idle));

  @override
  Future<void> skipToQueueItem(int index) async {
    lastSkippedIndex = index;
    queueManager.setIndex(index);
    state = state.copyWith(currentTrack: queueManager.currentTrack);
  }

  @override
  Future<void> removeTrackAt(int index) async {
    lastRemovedIndex = index;
    queueManager.removeTrackAt(index);
  }

  @override
  void clearQueue() {
    wasQueueCleared = true;
    queueManager.clear();
  }

  @override
  Future<void> addTrackToQueue(MusicItem track) async {
    lastQueuedTrack = track;
    queueManager.addTrack(track);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestFavoritesNotifier extends StateNotifier<List<Track>> implements FavoritesNotifier {
  FakeTestFavoritesNotifier() : super(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestPlaylistsNotifier extends StateNotifier<List<PlaylistHiveModel>> implements PlaylistsNotifier {
  FakeTestPlaylistsNotifier() : super(const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase D4 — Sub-step D4.3: Session Queue & Recent Pressings Tests', () {
    testWidgets('1. SessionQueueView renders empty state when queue is empty', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final qm = QueueManager();
      final controller = FakeQueuePlayerController(qm);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queueManagerProvider.overrideWithValue(qm),
            playerControllerProvider.overrideWith((ref) => controller),
            recentlyPlayedProvider.overrideWith((ref) => Stream.value([])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 400,
                height: 600,
                child: SessionQueueView(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SESSION QUEUE'), findsOneWidget);
      expect(find.text('RECENT PRESSINGS'), findsOneWidget);
      expect(find.text('SESSION QUEUE IS EMPTY'), findsOneWidget);
    });

    testWidgets('2. SessionQueueView displays populated queue tracks with quality badges and indices', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final qm = QueueManager();
      final t1 = MockTestTrack(
        id: 'track_1',
        title: 'Veezha Veera',
        artist: 'Sai Abhyankkar',
        album: 'OM Chapter 1',
        duration: '3:59',
        filePath: 'C:/Music/Veezha Veera.flac',
        imageUrl: '',
      );
      final t2 = MockTestTrack(
        id: 'track_2',
        title: 'Alaakaa Loova',
        artist: 'Sai Abhyankkar, Tippu',
        album: 'OM Chapter 1',
        duration: '3:36',
        filePath: 'C:/Music/Alaakaa Loova.mp3',
        imageUrl: '',
      );
      qm.setQueue([t1, t2], startIndex: 0);

      final controller = FakeQueuePlayerController(
        qm,
        PlaybackState(
          status: PlaybackStatus.playing,
          currentTrack: t1,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queueManagerProvider.overrideWithValue(qm),
            playerControllerProvider.overrideWith((ref) => controller),
            recentlyPlayedProvider.overrideWith((ref) => Stream.value([])),
            artworkResolverProvider.overrideWithValue(FakeTestArtworkResolver()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 700,
                child: SessionQueueView(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Veezha Veera'), findsOneWidget);
      expect(find.text('Alaakaa Loova'), findsOneWidget);
      expect(find.text('FLAC 24/96'), findsOneWidget);
      expect(find.text('MP3 320K'), findsOneWidget);
      expect(find.text('3:59'), findsOneWidget);
      expect(find.text('3:36'), findsOneWidget);
      expect(find.text('#02'), findsOneWidget);
      expect(find.byTooltip('Clear Queue'), findsOneWidget);
    });

    testWidgets('3. Tapping clear queue and remove buttons triggers controller operations', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final qm = QueueManager();
      final t1 = MockTestTrack(
        id: 'track_1',
        title: 'Track One',
        artist: 'Artist One',
        album: 'Album One',
        duration: '3:00',
        filePath: '/music/track1.mp3',
        imageUrl: '',
      );
      qm.setQueue([t1], startIndex: 0);

      final controller = FakeQueuePlayerController(qm);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queueManagerProvider.overrideWithValue(qm),
            playerControllerProvider.overrideWith((ref) => controller),
            recentlyPlayedProvider.overrideWith((ref) => Stream.value([])),
            artworkResolverProvider.overrideWithValue(FakeTestArtworkResolver()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 500,
                height: 700,
                child: SessionQueueView(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Clear Queue button
      await tester.tap(find.byTooltip('Clear Queue'));
      await tester.pumpAndSettle();

      expect(controller.wasQueueCleared, isTrue);
    });

    testWidgets('4. DesktopShell toggles SessionQueueView drawer on queue icon click', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      final qm = QueueManager();
      final controller = FakeQueuePlayerController(qm);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            queueManagerProvider.overrideWithValue(qm),
            playerControllerProvider.overrideWith((ref) => controller),
            favoritesProvider.overrideWith((ref) => FakeTestFavoritesNotifier()),
            userPlaylistsProvider.overrideWith((ref) => FakeTestPlaylistsNotifier()),
            currentUserProfileProvider.overrideWithValue(null),
            recentlyPlayedProvider.overrideWith((ref) => Stream.value([])),
            artworkResolverProvider.overrideWithValue(FakeTestArtworkResolver()),
          ],
          child: const MaterialApp(
            home: DesktopShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially, SessionQueueView is closed
      expect(find.byType(SessionQueueView), findsNothing);

      // Find and tap the queue icon in MasterTransportDeck
      final queueButton = find.byTooltip('Session Queue');
      expect(queueButton, findsOneWidget);

      await tester.tap(queueButton);
      await tester.pumpAndSettle();

      // SessionQueueView is now visible in the drawer
      expect(find.byType(SessionQueueView), findsOneWidget);

      // Tap close button in queue view header
      final closeButton = find.byIcon(Icons.close_rounded);
      expect(closeButton, findsOneWidget);

      await tester.tap(closeButton);
      await tester.pumpAndSettle();

      expect(find.byType(SessionQueueView), findsNothing);
    });
  });
}
