import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';

void main() {
  group('SearchDeduplicator Tests', () {
    test('1. Deduplicates Lana Del Rey - West Coast upload variants into 1 best canonical result', () {
      final videos = [
        const YouTubeVideo(
          id: 'v1',
          title: 'West Coast',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/v1/hqdefault.jpg',
          duration: '4:17',
          viewCount: '15M views',
          rawTitle: 'Lana Del Rey - West Coast (Official Audio)',
          rawChannelTitle: 'LanaDelReyVEVO',
        ),
        const YouTubeVideo(
          id: 'v2',
          title: 'West Coast',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/v2/hqdefault.jpg',
          duration: '4:17',
          viewCount: '2.1M views',
          rawTitle: 'West Coast - Lana Del Rey (Lyrics)',
          rawChannelTitle: '7clouds',
        ),
        const YouTubeVideo(
          id: 'v3',
          title: 'West Coast',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/v3/hqdefault.jpg',
          duration: '4:20',
          viewCount: '500K views',
          rawTitle: 'Lana Del Rey - West Coast [Official Music Video]',
          rawChannelTitle: 'Lana Del Rey',
        ),
        const YouTubeVideo(
          id: 'v4',
          title: 'West Coast',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/v4/hqdefault.jpg',
          duration: '4:17',
          viewCount: '100K views',
          rawTitle: 'West Coast (Visualizer)',
          rawChannelTitle: 'Lana Del Rey',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos, query: 'West Coast');

      // Must be deduplicated down to 1 single canonical track
      expect(results.length, 1);
      // The representative should be the official audio release on VEVO (highest ranking score)
      expect(results.first.id, 'v1');
      expect(results.first.title, 'West Coast');
    });

    test('2. Preserves songs from two different artists sharing the same title', () {
      final videos = [
        const YouTubeVideo(
          id: 'adele_hello',
          title: 'Hello',
          channelTitle: 'Adele',
          thumbnailUrl: 'https://i.ytimg.com/vi/adele_hello/hqdefault.jpg',
          duration: '4:55',
          viewCount: '3B views',
          rawTitle: 'Adele - Hello (Official Music Video)',
          rawChannelTitle: 'AdeleVEVO',
        ),
        const YouTubeVideo(
          id: 'lionel_hello',
          title: 'Hello',
          channelTitle: 'Lionel Richie',
          thumbnailUrl: 'https://i.ytimg.com/vi/lionel_hello/hqdefault.jpg',
          duration: '5:07',
          viewCount: '250M views',
          rawTitle: 'Lionel Richie - Hello (Official Video)',
          rawChannelTitle: 'LionelRichieVEVO',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos, query: 'Hello');

      // Both songs must be preserved because the artists are distinct
      expect(results.length, 2);
      expect(results.map((v) => v.id).toList(), containsAll(['adele_hello', 'lionel_hello']));
    });

    test('3. Distinguishes live, remix, cover, acoustic, sped-up, and slowed versions', () {
      final videos = [
        const YouTubeVideo(
          id: 'standard',
          title: 'West Coast',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/standard/hqdefault.jpg',
          duration: '4:17',
          viewCount: '15M views',
          rawTitle: 'Lana Del Rey - West Coast (Official Audio)',
          rawChannelTitle: 'LanaDelReyVEVO',
        ),
        const YouTubeVideo(
          id: 'live_1',
          title: 'West Coast (Live)',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/live_1/hqdefault.jpg',
          duration: '4:30',
          viewCount: '800K views',
          rawTitle: 'Lana Del Rey - West Coast (Live at Coachella)',
          rawChannelTitle: 'Coachella',
        ),
        const YouTubeVideo(
          id: 'live_dup',
          title: 'West Coast (Live)',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/live_dup/hqdefault.jpg',
          duration: '4:30',
          viewCount: '50K views',
          rawTitle: 'West Coast (Live) [Lyrics]',
          rawChannelTitle: 'RandomUploader',
        ),
        const YouTubeVideo(
          id: 'remix',
          title: 'West Coast (Remix)',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/remix/hqdefault.jpg',
          duration: '3:45',
          viewCount: '1.2M views',
          rawTitle: 'Lana Del Rey - West Coast (ZHU Remix)',
          rawChannelTitle: 'Mind of a Genius',
        ),
        const YouTubeVideo(
          id: 'acoustic',
          title: 'West Coast (Acoustic)',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/acoustic/hqdefault.jpg',
          duration: '4:10',
          viewCount: '400K views',
          rawTitle: 'Lana Del Rey - West Coast (Acoustic Version)',
          rawChannelTitle: 'Lana Del Rey',
        ),
        const YouTubeVideo(
          id: 'sped_up',
          title: 'West Coast (Sped Up)',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/sped_up/hqdefault.jpg',
          duration: '3:20',
          viewCount: '500K views',
          rawTitle: 'West Coast (Sped Up / Nightcore)',
          rawChannelTitle: 'SpeedAudio',
        ),
        const YouTubeVideo(
          id: 'slowed',
          title: 'West Coast (Slowed)',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/slowed/hqdefault.jpg',
          duration: '5:10',
          viewCount: '700K views',
          rawTitle: 'West Coast (Slowed + Reverb)',
          rawChannelTitle: 'AestheticVibes',
        ),
        const YouTubeVideo(
          id: 'instrumental',
          title: 'West Coast (Instrumental)',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/instrumental/hqdefault.jpg',
          duration: '4:17',
          viewCount: '200K views',
          rawTitle: 'Lana Del Rey - West Coast (Official Instrumental)',
          rawChannelTitle: 'Lana Del Rey',
        ),
        const YouTubeVideo(
          id: 'cover',
          title: 'West Coast (Cover)',
          channelTitle: 'James Bay',
          thumbnailUrl: 'https://i.ytimg.com/vi/cover/hqdefault.jpg',
          duration: '3:50',
          viewCount: '300K views',
          rawTitle: 'Lana Del Rey - West Coast (Cover by James Bay)',
          rawChannelTitle: 'BBC Radio 1',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos, query: 'West Coast');

      // The redundant live upload (live_dup) should be merged into live_1.
      // All genuinely distinct artistic variations must be present.
      final returnedIds = results.map((v) => v.id).toList();
      expect(returnedIds, contains('standard'));
      expect(returnedIds, contains('live_1'));
      expect(returnedIds, isNot(contains('live_dup')));
      expect(returnedIds, contains('remix'));
      expect(returnedIds, contains('acoustic'));
      expect(returnedIds, contains('sped_up'));
      expect(returnedIds, contains('slowed'));
      expect(returnedIds, contains('instrumental'));
      expect(returnedIds, contains('cover'));
      expect(results.length, 8);
    });

    test('4. Handles punctuation, case, and quotation variations in canonical matching', () {
      final videos = [
        const YouTubeVideo(
          id: 'case1',
          title: 'WEST COAST',
          channelTitle: 'LANA DEL REY',
          thumbnailUrl: 'https://i.ytimg.com/vi/case1/hqdefault.jpg',
          duration: '4:17',
          viewCount: '10M views',
          rawTitle: 'LANA DEL REY - WEST COAST (OFFICIAL AUDIO)',
          rawChannelTitle: 'LANADELREYVEVO',
        ),
        const YouTubeVideo(
          id: 'case2',
          title: '“West Coast”',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/case2/hqdefault.jpg',
          duration: '4:17',
          viewCount: '1M views',
          rawTitle: '“West Coast” -- Lana Del Rey!',
          rawChannelTitle: 'Lana Del Rey',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos);
      expect(results.length, 1);
    });

    test('5. Handles missing artist, unknown channel, or malformed duration gracefully', () {
      final videos = [
        const YouTubeVideo(
          id: 'no_artist',
          title: 'Unknown Track',
          channelTitle: '',
          thumbnailUrl: 'https://i.ytimg.com/vi/no_artist/hqdefault.jpg',
          duration: '',
          viewCount: '',
          rawTitle: 'Unknown Track',
          rawChannelTitle: '',
        ),
        const YouTubeVideo(
          id: 'bad_duration',
          title: 'Some Song',
          channelTitle: 'Independent Artist',
          thumbnailUrl: 'https://i.ytimg.com/vi/bad_duration/hqdefault.jpg',
          duration: 'invalid_duration',
          viewCount: 'no views data',
          rawTitle: 'Some Song - Independent Artist',
          rawChannelTitle: 'Independent Artist',
        ),
      ];

      expect(() => SearchDeduplicator.deduplicateAndRank(videos), returnsNormally);
      final results = SearchDeduplicator.deduplicateAndRank(videos);
      expect(results.length, 2);
    });

    test('6. Deduplicates identical YouTube video IDs immediately', () {
      final videos = [
        const YouTubeVideo(
          id: 'dup_id_123',
          title: 'Song Title',
          channelTitle: 'Artist Name',
          thumbnailUrl: 'https://i.ytimg.com/vi/dup_id_123/hqdefault.jpg',
          duration: '3:30',
          viewCount: '100K views',
        ),
        const YouTubeVideo(
          id: 'dup_id_123',
          title: 'Song Title Different Upload Title',
          channelTitle: 'Artist Name',
          thumbnailUrl: 'https://i.ytimg.com/vi/dup_id_123/hqdefault.jpg',
          duration: '3:30',
          viewCount: '100K views',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos);
      expect(results.length, 1);
      expect(results.first.id, 'dup_id_123');
    });

    test('7. Distinct tracks by the same artist must not be merged', () {
      final videos = [
        const YouTubeVideo(
          id: 'song1',
          title: 'Video Games',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/song1/hqdefault.jpg',
          duration: '4:42',
          viewCount: '300M views',
          rawTitle: 'Lana Del Rey - Video Games',
          rawChannelTitle: 'LanaDelReyVEVO',
        ),
        const YouTubeVideo(
          id: 'song2',
          title: 'Born to Die',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/song2/hqdefault.jpg',
          duration: '4:46',
          viewCount: '500M views',
          rawTitle: 'Lana Del Rey - Born to Die (Official Music Video)',
          rawChannelTitle: 'LanaDelReyVEVO',
        ),
        const YouTubeVideo(
          id: 'song3',
          title: 'Summertime Sadness',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://i.ytimg.com/vi/song3/hqdefault.jpg',
          duration: '4:25',
          viewCount: '400M views',
          rawTitle: 'Lana Del Rey - Summertime Sadness (Official Music Video)',
          rawChannelTitle: 'LanaDelReyVEVO',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(videos);
      expect(results.length, 3);
      expect(results.map((v) => v.title).toList(), [
        'Video Games',
        'Born to Die',
        'Summertime Sadness',
      ]);
    });

    test('8. Handles empty results and null queries without failure', () {
      expect(SearchDeduplicator.deduplicateAndRank([]), isEmpty);
      expect(SearchDeduplicator.deduplicateAndRank([], query: ''), isEmpty);
      expect(SearchDeduplicator.deduplicateAndRank([], query: 'Any query'), isEmpty);
    });
  });
}
