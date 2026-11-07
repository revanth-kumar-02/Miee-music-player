import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/recommendations/domain/music_language_service.dart';

void main() {
  group('Miee — Veezha Veera Track Validation & Discovery Verification (Bug 1)', () {
    test('1. Validates "Veezha Veera (From "Amaran")" as an individual song candidate', () {
      const candidate = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Veezha Veera (From "Amaran")',
        channelTitle: 'Sai Abhyankkar, Tippu & Anirudh',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:30',
        viewCount: '33.7M views',
        rawTitle: 'Veezha Veera (From "Amaran")',
        rawChannelTitle: 'Sai Abhyankkar, Tippu & Anirudh',
      );

      final classification = MusicResultClassifier.classify(candidate);
      expect(classification.isMusic, isTrue);
      expect(classification.confidence, equals(MusicTrackConfidence.officialMusic));
      expect(MusicResultClassifier.isValidIndividualSong(candidate), isTrue);
    });

    test('2. Recognizes composer and artist channels (Sai Abhyankkar, Dhanush, Anirudh) as verified music channels', () {
      const dhanushVideo = YouTubeVideo(
        id: 'v_dhanush_1',
        title: 'Veezha Veera Lyrical (Tamil)',
        channelTitle: 'Dhanush',
        thumbnailUrl: '',
        duration: '3:59',
        viewCount: '33.7M views',
        rawTitle: 'Veezha Veera Lyrical (Tamil)',
        rawChannelTitle: 'Dhanush',
      );

      final classification = MusicResultClassifier.classify(dhanushVideo);
      expect(classification.isMusic, isTrue);
      expect(classification.confidence, equals(MusicTrackConfidence.officialMusic));
    });

    test('3. Rejects non-music and creator channel archetypes (e.g. TN info, comedy, vlogs)', () {
      const infoVideo = YouTubeVideo(
        id: 'v_tn_info',
        title: 'Veezha Veera',
        channelTitle: 'TN info',
        thumbnailUrl: '',
        duration: '3:52',
        viewCount: '67K views',
        rawTitle: 'Veezha Veera',
        rawChannelTitle: 'TN info',
      );

      // TN info is identified as a creator / info channel archetype
      final editType = SearchDeduplicator.detectEditType(infoVideo, QueryIntent.fromQuery('Veezha Veera'));
      expect(
        editType == EditType.nonMusicEntertainment || editType == EditType.fanEdit,
        isTrue,
      );
    });
  });

  group('Miee — Veezha Veera Search Deduplication, Ranking & Language Preservation (Bug 2)', () {
    late List<YouTubeVideo> searchResults;

    setUp(() {
      searchResults = const [
        // 1. Official Lyrical release by Dhanush (Tamil)
        YouTubeVideo(
          id: 'v_official_tamil',
          title: 'Veezha Veera Lyrical (Tamil)',
          channelTitle: 'Dhanush',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_official_tamil/hqdefault.jpg',
          duration: '3:59',
          viewCount: '33.7M views',
          rawTitle: 'Veezha Veera Lyrical (Tamil)',
          rawChannelTitle: 'Dhanush',
        ),
        // 2. Unofficial fan edit / Vijay clip by TN info
        YouTubeVideo(
          id: 'v_tn_info',
          title: 'Veezha Veera',
          channelTitle: 'TN info',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_tn_info/hqdefault.jpg',
          duration: '3:52',
          viewCount: '67K views',
          rawTitle: 'Veezha Veera',
          rawChannelTitle: 'TN info',
        ),
        // 3. Official full video song by Dhanush
        YouTubeVideo(
          id: 'v_official_video',
          title: 'Veezha Veera Song',
          channelTitle: 'Dhanush',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_official_video/hqdefault.jpg',
          duration: '4:46',
          viewCount: '527K views',
          rawTitle: 'Veezha Veera Song',
          rawChannelTitle: 'Dhanush',
        ),
        // 4. Fan re-upload by AM SONG
        YouTubeVideo(
          id: 'v_am_song',
          title: 'VEEZHA VEERA SONG (NEW)',
          channelTitle: 'AM SONG',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_am_song/hqdefault.jpg',
          duration: '3:50',
          viewCount: '326K views',
          rawTitle: 'VEEZHA VEERA SONG (NEW)',
          rawChannelTitle: 'AM SONG',
        ),
        // 5. Fan re-upload by @ Min z$105
        YouTubeVideo(
          id: 'v_min_z',
          title: 'Veezha Veera Lyrical (Tamil)',
          channelTitle: '@ Min z\$105',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_min_z/hqdefault.jpg',
          duration: '3:39',
          viewCount: '200K views',
          rawTitle: 'Veezha Veera Lyrical (Tamil)',
          rawChannelTitle: '@ Min z\$105',
        ),
        // 6. Fan re-upload by tune zone
        YouTubeVideo(
          id: 'v_tune_zone',
          title: 'Veezha Veera Lyrical (Tamil)',
          channelTitle: 'tune zone',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_tune_zone/hqdefault.jpg',
          duration: '3:18',
          viewCount: '29K views',
          rawTitle: 'Veezha Veera Lyrical (Tamil)',
          rawChannelTitle: 'tune zone',
        ),
        // 7. Fan re-upload by JAN
        YouTubeVideo(
          id: 'v_jan',
          title: 'Veezha Veera lyrics video',
          channelTitle: 'JAN',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_jan/hqdefault.jpg',
          duration: '3:53',
          viewCount: '77K views',
          rawTitle: 'Veezha Veera lyrics video',
          rawChannelTitle: 'JAN',
        ),
        // 8. Fan re-upload by LyricalRed
        YouTubeVideo(
          id: 'v_lyrical_red',
          title: 'Veezha veera song lyrics',
          channelTitle: 'LyricalRed',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_lyrical_red/hqdefault.jpg',
          duration: '3:36',
          viewCount: '24K views',
          rawTitle: 'Veezha veera song lyrics',
          rawChannelTitle: 'LyricalRed',
        ),
        // 9. Official Telugu lyrical release by Dhanush
        YouTubeVideo(
          id: 'v_telugu_dhanush',
          title: 'Veera Veera Lyrical (Telugu)',
          channelTitle: 'Dhanush',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_telugu_dhanush/hqdefault.jpg',
          duration: '3:59',
          viewCount: '8.8M views',
          rawTitle: 'Veera Veera Lyrical (Telugu)',
          rawChannelTitle: 'Dhanush',
        ),
        // 10. Official Hindi lyrical release by Dhanush
        YouTubeVideo(
          id: 'v_hindi_dhanush',
          title: 'Veera Veera Lyrical (Hindi)',
          channelTitle: 'Dhanush',
          thumbnailUrl: 'https://i.ytimg.com/vi/v_hindi_dhanush/hqdefault.jpg',
          duration: '3:59',
          viewCount: '455K views',
          rawTitle: 'Veera Veera Lyrical (Hindi)',
          rawChannelTitle: 'Dhanush',
        ),
      ];
    });

    test('1. Accurately detects distinct languages for multilingual releases', () {
      final tamilLang = MusicLanguageService.detectLanguage('Veezha Veera Lyrical (Tamil)', artist: 'Dhanush');
      final teluguLang = MusicLanguageService.detectLanguage('Veera Veera Lyrical (Telugu)', artist: 'Dhanush');
      final hindiLang = MusicLanguageService.detectLanguage('Veera Veera Lyrical (Hindi)', artist: 'Dhanush');

      expect(tamilLang, equals('Tamil'));
      expect(teluguLang, equals('Telugu'));
      expect(hindiLang, equals('Hindi'));
    });

    test('2. Deduplicates low-view fan re-uploads while preserving canonical representative', () {
      final results = SearchDeduplicator.deduplicateAndRank(searchResults, query: 'Veezha Veera');
      final resultIds = results.map((v) => v.id).toList();

      // The top result must be the official Tamil lyrical release by Dhanush (33.7M views)
      expect(results.first.id, equals('v_official_tamil'));

      // Low-view duplicate fan re-uploads must NOT appear in the deduplicated results
      expect(resultIds, isNot(contains('v_min_z')));
      expect(resultIds, isNot(contains('v_tune_zone')));
      expect(resultIds, isNot(contains('v_jan')));
      expect(resultIds, isNot(contains('v_lyrical_red')));
      expect(resultIds, isNot(contains('v_am_song')));
    });

    test('3. Unofficial actor fan edit (TN info) is demoted / excluded from top results', () {
      final results = SearchDeduplicator.deduplicateAndRank(searchResults, query: 'Veezha Veera');
      final top3Ids = results.take(3).map((v) => v.id).toList();

      // TN info must NEVER be #2
      expect(top3Ids, isNot(contains('v_tn_info')));
    });

    test('4. Official multilingual releases (Telugu and Hindi) are preserved as distinct items', () {
      final results = SearchDeduplicator.deduplicateAndRank(searchResults, query: 'Veezha Veera');
      final resultIds = results.map((v) => v.id).toList();

      // Telugu and Hindi releases MUST be present in results
      expect(resultIds, contains('v_telugu_dhanush'));
      expect(resultIds, contains('v_hindi_dhanush'));

      // They must NOT be merged with Tamil
      final teluguItem = results.firstWhere((v) => v.id == 'v_telugu_dhanush');
      final hindiItem = results.firstWhere((v) => v.id == 'v_hindi_dhanush');
      expect(teluguItem.title, contains('Telugu'));
      expect(hindiItem.title, contains('Hindi'));
    });

    test('5. Result ranking prioritizes official original, official video, and official multilingual releases', () {
      final results = SearchDeduplicator.deduplicateAndRank(searchResults, query: 'Veezha Veera');

      // Top result must be official Tamil release
      expect(results[0].id, equals('v_official_tamil'));

      // Official Telugu release (8.8M views) must rank ahead of derivative fan edits
      final teluguIndex = results.indexWhere((v) => v.id == 'v_telugu_dhanush');
      final tnInfoIndex = results.indexWhere((v) => v.id == 'v_tn_info');
      expect(teluguIndex, isNonNegative);
      if (tnInfoIndex != -1) {
        expect(teluguIndex, lessThan(tnInfoIndex));
      }
    });
  });
}
