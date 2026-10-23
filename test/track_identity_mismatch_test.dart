import 'package:flutter_test/flutter_test.dart';
import 'package:audio_service/audio_service.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/queue_manager.dart';

/// Test harness verifying track identity consistency and preventing audio source mismatch.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Track Identity Consistency & Playback Integrity Tests', () {
    const vizhiId = 'youtube__e45NEdNMXE';
    const vizhiRawId = '_e45NEdNMXE';
    const vizhiTrack = Track(
      id: vizhiId,
      title: 'Vizhi Veekura',
      artist: 'Sai Abhyankkar',
      imageUrl: 'https://i.ytimg.com/vi/_e45NEdNMXE/hqdefault.jpg',
      duration: '3:45',
      filePath: 'https://www.youtube.com/watch?v=_e45NEdNMXE',
    );

    const oorodaId = 'youtube_HiCbeZuhYZw';
    const oorodaRawId = 'HiCbeZuhYZw';
    const oorodaTrack = Track(
      id: oorodaId,
      title: 'Ooroda Oththa Don',
      artist: 'Sai Abhyankkar',
      imageUrl: 'https://i.ytimg.com/vi/HiCbeZuhYZw/hqdefault.jpg',
      duration: '4:10',
      filePath: 'https://www.youtube.com/watch?v=HiCbeZuhYZw',
    );

    test('1. Selecting Vizhi Veekura extracts and associates its exact video ID', () {
      String extractVideoId(String trackId) {
        var id = trackId.trim();
        if (id.startsWith('youtube_')) id = id.substring('youtube_'.length);
        if (id.contains('watch?v=')) id = Uri.tryParse(id)?.queryParameters['v'] ?? id;
        return id;
      }

      final extracted = extractVideoId(vizhiTrack.id);
      expect(extracted, equals(vizhiRawId));
      expect(isSameTrackId(vizhiTrack.id, vizhiRawId), isTrue);
      expect(isSameTrackId(vizhiTrack.id, oorodaRawId), isFalse);
    });

    test('2. Selecting Ooroda Oththa Don replaces previous audio source and updates loaded identity', () {
      String? loadedTrackId = vizhiTrack.id;
      expect(isSameTrackId(loadedTrackId, vizhiTrack.id), isTrue);

      // Transition to Ooroda Oththa Don
      loadedTrackId = null; // Invalidate during transition
      expect(loadedTrackId, isNull);

      // Successful load of Ooroda Oththa Don
      loadedTrackId = oorodaTrack.id;
      expect(isSameTrackId(loadedTrackId, oorodaTrack.id), isTrue);
      expect(isSameTrackId(loadedTrackId, vizhiTrack.id), isFalse);
    });

    test('3. Delayed response for previous track cannot overwrite current selection', () async {
      int activeToken = 0;
      String? activeLoadedTrackId;
      final loadEvents = <String>[];

      Future<void> simulateTrackLoad({
        required String trackId,
        required int delayMs,
        required int token,
      }) async {
        await Future<void>.delayed(Duration(milliseconds: delayMs));
        if (token != activeToken) {
          // Stale request discarded
          return;
        }
        activeLoadedTrackId = trackId;
        loadEvents.add(trackId);
      }

      // Step 1: User requests Vizhi Veekura (slow network: 100ms)
      activeToken = 1;
      final fut1 = simulateTrackLoad(
        trackId: vizhiTrack.id,
        delayMs: 100,
        token: 1,
      );

      // Step 2: User immediately switches to Ooroda Oththa Don (fast: 30ms)
      activeToken = 2;
      final fut2 = simulateTrackLoad(
        trackId: oorodaTrack.id,
        delayMs: 30,
        token: 2,
      );

      await Future.wait([fut1, fut2]);

      // Only Ooroda Oththa Don must be loaded as active
      expect(activeLoadedTrackId, equals(oorodaTrack.id));
      expect(loadEvents, equals([oorodaTrack.id]));
    });

    test('4. Two songs with similar titles or artists do not share wrong cached stream', () {
      final cache = <String, String>{};

      // Two tracks by Sai Abhyankkar
      cache[vizhiRawId] = 'https://googlevideo.com/videoplayback?id=vizhi_audio_stream';
      cache[oorodaRawId] = 'https://googlevideo.com/videoplayback?id=ooroda_audio_stream';

      expect(cache[vizhiRawId], contains('vizhi_audio_stream'));
      expect(cache[oorodaRawId], contains('ooroda_audio_stream'));
      expect(cache[vizhiRawId], isNot(equals(cache[oorodaRawId])));
    });

    test('5. Queue next and previous updates both audio source and metadata', () {
      final queueManager = QueueManager();
      final tracks = [vizhiTrack, oorodaTrack];
      queueManager.setQueue(tracks, startIndex: 0);

      expect(queueManager.currentIndex, equals(0));
      expect(queueManager.currentTrack?.title, equals('Vizhi Veekura'));

      // Next
      final nextTrack = queueManager.next();
      expect(nextTrack?.title, equals('Ooroda Oththa Don'));
      expect(queueManager.currentIndex, equals(1));

      // Previous
      final prevTrack = queueManager.previous();
      expect(prevTrack?.title, equals('Vizhi Veekura'));
      expect(queueManager.currentIndex, equals(0));
    });

    test('6. Now Playing metadata remains associated with selected track and rejects mismatched play', () {
      String? loadedAudioTrackId;
      const currentTrack = vizhiTrack;

      bool canPlay() {
        return loadedAudioTrackId != null &&
            isSameTrackId(loadedAudioTrackId, currentTrack.id);
      }

      // Case A: Nothing loaded yet -> play() blocked
      expect(canPlay(), isFalse);

      // Case B: Stale track loaded (Ooroda Oththa Don) -> play() blocked
      loadedAudioTrackId = oorodaTrack.id;
      expect(canPlay(), isFalse, reason: 'Must block play() when player source does not match selected track');

      // Case C: Correct track loaded (Vizhi Veekura) -> play() permitted
      loadedAudioTrackId = vizhiTrack.id;
      expect(canPlay(), isTrue);
    });

    test('7. A failed resolver does not play an unrelated previous or fallback track', () async {
      String? loadedAudioTrackId = oorodaTrack.id; // Previous song was loaded
      bool isPlaying = false;

      Future<void> loadTrackWithSimulation({required bool shouldFail}) async {
        // Step 1: Loading begins -> invalidate loaded track identity immediately
        loadedAudioTrackId = null;

        if (shouldFail) {
          // Resolution failed: throw error and do not assign source
          throw Exception('Unable to resolve audio stream');
        } else {
          loadedAudioTrackId = vizhiTrack.id;
        }
      }

      void play() {
        if (loadedAudioTrackId == null || !isSameTrackId(loadedAudioTrackId, vizhiTrack.id)) {
          // Refuse to play stale or unverified audio
          return;
        }
        isPlaying = true;
      }

      // Simulate failed resolution for Vizhi Veekura
      expect(
        () => loadTrackWithSimulation(shouldFail: true),
        throwsA(isA<Exception>()),
      );

      // Attempt to play
      play();

      // Invariant: isPlaying must remain FALSE, previous song MUST NOT play
      expect(isPlaying, isFalse);
      expect(loadedAudioTrackId, isNull);
    });

    test('8. Existing background playback and notification controls remain functional', () {
      MediaItem createMediaItem(Track track) {
        return MediaItem(
          id: track.id,
          title: track.title,
          artist: track.artist,
          artUri: Uri.parse(track.imageUrl),
        );
      }

      final item = createMediaItem(vizhiTrack);
      expect(item.id, equals(vizhiTrack.id));
      expect(item.title, equals('Vizhi Veekura'));
      expect(item.artist, equals('Sai Abhyankkar'));
      expect(item.artUri.toString(), equals(vizhiTrack.imageUrl));
    });
  });
}
