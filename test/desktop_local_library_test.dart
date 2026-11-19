import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/desktop/presentation/views/desktop_local_library_view.dart';
import 'package:Miee/features/media/domain/library_filter_policy.dart';
import 'package:Miee/features/media/domain/media_repository.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/shared/models/music_item.dart';

class FakeTestArtworkResolver implements ArtworkResolver {
  @override
  Future<ResolvedArtwork> resolve(ArtworkQuery query, {bool forceRefresh = false}) async =>
      ResolvedArtwork.neutralFallback();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDesktopLibraryPlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  MusicItem? selectedTrack;
  List<MusicItem>? selectedList;
  String? playingFromContext;

  FakeDesktopLibraryPlayerController([PlaybackState? state])
      : super(state ?? const PlaybackState(status: PlaybackStatus.idle));

  @override
  void selectTrack(MusicItem track, List<MusicItem> currentList, {String? playingFrom}) {
    selectedTrack = track;
    selectedList = currentList;
    playingFromContext = playingFrom;
    state = state.copyWith(
      currentTrack: track,
      status: PlaybackStatus.playing,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTestMediaRepository implements MediaRepository {
  List<MediaSong> songs = [];
  List<MediaAlbum> albums = [];
  List<MediaArtist> artists = [];
  List<MediaFolder> folders = [];

  @override
  Future<bool> checkAndRequestPermissions() async => true;

  @override
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async => songs;

  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async => albums;

  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async => artists;

  @override
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false}) async => folders;

  @override
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false}) async => const [];

  @override
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false}) async => const [];

  @override
  Future<LibraryFolderPreferences> getFolderPreferences() async => const LibraryFolderPreferences();

  @override
  Future<void> saveFolderPreferences(LibraryFolderPreferences preferences) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase D5 — Desktop Local Music Library & Playback Tests', () {
    testWidgets('1. DesktopLocalLibraryView renders studio header, rescan and add folder buttons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final fakeRepo = FakeTestMediaRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaRepositoryProvider.overrideWithValue(fakeRepo),
            playerControllerProvider.overrideWith((ref) => FakeDesktopLibraryPlayerController()),
            artworkResolverProvider.overrideWithValue(FakeTestArtworkResolver()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DesktopLocalLibraryView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('STUDIO CATALOG'), findsOneWidget);
      expect(find.text('RESCAN'), findsOneWidget);
      expect(find.text('ADD MUSIC FOLDER'), findsOneWidget);
      expect(find.text('NO LOCAL TRACKS FOUND'), findsOneWidget);
    });

    testWidgets('2. Displays populated track rows with format badges and handles row click to play', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final fakeRepo = FakeTestMediaRepository();
      final song1 = const MediaSong(
        id: 'desktop_1',
        title: 'Nallaru Po',
        artist: 'Sai Abhyankkar',
        album: 'OM Chapter 1',
        duration: '3:36',
        durationMs: 216000,
        filePath: 'C:/Music/Nallaru Po.flac',
        artworkPath: '',
      );
      final song2 = const MediaSong(
        id: 'desktop_2',
        title: 'Veezha Veera',
        artist: 'Sai Abhyankkar, Dhanush',
        album: 'OM Chapter 1',
        duration: '3:59',
        durationMs: 239000,
        filePath: 'C:/Music/Veezha Veera.mp3',
        artworkPath: '',
      );
      fakeRepo.songs = [song1, song2];

      final controller = FakeDesktopLibraryPlayerController();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaRepositoryProvider.overrideWithValue(fakeRepo),
            playerControllerProvider.overrideWith((ref) => controller),
            artworkResolverProvider.overrideWithValue(FakeTestArtworkResolver()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DesktopLocalLibraryView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nallaru Po'), findsOneWidget);
      expect(find.text('Veezha Veera'), findsOneWidget);
      expect(find.text('FLAC 24/96'), findsOneWidget);
      expect(find.text('MP3 320K'), findsOneWidget);

      // Tap the second track row to trigger immediate playback
      await tester.tap(find.text('Veezha Veera'));
      await tester.pumpAndSettle();

      expect(controller.selectedTrack?.id, equals('desktop_2'));
      expect(controller.selectedList?.length, equals(2));
      expect(controller.playingFromContext, equals('Studio Catalog'));
    });

    testWidgets('3. Filters catalog tracks by text query', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final fakeRepo = FakeTestMediaRepository();
      fakeRepo.songs = [
        const MediaSong(
          id: 'desktop_1',
          title: 'Coldplay - Yellow',
          artist: 'Coldplay',
          album: 'Parachutes',
          duration: '4:29',
          durationMs: 269000,
          filePath: 'C:/Music/Coldplay - Yellow.mp3',
          artworkPath: '',
        ),
        const MediaSong(
          id: 'desktop_2',
          title: 'Imagine Dragons - Believer',
          artist: 'Imagine Dragons',
          album: 'Evolve',
          duration: '3:24',
          durationMs: 204000,
          filePath: 'C:/Music/Imagine Dragons - Believer.flac',
          artworkPath: '',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaRepositoryProvider.overrideWithValue(fakeRepo),
            playerControllerProvider.overrideWith((ref) => FakeDesktopLibraryPlayerController()),
            artworkResolverProvider.overrideWithValue(FakeTestArtworkResolver()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DesktopLocalLibraryView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Coldplay - Yellow'), findsOneWidget);
      expect(find.text('Imagine Dragons - Believer'), findsOneWidget);

      // Enter filter text "Yellow"
      await tester.enterText(find.byType(TextField), 'Yellow');
      await tester.pumpAndSettle();

      expect(find.text('Coldplay - Yellow'), findsOneWidget);
      expect(find.text('Imagine Dragons - Believer'), findsNothing);
    });

    testWidgets('4. Tapping ADD MUSIC FOLDER opens folder selection dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));

      final fakeRepo = FakeTestMediaRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaRepositoryProvider.overrideWithValue(fakeRepo),
            playerControllerProvider.overrideWith((ref) => FakeDesktopLibraryPlayerController()),
            artworkResolverProvider.overrideWithValue(FakeTestArtworkResolver()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: DesktopLocalLibraryView(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('ADD MUSIC FOLDER'));
      await tester.pumpAndSettle();

      expect(find.text('ADD LOCAL MUSIC FOLDER'), findsOneWidget);
      expect(find.text('ADD & SCAN'), findsOneWidget);
    });
  });
}
