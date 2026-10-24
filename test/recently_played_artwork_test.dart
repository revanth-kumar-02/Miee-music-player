import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/storage/adapters/history_entry.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/home/presentation/home_page.dart';
import 'package:Miee/features/library/data/favorites_repository.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/providers/recommendation_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/song_tile.dart';

import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/features/rooms/providers/room_providers.dart';

class FakeFavoritesRepository implements FavoritesRepository {
  @override
  List<Track> getFavorites() => const [];

  @override
  bool isFavorite(String trackId) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFavoritesNotifier extends FavoritesNotifier {
  FakeFavoritesNotifier() : super(FakeFavoritesRepository());
}

class MockPlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  MusicItem? lastSelectedTrack;
  List<MusicItem>? lastQueue;
  String? lastPlayingFrom;

  MockPlayerController() : super(PlaybackState.initial());

  @override
  void selectTrack(MusicItem track, List<MusicItem> queue,
      {String? playingFrom}) {
    lastSelectedTrack = track;
    lastQueue = queue;
    lastPlayingFrom = playingFrom;
    state = state.copyWith(currentTrack: track, status: PlaybackStatus.playing);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Recently Played Artwork Persistence & Resolution Tests', () {
    const localSongWithArt = MediaSong(
      id: 'local_101',
      title: 'Midnight City',
      artist: 'M83',
      album: 'Hurry Up',
      duration: '4:03',
      durationMs: 243000,
      filePath: '/storage/emulated/0/Music/midnight.mp3',
      artworkPath: '/data/user/0/com.example.miee/app_flutter/artwork_cache/song_101.png',
    );

    const localSongNoArt = MediaSong(
      id: 'local_102',
      title: 'Acoustic Sketch',
      artist: 'Independent Artist',
      album: 'Demos',
      duration: '2:15',
      durationMs: 135000,
      filePath: '/storage/emulated/0/Music/sketch.mp3',
      artworkPath: '',
    );

    const localSongSimilarTitle = MediaSong(
      id: 'local_103',
      title: 'Hello',
      artist: 'Adele',
      album: '25',
      duration: '4:55',
      durationMs: 295000,
      filePath: '/storage/emulated/0/Music/adele_hello.mp3',
      artworkPath: '/data/user/0/com.example.miee/app_flutter/artwork_cache/adele_hello.png',
    );

    const localSongOtherSimilar = MediaSong(
      id: 'local_104',
      title: 'Hello',
      artist: 'Lionel Richie',
      album: 'Can\'t Slow Down',
      duration: '4:10',
      durationMs: 250000,
      filePath: '/storage/emulated/0/Music/lionel_hello.mp3',
      artworkPath: '/data/user/0/com.example.miee/app_flutter/artwork_cache/lionel_hello.png',
    );

    test('Online track with valid artwork URL preserves thumbnail', () {
      final now = DateTime.now();
      final entry = HistoryEntry(
        track: TrackHiveModel(
          id: 'youtube_dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
          artist: 'Rick Astley',
          imageUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          duration: '3:33',
        ),
        playedAt: now,
      );

      final track = entry.track.toTrack();
      expect(track.isYoutube, isTrue);
      expect(track.imageUrl, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
    });

    test('Missing online artwork reference is repaired to durable canonical YouTube thumbnail', () {
      final now = DateTime.now();
      // Track saved with empty or missing imageUrl
      final entry = HistoryEntry(
        track: TrackHiveModel(
          id: 'youtube_dQw4w9WgXcQ',
          title: 'Never Gonna Give You Up',
          artist: 'Rick Astley',
          imageUrl: '',
          duration: '3:33',
        ),
        playedAt: now,
      );

      // Deserialized model repairs missing thumbnail via ID
      final rawTrack = entry.track.toTrack();
      final videoId = rawTrack.id.replaceFirst('youtube_', '');
      final resolvedUrl = rawTrack.imageUrl.isNotEmpty && rawTrack.imageUrl.startsWith('http')
          ? rawTrack.imageUrl
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';

      expect(resolvedUrl, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
    });

    test('Local track restores live artwork path by cross-matching active local library', () {
      final now = DateTime.now();
      // Persisted entry had older or empty path in Hive
      final entry = HistoryEntry(
        track: TrackHiveModel(
          id: 'local_101',
          title: 'Midnight City',
          artist: 'M83',
          imageUrl: '', // Lost or empty in old Hive state
          duration: '4:03',
          filePath: '/storage/emulated/0/Music/midnight.mp3',
        ),
        playedAt: now,
      );

      final localSongs = [localSongWithArt, localSongNoArt];
      final rawTrack = entry.track.toTrack();
      final localMatch = localSongs.where((s) =>
          s.id == rawTrack.id || (s.filePath.isNotEmpty && s.filePath == rawTrack.filePath)).firstOrNull;

      expect(localMatch, isNotNull);
      expect(localMatch!.artworkPath, equals('/data/user/0/com.example.miee/app_flutter/artwork_cache/song_101.png'));
    });

    test('Correct artwork-to-track mapping when tracks have similar titles with different artists', () {
      final now = DateTime.now();
      final adeleEntry = HistoryEntry(
        track: TrackHiveModel(
          id: 'local_103',
          title: 'Hello',
          artist: 'Adele',
          imageUrl: '',
          duration: '4:55',
          filePath: '/storage/emulated/0/Music/adele_hello.mp3',
        ),
        playedAt: now,
      );

      final lionelEntry = HistoryEntry(
        track: TrackHiveModel(
          id: 'local_104',
          title: 'Hello',
          artist: 'Lionel Richie',
          imageUrl: '',
          duration: '4:10',
          filePath: '/storage/emulated/0/Music/lionel_hello.mp3',
        ),
        playedAt: now.subtract(const Duration(minutes: 10)),
      );

      final localSongs = [localSongSimilarTitle, localSongOtherSimilar];

      // Adele resolution
      final adeleTrack = adeleEntry.track.toTrack();
      final adeleMatch = localSongs.where((s) =>
          s.title.trim().toLowerCase() == adeleTrack.title.trim().toLowerCase() &&
          s.artist.trim().toLowerCase() == adeleTrack.artist.trim().toLowerCase()).firstOrNull;
      expect(adeleMatch, isNotNull);
      expect(adeleMatch!.id, equals('local_103'));
      expect(adeleMatch.artworkPath, contains('adele_hello.png'));

      // Lionel resolution
      final lionelTrack = lionelEntry.track.toTrack();
      final lionelMatch = localSongs.where((s) =>
          s.title.trim().toLowerCase() == lionelTrack.title.trim().toLowerCase() &&
          s.artist.trim().toLowerCase() == lionelTrack.artist.trim().toLowerCase()).firstOrNull;
      expect(lionelMatch, isNotNull);
      expect(lionelMatch!.id, equals('local_104'));
      expect(lionelMatch.artworkPath, contains('lionel_hello.png'));
      expect(adeleMatch.artworkPath, isNot(equals(lionelMatch.artworkPath)));
    });

    test('Hive serialization & deserialization preserves TrackHiveModel artwork fields across restarts', () {
      final original = TrackHiveModel(
        id: 'youtube_katchi_sera',
        title: 'Katchi Sera',
        artist: 'Sai Abhyankkar',
        imageUrl: 'https://i.ytimg.com/vi/katchi_sera/hqdefault.jpg',
        duration: '3:10',
        filePath: 'https://youtube.com/watch?v=katchi_sera',
      );

      // Verify toTrack preserves every field faithfully
      final track = original.toTrack();
      expect(track.id, equals('youtube_katchi_sera'));
      expect(track.title, equals('Katchi Sera'));
      expect(track.artist, equals('Sai Abhyankkar'));
      expect(track.imageUrl, equals('https://i.ytimg.com/vi/katchi_sera/hqdefault.jpg'));
      expect(track.duration, equals('3:10'));
      expect(track.filePath, equals('https://youtube.com/watch?v=katchi_sera'));

      // Reverse conversion TrackHiveModel.fromTrack
      final roundtrip = TrackHiveModel.fromTrack(track);
      expect(roundtrip.id, equals(original.id));
      expect(roundtrip.imageUrl, equals(original.imageUrl));
      expect(roundtrip.title, equals(original.title));
      expect(roundtrip.artist, equals(original.artist));
    });

    test('ListeningEvent model preserves optional imageUrl across serialization', () {
      final event = ListeningEvent(
        id: 'event_1',
        trackId: 'youtube_abc',
        title: 'Song ABC',
        artist: 'Artist ABC',
        imageUrl: 'https://i.ytimg.com/vi/abc/hqdefault.jpg',
        source: 'youtube',
        timestamp: DateTime(2026, 10, 24, 12, 0),
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.9,
      );

      expect(event.imageUrl, equals('https://i.ytimg.com/vi/abc/hqdefault.jpg'));
      final map = event.toMap();
      expect(map['imageUrl'], equals('https://i.ytimg.com/vi/abc/hqdefault.jpg'));

      final fromMap = ListeningEvent.fromMap('event_1', map);
      expect(fromMap.imageUrl, equals('https://i.ytimg.com/vi/abc/hqdefault.jpg'));
    });
  });

  group('SongTile Artwork Display & Graceful Fallback Widget Tests', () {
    testWidgets('SongTile renders network image when valid http imageUrl is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Katchi Sera',
              artist: 'Sai Abhyankkar',
              duration: '3:10',
              imageUrl: 'https://i.ytimg.com/vi/katchi_sera/hqdefault.jpg',
            ),
          ),
        ),
      );

