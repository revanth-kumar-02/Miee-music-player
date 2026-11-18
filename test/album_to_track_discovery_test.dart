import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/metadata/domain/itunes_song.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/features/search/domain/canonical_music_ranker.dart';
import 'package:Miee/features/search/domain/query_relevance_evaluator.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';

void main() {
  group('Phase 1.3: Album-To-Track Discovery & Soundtrack Matching Tests', () {
    test('1. "the wild theme" discovers the OM soundtrack recording and outranks unrelated tracks', () {
      const query = 'the wild theme';

      // Discovered from OM Album tracklist
      const omTrack = YouTubeVideo(
        id: 'itunes_6782026766',
        title: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
        canonicalTitle: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
        channelTitle: 'Sai Abhyankkar & Dhanush',
        canonicalArtist: 'Sai Abhyankkar & Dhanush',
        albumName: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood") - Single',
        duration: '1:45',
        thumbnailUrl: 'https://example.com/om.jpg',
        viewCount: 'Apple Music',
        metadataProvider: 'itunes',
        metadataIdentifier: '6782026766',
      );

      // Obscure MusicBrainz 0:00 track
      const stDavid = YouTubeVideo(
        id: 'mb_stdavid',
        title: 'The Wild Theme',
        canonicalTitle: 'The Wild Theme',
        channelTitle: 'St. David',
        canonicalArtist: 'St. David',
        duration: '0:00',
        thumbnailUrl: '',
        viewCount: 'MusicBrainz Verified',
        metadataProvider: 'musicbrainz',
      );

      // Another unrelated recording
      const sharam = YouTubeVideo(
        id: 'mb_sharam',
        title: 'The Wild Theme',
        canonicalTitle: 'The Wild Theme',
        channelTitle: 'Sharam',
        canonicalArtist: 'Sharam',
        duration: '2:27',
        thumbnailUrl: '',
        viewCount: 'MusicBrainz Verified',
        metadataProvider: 'musicbrainz',
      );

      // Verify relevance evaluation
      expect(QueryRelevanceEvaluator.isCandidateRelevant(omTrack, query: query), isTrue);
      expect(QueryRelevanceEvaluator.hasFullQueryCoverage(omTrack, query: query), isTrue);

      final intent = QueryIntent.fromQuery(query);
      final scoreOM = CanonicalMusicRanker.calculateScore(omTrack, query: query, intent: intent);
      final scoreStDavid = CanonicalMusicRanker.calculateScore(stDavid, query: query, intent: intent);
      final scoreSharam = CanonicalMusicRanker.calculateScore(sharam, query: query, intent: intent);

      expect(scoreOM, greaterThan(scoreStDavid));
      expect(scoreOM, greaterThan(scoreSharam));

      final ranked = CanonicalMusicRanker.rankVideos([stDavid, sharam, omTrack], query: query);
      expect(ranked.first.id, equals('itunes_6782026766'));
      expect(ranked.first.canonicalArtist, equals('Sai Abhyankkar & Dhanush'));
    });

    test('2. Album track metadata is not mistaken for a playable YouTube source', () {
      const itunesSong = ItunesSong(
        trackId: 6782026766,
        trackName: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
        artistName: 'Sai Abhyankkar & Dhanush',
        collectionName: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood") - Single',
        artworkUrl100: 'https://example.com/artwork.jpg',
        trackTimeMillis: 105047,
        releaseDate: '2026-06-19',
        primaryGenreName: 'Soundtrack',
        isrc: '',
      );

      final video = YouTubeVideo.fromItunesSong(itunesSong);

      // ID preserves the itunes_ prefix to indicate it requires external playback resolution
      expect(video.id, equals('itunes_6782026766'));
      expect(video.metadataProvider, equals('itunes'));
      expect(video.metadataIdentifier, equals('6782026766'));
      // Not yet resolved to an 11-char YouTube ID
      expect(RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(video.id), isFalse);
    });

    test('3. PlaybackSourceResolver extracts clean core title and resolves authentic video', () {
      const fullTitle = 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")';
      final coreTitle = PlaybackSourceResolver.extractCoreTitle(fullTitle);

      expect(coreTitle, equals('The Wild Theme'));

      const omSpecialDuty = 'OM Special Duty (From "OM Chapter 1: Udhiram")';
      final coreTitleSpecial = PlaybackSourceResolver.extractCoreTitle(omSpecialDuty);
      expect(coreTitleSpecial, equals('OM Special Duty'));
    });

    test('4. Cross-linked sibling soundtrack songs retain independent playback identities', () {
      const v1 = YouTubeVideo(
        id: 'itunes_6782026766',
        title: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
        canonicalTitle: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
        channelTitle: 'Sai Abhyankkar & Dhanush',
        canonicalArtist: 'Sai Abhyankkar & Dhanush',
        thumbnailUrl: '',
        duration: '1:45',
        viewCount: '100',
      );

      const v2 = YouTubeVideo(
        id: 'itunes_9999999999',
        title: 'OM Special Duty (From "OM Chapter 1")',
        canonicalTitle: 'OM Special Duty (From "OM Chapter 1")',
        channelTitle: 'Sai Abhyankkar',
        canonicalArtist: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '2:10',
        viewCount: '100',
      );

      final key1 = SearchDeduplicator.computeRecordingKey(v1);
      final key2 = SearchDeduplicator.computeRecordingKey(v2);

      expect(key1, isNot(equals(key2)));
      expect(
        SearchDeduplicator.isSameCanonicalRecording(v1, v2),
        isFalse,
      );
    });

    test('5. Deduplicator preserves distinct soundtrack tracks and does not over-deduplicate', () {
      const v1 = YouTubeVideo(
        id: 'itunes_6782026766',
        title: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
        channelTitle: 'Sai Abhyankkar & Dhanush',
        thumbnailUrl: '',
        duration: '1:45',
        viewCount: '100',
      );

      const v2 = YouTubeVideo(
        id: 'itunes_9999999999',
        title: 'OM Special Duty (From "OM Chapter 1")',
        channelTitle: 'Sai Abhyankkar & Dhanush',
        thumbnailUrl: '',
        duration: '1:45',
        viewCount: '100',
      );

      expect(SearchDeduplicator.isSameCanonicalSong(v1, v2), isFalse);
    });

    test('6. Ordinary same-title songs remain discoverable when no soundtrack context exists', () {
      const query = 'First Strike';

      const benFrost = YouTubeVideo(
        id: 'itunes_benfrost',
        title: 'First Strike',
        canonicalTitle: 'First Strike',
        channelTitle: 'Ben Frost',
        canonicalArtist: 'Ben Frost',
        duration: '2:33',
        viewCount: 'Apple Music',
        thumbnailUrl: '',
      );

      const tomH = YouTubeVideo(
        id: 'itunes_tomh',
        title: 'First Strike',
        canonicalTitle: 'First Strike',
        channelTitle: 'Tom Holkenborg',
        canonicalArtist: 'Tom Holkenborg',
        duration: '2:09',
        viewCount: 'Apple Music',
        thumbnailUrl: '',
      );

      // Without 'OM' in query, ordinary First Strike songs are relevant
      expect(QueryRelevanceEvaluator.isCandidateRelevant(benFrost, query: query), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(tomH, query: query), isTrue);
    });
  });
}
