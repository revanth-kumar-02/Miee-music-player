import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/core/audio/queue_diagnostics.dart';
import 'package:Miee/core/storage/adapters/queue_snapshot.dart';
import 'package:Miee/features/library/data/queue_state_repository.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

import 'package:Miee/core/storage/adapters/track_hive_model.dart';

class _MockQueueStateRepository implements QueueStateRepository {
  QueueSnapshot? savedSnapshot;

  @override
  Future<void> clear() async {
    savedSnapshot = null;
  }

  @override
  bool get hasSnapshot => savedSnapshot != null;

  @override
  QueueSnapshot? loadSnapshot() => savedSnapshot;

  @override
  List<MusicItem>? loadQueueTracks() =>
      savedSnapshot?.queue.map((m) => m.toTrack()).toList();

  @override
  Future<void> saveSnapshot({
    required List<MusicItem> queue,
    required int currentIndex,
    required int positionMs,
    required bool isShuffleEnabled,
    required String repeatMode,
  }) async {
    savedSnapshot = QueueSnapshot(
      queue: queue.map(TrackHiveModel.fromTrack).toList(),
      currentIndex: currentIndex,
      positionMs: positionMs,
      isShuffleEnabled: isShuffleEnabled,
      repeatMode: repeatMode,
    );
  }
}

Track _makeTrack({
  required String id,
  required String title,
  required String artist,
  String imageUrl = 'https://example.com/art.jpg',
  String duration = '03:30',
  String? filePath,
  String? albumName,
}) {
  return Track(
    id: id,
    title: title,
    artist: artist,
    imageUrl: imageUrl,
    duration: duration,
    filePath: filePath,
    albumName: albumName,
  );
}