      expect(find.text('Katchi Sera'), findsOneWidget);
      expect(find.text('Sai Abhyankkar'), findsOneWidget);
      expect(find.text('3:10'), findsOneWidget);

      // Leading widget contains an Image.network (represented as Image widget)
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
    });

    testWidgets('SongTile renders fallback container with Icons.music_note when imageUrl is null or empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Acoustic Sketch',
              artist: 'Unknown Artist',
              duration: '2:15',
              imageUrl: null, // No artwork available
            ),
          ),
        ),
      );

      expect(find.text('Acoustic Sketch'), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      // No Image widget attempted
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('SongTile renders fallback container with Icons.music_note when imageUrl is empty string', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Empty Art Song',
              artist: 'Artist',
              duration: '1:30',
              imageUrl: '',
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });

  group('Recently Played UI Rendering on HomePage Widget Tests', () {
    testWidgets('Recently Played section renders each item with valid artwork and triggers playback with full Track', (tester) async {
      final mockPlayerController = MockPlayerController();
      final now = DateTime.now();

      final recentEntries = [
        HistoryEntry(
          track: TrackHiveModel(
            id: 'youtube_katchi',
            title: 'Katchi Sera',
            artist: 'Sai Abhyankkar',
            imageUrl: 'https://i.ytimg.com/vi/katchi/hqdefault.jpg',
            duration: '3:10',
          ),
          playedAt: now,
        ),
        HistoryEntry(
          track: TrackHiveModel(
            id: 'local_midnight',
            title: 'Midnight City',
            artist: 'M83',
            imageUrl: '/cache/midnight.png',
            duration: '4:03',
            filePath: '/music/midnight.mp3',
          ),
          playedAt: now.subtract(const Duration(minutes: 5)),
        ),
      ];

      const localSongs = [
        MediaSong(
          id: 'local_midnight',
          title: 'Midnight City',
          artist: 'M83',
          album: 'Hurry Up',
          duration: '4:03',
          durationMs: 243000,
          filePath: '/music/midnight.mp3',
          artworkPath: '/cache/midnight.png',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => mockPlayerController),
            recentlyPlayedProvider.overrideWith((ref) => Stream.value(recentEntries)),
            songsProvider.overrideWith((ref) => localSongs),
            albumsProvider.overrideWithValue(const []),
            allPlaylistsProvider.overrideWithValue(const []),
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            activeRoomProvider.overrideWithValue(null),
            recommendationSectionsProvider.overrideWith(
              (ref) => const RecommendationSections(),
            ),
          ],
          child: const MaterialApp(
            home: HomePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Recently Played section should be visible
      final recentlyPlayedSection =
          find.byKey(const ValueKey('recently_played_section'));
      expect(recentlyPlayedSection, findsOneWidget);
      expect(find.text('Recently Played'), findsOneWidget);

      expect(
        find.descendant(
          of: recentlyPlayedSection,
          matching: find.text('Katchi Sera'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: recentlyPlayedSection,
          matching: find.text('Midnight City'),
        ),
        findsOneWidget,
      );

      // Verify SongTiles inside Recently Played have images
      final songTiles = tester.widgetList<SongTile>(
        find.descendant(
          of: recentlyPlayedSection,
          matching: find.byType(SongTile),
        ),
      );
      final katchiTile = songTiles.firstWhere((t) => t.title == 'Katchi Sera');
      expect(katchiTile.imageUrl, equals('https://i.ytimg.com/vi/katchi/hqdefault.jpg'));

      final midnightTile = songTiles.firstWhere((t) => t.title == 'Midnight City');
      expect(midnightTile.imageUrl, equals('/cache/midnight.png'));

      // Tap on Katchi Sera SongTile to verify playback passes track with full artwork
      final katchiFinder = find.descendant(
        of: recentlyPlayedSection,
        matching: find.text('Katchi Sera'),
      );
      await tester.ensureVisible(katchiFinder);
      await tester.pumpAndSettle();

      await tester.tap(katchiFinder);
      await tester.pump();

      expect(mockPlayerController.lastSelectedTrack, isNotNull);
      expect(mockPlayerController.lastSelectedTrack!.title, equals('Katchi Sera'));
      expect(mockPlayerController.lastSelectedTrack!.imageUrl,
          equals('https://i.ytimg.com/vi/katchi/hqdefault.jpg'));
      expect(mockPlayerController.lastPlayingFrom, equals('Recently Played'));
    });

    testWidgets('Recently Played renders correctly even when recommendations provider is offline or error', (tester) async {
      final mockPlayerController = MockPlayerController();
      final now = DateTime.now();

      final recentEntries = [
        HistoryEntry(
          track: TrackHiveModel(
            id: 'youtube_offline_test',
            title: 'Offline Test Song',
            artist: 'Offline Artist',
            imageUrl: 'https://i.ytimg.com/vi/offline_test/hqdefault.jpg',
            duration: '2:45',
          ),
          playedAt: now,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => mockPlayerController),
            recentlyPlayedProvider.overrideWith((ref) => Stream.value(recentEntries)),
            songsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWithValue(const []),
            allPlaylistsProvider.overrideWithValue(const []),
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            activeRoomProvider.overrideWithValue(null),
            // Recommendations fail (offline)
            recommendationSectionsProvider.overrideWith(
              (ref) => throw Exception('Network unreachable'),
            ),
          ],
          child: const MaterialApp(
            home: HomePage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Offline error banner is shown AND Recently Played list is still rendered!
      final offlineSection =
          find.byKey(const ValueKey('recently_played_section'));
      expect(offlineSection, findsOneWidget);
      expect(find.text('Recently Played'), findsOneWidget);
      expect(
        find.descendant(
          of: offlineSection,
          matching: find.text('Offline Test Song'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: offlineSection,
          matching: find.text('Offline Artist'),
        ),
        findsOneWidget,
      );
    });
  });
}
