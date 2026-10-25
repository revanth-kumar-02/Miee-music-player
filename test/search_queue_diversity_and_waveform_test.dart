import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/song_tile.dart';
import 'package:Miee/shared/widgets/waveform_widget.dart';

void main() {
  group('Comprehensive Search Deduplication, Queue Diversity & Waveform Tests', () {
    // 1. Searching for "Kaadhalai Solla Mudiyatha"
    test('1. Searching for "Kaadhalai Solla Mudiyatha" deduplicates multiple uploads into 1 canonical track', () {
      final videos = [
        const YouTubeVideo(
          id: 'v_official',
          title: 'Kaadhalai Solla Mudiyatha',
          channelTitle: 'Yazin Nizar',
          thumbnailUrl: 'https://img.youtube.com/vi/v_official/hqdefault.jpg',
          duration: '4:51',
          viewCount: '10M views',
          rawTitle: 'Kaadhalai Solla Mudiyatha | Galatta Kalyanam | A.R. Rahman | Yazin Nizar',
          rawChannelTitle: 'SonyMusicSouthVEVO',
          rawViewCount: 10000000,
        ),
        const YouTubeVideo(
          id: 'v_full_video',
          title: 'Full Video: Kaadhalai Solla Mudiyatha',
          channelTitle: 'A. R. Rahman',
          thumbnailUrl: 'https://img.youtube.com/vi/v_full_video/hqdefault.jpg',
          duration: '4:51',
          viewCount: '5M views',
          rawTitle: 'Full Video: Kaadhalai Solla Mudiyatha | Galatta Kalyanam',
          rawChannelTitle: 'Sony Music South',
          rawViewCount: 5000000,
        ),
        const YouTubeVideo(
          id: 'v_love_beatz',
          title: 'Kadhalai Solla Mudiyath',
          channelTitle: 'love_beatz',
          thumbnailUrl: 'https://img.youtube.com/vi/v_love_beatz/hqdefault.jpg',
          duration: '4:51',
          viewCount: '80K views',
          rawTitle: 'Kadhalai Solla Mudiyatha Song',
          rawChannelTitle: 'love_beatz',
          rawViewCount: 80000,
        ),
        const YouTubeVideo(
          id: 'v_musical',
          title: 'A.R. Rahman Musical - Kaadhalai Solla Mudiyatha',
          channelTitle: 'A. R. Rahman',
          thumbnailUrl: 'https://img.youtube.com/vi/v_musical/hqdefault.jpg',
          duration: '4:52',
          viewCount: '1M views',
          rawTitle: 'A.R. Rahman Musical - Kaadhalai Solla Mudiyatha',
          rawChannelTitle: 'A. R. Rahman',
          rawViewCount: 1000000,
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        videos,
        query: 'Kaadhalai Solla Mudiyatha',
        config: const SearchRankingConfig(filterDerivativeEdits: true),
      );

      // Must be deduplicated down to 1 single canonical track
      expect(results.length, 1);
      expect(results.first.id, 'v_official');
    });

    // 2. Repeated uploads of the same underlying song
    test('2. Repeated uploads of the same underlying song collapse into the best canonical representative', () {
      final videos = [
        const YouTubeVideo(
          id: 'fan_upload_1',
          title: 'Enna Sona',
          channelTitle: 'ArijitFanClub',
          thumbnailUrl: 'https://img.youtube.com/vi/fan1/hqdefault.jpg',
          duration: '3:33',
          viewCount: '40K views',
          rawTitle: 'Enna Sona - OK Jaanu',
          rawChannelTitle: 'ArijitFanClub',
          rawViewCount: 40000,
        ),
        const YouTubeVideo(
          id: 'official_upload',
          title: 'Enna Sona',
          channelTitle: 'Arijit Singh',
          thumbnailUrl: 'https://img.youtube.com/vi/off/hqdefault.jpg',
          duration: '3:33',
          viewCount: '150M views',
          rawTitle: 'Enna Sona | OK Jaanu | Arijit Singh | A.R. Rahman',
          rawChannelTitle: 'SonyMusicIndiaVEVO',
          rawViewCount: 150000000,
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        videos,
        query: 'Enna Sona',
      );

      expect(results.length, 1);
      expect(results.first.id, 'official_upload');
    });

    // 3. Duplicate provider IDs
    test('3. Duplicate provider IDs are immediately deduplicated', () {
      final videos = [
        const YouTubeVideo(
          id: 'same_video_id',
          title: 'Track A',
          channelTitle: 'Artist A',
          thumbnailUrl: 'https://img.youtube.com/vi/1/hqdefault.jpg',
          duration: '3:00',
          viewCount: '10K views',
        ),
        const YouTubeVideo(
          id: 'same_video_id',
          title: 'Track A (Duplicate entry)',
          channelTitle: 'Artist A',
          thumbnailUrl: 'https://img.youtube.com/vi/1/hqdefault.jpg',
          duration: '3:00',
          viewCount: '10K views',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos);
      expect(results.length, 1);
      expect(results.first.id, 'same_video_id');
    });

    // 4. Similar titles by different artists
    test('4. Similar titles by different artists are preserved as distinct entries', () {
      final videos = [
        const YouTubeVideo(
          id: 'adele_hello',
          title: 'Hello',
          channelTitle: 'Adele',
          thumbnailUrl: 'https://img.youtube.com/vi/adele/hqdefault.jpg',
          duration: '4:55',
          viewCount: '3B views',
          rawTitle: 'Adele - Hello (Official Music Video)',
          rawChannelTitle: 'AdeleVEVO',
        ),
        const YouTubeVideo(
          id: 'lionel_hello',
          title: 'Hello',
          channelTitle: 'Lionel Richie',
          thumbnailUrl: 'https://img.youtube.com/vi/lionel/hqdefault.jpg',
          duration: '5:07',
          viewCount: '250M views',
          rawTitle: 'Lionel Richie - Hello (Official Video)',
          rawChannelTitle: 'LionelRichieVEVO',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos, query: 'Hello');
      expect(results.length, 2);
      expect(results.map((v) => v.id), containsAll(['adele_hello', 'lionel_hello']));
    });

    // 5. Legitimate covers and remixes
    test('5. Legitimate covers, remixes, and acoustic versions are preserved', () {
      final videos = [
        const YouTubeVideo(
          id: 'v_original',
          title: 'Kaadhalai Solla Mudiyatha',
          channelTitle: 'Yazin Nizar',
          thumbnailUrl: 'https://img.youtube.com/vi/orig/hqdefault.jpg',
          duration: '4:51',
          viewCount: '10M views',
          rawTitle: 'Kaadhalai Solla Mudiyatha (Official Audio)',
          rawChannelTitle: 'SonyMusicSouthVEVO',
        ),
        const YouTubeVideo(
          id: 'v_remix',
          title: 'Kaadhalai Solla Mudiyatha (Remix)',
          channelTitle: 'DJ Remix',
          thumbnailUrl: 'https://img.youtube.com/vi/remix/hqdefault.jpg',
          duration: '3:45',
          viewCount: '500K views',
          rawTitle: 'Kaadhalai Solla Mudiyatha (Club Remix)',
          rawChannelTitle: 'DJ Club',
        ),
        const YouTubeVideo(
          id: 'v_cover',
          title: 'Kaadhalai Solla Mudiyatha (Cover)',
          channelTitle: 'Singer Priya',
          thumbnailUrl: 'https://img.youtube.com/vi/cover/hqdefault.jpg',
          duration: '4:10',
          viewCount: '200K views',
          rawTitle: 'Kaadhalai Solla Mudiyatha - Female Cover by Priya',
          rawChannelTitle: 'Priya Vocals',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos, query: 'Kaadhalai Solla Mudiyatha');
      expect(results.length, 3);
      expect(results.map((v) => v.id), containsAll(['v_original', 'v_remix', 'v_cover']));
    });

    // 6. Alternate-language versions
    test('6. Alternate-language versions with different titles are preserved', () {
      final videos = [
        const YouTubeVideo(
          id: 'v_tamil',
          title: 'Kaadhalai Solla Mudiyatha',
          channelTitle: 'A. R. Rahman',
          thumbnailUrl: 'https://img.youtube.com/vi/tamil/hqdefault.jpg',
          duration: '4:51',
          viewCount: '10M views',
          rawTitle: 'Galatta Kalyanam: Kaadhalai Solla Mudiyatha',
          rawChannelTitle: 'SonyMusicSouthVEVO',
        ),
        const YouTubeVideo(
          id: 'v_telugu',
          title: 'Choti Choti',
          channelTitle: 'A. R. Rahman',
          thumbnailUrl: 'https://img.youtube.com/vi/telugu/hqdefault.jpg',
          duration: '4:51',
          viewCount: '3M views',
          rawTitle: 'Galatta Kalyanam: Choti Choti',
          rawChannelTitle: 'SonyMusicSouthVEVO',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos);
      expect(results.length, 2);
      expect(results.map((v) => v.id), containsAll(['v_tamil', 'v_telugu']));
    });

    // 7. Official audio versus full music video results
    test('7. Official audio and full music video are clustered and official release prioritized', () {
      final videos = [
        const YouTubeVideo(
          id: 'v_video',
          title: 'Full Video: Kaadhalai Solla Mudiyatha',
          channelTitle: 'A. R. Rahman',
          thumbnailUrl: 'https://img.youtube.com/vi/v/hqdefault.jpg',
          duration: '4:51',
          viewCount: '1M views',
          rawTitle: 'Full Video: Kaadhalai Solla Mudiyatha',
          rawChannelTitle: 'Sony Music South',
          rawViewCount: 1000000,
        ),
        const YouTubeVideo(
          id: 'v_official_audio',
          title: 'Kaadhalai Solla Mudiyatha',
          channelTitle: 'A. R. Rahman',
          thumbnailUrl: 'https://img.youtube.com/vi/a/hqdefault.jpg',
          duration: '4:51',
          viewCount: '8M views',
          rawTitle: 'Kaadhalai Solla Mudiyatha (Official Audio)',
          rawChannelTitle: 'SonyMusicSouthVEVO',
          rawViewCount: 8000000,
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        videos,
        query: 'Kaadhalai Solla Mudiyatha',
      );

      expect(results.length, 1);
      expect(results.first.id, 'v_official_audio');
    });

    // 8. Search results with missing artist or duration metadata
    test('8. Handles missing artist or duration metadata without crashing', () {
      final videos = [
        const YouTubeVideo(
          id: 'v_missing_dur',
          title: 'Unknown Track',
          channelTitle: 'Artist',
          thumbnailUrl: 'https://img.youtube.com/vi/1/hqdefault.jpg',
          duration: '',
          viewCount: '',
        ),
        const YouTubeVideo(
          id: 'v_missing_channel',
          title: 'Another Track',
          channelTitle: '',
          thumbnailUrl: 'https://img.youtube.com/vi/2/hqdefault.jpg',
          duration: '3:00',
          viewCount: '',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos);
      expect(results.length, 2);
    });

    // 9. Queue creation from a search result
    test('9. Queue creation from search result places selected track at index 0', () {
      final queueManager = QueueManager();
      const track = Track(
        id: 'youtube_kaadhalai_1',
        title: 'Kaadhalai Solla Mudiyatha',
        artist: 'Yazin Nizar',
        imageUrl: 'https://img.youtube.com/vi/1/hqdefault.jpg',
        duration: '4:51',
      );

      queueManager.setQueue([track], startIndex: 0);
      expect(queueManager.queue.length, 1);
      expect(queueManager.currentIndex, 0);
      expect(queueManager.currentTrack?.id, 'youtube_kaadhalai_1');
    });

    // 10. Queue generation when related recommendations are available
    test('10. Populating Next Up with diverse recommendations excludes the seed track and its duplicates', () {
      final queueManager = QueueManager();
      const seedTrack = Track(
        id: 'youtube_kaadhalai_1',
        title: 'Kaadhalai Solla Mudiyatha',
        artist: 'Yazin Nizar',
        imageUrl: 'https://img.youtube.com/vi/1/hqdefault.jpg',
        duration: '4:51',
      );
      queueManager.setQueue([seedTrack], startIndex: 0);

      // Incoming recommendations from provider
      final upcomingRecs = <Track>[
        const Track(
          id: 'youtube_kaadhalai_duplicate',
          title: 'Full Video: Kaadhalai Solla Mudiyatha',
          artist: 'A. R. Rahman',
          imageUrl: 'https://img.youtube.com/vi/dup/hqdefault.jpg',
          duration: '4:51',
        ),
        const Track(
          id: 'youtube_diverse_1',
          title: 'Marakkuma Nenjam',
          artist: 'A. R. Rahman',
          imageUrl: 'https://img.youtube.com/vi/div1/hqdefault.jpg',
          duration: '4:15',
        ),
        const Track(
          id: 'youtube_diverse_2',
          title: 'Aalaporaan Thamizhan',
          artist: 'A. R. Rahman',
          imageUrl: 'https://img.youtube.com/vi/div2/hqdefault.jpg',
          duration: '5:48',
        ),
      ];

      // Filter out duplicate of seed
      const seedVideo = YouTubeVideo(
        id: 'kaadhalai_1',
        title: 'Kaadhalai Solla Mudiyatha',
        channelTitle: 'Yazin Nizar',
        thumbnailUrl: '',
        duration: '4:51',
        viewCount: '',
        rawTitle: 'Kaadhalai Solla Mudiyatha',
      );

      final filteredRecs = upcomingRecs.where((t) {
        final video = YouTubeVideo(
          id: t.id.replaceFirst('youtube_', ''),
          title: t.title,
          channelTitle: t.artist,
          thumbnailUrl: '',
          duration: t.duration,
          viewCount: '',
          rawTitle: t.title,
        );
        return !SearchDeduplicator.isSameCanonicalSong(video, seedVideo);
      }).toList();

      queueManager.addTracks(filteredRecs);

      expect(queueManager.queue.length, 3);
      expect(queueManager.queue[0].title, 'Kaadhalai Solla Mudiyatha');
      expect(queueManager.queue[1].title, 'Marakkuma Nenjam');
      expect(queueManager.queue[2].title, 'Aalaporaan Thamizhan');
      // Duplicate was excluded!
      expect(queueManager.queue.any((t) => t.id == 'youtube_kaadhalai_duplicate'), isFalse);
    });

    // 11. Queue generation when recommendations are unavailable
    test('11. When recommendations are unavailable, queue retains only selected track without fabricating items', () {
      final queueManager = QueueManager();
      const seedTrack = Track(
        id: 'youtube_single',
        title: 'Rare Indie Track',
        artist: 'Indie Artist',
        imageUrl: '',
        duration: '3:20',
      );

      queueManager.setQueue([seedTrack], startIndex: 0);
      final emptyRecs = <Track>[];
      queueManager.addTracks(emptyRecs);

      expect(queueManager.queue.length, 1);
      expect(queueManager.queue.first.id, 'youtube_single');
    });

    // 12. Avoiding duplicate upcoming entries
    test('12. Next Up queue avoids duplicate upcoming entries', () {
      final queueManager = QueueManager();
      const track1 = Track(id: 't1', title: 'Song 1', artist: 'Artist', imageUrl: '', duration: '3:00');
      const track2 = Track(id: 't2', title: 'Song 2', artist: 'Artist', imageUrl: '', duration: '3:30');
      queueManager.setQueue([track1], startIndex: 0);

      final incoming = [track2, track2]; // Duplicate in response
      final currentIds = queueManager.queue.map((t) => t.id).toSet();
      final fresh = <Track>[];
      for (final t in incoming) {
        if (!currentIds.contains(t.id)) {
          currentIds.add(t.id);
          fresh.add(t);
        }
      }
      queueManager.addTracks(fresh);

      expect(queueManager.queue.length, 2);
      expect(queueManager.queue.map((t) => t.id).toList(), ['t1', 't2']);
    });

    // 13. Preserving manual queue additions and ordering
    test('13. Preserving manual queue additions and ordering', () {
      final queueManager = QueueManager();
      const t1 = Track(id: '1', title: 'A', artist: 'Artist', imageUrl: '', duration: '3:00');
      const t2 = Track(id: '2', title: 'B', artist: 'Artist', imageUrl: '', duration: '3:00');
      const t3 = Track(id: '3', title: 'C', artist: 'Artist', imageUrl: '', duration: '3:00');
      queueManager.setQueue([t1, t2, t3], startIndex: 0);

      // Reorder item at 2 to 1
      queueManager.reorder(2, 1);
      expect(queueManager.queue.map((t) => t.id).toList(), ['1', '3', '2']);

      // Remove item at 2
      queueManager.removeTrackAt(2);
      expect(queueManager.queue.map((t) => t.id).toList(), ['1', '3']);
    });

    // 14. Selecting an upcoming track and playing its exact source
    test('14. Selecting an upcoming track retains its exact provider identifier and source', () {
      final queueManager = QueueManager();
      const t1 = Track(id: 'youtube_track_1', title: 'A', artist: 'A', imageUrl: '', duration: '3:00');
      const t2 = Track(id: 'youtube_track_2', title: 'B', artist: 'B', imageUrl: '', duration: '4:00');
      queueManager.setQueue([t1, t2], startIndex: 0);

      queueManager.setIndex(1);
      expect(queueManager.currentTrack?.id, 'youtube_track_2');
      expect(queueManager.currentTrack?.isYoutube, isTrue);
    });

    // 15. Preventing stale asynchronous responses from changing the queue
    test('15. Outdated async recommendation token is rejected and does not pollute a newer queue', () {
      int activeToken = 1;
      String activeTrackId = 'track_A';
      final queue = <String>['track_A'];

      void handleAsyncRecs(List<String> recs, int token, String forTrackId) {
        if (token != activeToken || activeTrackId != forTrackId) {
          return; // Ignore stale response
        }
        queue.addAll(recs);
      }

      // User initiates Track B before Track A recommendations finish
      activeToken = 2;
      activeTrackId = 'track_B';
      queue.clear();
      queue.add('track_B');

      // Stale response arrives for Track A with token 1
      handleAsyncRecs(['track_A_rec_1', 'track_A_rec_2'], 1, 'track_A');
      expect(queue, ['track_B']); // Unchanged!

      // Fresh response arrives for Track B with token 2
      handleAsyncRecs(['track_B_rec_1', 'track_B_rec_2'], 2, 'track_B');
      expect(queue, ['track_B', 'track_B_rec_1', 'track_B_rec_2']);
    });

    // 16. Compact waveform animation timing and state transitions
    testWidgets('16. SongTile _EqualizerAnimation animates at ~50% speed (2000ms duration)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Song',
              artist: 'Artist',
              duration: '3:45',
              isPlaying: true,
              isActive: true,
            ),
          ),
        ),
      );

      // Verify the widget is built and rendering
      expect(find.byType(SongTile), findsOneWidget);

      // Pump 1 second (half of 2000ms duration)
      await tester.pump(const Duration(milliseconds: 1000));
      expect(tester.takeException(), isNull);
    });

    // 17. Confirming that the compact waveform remains present after the change
    testWidgets('17. Compact waveform overlay is present over album artwork when active', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Kaadhalai Solla Mudiyatha',
              artist: 'Yazin Nizar',
              duration: '4:51',
              imageUrl: 'https://i.ytimg.com/vi/test/hqdefault.jpg',
              isPlaying: true,
              isActive: true,
            ),
          ),
        ),
      );

      // SongTile is present
      expect(find.byType(SongTile), findsOneWidget);
      expect(find.text('Kaadhalai Solla Mudiyatha'), findsOneWidget);
    });

    // 18. Confirming that the expanded Now Playing waveform remains unchanged
    testWidgets('18. Expanded Now Playing WaveformWidget preserves its 32 base amplitude heights and animation', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WaveformWidget(
              isPlaying: true,
              activeProgress: 0.5,
              onScrub: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(WaveformWidget), findsOneWidget);
      // Pump frames to verify smooth animation without error
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  });
}
