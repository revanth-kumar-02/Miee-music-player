import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/youtube/domain/youtube_metadata_cleaner.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';

void main() {
  group('Playback Metadata Hardening Tests — Duration Verification & Promo Filtering', () {
    test('1. Rejects 40s milestone celebration promo (Pt0kTMTK6TY) and accepts 3:59 full song', () {
      final promoVideo = YouTubeVideo(
        id: 'Pt0kTMTK6TY',
        title: 'Veezha Veera 🔥 50M+ Views | Dhanush | OM | Sai Abhyankkar',
        channelTitle: 'Divo Music',
        thumbnailUrl: 'https://i.ytimg.com/vi/Pt0kTMTK6TY/hqdefault.jpg',
        duration: '0:40',
        viewCount: '50M views',
        rawTitle: 'Veezha Veera 🔥 50M+ Views | Dhanush | OM | Sai Abhyankkar',
        rawChannelTitle: 'Divo Music',
      );

      final fullSong = YouTubeVideo(
        id: '-ZnYdmreOrk',
        title: 'Veezha Veera Lyrical (Tamil) | OM | Dhanush | Mammootty | Sai Pallavi | Rajkumar | Sai Abhyankkar',
        channelTitle: 'Divo Music',
        thumbnailUrl: 'https://i.ytimg.com/vi/-ZnYdmreOrk/hqdefault.jpg',
        duration: '3:59',
        viewCount: '52M views',
        rawTitle: 'Veezha Veera Lyrical (Tamil) | OM | Dhanush | Mammootty | Sai Pallavi | Rajkumar | Sai Abhyankkar',
        rawChannelTitle: 'Divo Music',
      );

      // MusicResultClassifier rejection of promo teaser
      final promoVerdict = MusicResultClassifier.classify(promoVideo);
      expect(promoVerdict.isMusic, isFalse, reason: 'Milestone celebration promo must be rejected as non-music');

      final fullVerdict = MusicResultClassifier.classify(fullSong);
      expect(fullVerdict.isMusic, isTrue, reason: 'Full 3:59 song must be accepted');

      // RecommendationService.isLegitimateSong
      expect(RecommendationService.isLegitimateSong(promoVideo), isFalse);
      expect(RecommendationService.isLegitimateSong(fullSong), isTrue);

      // SearchDeduplicator.detectEditType
      final intent = QueryIntent.fromQuery('Veezha Veera');
      expect(SearchDeduplicator.detectEditType(promoVideo, intent), equals(EditType.nonMusicEntertainment));
      expect(SearchDeduplicator.detectEditType(fullSong, intent), equals(EditType.none));
    });

    test('2. Preserves legitimate 40-second short track (e.g. intro/interlude)', () {
      final interlude = YouTubeVideo(
        id: 'interlude_123',
        title: 'The Child In Us - Intro',
        channelTitle: 'Enigma - Topic',
        thumbnailUrl: 'https://i.ytimg.com/vi/interlude_123/hqdefault.jpg',
        duration: '0:42',
        viewCount: '100K views',
        rawTitle: 'The Child In Us - Intro',
        rawChannelTitle: 'Enigma - Topic',
      );

      final verdict = MusicResultClassifier.classify(interlude);
      expect(verdict.isMusic, isTrue, reason: 'Legitimate album intro/interlude must be preserved');
      expect(RecommendationService.isLegitimateSong(interlude), isTrue);
    });

    test('3. Milestone celebration regex catches variations across languages and counters', () {
      final cases = [
        'Veezha Veera 🔥 50M+ Views | Dhanush | OM',
        'Arabic Kuthu - 100M+ Views Celebration Video',
        'Katchi Sera - 200M Views Milestone',
        'Tauba Tauba | 1B Views Promo Video',
        'Illuminati 🔥 10M Views Thanks Meet',
      ];

      for (final title in cases) {
        final video = YouTubeVideo(
          id: 'test_id',
          title: title,
          channelTitle: 'Label Music',
          thumbnailUrl: '',
          duration: '0:45',
          viewCount: '',
          rawTitle: title,
        );
        expect(MusicResultClassifier.isValidIndividualSong(video), isFalse,
            reason: 'Milestone promo "$title" must be rejected');
      }
    });

    test('4. Base title normalization strips milestone view counts and groups with parent song', () {
      final rawPromoTitle = 'Veezha Veera 🔥 50M+ Views | Dhanush | OM | Sai Abhyankkar';
      final clean = YouTubeMetadataCleaner.clean(
        rawTitle: rawPromoTitle,
        rawChannel: 'Divo Music',
      );
      expect(clean.title, isNot(contains('50M+ Views')));

      final baseNorm = SearchDeduplicator.normalizeBaseTitle(
        clean.title,
        rawTitle: rawPromoTitle,
        artist: 'Sai Abhyankkar',
      );
      expect(baseNorm.toLowerCase(), equals('veezha veera'));
    });

    test('5. PlaybackSourceResolver penalizes teaser/promo durations when resolving standard song', () {
      final resolver = PlaybackSourceResolver();
      final targetSeconds = 239; // 3:59 target for Veezha Veera

      final promoCandidate = YouTubeVideo(
        id: 'Pt0kTMTK6TY',
        title: 'Veezha Veera 🔥 50M+ Views | Dhanush | OM | Sai Abhyankkar',
        channelTitle: 'Divo Music',
        thumbnailUrl: '',
        duration: '0:40',
        viewCount: '',
        rawTitle: 'Veezha Veera 🔥 50M+ Views | Dhanush | OM | Sai Abhyankkar',
        rawChannelTitle: 'Divo Music',
      );

      final fullCandidate = YouTubeVideo(
        id: '-ZnYdmreOrk',
        title: 'Veezha Veera Lyrical (Tamil) | OM | Dhanush | Mammootty | Sai Pallavi | Rajkumar | Sai Abhyankkar',
        channelTitle: 'Divo Music',
        thumbnailUrl: '',
        duration: '3:59',
        viewCount: '',
        rawTitle: 'Veezha Veera Lyrical (Tamil) | OM | Dhanush | Mammootty | Sai Pallavi | Rajkumar | Sai Abhyankkar',
        rawChannelTitle: 'Divo Music',
      );

      final scorePromo = resolver.evaluateCandidateForTesting(
        candidate: promoCandidate,
        cleanTitle: 'Veezha Veera',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: targetSeconds,
      );

      final scoreFull = resolver.evaluateCandidateForTesting(
        candidate: fullCandidate,
        cleanTitle: 'Veezha Veera',
        cleanArtist: 'Sai Abhyankkar',
        targetDurationSec: targetSeconds,
      );

      expect(scoreFull.score, greaterThan(scorePromo.score + 100),
          reason: 'Full 3:59 candidate must overwhelmingly outscore 40s promo clip');
    });

    test('6. Duration string parser handles m:ss, mm:ss, and h:mm:ss accurately', () {
      expect(MusicResultClassifier.parseDurationSeconds('0:40'), equals(40));
      expect(MusicResultClassifier.parseDurationSeconds('3:59'), equals(239));
      expect(MusicResultClassifier.parseDurationSeconds('03:59'), equals(239));
      expect(MusicResultClassifier.parseDurationSeconds('1:02:15'), equals(3735));
      expect(MusicResultClassifier.parseDurationSeconds(''), equals(0));
    });

    test('7. Track model and TrackHiveModel preserve and restore verified duration', () {
      const originalTrack = Track(
        id: 'youtube_-ZnYdmreOrk',
        title: 'Veezha Veera',
        artist: 'Sai Abhyankkar',
        imageUrl: 'https://example.com/cover.jpg',
        duration: '3:59',
      );

      final hiveModel = TrackHiveModel.fromTrack(originalTrack);
      expect(hiveModel.duration, equals('3:59'));

      final restored = hiveModel.toTrack();
      expect(restored.duration, equals('3:59'));
    });

    test('8. Track copyWith updates duration cleanly without mutating other fields', () {
      const track = Track(
        id: 'youtube_abc',
        title: 'Test Song',
        artist: 'Artist',
        imageUrl: 'https://example.com/cover.jpg',
        duration: '0:40', // Initially unverified / short
      );

      final updated = track.copyWith(duration: '3:59');
      expect(updated.duration, equals('3:59'));
      expect(updated.id, equals(track.id));
      expect(updated.title, equals(track.title));
      expect(updated.artist, equals(track.artist));
    });
  });
}

extension PlaybackSourceResolverTestExt on PlaybackSourceResolver {
  dynamic evaluateCandidateForTesting({
    required YouTubeVideo candidate,
    required String cleanTitle,
    required String cleanArtist,
    required int targetDurationSec,
  }) {
    // Invoke internal candidate evaluation
    return evaluateCandidateInternal(
      candidate: candidate,
      cleanTitle: cleanTitle,
      cleanArtist: cleanArtist,
      targetDurationSec: targetDurationSec,
    );
  }
}
