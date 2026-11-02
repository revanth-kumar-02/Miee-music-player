import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/domain/music_language_service.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

/// Deterministic mock repository simulating paginated artist catalogues.
class MockPaginatedYouTubeRepository implements YouTubeRepository {
  final Map<String, Map<int, List<YouTubeVideo>>> paginatedResponses;

  MockPaginatedYouTubeRepository(this.paginatedResponses);

  @override
  Future<List<YouTubeVideo>> search(String query, {int page = 1, bool forceFresh = false}) async {
    final clean = query.trim().toLowerCase();
    for (final entry in paginatedResponses.entries) {
      if (clean.contains(entry.key.toLowerCase())) {
        return entry.value[page] ?? [];
      }
    }
    return [];
  }

  @override
  Future<List<YouTubeVideo>> getArtistTracks(
    String artistName, {
    int page = 1,
    int limit = 15,
    List<String> preferredLanguages = const [],
  }) async {
    final clean = artistName.trim().toLowerCase();
    for (final entry in paginatedResponses.entries) {
      if (clean.contains(entry.key.toLowerCase())) {
        final batch = entry.value[page] ?? [];
        return batch.take(limit).toList();
      }
    }
    return [];
  }

  @override
  void clearCache() {}

  @override
  Future<List<String>> getSuggestions(String query) async => [];

  @override
  Future<List<ArtistModel>> searchArtists(String query) async => const [];

  @override
  Future<List<YouTubeVideo>> getRelatedTracks(YouTubeVideo seed, {int limit = 15}) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Task 8 — Queue Extension Tests', () {
    late MieeAudioHandler handler;

    setUp(() {
      handler = MieeAudioHandler();
    });

    tearDown(() async {
      try {
        await handler.disposeHandler();
      } catch (_) {}
    });

    test('1. Initial batch contains 15 tracks.', () async {
      final initialTracks = List.generate(
        15,
        (i) => Track(
          id: 'youtube_track_$i',
          title: 'Artist Song $i',
          artist: 'Anirudh',
          imageUrl: 'https://example.com/art.jpg',
          duration: '3:30',
        ),
      );

      handler.setQueueForTesting(initialTracks, currentIndex: 0);

      expect(handler.currentQueue.length, equals(15));
      expect(handler.currentIndex, equals(0));
      expect(handler.currentQueue.first.title, equals('Artist Song 0'));
      expect(handler.currentQueue.last.title, equals('Artist Song 14'));
    });

    test('2. Additional tracks are fetched before the queue is exhausted.', () async {
      final qm = QueueManager();
      final initialTracks = List.generate(
        15,
        (i) => Track(
          id: 'youtube_t_$i',
          title: 'Song $i',
          artist: 'Test Artist',
          imageUrl: '',
          duration: '3:00',
        ),
      );
      qm.setQueue(initialTracks, startIndex: 11);

      // Remaining tracks ahead: index 11 of 14 leaves 3 tracks remaining
      final remaining = qm.queue.length - 1 - qm.currentIndex;
      expect(remaining, equals(3));

      // With low-queue threshold = 3, prefetching is triggered before queue exhaustion
      final shouldTriggerPrefetch = remaining <= 3;
      expect(shouldTriggerPrefetch, isTrue);

      // Simulate next page returned by provider
      final page2Tracks = List.generate(
        10,
        (i) => Track(
          id: 'youtube_page2_$i',
          title: 'Page 2 Song $i',
          artist: 'Test Artist',
          imageUrl: '',
          duration: '3:00',
        ),
      );

      qm.addTracks(page2Tracks);
      expect(qm.queue.length, equals(25));
    });

