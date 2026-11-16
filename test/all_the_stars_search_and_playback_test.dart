import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';

void main() {
  group('All The Stars — Search Ranking, Non-Music Filtering & Playback Validation', () {
    const query = 'All The Stars';

    const vEdSheeran = YouTubeVideo(
      id: 'ed_sheeran_id',
      title: 'All of the Stars',
      channelTitle: 'Ed Sheeran',
      thumbnailUrl: '',
      duration: '4:15',
      viewCount: '167.7M views',
      rawTitle: 'Ed Sheeran - All of the Stars [Official Video]',
      rawChannelTitle: 'Ed Sheeran',
    );

    const vCreateanera = YouTubeVideo(
      id: 'createanera_id',
      title: 'All The Stars',
      channelTitle: 'CREATEANERA',
      thumbnailUrl: '',
      duration: '2:44',
      viewCount: '7.6M views',
      rawTitle: 'All The Stars',
      rawChannelTitle: 'CREATEANERA',
    );

    const vRish = YouTubeVideo(
      id: 'rish_id',
      title: 'All These Stars',
      channelTitle: 'RISH',
      thumbnailUrl: '',
      duration: '2:50',
      viewCount: '66K views',
      rawTitle: 'RISH - All These Stars',
      rawChannelTitle: 'RISH',
    );

    const vKendrick = YouTubeVideo(
      id: 'kendrick_id',
      title: 'All The Stars',
      channelTitle: 'Kendrick Lamar, SZA',
      thumbnailUrl: '',
      duration: '3:55',
      viewCount: '776.7M views',
      rawTitle: 'Kendrick Lamar, SZA - All The Stars',
      rawChannelTitle: 'Kendrick Lamar, SZA',
    );

    const vBlackPanther = YouTubeVideo(
      id: 'black_panther_id',
      title: '[BLACK PANTHER] (2018)...',
      channelTitle: 'Kshitiz Singh',
      thumbnailUrl: '',
      duration: '2:51',
      viewCount: '3.1M views',
      rawTitle: '[BLACK PANTHER] (2018) All The Stars Scene',
      rawChannelTitle: 'Kshitiz Singh',
    );

    test('1. True original recording (Kendrick Lamar, SZA) ranks #1 over divergent songs and covers', () {
      final candidates = [vEdSheeran, vCreateanera, vRish, vKendrick, vBlackPanther];
      final ranked = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: query,
        config: const SearchRankingConfig(filterDerivativeEdits: true),
      );

      expect(ranked, isNotEmpty);
      expect(ranked.first.id, equals('kendrick_id'),
          reason: 'Kendrick Lamar, SZA (776.7M views) must rank #1 for "All The Stars"');
    });

    test('2. Non-music scene clips ([BLACK PANTHER] Scene) are strictly pruned from Songs results', () {
      final candidates = [vEdSheeran, vCreateanera, vRish, vKendrick, vBlackPanther];
      final ranked = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: query,
        config: const SearchRankingConfig(filterDerivativeEdits: true),
      );

      final hasSceneClip = ranked.any((v) => v.id == 'black_panther_id');
      expect(hasSceneClip, isFalse, reason: 'Movie scene clip must not appear in Songs results');
    });

    test('3. Reconstructed playback candidates from Track are recognized as valid music tracks', () {
      // Reconstructed from Track after iTunes metadata enrichment
      const candidateReconstructedFromTrack = YouTubeVideo(
        id: 'JQbjS0_ZfJ0',
        title: 'All The Stars',
        channelTitle: 'Kendrick Lamar, SZA',
        thumbnailUrl: 'https://i.ytimg.com/vi/JQbjS0_ZfJ0/hqdefault.jpg',
        duration: '3:55',
        viewCount: '776.7M views',
        rawTitle: 'All The Stars',
        rawChannelTitle: 'Kendrick Lamar, SZA',
        metadataProvider: 'itunes',
      );

      final isApproved = MusicResultClassifier.isValidIndividualSong(
            candidateReconstructedFromTrack,
            query: 'All The Stars Kendrick Lamar, SZA',
          ) ||
          MusicResultClassifier.isValidMusicTrack(
            candidateReconstructedFromTrack,
            query: 'All The Stars Kendrick Lamar, SZA',
          );

      expect(isApproved, isTrue,
          reason: 'Verified iTunes track must not be rejected with "This video is not a recognized music track"');
    });

    test('4. Selected YouTube search result (CREATEANERA) passes playback validation without error', () {
      final isApproved = MusicResultClassifier.isValidIndividualSong(
            vCreateanera,
            query: 'All The Stars',
          ) ||
          MusicResultClassifier.isValidMusicTrack(
            vCreateanera,
            query: 'All The Stars',
          );

      expect(isApproved, isTrue,
          reason: 'Standard musical track returned by search must be accepted for playback');
    });
  });
}
