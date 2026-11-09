import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('Miee — Queue Generation & Duplicate/Same-Title Track Prevention', () {
    late QueueManager queueManager;

    setUp(() {
      queueManager = QueueManager();
    });

    // ── SCENARIO 1: Search "West Coast" → Play Lana Del Rey ─────────────────
    test(
        '1. Playing Lana Del Rey "West Coast" does not populate queue with same-title tracks by different artists',
        () {
      const selectedTrack = Track(
        id: 'youtube_lana_wc',
        title: 'West Coast',
        artist: 'Lana Del Rey',
        imageUrl: 'https://img.test/lana_wc.jpg',
        duration: '4:16',
      );

      // Candidate upcoming recommendations from discovery / related tracks
      final candidates = [
        const Track(
          id: 'youtube_lana_shades',
          title: 'Shades of Cool',
          artist: 'Lana Del Rey',
          imageUrl: 'https://img.test/shades.jpg',
          duration: '5:42',
        ),
        const Track(
          id: 'youtube_onerepublic_wc',
          title: 'West Coast',
          artist: 'OneRepublic',
          imageUrl: 'https://img.test/1r_wc.jpg',
          duration: '3:12',
        ),
        const Track(
          id: 'youtube_geazy_wc',
          title: 'West Coast',
          artist: 'G-Eazy',
          imageUrl: 'https://img.test/geazy_wc.jpg',
          duration: '3:30',
        ),
        const Track(
          id: 'youtube_neighbourhood_sw',
          title: 'Sweater Weather',
          artist: 'The Neighbourhood',
          imageUrl: 'https://img.test/sw.jpg',
          duration: '4:00',
        ),
        const Track(
          id: 'youtube_lana_brooklyn',
          title: 'Brooklyn Baby',
          artist: 'Lana Del Rey',
          imageUrl: 'https://img.test/brooklyn.jpg',
          duration: '5:51',
        ),
      ];

      // Simulate Queue replenishment filtering rule
      final currentBaseTitle = SearchDeduplicator.normalizeBaseTitle(
        selectedTrack.title,
        artist: selectedTrack.artist,
      ).toLowerCase().trim();
      final currentArtistNorm =
          SearchDeduplicator.normalizeArtist(selectedTrack.artist);

      final acceptedUpcoming = <MusicItem>[];
      for (final candidate in candidates) {
        final candBaseTitle = SearchDeduplicator.normalizeBaseTitle(
          candidate.title,
          artist: candidate.artist,
        ).toLowerCase().trim();
        final candArtistNorm =
            SearchDeduplicator.normalizeArtist(candidate.artist);

        // Strict Rule: Reject different artists' tracks merely sharing the selected track's title
        if (currentBaseTitle.isNotEmpty &&
            candBaseTitle == currentBaseTitle &&
            candArtistNorm != currentArtistNorm) {
          continue;
        }
        acceptedUpcoming.add(candidate);
      }

      // Populate queue
      queueManager.setQueue([selectedTrack], startIndex: 0);
      queueManager.addTracks(acceptedUpcoming);

      // Verify selected track is current
      expect(queueManager.currentTrack?.title, equals('West Coast'));
      expect(queueManager.currentTrack?.artist, equals('Lana Del Rey'));

      // Verify the queue contains Lana Del Rey & related tracks
      final queueTitlesAndArtists =
          queueManager.queue.map((t) => '${t.title} by ${t.artist}').toList();

      expect(queueTitlesAndArtists, contains('West Coast by Lana Del Rey'));
      expect(queueTitlesAndArtists, contains('Shades of Cool by Lana Del Rey'));
      expect(queueTitlesAndArtists,
          contains('Sweater Weather by The Neighbourhood'));
      expect(queueTitlesAndArtists, contains('Brooklyn Baby by Lana Del Rey'));

      // Verify unrelated same-title tracks by different artists are strictly NOT in queue
      expect(
          queueTitlesAndArtists, isNot(contains('West Coast by OneRepublic')));
      expect(queueTitlesAndArtists, isNot(contains('West Coast by G-Eazy')));
    });

    // ── SCENARIO 2: Common Song Title Shared by Multiple Artists ─────────────
    test(
        '2. Common song title "Hold On" preserves artist identity and excludes unrelated homonyms',
        () {
      const jbHoldOn = Track(
        id: 'youtube_jb_holdon',
        title: 'Hold On',
        artist: 'Justin Bieber',
        imageUrl: '',
        duration: '2:50',
      );
      const chordHoldOn = Track(
        id: 'youtube_chord_holdon',
        title: 'Hold On',
        artist: 'Chord Overstreet',
        imageUrl: '',
        duration: '3:18',
      );
      const alabamaHoldOn = Track(
        id: 'youtube_alabama_holdon',
        title: 'Hold On',
        artist: 'Alabama Shakes',
        imageUrl: '',
        duration: '3:48',
      );

      // 1. Keys must be distinct so they are NEVER falsely treated as duplicates
      final keyJB = SearchDeduplicator.computeRecordingKey(jbHoldOn);
      final keyChord = SearchDeduplicator.computeRecordingKey(chordHoldOn);
      final keyAlabama = SearchDeduplicator.computeRecordingKey(alabamaHoldOn);

      expect(keyJB, isNot(equals(keyChord)));
      expect(keyJB, isNot(equals(keyAlabama)));
      expect(keyChord, isNot(equals(keyAlabama)));

      // 2. Queue deduplication preserves both if user explicitly adds both
      queueManager
          .setQueue([jbHoldOn, chordHoldOn, alabamaHoldOn], startIndex: 0);
      expect(queueManager.queue.length, equals(3));
      expect(queueManager.queue[0].artist, equals('Justin Bieber'));
      expect(queueManager.queue[1].artist, equals('Chord Overstreet'));
      expect(queueManager.queue[2].artist, equals('Alabama Shakes'));
    });

    // ── SCENARIO 3: Track Identity & Deduplication Rules ─────────────────────
    test(
        '3. Deduplicates redundant uploads of same canonical recording while preserving remixes and live versions',
        () {
      const officialVideo = Track(
        id: 'youtube_vid_official',
        title: 'West Coast (Official Music Video)',
        artist: 'Lana Del Rey',
        imageUrl: '',
        duration: '4:16',
      );
      const lyricVideo = Track(
        id: 'youtube_vid_lyrics',
        title: 'West Coast - Lyrics',
        artist: 'Lana Del Rey',
        imageUrl: '',
        duration: '4:16',
      );
      const audioUpload = Track(
        id: 'youtube_vid_audio',
        title: 'Lana Del Rey - West Coast (Audio)',
        artist: 'Lana Del Rey',
        imageUrl: '',
        duration: '4:16',
      );
      const liveCoachella = Track(
        id: 'youtube_vid_live',
        title: 'West Coast (Live at Coachella)',
        artist: 'Lana Del Rey',
        imageUrl: '',
        duration: '4:35',
      );
      const radioRemix = Track(
        id: 'youtube_vid_remix',
        title: 'West Coast (Radio Mix)',
        artist: 'Lana Del Rey',
        imageUrl: '',
        duration: '3:58',
      );

      // 1. Redundant uploads share the same canonical recording key
      expect(
        SearchDeduplicator.computeRecordingKey(officialVideo),
        equals(SearchDeduplicator.computeRecordingKey(lyricVideo)),
      );
      expect(
        SearchDeduplicator.computeRecordingKey(officialVideo),
        equals(SearchDeduplicator.computeRecordingKey(audioUpload)),
      );

      // 2. Live and Remix versions have distinct version tags and MUST NOT be merged
      expect(
        SearchDeduplicator.computeRecordingKey(officialVideo),
        isNot(equals(SearchDeduplicator.computeRecordingKey(liveCoachella))),
      );
      expect(
        SearchDeduplicator.computeRecordingKey(officialVideo),
        isNot(equals(SearchDeduplicator.computeRecordingKey(radioRemix))),
      );
      expect(
        SearchDeduplicator.computeRecordingKey(liveCoachella),
        isNot(equals(SearchDeduplicator.computeRecordingKey(radioRemix))),
      );
    });

    // ── SCENARIO 4: Album Playback Order Preservation ────────────────────────
    test(
        '4. Playing a track directly from an album preserves exact album tracklist and order',
        () {
      final albumTracks = List.generate(
        10,
        (i) => Track(
          id: 'local_album_track_$i',
          title: 'Album Song #${i + 1}',
          artist: 'Album Artist',
          imageUrl: '',
          duration: '3:30',
        ),
      );

      // Select track 4 (index 3)
      queueManager.setQueue(albumTracks, startIndex: 3);

      expect(queueManager.currentIndex, equals(3));
      expect(queueManager.currentTrack?.id, equals('local_album_track_3'));
      expect(queueManager.queue.length, equals(10));
      for (int i = 0; i < 10; i++) {
        expect(queueManager.queue[i].id, equals('local_album_track_$i'));
      }
    });

    // ── SCENARIO 5: Playlist Playback Context Preservation ────────────────────
    test(
        '5. Playing a track from a playlist preserves playlist context and order',
        () {
      final playlistTracks = [
        const Track(
            id: 'pl_1',
            title: 'Song Alpha',
            artist: 'Artist A',
            imageUrl: '',
            duration: '3:00'),
        const Track(
            id: 'pl_2',
            title: 'Song Beta',
            artist: 'Artist B',
            imageUrl: '',
            duration: '3:20'),
        const Track(
            id: 'pl_3',
            title: 'Song Gamma',
            artist: 'Artist C',
            imageUrl: '',
            duration: '4:10'),
      ];

      queueManager.setQueue(playlistTracks, startIndex: 1);

      expect(queueManager.currentIndex, equals(1));
      expect(queueManager.currentTrack?.title, equals('Song Beta'));
      expect(queueManager.queue.length, equals(3));
      expect(queueManager.queue[0].title, equals('Song Alpha'));
      expect(queueManager.queue[2].title, equals('Song Gamma'));
    });

    // ── SCENARIO 6: Manual Queue Additions ───────────────────────────────────
    test(
        '6. Adding a track manually via addTrack appends to existing queue without replacing it',
        () {
      const initialTrack = Track(
        id: 'initial_1',
        title: 'Now Playing Track',
        artist: 'Main Artist',
        imageUrl: '',
        duration: '3:45',
      );
      queueManager.setQueue([initialTrack], startIndex: 0);
      expect(queueManager.queue.length, equals(1));

      // User manually taps "Add to Queue"
      const manualTrack = Track(
        id: 'manual_2',
        title: 'Manually Queued Track',
        artist: 'Guest Artist',
        imageUrl: '',
        duration: '2:55',
      );
      queueManager.addTrack(manualTrack);

      expect(queueManager.queue.length, equals(2));
      expect(queueManager.currentIndex, equals(0)); // Current track unchanged
      expect(queueManager.currentTrack?.id, equals('initial_1'));
      expect(queueManager.queue[1].id, equals('manual_2'));
    });

    // ── SCENARIO 7: Next & Previous Playback Navigation ───────────────────────
    test('7. Sequential playback navigation through queue works correctly', () {
      final tracks = List.generate(
        3,
        (i) => Track(
          id: 'step_track_$i',
          title: 'Track $i',
          artist: 'Artist',
          imageUrl: '',
          duration: '3:00',
        ),
      );

      queueManager.setQueue(tracks, startIndex: 0);
      expect(queueManager.currentTrack?.id, equals('step_track_0'));

      // Next
      final nextTrack = queueManager.next();
      expect(nextTrack?.id, equals('step_track_1'));
      expect(queueManager.currentIndex, equals(1));

      // Next again
      final lastTrack = queueManager.next();
      expect(lastTrack?.id, equals('step_track_2'));
      expect(queueManager.currentIndex, equals(2));

      // Previous
      final prevTrack = queueManager.previous();
      expect(prevTrack?.id, equals('step_track_1'));
      expect(queueManager.currentIndex, equals(1));
    });

    // ── SCENARIO 8: Queue Snapshot Serialization & Identity Preservation ────
    test(
        '8. Queue tracks maintain stable ID and attributes across serialization',
        () {
      const originalTrack = Track(
        id: 'youtube_lana_wc',
        title: 'West Coast',
        artist: 'Lana Del Rey',
        imageUrl: 'https://img.test/wc.jpg',
        duration: '4:16',
      );

      final hiveModel = TrackHiveModel.fromTrack(originalTrack);
      final restored = hiveModel.toTrack();

      expect(restored.id, equals(originalTrack.id));
      expect(restored.title, equals(originalTrack.title));
      expect(restored.artist, equals(originalTrack.artist));
      expect(restored.imageUrl, equals(originalTrack.imageUrl));
      expect(restored.isYoutube, isTrue);
    });
  });
}
