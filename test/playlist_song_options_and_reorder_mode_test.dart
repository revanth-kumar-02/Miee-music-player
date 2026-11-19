import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';
import 'package:Miee/features/playlists/presentation/playlist_detail_page.dart';
import 'package:Miee/features/playlists/providers/playlist_providers.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('QueueManager playNext and insertTrack', () {
    late QueueManager queueManager;
    late Track track1;
    late Track track2;
    late Track track3;

    setUp(() {
      queueManager = QueueManager();
      track1 = const Track(
        id: 't1',
        title: 'Song 1',
        artist: 'Artist 1',
        imageUrl: '',
        duration: '3:00',
      );
      track2 = const Track(
        id: 't2',
        title: 'Song 2',
        artist: 'Artist 2',
        imageUrl: '',
        duration: '3:30',
      );
      track3 = const Track(
        id: 't3',
        title: 'Song 3 (Play Next)',
        artist: 'Artist 3',
        imageUrl: '',
        duration: '4:00',
      );
    });

    test('insertTrack inserts immediately after current index', () {
      queueManager.setQueue([track1, track2], startIndex: 0);
      expect(queueManager.currentIndex, 0);
      expect(queueManager.queue.length, 2);

      // Insert track3 right after track1 (index 1)
      queueManager.insertTrack(1, track3);

      expect(queueManager.queue.length, 3);
      expect(queueManager.queue[0].id, 't1');
      expect(queueManager.queue[1].id, 't3');
      expect(queueManager.queue[2].id, 't2');
      expect(queueManager.currentIndex, 0);
    });

    test('insertTrack adjusts currentIndex when inserting before active track', () {
      queueManager.setQueue([track1, track2], startIndex: 1);
      expect(queueManager.currentIndex, 1);

      // Insert at index 0 (before current track)
      queueManager.insertTrack(0, track3);

      expect(queueManager.queue.length, 3);
      expect(queueManager.queue[0].id, 't3');
      expect(queueManager.queue[1].id, 't1');
      expect(queueManager.queue[2].id, 't2');
      expect(queueManager.currentIndex, 2);
    });
  });

  group('Playlist Detail Page UX - Song Options and Reorder Mode', () {
    late PlaylistModel testPlaylist;
    late Track song1;
    late Track song2;

    setUp(() {
      song1 = const Track(
        id: 's1',
        title: 'The Child In Us',
        artist: 'Enigma',
        imageUrl: '',
        duration: '3:00',
      );
      song2 = const Track(
        id: 's2',
        title: 'One Sun One Moon',
        artist: 'Anirudh Ravichander',
        imageUrl: '',
        duration: '3:15',
      );
      testPlaylist = PlaylistModel(
        id: 'p1',
        name: 'One piece',
        tracks: [song1, song2],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        role: PlaylistRole.owner,
      );
    });

    testWidgets('Normal mode displays three-dot more options and no drag handles', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistControllerProvider.overrideWith(
              (ref) => _MockPlaylistController(PlaylistsState(playlists: [testPlaylist])),
            ),
            playerControllerProvider.overrideWith(
              (ref) => _MockPlayerController(const pb.PlaybackState(status: pb.PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: PlaylistDetailPage(playlistId: 'p1'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 15));

      // Verify playlist name is rendered
      expect(find.text('One piece'), findsOneWidget);
      expect(find.text('The Child In Us'), findsOneWidget);
      expect(find.text('One Sun One Moon'), findsOneWidget);

      // Verify three-dot overflow button exists for each song
      expect(find.byIcon(Icons.more_vert), findsWidgets);

      // Verify drag handles are NOT present in normal browsing mode
      expect(find.byIcon(Icons.drag_handle_rounded), findsNothing);
      expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    });

    testWidgets('Tapping three-dot button displays track options sheet with all actions', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistControllerProvider.overrideWith(
              (ref) => _MockPlaylistController(PlaylistsState(playlists: [testPlaylist])),
            ),
            playerControllerProvider.overrideWith(
              (ref) => _MockPlayerController(const pb.PlaybackState(status: pb.PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: PlaylistDetailPage(playlistId: 'p1'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 15));

      // Find the song tile more button (first one is top bar more_vert, second is first song's more_vert)
      final moreButtons = find.byIcon(Icons.more_vert);
      expect(moreButtons, findsNWidgets(3)); // Top bar + 2 songs

      // Tap first song's more button (at index 1)
      await tester.tap(moreButtons.at(1));
      await tester.pumpAndSettle();

      // Verify song options sheet actions are present
      expect(find.text('Play next'), findsOneWidget);
      expect(find.text('Add to queue'), findsOneWidget);
      expect(find.text('Add to another playlist'), findsOneWidget);
      expect(find.text('Remove from this playlist'), findsOneWidget);
      expect(find.text('View artist (Enigma)'), findsOneWidget);
      expect(find.text('Share track'), findsOneWidget);
    });

    testWidgets('Playlist settings allows entering Reorder Mode with drag handles', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playlistControllerProvider.overrideWith(
              (ref) => _MockPlaylistController(PlaylistsState(playlists: [testPlaylist])),
            ),
            playerControllerProvider.overrideWith(
              (ref) => _MockPlayerController(const pb.PlaybackState(status: pb.PlaybackStatus.idle)),
            ),
          ],
          child: const MaterialApp(
            home: PlaylistDetailPage(playlistId: 'p1'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 15));

      // Tap top app bar options menu (index 0)
      final topAppBarMore = find.byIcon(Icons.more_vert).first;
      await tester.tap(topAppBarMore);
      await tester.pumpAndSettle();

      // Verify Reorder Songs option is in the menu
      expect(find.text('Reorder Songs'), findsOneWidget);

      // Tap Reorder Songs
      await tester.tap(find.text('Reorder Songs'));
      await tester.pumpAndSettle();

      // Verify we are in Reorder Mode
      expect(find.text('Reorder Songs'), findsOneWidget); // App bar title
      expect(find.text('Done'), findsOneWidget); // Save action button
      expect(find.text('Drag the handles to rearrange songs'), findsOneWidget); // Hint banner

      // Verify drag handles are now visible for each song
      expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(2));
    });
  });
}

class _MockPlaylistController extends StateNotifier<PlaylistsState> implements PlaylistController {
  _MockPlaylistController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockPlayerController extends StateNotifier<pb.PlaybackState> implements PlayerController {
  _MockPlayerController(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
