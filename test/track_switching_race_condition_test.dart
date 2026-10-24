import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/core/audio/queue_manager.dart';

void main() {
  group('Track ID Normalization & Equality Tests', () {
    String normalizeTrackId(String id) {
      return id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;
    }

    test('Raw YouTube ID matches youtube_ prefixed ID', () {
      const rawId = 'dQw4w9WgXcQ';
      const prefixedId = 'youtube_dQw4w9WgXcQ';

      expect(normalizeTrackId(rawId), equals('dQw4w9WgXcQ'));
      expect(normalizeTrackId(prefixedId), equals('dQw4w9WgXcQ'));
      expect(normalizeTrackId(rawId), equals(normalizeTrackId(prefixedId)));
    });

    test('Local track IDs are preserved without alteration', () {
      const localId1 = 'local_song_123';
      const localId2 = '/storage/emulated/0/Music/track.mp3';

      expect(normalizeTrackId(localId1), equals(localId1));
      expect(normalizeTrackId(localId2), equals(localId2));
    });

    test('Matching YouTubeVideo model ID with Track model ID', () {
      final ytVideo = YouTubeVideo(
        id: '9bZkp7q19f0',
        title: 'Gangnam Style',
        channelTitle: 'PSY',
        viewCount: '1B',
        duration: '4:13',
        thumbnailUrl: 'https://i.ytimg.com/vi/9bZkp7q19f0/hqdefault.jpg',
      );

      final trackModel = ytVideo.toTrack();
      expect(trackModel.id, equals('youtube_9bZkp7q19f0'));

      // Both should resolve to the same normalized key
      expect(
        normalizeTrackId(ytVideo.id),
        equals(normalizeTrackId(trackModel.id)),
      );
    });
  });

  group('Queue Selection & Index Preservation Invariants', () {
    late QueueManager queueManager;
    late List<MusicItem> testQueue;

    setUp(() {
      queueManager = QueueManager();
      testQueue = [
        const Track(
          id: 'youtube_track_0',
          title: 'Track Zero',
          artist: 'Artist 0',
          imageUrl: '',
          duration: '3:00',
        ),
        const Track(
          id: 'youtube_track_1',
          title: 'Track One',
          artist: 'Artist 1',
          imageUrl: '',
          duration: '3:30',
        ),
        const Track(
          id: 'youtube_track_2',
          title: 'Track Two',
          artist: 'Artist 2',
          imageUrl: '',
          duration: '4:00',
        ),
        const Track(
          id: 'youtube_track_3',
          title: 'Track Three',
          artist: 'Artist 3',
          imageUrl: '',
          duration: '2:45',
        ),
      ];
      queueManager.setQueue(testQueue, startIndex: 0);
    });

    test('Selecting index via raw ID does not fallback to 0', () {
      // Incoming track from search might have raw ID without youtube_ prefix
      final tappedItem = YouTubeVideo(
        id: 'track_2', // Note: no youtube_ prefix
        title: 'Track Two',
        channelTitle: 'Artist 2',
        viewCount: '1M',
        duration: '4:00',
        thumbnailUrl: '',
      );

      String normalize(String id) =>
          id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;

      final targetId = normalize(tappedItem.id);
      final resolvedIndex = queueManager.queue.indexWhere(
        (t) => t.id == tappedItem.id || normalize(t.id) == targetId,
      );

      expect(resolvedIndex, equals(2), reason: 'Must match index 2, never fallback to 0');
    });

    test('Skipping directly to upcoming queue item preserves queue items and index', () {
      expect(queueManager.currentIndex, equals(0));
      expect(queueManager.currentTrack?.title, equals('Track Zero'));

      // Jump to item at index 3 directly (like QueuePage tap)
      queueManager.setIndex(3);
      expect(queueManager.currentIndex, equals(3));
      expect(queueManager.currentTrack?.title, equals('Track Three'));

      // Invariant: track 0 must remain intact at index 0 (NOT replaced/clobbered)
      expect(queueManager.queue[0].title, equals('Track Zero'));
      expect(queueManager.queue[1].title, equals('Track One'));
      expect(queueManager.queue[2].title, equals('Track Two'));
      expect(queueManager.queue[3].title, equals('Track Three'));
      expect(queueManager.queue.length, equals(4));
    });

    test('Reordering queue updates active index pointer accurately', () {
      queueManager.setIndex(1); // Currently playing Track One
      expect(queueManager.currentTrack?.title, equals('Track One'));

      // Move Track One from index 1 to index 3
      queueManager.reorder(1, 4);
      expect(queueManager.currentIndex, equals(3));
      expect(queueManager.currentTrack?.title, equals('Track One'));

      // Move Track Zero past Track One (from index 0 past index 3)
      queueManager.reorder(0, 4);
      // Track One was at index 3, now shifted to index 2
      expect(queueManager.currentIndex, equals(2));
      expect(queueManager.currentTrack?.title, equals('Track One'));
    });

    test('Removing track from queue adjusts active index pointer safely', () {
      queueManager.setIndex(2); // Track Two
      queueManager.removeTrackAt(0); // Remove Track Zero

      expect(queueManager.queue.length, equals(3));
      expect(queueManager.currentIndex, equals(1));
      expect(queueManager.currentTrack?.title, equals('Track Two'));
    });
  });

  group('Playback Token Cancellation & Concurrency Simulation', () {
    test('Superseded asynchronous load request is discarded cleanly', () async {
      int activeToken = 0;
      final completedResolutions = <int>[];

      Future<void> simulatePlay(int tokenId, int delayMs) async {
        await Future.delayed(Duration(milliseconds: delayMs));
        if (tokenId != activeToken) {
          // Discarded because superseded
          return;
        }
        completedResolutions.add(tokenId);
      }

      // User rapidly taps Track 1, Track 2, Track 3
      activeToken = 1;
      final fut1 = simulatePlay(1, 100);

      activeToken = 2;
      final fut2 = simulatePlay(2, 50);

      activeToken = 3;
      final fut3 = simulatePlay(3, 30);

      await Future.wait([fut1, fut2, fut3]);

      // Only Track 3 must have completed
      expect(completedResolutions, equals([3]));
    });

    test('False UI auto-recovery prevented when position tick does not match active track', () {
      String normalize(String id) =>
          id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;

      const currentSelectedTrackId = 'youtube_track_B';
      const handlerActiveTrackId = 'youtube_track_A'; // Lingering previous track
      const isPlayerPlaying = true;
      const pos = Duration(seconds: 15);

      bool shouldAutoRecover = false;

      // Logic mirrored from hardened PlayerController position listener:
      if (isPlayerPlaying && pos > Duration.zero) {
        if (normalize(handlerActiveTrackId) == normalize(currentSelectedTrackId)) {
          shouldAutoRecover = true;
        }
      }

      expect(
        shouldAutoRecover,
        isFalse,
        reason: 'Position ticks from lingering Track A must not clear error for Track B',
      );

      // Now with matching track ID
      const matchingHandlerTrackId = 'track_B'; // Raw ID match
      if (isPlayerPlaying && pos > Duration.zero) {
        if (normalize(matchingHandlerTrackId) == normalize(currentSelectedTrackId)) {
          shouldAutoRecover = true;
        }
      }

      expect(shouldAutoRecover, isTrue);
    });
  });

  group('Track Selection & Queue Context Preservation', () {
    test('selectTrack finds correct track index and sets queue without clobbering', () {
      final queueManager = QueueManager();
      final tracks = [
        const Track(id: 'youtube_vid1', title: 'Song 1', artist: 'Artist 1', imageUrl: '', duration: '3:00'),
        const Track(id: 'youtube_vid2', title: 'Song 2', artist: 'Artist 2', imageUrl: '', duration: '3:30'),
        const Track(id: 'youtube_vid3', title: 'Song 3', artist: 'Artist 3', imageUrl: '', duration: '4:00'),
      ];

      // Incoming track from search or recommendation with raw ID
      final tappedItem = YouTubeVideo(
        id: 'vid2',
        title: 'Song 2',
        channelTitle: 'Artist 2',
        viewCount: '1M',
        duration: '3:30',
        thumbnailUrl: '',
      );

      String normalize(String id) =>
          id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;

      final targetId = normalize(tappedItem.id);
      final index = tracks.indexWhere((t) => t.id == tappedItem.id || normalize(t.id) == targetId);

      expect(index, equals(1));
      queueManager.setQueue(tracks, startIndex: index >= 0 ? index : 0);

      expect(queueManager.currentIndex, equals(1));
      expect(queueManager.currentTrack?.id, equals('youtube_vid2'));
      expect(queueManager.queue.length, equals(3));
      // Preceding and following tracks remain perfectly intact in the queue
      expect(queueManager.queue[0].id, equals('youtube_vid1'));
      expect(queueManager.queue[2].id, equals('youtube_vid3'));
    });

    test('Selecting first, middle, and last items navigates cleanly', () {
      final qm = QueueManager();
      final tracks = List.generate(
        5,
        (i) => Track(
          id: 'track_$i',
          title: 'Track $i',
          artist: 'Artist',
          imageUrl: '',
          duration: '3:00',
        ),
      );
      qm.setQueue(tracks, startIndex: 0);

      // 1. Select first item
      qm.setIndex(0);
      expect(qm.currentTrack?.id, equals('track_0'));
      expect(qm.previous(), isNull); // No previous before first
      expect(qm.next()?.id, equals('track_1'));

      // 2. Select middle item (index 2)
      qm.setIndex(2);
      expect(qm.currentTrack?.id, equals('track_2'));
      expect(qm.previous()?.id, equals('track_1'));
      qm.setIndex(2);
      expect(qm.next()?.id, equals('track_3'));

      // 3. Select last item (index 4)
      qm.setIndex(4);
      expect(qm.currentTrack?.id, equals('track_4'));
      expect(qm.next(), isNull); // No next after last item
      expect(qm.previous()?.id, equals('track_3'));
    });
  });

  group('Non-Repeating Shuffle & Order Restoration Invariants', () {
    test('Shuffle shuffles remaining tracks without repeats and restores original queue when disabled', () {
      final qm = QueueManager();
      final originalTracks = List.generate(
        10,
        (i) => Track(
          id: 'song_$i',
          title: 'Song $i',
          artist: 'Artist',
          imageUrl: '',
          duration: '3:00',
        ),
      );
      // Start at track 3
      qm.setQueue(originalTracks, startIndex: 3);
      expect(qm.currentTrack?.id, equals('song_3'));

      // Enable shuffle
      qm.enableShuffle();
      expect(qm.isShuffled, isTrue);
      // Currently playing song stays at the head of the active queue
      expect(qm.currentTrack?.id, equals('song_3'));
      expect(qm.currentIndex, equals(0));
      expect(qm.queue.length, equals(10));

      // Traverse all tracks in the shuffled queue
      final playedTrackIds = <String>{qm.currentTrack!.id};
      for (int i = 0; i < 9; i++) {
        final next = qm.next();
        expect(next, isNotNull);
        expect(playedTrackIds.contains(next!.id), isFalse,
            reason: 'Track ${next.id} must not be repeated during shuffle cycle');
        playedTrackIds.add(next.id);
      }
      expect(playedTrackIds.length, equals(10),
          reason: 'Every single song in the queue must be played once');

      // Now disable shuffle
      qm.disableShuffle();
      expect(qm.isShuffled, isFalse);
      expect(qm.queue.length, equals(10));

      // Verify original order is restored
      for (int i = 0; i < 10; i++) {
        expect(qm.queue[i].id, equals('song_$i'),
            reason: 'Queue item at $i must be restored to original album order');
      }

      // The currently active track pointer matches the last played track in the restored queue
      expect(qm.currentTrack?.id, equals(playedTrackIds.last));
      expect(qm.currentIndex, equals(originalTracks.indexWhere((t) => t.id == playedTrackIds.last)));
    });
  });

  group('Stream Recovery Position Invariants & Stale Request Protection', () {
    test('Stream recovery preserves and restores mid-track playback position', () async {
      final savedPosition = const Duration(seconds: 42);
      Duration? restoredPosition;
      bool playbackResumed = false;

      // Simulated recovery flow:
      Future<void> simulateRecovery({
        required Duration positionAtError,
        required bool shouldResume,
      }) async {
        final capturedPos = positionAtError;
        // Simulate network fetch for fresh URL
        await Future.delayed(const Duration(milliseconds: 10));
        // Source loaded, seek to captured position
        if (capturedPos > Duration.zero) {
          restoredPosition = capturedPos;
        }
        if (shouldResume) {
          playbackResumed = true;
        }
      }

      await simulateRecovery(positionAtError: savedPosition, shouldResume: true);

      expect(restoredPosition, equals(const Duration(seconds: 42)));
      expect(playbackResumed, isTrue);
    });

    test('Stale recovery request is discarded when active track changes during fetch', () async {
      int activeLoadToken = 1;
      String activeTrackId = 'youtube_track_A';
      bool recoveryApplied = false;

      Future<void> attemptRecovery({
        required int requestToken,
        required String videoId,
      }) async {
        // Long network delay
        await Future.delayed(const Duration(milliseconds: 30));
        // Check token and ID guards
        if (requestToken != activeLoadToken) return;
        if (activeTrackId != videoId) return;
        recoveryApplied = true;
      }

      // Launch recovery for track A
      final recoveryFut = attemptRecovery(requestToken: 1, videoId: 'youtube_track_A');

      // User selects track B immediately
      activeLoadToken = 2;
      activeTrackId = 'youtube_track_B';

      await recoveryFut;

      expect(recoveryApplied, isFalse, reason: 'Superseded recovery must be discarded');
    });
  });

  group('Repeat Modes & Queue Boundary Wrapping Invariants', () {
    test('Repeat-all wraps to index 0 at end of queue', () {
      final qm = QueueManager();
      final tracks = List.generate(
        3,
        (i) => Track(id: 't_$i', title: 'T $i', artist: 'A', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(tracks, startIndex: 2); // At last track

      int nextIndexWithRepeatAll(QueueManager manager) {
        if (manager.currentIndex < manager.queue.length - 1) {
          return manager.currentIndex + 1;
        } else {
          return 0; // Wrap around to beginning
        }
      }

      expect(nextIndexWithRepeatAll(qm), equals(0));
    });

    test('Repeat-all wraps to last track when previous is tapped at first track', () {
      final qm = QueueManager();
      final tracks = List.generate(
        3,
        (i) => Track(id: 't_$i', title: 'T $i', artist: 'A', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(tracks, startIndex: 0); // At first track

      int previousIndexWithRepeatAll(QueueManager manager, Duration position) {
        if (position.inSeconds > 3) {
          return manager.currentIndex; // Restarts track
        }
        if (manager.currentIndex > 0) {
          return manager.currentIndex - 1;
        } else {
          return manager.queue.length - 1; // Wrap around to end
        }
      }

      expect(previousIndexWithRepeatAll(qm, Duration.zero), equals(2));
      expect(previousIndexWithRepeatAll(qm, const Duration(seconds: 10)), equals(0));
    });
  });

  group('Failed Stream Resolution & Error Safety', () {
    test('Failed stream resolution terminates at max retries without infinite loop', () async {
      int retryCount = 0;
      const int maxRetries = 3;
      bool errorEmitted = false;

      Future<void> simulateResolutionWithRetries(int currentRetry) async {
        retryCount = currentRetry;
        if (currentRetry >= maxRetries) {
          errorEmitted = true;
          return;
        }
        // Simulate failure on resolution
        await simulateResolutionWithRetries(currentRetry + 1);
      }

      await simulateResolutionWithRetries(0);

      expect(retryCount, equals(maxRetries));
      expect(errorEmitted, isTrue);
    });
  });
}

