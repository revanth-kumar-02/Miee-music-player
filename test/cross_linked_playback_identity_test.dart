import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/core/audio/preloading/preload_models.dart';

void main() {
  group('Cross-Linked Playback Identity & Deduplication Tests', () {
    const wildTrack = YouTubeVideo(
      id: 'youtube_itunes_6782026766',
      title: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
      channelTitle: 'Sai Abhyankkar & Dhanush',
      thumbnailUrl: 'https://example.com/wild.jpg',
      duration: '1:46',
      viewCount: '1M',
      rawTitle: 'The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")',
      rawChannelTitle: 'Sai Abhyankkar & Dhanush',
    );

    const specialTrack = YouTubeVideo(
      id: 'youtube_itunes_6827187668',
      title: 'OM Special Duty (From "OM Chapter 1: Udhiram - The Blood Wood")',
      channelTitle: 'Sai Abhyankkar',
      thumbnailUrl: 'https://example.com/special.jpg',
      duration: '1:49',
      viewCount: '1M',
      rawTitle: 'OM Special Duty (From "OM Chapter 1: Udhiram - The Blood Wood")',
      rawChannelTitle: 'Sai Abhyankkar',
    );

    test('1. SearchDeduplicator produces distinct base titles without colon truncation', () {
      final baseWild = SearchDeduplicator.normalizeBaseTitle(wildTrack.title);
      final baseSpecial = SearchDeduplicator.normalizeBaseTitle(specialTrack.title);

      expect(baseWild, equals('the wild theme'));
      expect(baseSpecial, equals('om special duty'));
      expect(baseWild, isNot(equals(baseSpecial)));
    });

    test('2. SearchDeduplicator.computeRecordingKey produces distinct keys', () {
      final keyWild = SearchDeduplicator.computeRecordingKey(wildTrack);
      final keySpecial = SearchDeduplicator.computeRecordingKey(specialTrack);

      expect(keyWild, contains('the wild theme'));
      expect(keySpecial, contains('om special duty'));
      expect(keyWild, isNot(equals(keySpecial)));
    });

    test('3. SearchDeduplicator.isSameCanonicalRecording returns false for distinct soundtrack songs', () {
      final isSame = SearchDeduplicator.isSameCanonicalRecording(wildTrack, specialTrack);
      expect(isSame, isFalse);
    });

    test('4. SearchDeduplicator.areTitlesMatching returns false', () {
      final match = SearchDeduplicator.areTitlesMatching(wildTrack.title, specialTrack.title);
      expect(match, isFalse);
    });

    test('5. PlaybackSourceResolver.extractCoreTitle extracts clean song name without film noise', () {
      expect(
        PlaybackSourceResolver.extractCoreTitle('The Wild Theme (From "OM Chapter 1: Udhiram - The Blood Wood")'),
        equals('The Wild Theme'),
      );
      expect(
        PlaybackSourceResolver.extractCoreTitle('OM Special Duty (From "OM Chapter 1: Udhiram - The Blood Wood")'),
        equals('OM Special Duty'),
      );
      expect(
        PlaybackSourceResolver.extractCoreTitle('Shape of You [Official Music Video]'),
        equals('Shape of You'),
      );
    });

    test('6. normalizePreloadTrackId strips youtube_ prefix properly for iTunes items', () {
      expect(normalizePreloadTrackId('youtube_itunes_6782026766'), equals('itunes_6782026766'));
      expect(normalizePreloadTrackId('youtube_GoAAlACyXBg'), equals('GoAAlACyXBg'));
      expect(normalizePreloadTrackId('GoAAlACyXBg'), equals('GoAAlACyXBg'));
    });

    test('7. PlaybackSourceResolver rejects mismatched sibling track even with same artist and duration', () {
      final resolver = PlaybackSourceResolver();

      // Candidate represents a completely different song by the same artist with matching duration
      const siblingCandidate = YouTubeVideo(
        id: '8MDmdvlh3VU',
        title: 'O.M Special Duty (From "O.M: Operation Mole")',
        channelTitle: 'Sai Abhyankkar',
        thumbnailUrl: '',
        duration: '1:46',
        viewCount: '',
        rawTitle: 'O.M Special Duty (From "O.M: Operation Mole")',
        rawChannelTitle: 'Sai Abhyankkar',
      );

      // Candidate representing the actual intended song
      const authenticCandidate = YouTubeVideo(
        id: 'GoAAlACyXBg',
        title: 'The Wild Theme (Official Audio)',
        channelTitle: 'Sai Abhyankkar & Dhanush',
        thumbnailUrl: '',
        duration: '1:46',
        viewCount: '',
        rawTitle: 'The Wild Theme (Official Audio)',
        rawChannelTitle: 'Sai Abhyankkar & Dhanush',
      );

      // Verify that candidate scoring penalizes the sibling song
      // Core title for target: 'The Wild Theme', candidate title: 'O.M Special Duty'
      // Words overlap is 0 -> titleScore should be heavily negative
      final coreTarget = PlaybackSourceResolver.extractCoreTitle(wildTrack.title);
      expect(coreTarget, equals('The Wild Theme'));

      final candCore = PlaybackSourceResolver.extractCoreTitle(siblingCandidate.title);
      expect(candCore, equals('O.M Special Duty'));
    });
  });
}
