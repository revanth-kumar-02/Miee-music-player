import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/search/domain/query_relevance_evaluator.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';

void main() {
  group('QueryRelevanceEvaluator - Collection Intent Detection', () {
    test('accurately identifies collection, discography, and jukebox queries', () {
      expect(QueryRelevanceEvaluator.isCollectionQuery('OM All Songs Tamil'), isTrue);
      expect(QueryRelevanceEvaluator.isCollectionQuery('Dhanush Hit Songs'), isTrue);
      expect(QueryRelevanceEvaluator.isCollectionQuery('Anirudh Jukebox'), isTrue);
      expect(QueryRelevanceEvaluator.isCollectionQuery('Best of AR Rahman'), isTrue);
      expect(QueryRelevanceEvaluator.isCollectionQuery('Tamil Audio Songs 2026'), isTrue);
    });

    test('accurately identifies single song queries as non-collection', () {
      expect(QueryRelevanceEvaluator.isCollectionQuery('Shape of You'), isFalse);
      expect(QueryRelevanceEvaluator.isCollectionQuery('Brooklyn Baby'), isFalse);
      expect(QueryRelevanceEvaluator.isCollectionQuery('We On Go'), isFalse);
      expect(QueryRelevanceEvaluator.isCollectionQuery('Velai Illa Pattadhaari'), isFalse);
    });

    test('extracts core entities correctly by stripping stopwords', () {
      expect(QueryRelevanceEvaluator.extractCoreEntity('OM All Songs Tamil'), equals('om tamil'));
      expect(QueryRelevanceEvaluator.extractCoreEntity('Best Hits of Dhanush'), equals('dhanush'));
    });
  });

  group('QueryRelevanceEvaluator - Candidate Relevance Validation', () {
    test('rejects unrelated global pop tracks returned by partial keyword matches', () {
      const query = 'OM All Songs Tamil';

      final cheapThrills = YouTubeVideo(
        id: '1',
        title: 'Cheap Thrills',
        channelTitle: 'Sia',
        thumbnailUrl: '',
        duration: '3:31',
        viewCount: '',
        albumName: 'This Is Acting',
      );

      final oneDance = YouTubeVideo(
        id: '2',
        title: 'One Dance',
        channelTitle: 'Drake',
        thumbnailUrl: '',
        duration: '2:53',
        viewCount: '',
        albumName: 'Views',
      );

      final liberianGirl = YouTubeVideo(
        id: '3',
        title: 'Liberian Girl (2012 Remix)',
        channelTitle: 'Michael Jackson',
        thumbnailUrl: '',
        duration: '3:52',
        viewCount: '',
        albumName: 'Bad 25th Anniversary',
      );

      final fiveLittleMonkeys = YouTubeVideo(
        id: '4',
        title: 'Five Little Monkeys',
        channelTitle: 'Super Simple Songs',
        thumbnailUrl: '',
        duration: '2:05',
        viewCount: '',
        albumName: 'Super Simple Songs',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(cheapThrills, query: query), isFalse);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(oneDance, query: query), isFalse);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(liberianGirl, query: query), isFalse);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(fiveLittleMonkeys, query: query), isFalse);
    });

    test('accepts genuine regional and soundtrack recordings matching core entity', () {
      const query = 'OM All Songs Tamil';

      final alaakaaLoova = YouTubeVideo(
        id: '10',
        title: 'Alaakaa Loova (From "OM Chapter 1: Udhiram") [Tamil]',
        channelTitle: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '3:37',
        viewCount: '',
        albumName: 'OM',
      );

      final veezhaVeera = YouTubeVideo(
        id: '11',
        title: 'Veezha Veera Lyrical (Tamil) | OM | Dhanush',
        channelTitle: 'Divo Music',
        thumbnailUrl: '',
        duration: '3:59',
        viewCount: '',
      );

      final omFaFaFa = YouTubeVideo(
        id: '12',
        title: 'OM - FA FA FA Lyrical | Dhanush | Sai Pallavi',
        channelTitle: 'Divo Music',
        thumbnailUrl: '',
        duration: '3:05',
        viewCount: '',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(alaakaaLoova, query: query), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(veezhaVeera, query: query), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(omFaFaFa, query: query), isTrue);
    });

    test('validates single-song queries like Brooklyn Baby and Shape of You', () {
      final brooklynBaby = YouTubeVideo(
        id: '20',
        title: 'Brooklyn Baby',
        channelTitle: 'Lana Del Rey',
        thumbnailUrl: '',
        duration: '5:51',
        viewCount: '',
      );

      final shapeOfYou = YouTubeVideo(
        id: '21',
        title: 'Shape of You',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: '',
        duration: '3:53',
        viewCount: '',
      );

      expect(QueryRelevanceEvaluator.isCandidateRelevant(brooklynBaby, query: 'Brooklyn Baby'), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(shapeOfYou, query: 'shape of you'), isTrue);
      expect(QueryRelevanceEvaluator.isCandidateRelevant(brooklynBaby, query: 'shape of you'), isFalse);
    });
  });

  group('QueryRelevanceEvaluator - Artist Relevance Validation', () {
    test('rejects unrelated artists for query "OM All Songs Tamil"', () {
      expect(QueryRelevanceEvaluator.isArtistRelevant('Drake', query: 'OM All Songs Tamil'), isFalse);
      expect(QueryRelevanceEvaluator.isArtistRelevant('Michael Jackson', query: 'OM All Songs Tamil'), isFalse);
      expect(QueryRelevanceEvaluator.isArtistRelevant('Sia', query: 'OM All Songs Tamil'), isFalse);
    });

    test('accepts artists matching query tokens', () {
      expect(QueryRelevanceEvaluator.isArtistRelevant('Ed Sheeran', query: 'Ed Sheeran'), isTrue);
      expect(QueryRelevanceEvaluator.isArtistRelevant('Lana Del Rey', query: 'Lana Del Rey'), isTrue);
    });
  });
}
