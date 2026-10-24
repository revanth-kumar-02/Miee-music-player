import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/media/domain/models.dart';

void main() {
  group('Miee — Song Search Quality & View-Count Filtering Specification Tests', () {
    const activeSearchConfig = SearchRankingConfig(
      filterDerivativeEdits: true,
      relativeViewRatioThreshold: 0.05,
      minViewCountForEdits: 50000,
    );

    test('1. High-view original song ranks above a comparable low-view derivative edit', () {
      final candidates = [
        const YouTubeVideo(
          id: 'status_edit_12k',
          title: 'West Coast - 4K WhatsApp Status Video',
          channelTitle: 'EditKing',
          thumbnailUrl: 'https://img.youtube.com/vi/status_edit_12k/hqdefault.jpg',
          duration: '0:30',
          viewCount: '12K views',
          rawViewCount: 12000,
          rawTitle: 'Lana Del Rey - West Coast (4K Full Screen Status Video)',
          rawChannelTitle: 'EditKing',
        ),
        const YouTubeVideo(
          id: 'fan_edit_5k',
          title: 'West Coast (Fan Edit Audio)',
          channelTitle: 'AestheticEdits',
          thumbnailUrl: 'https://img.youtube.com/vi/fan_edit_5k/hqdefault.jpg',
          duration: '3:40',
          viewCount: '5K views',
          rawViewCount: 5000,
          rawTitle: 'West Coast - Lana Del Rey (Fan Edit Audio)',
          rawChannelTitle: 'AestheticEdits',
        ),
        const YouTubeVideo(
          id: 'official_audio_15m',
          title: 'West Coast',
          channelTitle: 'Lana Del Rey',
          thumbnailUrl: 'https://img.youtube.com/vi/official_audio_15m/hqdefault.jpg',
          duration: '4:17',
          viewCount: '15M views',
          rawViewCount: 15000000,
          rawTitle: 'Lana Del Rey - West Coast (Official Audio)',
          rawChannelTitle: 'LanaDelReyVEVO',
        ),
        const YouTubeVideo(
          id: 'slowed_reverb_30k',
          title: 'West Coast (Slowed + Reverb)',
          channelTitle: 'SlowVibes',
          thumbnailUrl: 'https://img.youtube.com/vi/slowed_reverb_30k/hqdefault.jpg',
          duration: '5:10',
          viewCount: '30K views',
          rawViewCount: 30000,
          rawTitle: 'Lana Del Rey - West Coast (Slowed + Reverb)',
          rawChannelTitle: 'SlowVibes',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'West Coast',
        config: activeSearchConfig,
      );

      // Official audio must rank #1
      expect(results, isNotEmpty);
      expect(results.first.id, equals('official_audio_15m'));
      expect(results.first.title, equals('West Coast'));

      // Derivative status and fan edits must be filtered out
      final resultIds = results.map((v) => v.id).toList();
      expect(resultIds, isNot(contains('status_edit_12k')));
      expect(resultIds, isNot(contains('fan_edit_5k')));
      expect(resultIds, isNot(contains('slowed_reverb_30k')));
    });

    test('2. A highly viewed unrelated song does not outrank the correct query song', () {
      final candidates = [
        const YouTubeVideo(
          id: 'despacito_viral',
          title: 'Despacito',
          channelTitle: 'Luis Fonsi',
          thumbnailUrl: 'https://img.youtube.com/vi/despacito_viral/hqdefault.jpg',
          duration: '4:42',
          viewCount: '8.2B views',
          rawViewCount: 8200000000,
          rawTitle: 'Luis Fonsi - Despacito ft. Daddy Yankee',
          rawChannelTitle: 'LuisFonsiVEVO',
        ),
        const YouTubeVideo(
          id: 'enna_sona_official',
          title: 'Enna Sona',
          channelTitle: 'A.R. Rahman',
          thumbnailUrl: 'https://img.youtube.com/vi/enna_sona_official/hqdefault.jpg',
          duration: '3:34',
          viewCount: '95M views',
          rawViewCount: 95000000,
          rawTitle: 'OK Jaanu - Enna Sona (Official Audio) | Arijit Singh | A.R. Rahman',
          rawChannelTitle: 'SonyMusicIndiaVEVO',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Enna Sona',
        config: activeSearchConfig,
      );

      expect(results, isNotEmpty);
      // The relevant song must strictly rank at index 0 despite Despacito having 8.2 Billion views
      expect(results.first.id, equals('enna_sona_official'));
    });

    test('3. Searches containing explicit terms such as "4K edit" retain edits when requested', () {
      final candidates = [
        const YouTubeVideo(
          id: 'official_standard',
          title: 'Starboy',
          channelTitle: 'The Weeknd',
          thumbnailUrl: 'https://img.youtube.com/vi/official_standard/hqdefault.jpg',
          duration: '3:50',
          viewCount: '500M views',
          rawViewCount: 500000000,
          rawTitle: 'The Weeknd - Starboy (Official Music Video) ft. Daft Punk',
          rawChannelTitle: 'TheWeekndVEVO',
        ),
        const YouTubeVideo(
          id: 'requested_4k_edit',
          title: 'Starboy (4K Edit)',
          channelTitle: 'EditCentral',
          thumbnailUrl: 'https://img.youtube.com/vi/requested_4k_edit/hqdefault.jpg',
          duration: '1:10',
          viewCount: '150K views',
          rawViewCount: 150000,
          rawTitle: 'The Weeknd - Starboy (4K Edit Audio)',
          rawChannelTitle: 'EditCentral',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Starboy 4K edit',
        config: activeSearchConfig,
      );

      final resultIds = results.map((v) => v.id).toList();
      expect(resultIds, contains('requested_4k_edit'), reason: '4K edit must not be filtered when explicitly requested');
    });

    test('4. Official remixes and live versions remain discoverable when requested', () {
      final liveCandidates = [
        const YouTubeVideo(
          id: 'hotel_california_studio',
          title: 'Hotel California',
          channelTitle: 'Eagles',
          thumbnailUrl: 'https://img.youtube.com/vi/studio/hqdefault.jpg',
          duration: '6:30',
          viewCount: '600M views',
          rawViewCount: 600000000,
          rawTitle: 'Eagles - Hotel California (Official Audio)',
          rawChannelTitle: 'Eagles Band',
        ),
        const YouTubeVideo(
          id: 'hotel_california_live_mtv',
          title: 'Hotel California (Live)',
          channelTitle: 'Eagles',
          thumbnailUrl: 'https://img.youtube.com/vi/live/hqdefault.jpg',
          duration: '7:12',
          viewCount: '450M views',
          rawViewCount: 450000000,
          rawTitle: 'Eagles - Hotel California (Live On MTV 1994) [Official Video]',
          rawChannelTitle: 'Eagles Band',
        ),
      ];

      final liveResults = SearchDeduplicator.deduplicateAndRank(
        liveCandidates,
        query: 'Hotel California live',
        config: activeSearchConfig,
      );

      expect(liveResults, isNotEmpty);
      expect(liveResults.first.id, equals('hotel_california_live_mtv'));

      final remixCandidates = [
        const YouTubeVideo(
          id: 'faded_alan_walker',
          title: 'Faded',
          channelTitle: 'Alan Walker',
          thumbnailUrl: 'https://img.youtube.com/vi/faded/hqdefault.jpg',
          duration: '3:32',
          viewCount: '3.5B views',
          rawViewCount: 3500000000,
          rawTitle: 'Alan Walker - Faded',
          rawChannelTitle: 'Alan Walker',
        ),
        const YouTubeVideo(
          id: 'faded_tiesto_remix',
          title: 'Faded (Remix)',
          channelTitle: 'Alan Walker',
          thumbnailUrl: 'https://img.youtube.com/vi/faded_remix/hqdefault.jpg',
          duration: '3:15',
          viewCount: '45M views',
          rawViewCount: 45000000,
          rawTitle: 'Alan Walker - Faded (Tiësto’s Deep House Remix)',
          rawChannelTitle: 'Alan Walker',
        ),
      ];

      final remixResults = SearchDeduplicator.deduplicateAndRank(
        remixCandidates,
        query: 'Faded Remix',
        config: activeSearchConfig,
      );

      expect(remixResults, isNotEmpty);
      expect(remixResults.first.id, equals('faded_tiesto_remix'));
    });

    test('5. Missing view counts are handled gracefully without inventing values or treating as zero', () {
      final candidates = [
        const YouTubeVideo(
          id: 'indie_song_missing_views',
          title: 'Midnight Echoes',
          channelTitle: 'Indie Artist Collective',
          thumbnailUrl: 'https://img.youtube.com/vi/indie1/hqdefault.jpg',
          duration: '3:45',
          viewCount: '', // Missing view count from discovery source
          rawViewCount: null,
          rawTitle: 'Midnight Echoes (Official Audio)',
          rawChannelTitle: 'Indie Artist Collective',
        ),
        const YouTubeVideo(
          id: 'indie_song_two_missing_views',
          title: 'Sunlight Memories',
          channelTitle: 'Indie Duo',
          thumbnailUrl: 'https://img.youtube.com/vi/indie2/hqdefault.jpg',
          duration: '4:00',
          viewCount: '',
          rawViewCount: null,
          rawTitle: 'Sunlight Memories',
          rawChannelTitle: 'Indie Duo',
        ),
      ];

      expect(SearchDeduplicator.parseViewCount(candidates[0]), isNull);

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Midnight Echoes',
        config: activeSearchConfig,
      );

      // Must not be dropped!
      expect(results, isNotEmpty);
      expect(results.first.id, equals('indie_song_missing_views'));
    });

    test('6. Low-view or newly released regional songs are not eliminated by rigid thresholding', () {
      final regionalCandidates = [
        const YouTubeVideo(
          id: 'regional_folk_song',
          title: 'Yem Maya Chesave Melody',
          channelTitle: 'Telugu Folk Studio',
          thumbnailUrl: 'https://img.youtube.com/vi/folk/hqdefault.jpg',
          duration: '4:15',
          viewCount: '18K views',
          rawViewCount: 18000,
          rawTitle: 'Yem Maya Chesave Melody | Traditional Folk Track',
          rawChannelTitle: 'Telugu Folk Studio',
        ),
        const YouTubeVideo(
          id: 'regional_cover_2k',
          title: 'Yem Maya Chesave Melody (Cover)',
          channelTitle: 'Home Singer',
          thumbnailUrl: 'https://img.youtube.com/vi/home/hqdefault.jpg',
          duration: '3:50',
          viewCount: '2K views',
          rawViewCount: 2000,
          rawTitle: 'Yem Maya Chesave Melody (Cover)',
          rawChannelTitle: 'Home Singer',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        regionalCandidates,
        query: 'Yem Maya Chesave Melody',
        config: activeSearchConfig,
      );

      // Relative ranking must keep the 18K-view original song despite being below an arbitrary 100K cutoff
      expect(results, isNotEmpty);
      expect(results.first.id, equals('regional_folk_song'));
    });

    test('7. Duplicate uploads of the same song are merged into the highest quality canonical representative', () {
      final duplicateUploads = [
        const YouTubeVideo(
          id: 'weeknd_starboy_vevo',
          title: 'Starboy',
          channelTitle: 'The Weeknd',
          thumbnailUrl: 'https://img.youtube.com/vi/vevo/hqdefault.jpg',
          duration: '3:50',
          viewCount: '500M views',
          rawViewCount: 500000000,
          rawTitle: 'The Weeknd - Starboy (Official Music Video) ft. Daft Punk',
          rawChannelTitle: 'TheWeekndVEVO',
        ),
        const YouTubeVideo(
          id: 'weeknd_starboy_lyric_repost',
          title: 'Starboy',
          channelTitle: 'The Weeknd',
          thumbnailUrl: 'https://img.youtube.com/vi/lyrics/hqdefault.jpg',
          duration: '3:50',
          viewCount: '2.5M views',
          rawViewCount: 2500000,
          rawTitle: 'The Weeknd - Starboy (Lyrics)',
          rawChannelTitle: 'ShadowLyrics',
        ),
        const YouTubeVideo(
          id: 'weeknd_starboy_audio_repost',
          title: 'Starboy',
          channelTitle: 'The Weeknd',
          thumbnailUrl: 'https://img.youtube.com/vi/repost/hqdefault.jpg',
          duration: '3:50',
          viewCount: '150K views',
          rawViewCount: 150000,
          rawTitle: 'The Weeknd - Starboy (Audio Reupload)',
          rawChannelTitle: 'RandomMusicDrop',
        ),
      ];

      final results = SearchDeduplicator.deduplicateAndRank(
        duplicateUploads,
        query: 'Starboy',
        config: activeSearchConfig,
      );

      expect(results.length, equals(1));
      expect(results.first.id, equals('weeknd_starboy_vevo'));
    });

    test('8. Legitimate original songs with flagged words in title (e.g., "Slow Down") are not falsely classified as edits', () {
      final candidates = [
        const YouTubeVideo(
          id: 'selena_slow_down',
          title: 'Slow Down',
          channelTitle: 'Selena Gomez',
          thumbnailUrl: 'https://img.youtube.com/vi/slowdown/hqdefault.jpg',
          duration: '3:30',
          viewCount: '120M views',
          rawViewCount: 120000000,
          rawTitle: 'Selena Gomez - Slow Down (Official Music Video)',
          rawChannelTitle: 'SelenaGomezVEVO',
        ),
      ];

      final intent = QueryIntent.fromQuery('Slow Down');
      final editType = SearchDeduplicator.detectEditType(candidates.first, intent);
      expect(editType, equals(EditType.none), reason: 'Legitimate song titled "Slow Down" must not be classified as slowed edit');

      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'Slow Down',
        config: activeSearchConfig,
      );

      expect(results, isNotEmpty);
      expect(results.first.id, equals('selena_slow_down'));
    });

    test('9. Existing SearchState retains local and category classification independently', () {
      const state = SearchState(
        query: 'Billie Eilish',
        activeFilter: 'Songs',
        localSongs: [
          MediaSong(
            id: 'local_1',
            title: 'Bad Guy',
            artist: 'Billie Eilish',
            album: 'When We All Fall Asleep',
            duration: '3:14',
            durationMs: 194000,
            filePath: '/storage/music/bad_guy.mp3',
            artworkPath: '',
          ),
        ],
        youtubeResults: [
          YouTubeVideo(
            id: 'online_1',
            title: 'Bad Guy',
            channelTitle: 'Billie Eilish',
            thumbnailUrl: 'https://img.youtube.com/vi/online_1/hqdefault.jpg',
            duration: '3:14',
            viewCount: '1.2B views',
          ),
        ],
      );

      expect(state.localSongs.length, equals(1));
      expect(state.youtubeResults.length, equals(1));
      expect(state.totalSongsCount, equals(2));
      expect(state.activeFilter, equals('Songs'));
    });

    test('10. Selected YouTubeVideo preserves exact track identity upon toTrack() conversion', () {
      const chosenVideo = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        channelTitle: 'Rick Astley',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:33',
        viewCount: '1.5B views',
        rawTitle: 'Rick Astley - Never Gonna Give You Up (Official Music Video)',
        rawChannelTitle: 'Rick Astley',
      );

      final track = chosenVideo.toTrack();
      expect(track.id, equals('youtube_dQw4w9WgXcQ'));
      expect(track.title, equals('Never Gonna Give You Up'));
      expect(track.artist, equals('Rick Astley'));
      expect(track.imageUrl, equals('https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg'));
      expect(track.isYoutube, isTrue);
      expect(track.filePath, equals('https://www.youtube.com/watch?v=dQw4w9WgXcQ'));
    });
  });
}
