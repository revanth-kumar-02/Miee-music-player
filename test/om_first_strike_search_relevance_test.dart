import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/search/domain/query_relevance_evaluator.dart';
import 'package:Miee/features/search/domain/canonical_music_ranker.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';

void main() {
  group('Phase 1.3: Search Query Relevance & Contextual Matching Tests', () {
    const omFirstStrikeDhanush = YouTubeVideo(
      id: 'zr9QY9am5XE',
      title: 'OM First Strike',
      channelTitle: 'Dhanush',
      thumbnailUrl: '',
      duration: '2:33',
      viewCount: '10M',
      rawTitle: 'OM First Strike',
      rawChannelTitle: 'Dhanush',
    );

    const firstStrikeLuisM = YouTubeVideo(
      id: 'itunes_1531329135',
      title: 'First Strike',
      channelTitle: 'Luis M & Peter Groskreutz',
      thumbnailUrl: '',
      duration: '6:14',
      viewCount: 'Apple Music',
      rawTitle: 'First Strike',
      rawChannelTitle: 'Luis M & Peter Groskreutz',
      canonicalTitle: 'First Strike',
      canonicalArtist: 'Luis M & Peter Groskreutz',
      albumName: 'First Strike - Single',
    );

    const firstStrikeBenFrost = YouTubeVideo(
      id: 'itunes_benfrost',
      title: 'First Strike',
      channelTitle: 'Ben Frost',
      thumbnailUrl: '',
      duration: '2:33',
      viewCount: 'Apple Music',
      rawTitle: 'First Strike',
      rawChannelTitle: 'Ben Frost',
      canonicalTitle: 'First Strike',
      canonicalArtist: 'Ben Frost',
      albumName: "Tom Clancy's Siege (Original Game Soundtrack)",
    );

    const firstStrikeFromMarsHarvey = YouTubeVideo(
      id: 'itunes_harvey',
      title: 'First Strike from Mars',
      channelTitle: 'Harvey McKay',
      thumbnailUrl: '',
      duration: '7:08',
      viewCount: 'Apple Music',
      rawTitle: 'First Strike from Mars',
      rawChannelTitle: 'Harvey McKay',
      canonicalTitle: 'First Strike from Mars',
      canonicalArtist: 'Harvey McKay',
      albumName: 'Dots & Pearls II',
    );

    const firstStrikeTomHolkenborg = YouTubeVideo(
      id: 'itunes_tomh',
      title: 'First Strike',
      channelTitle: 'Tom Holkenborg',
      thumbnailUrl: '',
      duration: '2:09',
      viewCount: 'Apple Music',
      rawTitle: 'First Strike',
      rawChannelTitle: 'Tom Holkenborg',
      canonicalTitle: 'First Strike',
      canonicalArtist: 'Tom Holkenborg',
      albumName: 'Mortal Engines',
    );

    const firstStrikeHorstClooney = YouTubeVideo(
      id: 'itunes_horst',
      title: 'First Strike',
      channelTitle: 'Horst Clooney',
      thumbnailUrl: '',
      duration: '2:20',
      viewCount: 'Apple Music',
      rawTitle: 'First Strike',
      rawChannelTitle: 'Horst Clooney',
      canonicalTitle: 'First Strike',
      canonicalArtist: 'Horst Clooney',
      albumName: 'Homeland',
    );

    test('1. "om first strike" prioritizes the OM soundtrack recording and rejects unrelated singles', () {
      const query = 'om first strike';

      // Authentic track has full coverage
      expect(
        QueryRelevanceEvaluator.hasFullQueryCoverage(omFirstStrikeDhanush, query: query),
        isTrue,
      );
      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(omFirstStrikeDhanush, query: query),
        isTrue,
      );

      // Unrelated techno single missing 'om' is rejected as irrelevant
      expect(
        QueryRelevanceEvaluator.hasFullQueryCoverage(firstStrikeLuisM, query: query),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(firstStrikeLuisM, query: query),
        isFalse,
      );

      // Verify word boundary token isolation:
      // 'om' must NOT match 'from' in Harvey McKay - First Strike from Mars
      expect(
        QueryRelevanceEvaluator.hasFullQueryCoverage(firstStrikeFromMarsHarvey, query: query),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(firstStrikeFromMarsHarvey, query: query),
        isFalse,
      );

      // 'om' must NOT match 'tom' in Ben Frost - First Strike (Tom Clancy's Siege)
      expect(
        QueryRelevanceEvaluator.hasFullQueryCoverage(firstStrikeBenFrost, query: query),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(firstStrikeBenFrost, query: query),
        isFalse,
      );

      // 'om' must NOT match 'tom' in Tom Holkenborg - First Strike
      expect(
        QueryRelevanceEvaluator.hasFullQueryCoverage(firstStrikeTomHolkenborg, query: query),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(firstStrikeTomHolkenborg, query: query),
        isFalse,
      );

      // 'om' must NOT match 'homeland' in Horst Clooney - First Strike (Homeland)
      expect(
        QueryRelevanceEvaluator.hasFullQueryCoverage(firstStrikeHorstClooney, query: query),
        isFalse,
      );
      expect(
        QueryRelevanceEvaluator.isCandidateRelevant(firstStrikeHorstClooney, query: query),
        isFalse,
      );

      final intent = QueryIntent.fromQuery(query);
      final scoreDhanush = CanonicalMusicRanker.calculateScore(omFirstStrikeDhanush, query: query, intent: intent);
      final scoreLuis = CanonicalMusicRanker.calculateScore(firstStrikeLuisM, query: query, intent: intent);

      expect(scoreDhanush, greaterThan(scoreLuis));
      expect(scoreDhanush, greaterThanOrEqualTo(500.0));
    });

    test('2. "OM All Songs Tamil" avoids unrelated international songs like Sia or Michael Jackson', () {
      const query = 'OM All Songs Tamil';

      const michaelJackson = YouTubeVideo(
        id: 'mj_123',
        title: 'Liberian Girl',
        channelTitle: 'Michael Jackson',
        thumbnailUrl: '',
        duration: '3:52',
        viewCount: '100M',
      );

      const omTamilSong = YouTubeVideo(
        id: 'om_tamil_1',
        title: 'Alaakaa Loova (From "OM Chapter 1: Udhiram") [Tamil]',
        channelTitle: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '3:37',
        viewCount: '5M',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(michaelJackson, query: query), isFalse);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(omTamilSong, query: query), isTrue);
    });

    test('3. "Anirudh All Songs Tamil" recognizes artist and collection intent', () {
      const query = 'Anirudh All Songs Tamil';
      expect(QueryRelevanceEvaluator.isCollectionQuery(query), isTrue);

      const anirudhSong = YouTubeVideo(
        id: 'ani_1',
        title: 'Hukum',
        channelTitle: 'Anirudh Ravichander',
        thumbnailUrl: '',
        duration: '3:20',
        viewCount: '50M',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(anirudhSong, query: query), isTrue);
    });

    test('4. "AR Rahman Hits Tamil" recognizes artist, language, and collection intent', () {
      const query = 'AR Rahman Hits Tamil';
      expect(QueryRelevanceEvaluator.isCollectionQuery(query), isTrue);

      const rahmanSong = YouTubeVideo(
        id: 'arr_1',
        title: 'Urvasi Urvasi',
        channelTitle: 'A.R. Rahman',
        thumbnailUrl: '',
        duration: '5:40',
        viewCount: '30M',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(rahmanSong, query: query), isTrue);
    });

    test('5. "Shape of You" correctly ranks Ed Sheeran as top canonical result', () {
      const query = 'Shape of You';

      const edSheeran = YouTubeVideo(
        id: 'ed_shape',
        title: 'Shape of You',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: '',
        duration: '3:53',
        viewCount: '1000M',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Ed Sheeran',
      );

      final intent = QueryIntent.fromQuery(query);
      final score = CanonicalMusicRanker.calculateScore(
        edSheeran,
        query: query,
        intent: intent,
        canonicalArtist: 'Ed Sheeran',
        prominentArtists: [const ArtistModel(id: 'ed_1', name: 'Ed Sheeran', imageUrl: '', fanCount: 20000000)],
      );

      expect(score, greaterThanOrEqualTo(600.0));
    });

    test('6. "Brooklyn Baby" correctly ranks Lana Del Rey canonical recording', () {
      const query = 'Brooklyn Baby';

      const lanaDelRey = YouTubeVideo(
        id: 'lana_bb',
        title: 'Brooklyn Baby',
        channelTitle: 'Lana Del Rey',
        thumbnailUrl: '',
        duration: '5:51',
        viewCount: '200M',
        canonicalTitle: 'Brooklyn Baby',
        canonicalArtist: 'Lana Del Rey',
      );

      final intent = QueryIntent.fromQuery(query);
      final score = CanonicalMusicRanker.calculateScore(
        lanaDelRey,
        query: query,
        intent: intent,
        canonicalArtist: 'Lana Del Rey',
        prominentArtists: [const ArtistModel(id: 'lana_1', name: 'Lana Del Rey', imageUrl: '', fanCount: 5800000)],
      );

      expect(score, greaterThanOrEqualTo(600.0));
    });

    test('7. "All The Stars" correctly ranks Kendrick Lamar and SZA', () {
      const query = 'All The Stars';

      const kendrickSza = YouTubeVideo(
        id: 'ats_1',
        title: 'All The Stars',
        channelTitle: 'Kendrick Lamar & SZA',
        thumbnailUrl: '',
        duration: '3:54',
        viewCount: '500M',
        canonicalTitle: 'All The Stars',
        canonicalArtist: 'Kendrick Lamar & SZA',
      );

      final intent = QueryIntent.fromQuery(query);
      final score = CanonicalMusicRanker.calculateScore(
        kendrickSza,
        query: query,
        intent: intent,
        canonicalArtist: 'Kendrick Lamar & SZA',
      );

      expect(score, greaterThanOrEqualTo(550.0));
    });

    test('8. "I Thought I Saw Your Face Today" correctly matches She & Him', () {
      const query = 'I Thought I Saw Your Face Today';

      const sheAndHim = YouTubeVideo(
        id: 'sh_1',
        title: 'I Thought I Saw Your Face Today',
        channelTitle: 'She & Him',
        thumbnailUrl: '',
        duration: '2:53',
        viewCount: '10M',
        canonicalTitle: 'I Thought I Saw Your Face Today',
        canonicalArtist: 'She & Him',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(sheAndHim, query: query), isTrue);
      expect(QueryRelevanceEvaluator.hasFullQueryCoverage(sheAndHim, query: query), isTrue);
    });

    test('9. "First Strike" without OM context preserves legitimate same-title alternatives', () {
      const query = 'First Strike';

      // When the user searches without the "OM" prefix, both Luis M and Ben Frost are valid candidates
      expect(QueryRelevanceEvaluator.isCandidateRelevant(firstStrikeLuisM, query: query), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(firstStrikeBenFrost, query: query), isTrue);
      expect(QueryRelevanceEvaluator.hasFullQueryCoverage(firstStrikeLuisM, query: query), isTrue);
    });

    test('10. "Drake Songs" recognizes artist-oriented query intent', () {
      const query = 'Drake Songs';
      expect(QueryRelevanceEvaluator.isCollectionQuery(query), isTrue);
      expect(QueryRelevanceEvaluator.extractCoreEntity(query), equals('drake'));

      const drakeSong = YouTubeVideo(
        id: 'drake_1',
        title: 'God\'s Plan',
        channelTitle: 'Drake',
        thumbnailUrl: '',
        duration: '3:18',
        viewCount: '1000M',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(drakeSong, query: query), isTrue);
    });

    test('11. Movie soundtrack query preserves film context', () {
      const query = 'Interstellar Stay';

      const stayTrack = YouTubeVideo(
        id: 'hans_1',
        title: 'Stay',
        channelTitle: 'Hans Zimmer',
        thumbnailUrl: '',
        duration: '6:52',
        viewCount: '50M',
        albumName: 'Interstellar (Original Motion Picture Soundtrack)',
      );

      expect(QueryRelevanceEvaluator.hasFullQueryCoverage(stayTrack, query: query), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(stayTrack, query: query), isTrue);
    });

    test('12. Multi-word artist name is recognized and preserved', () {
      const query = 'Red Hot Chili Peppers Californication';

      const rhcp = YouTubeVideo(
        id: 'rhcp_1',
        title: 'Californication',
        channelTitle: 'Red Hot Chili Peppers',
        thumbnailUrl: '',
        duration: '5:21',
        viewCount: '800M',
      );

      expect(QueryRelevanceEvaluator.hasFullQueryCoverage(rhcp, query: query), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(rhcp, query: query), isTrue);
    });
  });
}
