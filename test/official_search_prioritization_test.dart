import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('Official Song Search Prioritization & Filter Test Suite', () {
    const config = SearchRankingConfig(
      filterDerivativeEdits: true,
      relativeViewRatioThreshold: 0.05,
      minViewCountForEdits: 50000,
    );

    test('1. Exact title + artist match: Official Audio > Official Video > Fan Lyric > Cover > Karaoke', () {
      final candidates = [
        const YouTubeVideo(
          id: 'fan_lyrics',
          title: 'Kadhal En Kadhal',
          channelTitle: 'LyricsZone',
          thumbnailUrl: '',
          duration: '5:36',
          viewCount: '2M views',
          rawViewCount: 2000000,
          rawTitle: 'Kadhal En Kadhal Lyrics Video',
          rawChannelTitle: 'LyricsZone',
        ),
        const YouTubeVideo(
          id: 'official_audio',
          title: 'Kadhal En Kadhal',
          channelTitle: 'Dhanush - Topic',
          thumbnailUrl: '',
          duration: '5:36',
          viewCount: '15M views',
          rawViewCount: 15000000,
          rawTitle: 'Kadhal En Kadhal (Official Audio)',
          rawChannelTitle: 'Dhanush - Topic',
        ),
        const YouTubeVideo(
          id: 'karaoke_ver',
          title: 'Kadhal En Kadhal (Karaoke)',
          channelTitle: 'Karaoke King',
          thumbnailUrl: '',
          duration: '5:36',
          viewCount: '500K views',
          rawViewCount: 500000,
          rawTitle: 'Kadhal En Kadhal Karaoke Track with Lyrics',
          rawChannelTitle: 'Karaoke King',
        ),
        const YouTubeVideo(
          id: 'cover_ver',
          title: 'Kadhal En Kadhal (Cover)',
          channelTitle: 'Indie Singer',
          thumbnailUrl: '',
          duration: '4:10',
          viewCount: '3M views',
          rawViewCount: 3000000,
          rawTitle: 'Kadhal En Kadhal Cover by Indie Singer',
          rawChannelTitle: 'Indie Singer',
        ),
        const YouTubeVideo(
          id: 'official_video',
          title: 'Kadhal En Kadhal',
          channelTitle: 'SonyMusicSouthVEVO',
          thumbnailUrl: '',
          duration: '5:36',
          viewCount: '25M views',
          rawViewCount: 25000000,
          rawTitle: 'Kadhal En Kadhal - Official Video | Dhanush',
          rawChannelTitle: 'SonyMusicSouthVEVO',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Kadhal En Kadhal Dhanush',
        config: config,
      );

      expect(results, isNotEmpty);
      // Official Topic (Audio) wins as the single best canonical recording representative
      expect(results.first.id, equals('official_audio'));

      // Karaoke and covers must be filtered out in default search
      final allIds = results.map((r) => r.id).toList();
      expect(allIds.contains('karaoke_ver'), isFalse, reason: 'Karaoke must be filtered');
      expect(allIds.contains('cover_ver'), isFalse, reason: 'Cover must be filtered in default search');
    });

    test('2. Song title without artist prioritizes official recording from verified channel/label', () {
      final candidates = [
        const YouTubeVideo(
          id: 'fan_cover_high_views',
          title: 'Shape of You',
          channelTitle: 'Acoustic Covers',
          thumbnailUrl: '',
          duration: '3:50',
          viewCount: '100M views',
          rawViewCount: 100000000,
          rawTitle: 'Ed Sheeran - Shape of You (Acoustic Cover)',
          rawChannelTitle: 'Acoustic Covers',
        ),
        const YouTubeVideo(
          id: 'official_ed_sheeran',
          title: 'Shape of You',
          channelTitle: 'Ed Sheeran',
          thumbnailUrl: '',
          duration: '3:53',
          viewCount: '6B views',
          rawViewCount: 6000000000,
          rawTitle: 'Ed Sheeran - Shape of You (Official Music Video)',
          rawChannelTitle: 'Ed Sheeran',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Shape of You',
        config: config,
      );

      expect(results.first.id, equals('official_ed_sheeran'));
      expect(results.any((r) => r.id == 'fan_cover_high_views'), isFalse);
    });

    test('3. Topic and VEVO channels receive definitive ranking boost', () {
      final scoreTopic = SearchDeduplicator.calculateGlobalCandidateScore(
        const YouTubeVideo(
          id: 'v_topic',
          title: 'Song A',
          channelTitle: 'Artist - Topic',
          thumbnailUrl: '',
          duration: '3:45',
          viewCount: '1M views',
          rawViewCount: 1000000,
          rawTitle: 'Song A',
          rawChannelTitle: 'Artist - Topic',
        ),
        query: 'Song A Artist',
        maxViewsInResultSet: 1000000,
      );

      final scoreGeneric = SearchDeduplicator.calculateGlobalCandidateScore(
        const YouTubeVideo(
          id: 'v_generic',
          title: 'Song A',
          channelTitle: 'Random Music Uploader',
          thumbnailUrl: '',
          duration: '3:45',
          viewCount: '1M views',
          rawViewCount: 1000000,
          rawTitle: 'Song A',
          rawChannelTitle: 'Random Music Uploader',
        ),
        query: 'Song A Artist',
        maxViewsInResultSet: 1000000,
      );

      expect(scoreTopic, greaterThan(scoreGeneric + 300),
          reason: 'Topic channel should receive +350 authoritative audio boost');
    });

    test('4. Karaoke preserved when user explicitly searches "karaoke"', () {
      final candidates = [
        const YouTubeVideo(
          id: 'regular_song',
          title: 'Starboy',
          channelTitle: 'The Weeknd - Topic',
          thumbnailUrl: '',
          duration: '3:50',
          viewCount: '1B views',
          rawViewCount: 1000000000,
          rawTitle: 'Starboy (Official Audio)',
          rawChannelTitle: 'The Weeknd - Topic',
        ),
        const YouTubeVideo(
          id: 'karaoke_track',
          title: 'Starboy (Karaoke)',
          channelTitle: 'Sing King Karaoke',
          thumbnailUrl: '',
          duration: '3:50',
          viewCount: '5M views',
          rawViewCount: 5000000,
          rawTitle: 'The Weeknd - Starboy (Karaoke Version)',
          rawChannelTitle: 'Sing King Karaoke',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Starboy karaoke',
        config: config,
      );

      expect(results, isNotEmpty);
      expect(results.first.id, equals('karaoke_track'),
          reason: 'Explicit karaoke intent must prioritize karaoke track');
    });

    test('5. Cover preserved when user explicitly searches "cover"', () {
      final candidates = [
        const YouTubeVideo(
          id: 'original_track',
          title: 'Hurt',
          channelTitle: 'Nine Inch Nails - Topic',
          thumbnailUrl: '',
          duration: '6:14',
          viewCount: '50M views',
          rawViewCount: 50000000,
          rawTitle: 'Nine Inch Nails - Hurt (Official Audio)',
          rawChannelTitle: 'Nine Inch Nails - Topic',
        ),
        const YouTubeVideo(
          id: 'cash_cover',
          title: 'Hurt (Cover)',
          channelTitle: 'Johnny Cash',
          thumbnailUrl: '',
          duration: '4:02',
          viewCount: '180M views',
          rawViewCount: 180000000,
          rawTitle: 'Johnny Cash - Hurt (Official Music Video)',
          rawChannelTitle: 'Johnny Cash',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Hurt cover',
        config: config,
      );

      expect(results, isNotEmpty);
      expect(results.first.id, equals('cash_cover'));
    });

    test('6. Fallback preservation: when only live or cover exists, list is NOT empty', () {
      final candidates = [
        const YouTubeVideo(
          id: 'rare_live_performance',
          title: 'Unreleased Track',
          channelTitle: 'Indie Band',
          thumbnailUrl: '',
          duration: '4:30',
          viewCount: '10K views',
          rawViewCount: 10000,
          rawTitle: 'Unreleased Track (Live at Basement 2018)',
          rawChannelTitle: 'Indie Band',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Unreleased Track',
        config: config,
      );

      expect(results, isNotEmpty,
          reason: 'Safe fallback must retain legitimate musical tracks instead of returning empty');
      expect(results.first.id, equals('rare_live_performance'));
    });

    test('7. "She & Him" regression fixture: artist catalog prioritized over unrelated songs', () {
      final candidates = [
        const YouTubeVideo(
          id: 'unrelated_song_she_him',
          title: 'She Loved Him',
          channelTitle: 'Unrelated Singer',
          thumbnailUrl: '',
          duration: '3:30',
          viewCount: '50M views',
          rawViewCount: 50000000,
          rawTitle: 'She Loved Him So Deeply',
          rawChannelTitle: 'Unrelated Singer',
        ),
        const YouTubeVideo(
          id: 'she_and_him_real',
          title: 'In the Sun',
          channelTitle: 'She & Him',
          thumbnailUrl: '',
          duration: '2:52',
          viewCount: '3M views',
          rawViewCount: 3000000,
          rawTitle: 'She & Him - In the Sun (Official Video)',
          rawChannelTitle: 'She & Him',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'She & Him',
        config: config,
      );

      expect(results, isNotEmpty);
      expect(results.first.id, equals('she_and_him_real'),
          reason: 'Searching artist "She & Him" must prioritize songs by She & Him over songs titled "She Loved Him"');
    });

    test('8. Duration synchronization: 03:30 placeholder never leaks to MediaItem when container resolves 5:36', () {
      final handler = MieeAudioHandler();

      // Track with empty or placeholder duration
      final dummyTrack = Track(
        id: 'kadhal_8k_yt',
        title: 'Kadhal En Kadhal - 8K',
        artist: 'Dhanush',
        duration: '03:30',
        imageUrl: '',
        filePath: '',
      );

      // Verify TrackToMediaItem rejects 03:30
      final mediaItem = handler.trackToMediaItemForTesting(dummyTrack);
      expect(mediaItem.duration, isNull,
          reason: 'Placeholder 03:30 must be null in MediaItem until player resolves container');

      // Now player resolves ground truth 5:36
      handler.setQueueForTesting([dummyTrack], currentIndex: 0);
      handler.onDurationChangedForTesting(const Duration(minutes: 5, seconds: 36));

      // MediaItem stream must reflect 5:36
      final active = handler.mediaItem.value;
      expect(active, isNotNull);
      expect(active!.duration, equals(const Duration(minutes: 5, seconds: 36)));
    });
  });
}
