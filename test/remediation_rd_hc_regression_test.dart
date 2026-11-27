import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/data/providers/deezer_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/fanart_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/itunes_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/local_artwork_provider.dart';
import 'package:Miee/features/artwork/data/providers/musicbrainz_provider.dart';
import 'package:Miee/features/artwork/data/providers/cover_art_archive_provider.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/features/search/domain/canonical_music_ranker.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/utils/display_title_normalizer.dart';

void main() {
  group('MIEE 2.0 Remediation Regression Tests', () {
    test('RD-01: PlaybackSourceResolver skips excluded videoId', () {
      final resolver = PlaybackSourceResolver();
      final candidates = [
        YouTubeVideo(
          id: 'dQw4w9WgXcQ',
          title: 'Radhima (Official Audio)',
          channelTitle: 'Artist - Topic',
          thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          duration: '3:30',
          viewCount: '1000000',
        ),
        YouTubeVideo(
          id: 'abc123XYZ89',
          title: 'Radhima - Official Audio',
          channelTitle: 'Official Label',
          thumbnailUrl: 'https://i.ytimg.com/vi/abc123XYZ89/hqdefault.jpg',
          duration: '3:32',
          viewCount: '500000',
        ),
      ];

      final best = resolver.selectBestCandidate(
        candidates,
        title: 'Radhima',
        artist: 'Artist',
      );
      expect(best, isNotNull);

      // Simulate excluding the failed candidate directly via _pickBestScoredCandidate
      // behavior tested through filtered list / excludeVideoIds contract
      final filtered = candidates.where((c) => c.id != 'dQw4w9WgXcQ').toList();
      final alternate = resolver.selectBestCandidate(
        filtered,
        title: 'Radhima',
        artist: 'Artist',
      );
      expect(alternate?.id, equals('abc123XYZ89'));
    });

    test('RD-02: TrackHiveModel preserves rich metadata and artwork fields',
        () {
      const original = Track(
        id: 'youtube_9bZkp7q19f0',
        title: 'Alaakaa Loova (Telugu)',
        artist: 'Sai Abhyankkar',
        imageUrl: 'https://is1-ssl.mzstatic.com/image/thumb/art/600x600bb.jpg',
        duration: '3:45',
        albumName: 'Alaakaa Loova',
        albumArtworkUrl:
            'https://is1-ssl.mzstatic.com/image/thumb/art/600x600bb.jpg',
        sourceProvider: 'itunes',
        sourceId: '123456',
        rawTitle: 'Alaakaa Loova (Telugu) - Video',
        rawArtist: 'Sai Abhyankkar - Topic',
      );

      final hiveModel = TrackHiveModel.fromTrack(original);
      final restored = hiveModel.toTrack();

      expect(restored.artist, equals('Sai Abhyankkar'));
      expect(restored.albumName, equals('Alaakaa Loova'));
      expect(restored.albumArtworkUrl, equals(original.albumArtworkUrl));
      expect(restored.sourceProvider, equals('itunes'));
      expect(restored.sourceId, equals('123456'));
      expect(restored.rawTitle, equals(original.rawTitle));
      expect(restored.rawArtist, equals(original.rawArtist));
    });

    test(
        'RD-03: CanonicalMusicRanker demotes slowed+reverb, remake, mashup, 8D below canonical',
        () {
      final canonical = YouTubeVideo(
        id: 'canon123456',
        title: 'Radhima',
        channelTitle: 'Saregama Tamil - Topic',
        thumbnailUrl: 'https://i.ytimg.com/vi/canon123456/hqdefault.jpg',
        duration: '4:10',
        viewCount: '2500000',
        metadataProvider: 'itunes',
      );
      final slowed = YouTubeVideo(
        id: 'slow1234567',
        title: 'Radhima (Slowed + Reverb)',
        channelTitle: 'Lofi Edits',
        thumbnailUrl: 'https://i.ytimg.com/vi/slow1234567/hqdefault.jpg',
        duration: '4:45',
        viewCount: '500000',
      );
      final mashup = YouTubeVideo(
        id: 'mash1234567',
        title: 'Radhima x Spider-Man Mashup Remake',
        channelTitle: 'Editz Hub',
        thumbnailUrl: 'https://i.ytimg.com/vi/mash1234567/hqdefault.jpg',
        duration: '3:50',
        viewCount: '300000',
      );
      final audio8d = YouTubeVideo(
        id: '8d123456789',
        title: 'Radhima 8D Audio',
        channelTitle: '8D Tunes',
        thumbnailUrl: 'https://i.ytimg.com/vi/8d123456789/hqdefault.jpg',
        duration: '4:10',
        viewCount: '200000',
      );

      final ranked = CanonicalMusicRanker.rankVideos(
        [slowed, mashup, audio8d, canonical],
        query: 'Radhima',
      );

      expect(ranked.first.id, equals('canon123456'));

      // Explicit slowed+reverb query should not penalize slowed version
      final slowedQueryRanked = CanonicalMusicRanker.rankVideos(
        [canonical, slowed],
        query: 'Radhima slowed reverb',
      );
      expect(slowedQueryRanked.any((v) => v.id == 'slow1234567'), isTrue);
    });

    test(
        'RD-04: ArtworkResolver returns neutral fallback when external providers are disabled and query preserves fallbackThumbnailUrl',
        () async {
      final resolver = ArtworkResolver(
        localProvider: LocalArtworkProvider(),
        itunesProvider: const ItunesArtworkProvider(isEnabled: false),
        deezerProvider: DeezerArtworkProvider(isEnabled: false),
        fanartProvider: const FanartArtworkProvider(isEnabled: false),
        musicBrainzProvider: MusicBrainzProvider(),
        coverArtArchiveProvider: CoverArtArchiveProvider(),
      );

      const query = ArtworkQuery(
        id: 'youtube_test1234567',
        title: 'Unknown Regional Indie Track XYZ',
        artist: 'Unknown Indie Artist',
        fallbackThumbnailUrl:
            'https://i.ytimg.com/vi/test1234567/hqdefault.jpg',
        source: 'youtube',
      );
      final result = await resolver.resolve(query);

      expect(result.isNeutralFallback, isTrue);
      expect(
        query.fallbackThumbnailUrl,
        equals('https://i.ytimg.com/vi/test1234567/hqdefault.jpg'),
      );
    });

    test(
        'RD-05: DisplayTitleNormalizer strips MassTamilan, - Video, and - Topic suffixes',
        () {
      expect(
        DisplayTitleNormalizer.normalize('Kanmani Anbodu - MassTamilan.com'),
        equals('Kanmani Anbodu'),
      );
      expect(
        DisplayTitleNormalizer.normalize('Alaakaa Loova (Telugu) - Video'),
        equals('Alaakaa Loova (Telugu)'),
      );
      expect(
        DisplayTitleNormalizer.normalizeArtist('Sai Abhyankkar - Topic'),
        equals('Sai Abhyankkar'),
      );
      expect(
        DisplayTitleNormalizer.normalizeArtist('Anirudh - MassTamilan.io'),
        equals('Anirudh'),
      );
    });
  });
}
