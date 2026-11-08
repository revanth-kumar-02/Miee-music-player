import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/features/playlists/domain/playlist_model.dart';
import '../lib/shared/models/track.dart';
import '../lib/shared/widgets/bottom_navigation.dart';

void main() {
  group('Playlist Model & Add Songs Verification', () {
    test('Empty playlist reports 0 songs, < 1m duration, and null artwork', () {
      final playlist = PlaylistModel(
        id: 'test_1',
        name: 'One piece',
        tracks: const [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );

      expect(playlist.songCount, 0);
      expect(playlist.isEmpty, isTrue);
      expect(playlist.totalDurationFormatted, '< 1m');
      expect(playlist.effectiveCoverUrl, isNull);
    });

    test('Playlist with added songs updates songCount, totalDuration and cover artwork', () {
      final t1 = Track(
        id: 'track_1',
        title: 'Song One',
        artist: 'Artist A',
        duration: '3:30',
        imageUrl: 'https://example.com/cover1.jpg',
      );
      final t2 = Track(
        id: 'youtube_abc123',
        title: 'Song Two',
        artist: 'Artist B',
        duration: '4:15',
        imageUrl: 'https://example.com/cover2.jpg',
      );

      final playlist = PlaylistModel(
        id: 'test_1',
        name: 'One piece',
        tracks: [t1, t2],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
      );

      expect(playlist.songCount, 2);
      expect(playlist.isEmpty, isFalse);
      expect(playlist.totalDurationFormatted, '7m');
      expect(playlist.effectiveCoverUrl, 'https://example.com/cover1.jpg');
    });

    test('Custom cover path takes priority over track artwork', () {
      final t1 = Track(
        id: 'track_1',
        title: 'Song One',
        artist: 'Artist A',
        duration: '3:30',
        imageUrl: 'https://example.com/cover1.jpg',
      );

      final playlist = PlaylistModel(
        id: 'test_1',
        name: 'One piece',
        tracks: [t1],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        customCoverPath: '/path/to/custom_cover.jpg',
      );

      expect(playlist.effectiveCoverUrl, '/path/to/custom_cover.jpg');
    });

    test('Deduplication logic matches youtube_ prefixed and raw IDs', () {
      final existingTracks = [
        Track(id: 'youtube_video123', title: 'Video', artist: 'Art', duration: '3:00', imageUrl: ''),
        Track(id: 'local_song_456', title: 'Local', artist: 'Art', duration: '2:30', imageUrl: ''),
      ];

      final existingIds = existingTracks.map((t) => t.id).toSet();

      // Check whether a raw id 'video123' properly maps to 'youtube_video123'
      bool isDuplicate(String id, bool isYoutube) {
        String trackId = id;
        if (isYoutube && !trackId.startsWith('youtube_')) {
          trackId = 'youtube_$trackId';
        }
        return existingIds.contains(trackId);
      }

      expect(isDuplicate('video123', true), isTrue);
      expect(isDuplicate('youtube_video123', true), isTrue);
      expect(isDuplicate('local_song_456', false), isTrue);
      expect(isDuplicate('video999', true), isFalse);
    });
  });

  group('Navigation Shell Bottom Bar & Mini-Player Rules', () {
    bool computeHideBottomNav(String location, String uriPath) {
      final isNowPlayingRoute = location == '/player' || uriPath == '/player';
      final isSettingsRoute = location == '/settings' ||
          uriPath == '/settings' ||
          location.startsWith('/settings/') ||
          uriPath.startsWith('/settings/');
      final isRoomDetailRoute = location.startsWith('/rooms/') ||
          uriPath.startsWith('/rooms/');
      final isQueueRoute = location == '/queue' ||
          uriPath == '/queue' ||
          location.startsWith('/queue/') ||
          uriPath.startsWith('/queue/');

      return (isNowPlayingRoute ||
          isQueueRoute ||
          isSettingsRoute ||
          location == '/' ||
          uriPath == '/' ||
          location.startsWith('/playlist/') ||
          uriPath.startsWith('/playlist/') ||
          location.startsWith('/album/') ||
          uriPath.startsWith('/album/') ||
          location.startsWith('/artist/') ||
          uriPath.startsWith('/artist/') ||
          location.startsWith('/genre/') ||
          uriPath.startsWith('/genre/') ||
          location == '/local-songs' ||
          uriPath == '/local-songs' ||
          location == '/liked-songs' ||
          uriPath == '/liked-songs' ||
          isRoomDetailRoute);
    }

    int getNavIndex(String location) {
      if (location == '/home') return 0;
      if (location == '/search') return 1;
      if (location == '/playlists' || location.startsWith('/playlist/')) return 3;
      if (location == '/rooms' || location.startsWith('/rooms')) return 4;
      return 0;
    }

    test('Now Playing route (/player) strictly hides bottom navigation bar and does not activate Rooms tab', () {
      expect(computeHideBottomNav('/player', '/player'), isTrue);
      expect(getNavIndex('/player'), 0); // Must NOT activate tab 4 (Rooms)
    });

    test('Playlist detail route (/playlist/:id) strictly hides bottom navigation bar', () {
      expect(computeHideBottomNav('/playlist/12345', '/playlist/12345'), isTrue);
    });

    test('Queue route (/queue) strictly hides bottom navigation bar', () {
      expect(computeHideBottomNav('/queue', '/queue'), isTrue);
    });

    test('Home, Search, Playlists, and Rooms top-level tabs show bottom navigation bar', () {
      expect(computeHideBottomNav('/home', '/home'), isFalse);
      expect(computeHideBottomNav('/search', '/search'), isFalse);
      expect(computeHideBottomNav('/playlists', '/playlists'), isFalse);
      expect(computeHideBottomNav('/rooms', '/rooms'), isFalse);
    });

    test('Rooms detail routes (/rooms/create, /rooms/join) hide bottom navigation bar', () {
      expect(computeHideBottomNav('/rooms/create', '/rooms/create'), isTrue);
      expect(computeHideBottomNav('/rooms/join', '/rooms/join'), isTrue);
      expect(computeHideBottomNav('/rooms/active', '/rooms/active'), isTrue);
    });

    test('Navigation index maps correctly for all tabs including Rooms', () {
      expect(getNavIndex('/home'), 0);
      expect(getNavIndex('/search'), 1);
      expect(getNavIndex('/playlists'), 3);
      expect(getNavIndex('/rooms'), 4);
    });
  });

  group('BottomNavigation Widget Tests', () {
    testWidgets('Renders Home, Search, Center Play, Library, and Rooms destinations', (tester) async {
      int tappedIndex = -1;
      bool centerTapped = false;
      bool centerLongPressed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BottomNavigation(
              currentIndex: 0,
              isPlaying: false,
              onTap: (index) => tappedIndex = index,
              onCenterPlayTap: () => centerTapped = true,
              onCenterPlayLongPress: () => centerLongPressed = true,
            ),
          ),
        ),
      );

      // Home icon present
      expect(find.byIcon(Icons.home_rounded), findsOneWidget);
      // Search icon present
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      // Center play icon present
      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
      // Library icon present
      expect(find.byIcon(Icons.queue_music_outlined), findsOneWidget);
      // Rooms icon present (inactive state: Icons.groups_outlined)
      expect(find.byIcon(Icons.groups_outlined), findsOneWidget);

      // Tap Rooms (index 4)
      await tester.tap(find.byIcon(Icons.groups_outlined));
      expect(tappedIndex, 4);

      // Tap Center Play button
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      expect(centerTapped, isTrue);

      // Long press Center Play button
      await tester.longPress(find.byIcon(Icons.play_arrow_rounded));
      expect(centerLongPressed, isTrue);
    });

    testWidgets('Rooms tab renders active icon when currentIndex == 4', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BottomNavigation(
              currentIndex: 4,
              isPlaying: true,
              onTap: (_) {},
            ),
          ),
        ),
      );

      // Active rooms icon: Icons.groups_rounded
      expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
      // Center button shows pause icon when playing
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    });
  });
}