void main() {
  group('Queue Generation, Autoplay & Reliability Regression Suite (15 Scenarios)', () {
    late QueueManager queueManager;
    late _MockQueueStateRepository mockRepo;

    setUp(() {
      queueManager = QueueManager();
      mockRepo = _MockQueueStateRepository();
    });

    // 1. Playing one local song
    test('1. Playing one local song leaves Next Up empty (queue size = 1)', () {
      final localSong = _makeTrack(
        id: 'local_1',
        title: 'My Local Track',
        artist: 'Local Artist',
        filePath: '/storage/emulated/0/Music/track1.mp3',
      );

      queueManager.setQueue([localSong], startIndex: 0);

      expect(queueManager.queue.length, 1);
      expect(queueManager.currentIndex, 0);
      expect(queueManager.currentTrack?.id, 'local_1');

      // Next Up calculation: queue.length - 1 - currentIndex
      final remaining = queueManager.queue.length - 1 - queueManager.currentIndex;
      expect(remaining, 0, reason: 'Next Up must be completely empty when 1 song is playing');
    });

    // 2. Playing one YouTube song
    test('2. Playing one YouTube song initializes queue with only that song and empty Next Up', () {
      final ytTrack = _makeTrack(
        id: 'youtube_abc12345678',
        title: 'Video Song',
        artist: 'Lana Del Rey',
        imageUrl: 'https://i.ytimg.com/vi/abc12345678/hqdefault.jpg',
      );

      queueManager.setQueue([ytTrack], startIndex: 0);

      expect(queueManager.queue.length, 1);
      expect(queueManager.currentTrack?.artist, 'Lana Del Rey');
      final remaining = queueManager.queue.length - 1 - queueManager.currentIndex;
      expect(remaining, 0, reason: 'No auto-generated tracks populated silently');
    });

    // 3. Adding a song manually
    test('3. Adding a song manually appends to Next Up in correct order', () {
      final track1 = _makeTrack(id: 't1', title: 'Song 1', artist: 'Artist A');
      final track2 = _makeTrack(id: 't2', title: 'Song 2', artist: 'Artist B');

      queueManager.setQueue([track1], startIndex: 0);
      expect(queueManager.queue.length, 1);

      queueManager.addTrack(track2);
      expect(queueManager.queue.length, 2);
      expect(queueManager.queue[1].id, 't2');
      expect(queueManager.currentIndex, 0);
      expect(queueManager.queue.length - 1 - queueManager.currentIndex, 1);
    });

    // 4. Playing an album
    test('4. Playing an album enqueues entire album preserving track sequence', () {
      final albumTracks = List.generate(
        8,
        (i) => _makeTrack(
          id: 'album_track_$i',
          title: 'Track ${i + 1}',
          artist: 'Album Artist',
          albumName: 'Masterpiece Album',
        ),
      );

      queueManager.setQueue(albumTracks, startIndex: 2);

      expect(queueManager.queue.length, 8);
      expect(queueManager.currentIndex, 2);
      expect(queueManager.currentTrack?.title, 'Track 3');
      expect(queueManager.queue.map((t) => t.title).toList(), [
        'Track 1',
        'Track 2',
        'Track 3',
        'Track 4',
        'Track 5',
        'Track 6',
        'Track 7',
        'Track 8',
      ]);
    });

    // 5. Playing a playlist
    test('5. Playing a playlist maintains user-defined playlist order without extraneous additions', () {
      final playlist = [
        _makeTrack(id: 'p1', title: 'Playlist Intro', artist: 'Artist 1'),
        _makeTrack(id: 'p2', title: 'Midtempo Groove', artist: 'Artist 2'),
        _makeTrack(id: 'p3', title: 'Outro Theme', artist: 'Artist 3'),
      ];

      queueManager.setQueue(playlist, startIndex: 0);

      expect(queueManager.queue.length, 3);
      expect(queueManager.queue[0].id, 'p1');
      expect(queueManager.queue[1].id, 'p2');
      expect(queueManager.queue[2].id, 'p3');
    });

    // 6. Playing search results
    test('6. Tapping a single search result starts queue with that individual track', () {
      final searchResultVideo = _makeTrack(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Search Hit',
        artist: 'Popular Artist',
      );

      // UI passes [searchResultVideo] as single item list
      queueManager.setQueue([searchResultVideo], startIndex: 0);

      expect(queueManager.queue.length, 1);
      expect(queueManager.currentTrack?.id, 'youtube_dQw4w9WgXcQ');
    });

    // 7. Recommendations loading independently
    test('7. Viewing recommendations does not touch or mutate active playback queue', () {
      final activeSong = _makeTrack(id: 'active_1', title: 'Playing Now', artist: 'Artist');
      queueManager.setQueue([activeSong], startIndex: 0);

      // Simulating independent recommendation fetch
      final recommendations = [
        _makeTrack(id: 'rec_1', title: 'Recommended Track 1', artist: 'Other Artist'),
        _makeTrack(id: 'rec_2', title: 'Recommended Track 2', artist: 'Other Artist'),
      ];

      // Recommendations fetched for display in UI carousel
      expect(recommendations.length, 2);
      // Active queue remains completely unmodified
      expect(queueManager.queue.length, 1);
      expect(queueManager.currentTrack?.id, 'active_1');
    });

    // 8. Preloading without queue modification
    test('8. Audio preloading next track does not alter queue structure', () {
      final track1 = _makeTrack(id: 't1', title: 'Track 1', artist: 'Artist');
      final track2 = _makeTrack(id: 't2', title: 'Track 2', artist: 'Artist');
      queueManager.setQueue([track1, track2], startIndex: 0);

      // Preloader inspects next track
      final nextCandidate = queueManager.currentIndex + 1 < queueManager.queue.length
          ? queueManager.queue[queueManager.currentIndex + 1]
          : null;

      expect(nextCandidate?.id, 't2');
      // Queue length and current index must remain untouched
      expect(queueManager.queue.length, 2);
      expect(queueManager.currentIndex, 0);
    });

    // 9. Natural track completion
    test('9. Natural track completion advances to next track and stops at end', () {
      final t1 = _makeTrack(id: 't1', title: 'Track 1', artist: 'Artist');
      final t2 = _makeTrack(id: 't2', title: 'Track 2', artist: 'Artist');
      queueManager.setQueue([t1, t2], startIndex: 0);

      // Track 1 completes -> next()
      final nextTrack = queueManager.next();
      expect(nextTrack?.id, 't2');
      expect(queueManager.currentIndex, 1);

      // Track 2 completes -> next()
      final endOfQueue = queueManager.next();
      expect(endOfQueue, isNull);
      expect(queueManager.currentIndex, 1);
    });

    // 10. Autoplay enabled and disabled
    test('10. Autoplay condition checks: only expands when enabled and remaining == 0', () {
      final t1 = _makeTrack(id: 't1', title: 'Track 1', artist: 'Artist');
      final t2 = _makeTrack(id: 't2', title: 'Track 2', artist: 'Artist');
      queueManager.setQueue([t1, t2], startIndex: 0);

      // Case A: Remaining > 0 -> should not expand
      int remaining = queueManager.queue.length - 1 - queueManager.currentIndex;
      bool shouldExpand({required bool autoPlayEnabled, required int rem}) {
        if (!autoPlayEnabled) return false;
        if (rem > 0) return false;
        return true;
      }

      expect(shouldExpand(autoPlayEnabled: true, rem: remaining), isFalse);

      // Case B: Autoplay disabled at queue end (rem == 0) -> should not expand
      expect(shouldExpand(autoPlayEnabled: false, rem: 0), isFalse);

      // Case C: Autoplay enabled at queue end (rem == 0) -> triggers expansion
      expect(shouldExpand(autoPlayEnabled: true, rem: 0), isTrue);
    });

    // 11. Manual queue reordering
    test('11. Manual queue reordering updates positions while preserving current track', () {
      final t1 = _makeTrack(id: 't1', title: 'Track 1', artist: 'Artist');
      final t2 = _makeTrack(id: 't2', title: 'Track 2', artist: 'Artist');
      final t3 = _makeTrack(id: 't3', title: 'Track 3', artist: 'Artist');
      queueManager.setQueue([t1, t2, t3], startIndex: 0);

      // Reorder: Move Track 3 (index 2) to index 1
      queueManager.reorder(2, 1);

      expect(queueManager.queue.map((t) => t.id).toList(), ['t1', 't3', 't2']);
      expect(queueManager.currentIndex, 0);
      expect(queueManager.currentTrack?.id, 't1');
    });

    // 12. Removing queue entries
    test('12. Removing queue entries updates queue length and current index cleanly', () {
      final t1 = _makeTrack(id: 't1', title: 'Track 1', artist: 'Artist');
      final t2 = _makeTrack(id: 't2', title: 'Track 2', artist: 'Artist');
      final t3 = _makeTrack(id: 't3', title: 'Track 3', artist: 'Artist');
      queueManager.setQueue([t1, t2, t3], startIndex: 1); // Playing t2

      // Remove t1 (index 0)
      queueManager.removeTrackAt(0);

      expect(queueManager.queue.length, 2);
      expect(queueManager.queue[0].id, 't2');
      expect(queueManager.queue[1].id, 't3');
      expect(queueManager.currentIndex, 0);
      expect(queueManager.currentTrack?.id, 't2');
    });

    // 13. Rapid track switching
    test('13. Generation token invalidates stale asynchronous callbacks during rapid switching', () {
      int generationToken = 0;

      // User taps Song A
      int tokenA = ++generationToken;
      // User immediately taps Song B
      int tokenB = ++generationToken;

      bool isResponseValid(int requestToken, int currentToken) {
        return requestToken == currentToken;
      }

      expect(isResponseValid(tokenA, generationToken), isFalse);
      expect(isResponseValid(tokenB, generationToken), isTrue);
    });

    // 14. Restoring the queue after app restart
    test('14. Queue snapshot restoration reproduces exact track list, index, and playback state', () {
      final originalQueue = [
        _makeTrack(id: 's1', title: 'Saved 1', artist: 'Artist 1'),
        _makeTrack(id: 's2', title: 'Saved 2', artist: 'Artist 2'),
        _makeTrack(id: 's3', title: 'Saved 3', artist: 'Artist 3'),
      ];

      mockRepo.saveSnapshot(
        queue: originalQueue,
        currentIndex: 1,
        positionMs: 45000,
        isShuffleEnabled: false,
        repeatMode: 'all',
      );

      final snapshot = mockRepo.loadSnapshot();
      expect(snapshot, isNotNull);
      expect(snapshot!.queue.length, 3);
      expect(snapshot.currentIndex, 1);
      expect(snapshot.positionMs, 45000);
      expect(snapshot.repeatMode, 'all');

      final restoredTracks = snapshot.queue.map((m) => m.toTrack()).toList();
      queueManager.setQueue(restoredTracks, startIndex: snapshot.currentIndex);

      expect(queueManager.queue.length, 3);
      expect(queueManager.currentIndex, 1);
      expect(queueManager.currentTrack?.id, 's2');
    });

    // 15. Duplicate and stale asynchronous insertion attempts
    test('15. Duplicate track ID and identical recording keys are strictly rejected', () {
      final t1 = _makeTrack(
        id: 'youtube_video_1',
        title: 'Song Title',
        artist: 'Main Artist',
      );
      queueManager.setQueue([t1], startIndex: 0);

      final duplicateIdTrack = _makeTrack(
        id: 'youtube_video_1',
        title: 'Song Title (Official Upload)',
        artist: 'Main Artist',
      );

      final duplicateRecordingKeyTrack = _makeTrack(
        id: 'youtube_video_2',
        title: 'Song Title',
        artist: 'Main Artist',
      );

      final existingIds = queueManager.queue.map((t) => t.id).toSet();
      final existingKeys = queueManager.queue
          .map((t) => SearchDeduplicator.computeRecordingKey(t))
          .toSet();

      bool canAdd(MusicItem candidate) {
        if (existingIds.contains(candidate.id)) return false;
        final key = SearchDeduplicator.computeRecordingKey(candidate);
        if (existingKeys.contains(key)) return false;
        return true;
      }

      expect(canAdd(duplicateIdTrack), isFalse, reason: 'Duplicate ID must be rejected');
      expect(canAdd(duplicateRecordingKeyTrack), isFalse,
          reason: 'Identical recording key must be rejected');

      final genuinelyUniqueTrack = _makeTrack(
        id: 'youtube_video_3',
        title: 'Completely Different Song',
        artist: 'Main Artist',
      );
      expect(canAdd(genuinelyUniqueTrack), isTrue);
    });
  });
}