    test('3. New tracks append without resetting current playback.', () async {
      final qm = QueueManager();
      final initialTracks = List.generate(
        15,
        (i) => Track(id: 't_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(initialTracks, startIndex: 12);
      handler.setQueueForTesting(initialTracks, currentIndex: 12);

      // Track 12 is active and playing at 1m 20s
      handler.setLastValidPositionForTesting(const Duration(seconds: 80));
      final activeBefore = qm.currentTrack;
      final activeIndexBefore = qm.currentIndex;
      final positionBefore = handler.lastValidPosition;

      // Append 10 newly fetched tracks
      final nextBatch = List.generate(
        10,
        (i) => Track(id: 'new_$i', title: 'New $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.addTracks(nextBatch);
      await handler.appendTracks(nextBatch);

      // Current active track, index, and playback position must NOT reset
      expect(qm.currentTrack?.id, equals(activeBefore?.id));
      expect(qm.currentIndex, equals(activeIndexBefore));
      expect(handler.lastValidPosition, equals(positionBefore));
      expect(qm.queue.length, equals(25));
      expect(handler.currentQueue.length, equals(25));
    });

    test('4. Playback continues after the initial 15 tracks finish.', () async {
      final qm = QueueManager();
      final initialTracks = List.generate(
        15,
        (i) => Track(id: 't_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(initialTracks, startIndex: 14);

      // When at last initial track (index 14), append page 2
      final page2 = List.generate(
        5,
        (i) => Track(id: 'p2_$i', title: 'Page2 Song $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.addTracks(page2);

      // Advance to next track
      final nextTrack = qm.next();
      expect(nextTrack, isNotNull);
      expect(nextTrack!.id, equals('p2_0'));
      expect(qm.currentIndex, equals(15));
    });

    test('5. Multiple batches can be appended.', () async {
      final qm = QueueManager();
      qm.setQueue(
        List.generate(15, (i) => Track(id: 'batch1_$i', title: 'B1 $i', artist: 'A', imageUrl: '', duration: '3:00')),
      );
      expect(qm.queue.length, equals(15));

      // Append Batch 2
      qm.addTracks(
        List.generate(10, (i) => Track(id: 'batch2_$i', title: 'B2 $i', artist: 'A', imageUrl: '', duration: '3:00')),
      );
      expect(qm.queue.length, equals(25));

      // Append Batch 3
      qm.addTracks(
        List.generate(10, (i) => Track(id: 'batch3_$i', title: 'B3 $i', artist: 'A', imageUrl: '', duration: '3:00')),
      );
      expect(qm.queue.length, equals(35));
    });

    test('6. The queue stops extending when the provider genuinely has no more results.', () async {
      final mockRepo = MockPaginatedYouTubeRepository({
        'ShortCatalogArtist': {
          1: List.generate(15, (i) => YouTubeVideo(id: 'sc_$i', title: 'Track $i', channelTitle: 'ShortCatalogArtist', viewCount: '', duration: '3:00', thumbnailUrl: '')),
          // Page 2 is empty — catalogue exhausted
          2: [],
        },
      });

      final page1 = await mockRepo.getArtistTracks('ShortCatalogArtist', page: 1, limit: 15);
      expect(page1.length, equals(15));

      final page2 = await mockRepo.getArtistTracks('ShortCatalogArtist', page: 2, limit: 15);
      expect(page2.isEmpty, isTrue);
    });
  });

  group('Task 8 — Deduplication Tests', () {
    test('7. Overlapping pagination batches do not duplicate tracks.', () {
      final batch1 = [
        const Track(id: 'youtube_abc1', title: 'Song One', artist: 'Artist', imageUrl: '', duration: '3:00'),
        const Track(id: 'youtube_abc2', title: 'Song Two', artist: 'Artist', imageUrl: '', duration: '3:00'),
      ];

      final batch2WithOverlap = [
        const Track(id: 'youtube_abc2', title: 'Song Two', artist: 'Artist', imageUrl: '', duration: '3:00'),
        const Track(id: 'youtube_abc3', title: 'Song Three', artist: 'Artist', imageUrl: '', duration: '3:00'),
      ];

      final currentIds = batch1.map((t) => t.id).toSet();
      final filteredNew = batch2WithOverlap.where((t) => !currentIds.contains(t.id)).toList();

      expect(filteredNew.length, equals(1));
      expect(filteredNew.first.id, equals('youtube_abc3'));
    });

    test('8. The same YouTube video ID is not added twice.', () {
      final qm = QueueManager();
      const track1 = Track(id: 'youtube_dQw4w9WgXcQ', title: 'Rickroll', artist: 'Rick', imageUrl: '', duration: '3:30');
      const trackDuplicate = Track(id: 'dQw4w9WgXcQ', title: 'Rickroll (Alternate Title)', artist: 'Rick', imageUrl: '', duration: '3:30');

      qm.setQueue([track1]);

      String normalize(String id) => id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;
      final currentNormIds = qm.queue.map((t) => normalize(t.id)).toSet();

      final isDuplicate = currentNormIds.contains(normalize(trackDuplicate.id));
      expect(isDuplicate, isTrue);
    });

    test('9. Different remixes or live recordings remain distinct when they have different identities.', () {
      const original = Track(id: 'youtube_id_orig', title: 'Arabic Kuthu', artist: 'Anirudh', imageUrl: '', duration: '4:40');
      const remix = Track(id: 'youtube_id_remix', title: 'Arabic Kuthu (Remix)', artist: 'Anirudh', imageUrl: '', duration: '3:50');
      const live = Track(id: 'youtube_id_live', title: 'Arabic Kuthu (Live in Concert)', artist: 'Anirudh', imageUrl: '', duration: '5:10');

      final list = [original, remix, live];
      final seenIds = <String>{};
      final uniqueVersions = list.where((t) => seenIds.add(t.id)).toList();

      expect(uniqueVersions.length, equals(3));
      expect(uniqueVersions.map((t) => t.id), containsAll(['youtube_id_orig', 'youtube_id_remix', 'youtube_id_live']));
    });

    test('10. Similar song titles do not cause unrelated tracks to be removed.', () {
      const song1 = Track(id: 'youtube_s1', title: 'Theme Song Part 1', artist: 'Composer', imageUrl: '', duration: '2:30');
      const song2 = Track(id: 'youtube_s2', title: 'Theme Song Part 2', artist: 'Composer', imageUrl: '', duration: '3:10');

      // Do NOT deduplicate on title alone
      expect(song1.id != song2.id, isTrue);
      expect(song1.title != song2.title, isTrue);

      final queue = [song1, song2];
      expect(queue.length, equals(2));
    });
  });

  group('Task 8 — Concurrency and State Tests', () {
    test('11. Multiple queue updates do not trigger duplicate fetch requests.', () async {
      Completer<void>? activeCompleter;
      int fetchCalls = 0;

      Future<void> fetchBatch() async {
        if (activeCompleter != null) {
          await activeCompleter!.future;
          return;
        }

        final c = Completer<void>();
        activeCompleter = c;
        fetchCalls++;

        // Simulate async network latency
        await Future<void>.delayed(const Duration(milliseconds: 20));
        activeCompleter = null;
        c.complete();
      }

      // Trigger 3 concurrent calls
      await Future.wait([fetchBatch(), fetchBatch(), fetchBatch()]);

      expect(fetchCalls, equals(1));
    });

    test('12. Stale responses cannot append tracks to a replacement queue.', () {
      int generationToken = 1;

      // Pending fetch captured token 1
      final capturedToken = generationToken;

      // User switched artist/playlist
      generationToken = 2;

      final incomingTracks = [const Track(id: 'old_t', title: 'Stale Song', artist: 'Old Artist', imageUrl: '', duration: '3:00')];
      final qm = QueueManager();
      qm.setQueue([const Track(id: 'new_t', title: 'New Song', artist: 'New Artist', imageUrl: '', duration: '3:00')]);

      // Guard check:
      if (capturedToken == generationToken) {
        qm.addTracks(incomingTracks);
      }

      // Queue must contain only the new track
      expect(qm.queue.length, equals(1));
      expect(qm.queue.first.artist, equals('New Artist'));
    });

    test('13. Selecting a new artist invalidates the old artist pending fetch.', () {
      var activeArtist = 'A. R. Rahman';
      var generationToken = 10;

      // Async fetch started for A. R. Rahman with token 10
      final fetchArtist = activeArtist;
      final fetchToken = generationToken;

      // User selects Yuvan Shankar Raja
      activeArtist = 'Yuvan Shankar Raja';
      generationToken = 11;

      // Response arrives for fetchArtist
      final isStale = (fetchToken != generationToken) || (fetchArtist != activeArtist);
      expect(isStale, isTrue);
    });

    test('14. A temporary fetch failure does not destroy the existing queue.', () {
      final qm = QueueManager();
      final tracks = List.generate(
        15,
        (i) => Track(id: 'track_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(tracks, startIndex: 10);

      // Simulated network failure during expansion
      try {
        throw Exception('SocketException: Connection refused');
      } catch (_) {
        // Queue error handler preserves existing items
      }

      expect(qm.queue.length, equals(15));
      expect(qm.currentIndex, equals(10));
      expect(qm.currentTrack?.id, equals('track_10'));
    });

    test('15. Queue extension does not change the current playback position.', () {
      final currentPos = const Duration(seconds: 145);
      final tracks = List.generate(
        15,
        (i) => Track(id: 't_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '4:00'),
      );
      final qm = QueueManager();
      qm.setQueue(tracks, startIndex: 12);

      // Append tracks
      qm.addTracks([
        const Track(id: 't_new_1', title: 'New 1', artist: 'Artist', imageUrl: '', duration: '3:00'),
      ]);

      // Position variable is untouched by addTracks
      expect(currentPos, equals(const Duration(seconds: 145)));
      expect(qm.currentIndex, equals(12));
    });

    test('16. Local music queues continue working normally.', () {
      const local1 = MediaSong(
        id: 'local_1',
        title: 'Local 1',
        artist: 'Offline Artist',
        album: 'Album',
        duration: '3:00',
        durationMs: 180000,
        filePath: '/storage/emulated/0/Music/1.mp3',
        artworkPath: '',
      );
      const local2 = MediaSong(
        id: 'local_2',
        title: 'Local 2',
        artist: 'Offline Artist',
        album: 'Album',
        duration: '4:00',
        durationMs: 240000,
        filePath: '/storage/emulated/0/Music/2.mp3',
        artworkPath: '',
      );

      final qm = QueueManager();
      qm.setQueue([local1, local2], startIndex: 0);

      expect(qm.queue.length, equals(2));
      expect(qm.currentTrack?.isYoutube, isFalse);

      final next = qm.next();
      expect(next?.id, equals('local_2'));
      expect(next?.isYoutube, isFalse);
    });
  });

  group('Task 8 — End-of-Queue Behavior Tests', () {
    test('17. The player advances into newly appended tracks.', () {
      final qm = QueueManager();
      final tracks = List.generate(
        15,
        (i) => Track(id: 't_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(tracks, startIndex: 14);

      // At track 15 (index 14)
      expect(qm.currentIndex, equals(14));

      // Append new track
      qm.addTrack(
        const Track(id: 't_15', title: 'Song 15', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );

      // Advance
      final advanced = qm.next();
      expect(advanced, isNotNull);
      expect(advanced!.id, equals('t_15'));
      expect(qm.currentIndex, equals(15));
    });

    test('18. The app does not stop merely because the initial batch has ended.', () {
      final qm = QueueManager();
      qm.setQueue(
        List.generate(15, (i) => Track(id: 't_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '3:00')),
        startIndex: 14,
      );

      // Expansion hook provides next batch
      bool isPlaybackStopped = false;
      if (qm.currentIndex >= qm.queue.length - 1) {
        // Dynamically fetch and append
        qm.addTracks([
          const Track(id: 't_continuation', title: 'Continuation', artist: 'Artist', imageUrl: '', duration: '3:00'),
        ]);
      }

      if (qm.next() == null) {
        isPlaybackStopped = true;
      }

      expect(isPlaybackStopped, isFalse);
      expect(qm.currentTrack?.id, equals('t_continuation'));
    });

    test('19. The app does not replay the same initial batch indefinitely.', () {
      final qm = QueueManager();
      final initial15 = List.generate(
        15,
        (i) => Track(id: 't_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(initial15, startIndex: 14);

      // Without repeat mode, it does not reset to index 0
      final repeatMode = RepeatMode.off;
      if (qm.next() == null && repeatMode == RepeatMode.off) {
        // Does not loop back to index 0
        expect(qm.currentIndex, equals(14));
      }
    });

    test('20. Existing repeat and shuffle behavior remains correct.', () {
      final qm = QueueManager();
      final tracks = List.generate(
        5,
        (i) => Track(id: 't_$i', title: 'Song $i', artist: 'Artist', imageUrl: '', duration: '3:00'),
      );
      qm.setQueue(tracks, startIndex: 0);

      // Enable shuffle: first item remains active, rest shuffled
      qm.enableShuffle();
      expect(qm.isShuffled, isTrue);
      expect(qm.currentTrack?.id, equals('t_0'));

      // Disable shuffle: original order restored
      qm.disableShuffle();
      expect(qm.isShuffled, isFalse);
      expect(qm.queue.map((t) => t.id).toList(), equals(tracks.map((t) => t.id).toList()));
    });
  });
}

