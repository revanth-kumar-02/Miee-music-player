import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/lyrics/domain/lyrics_search_query_builder.dart';
import 'package:Miee/features/lyrics/domain/lyrics_title_normalizer.dart';
import 'package:Miee/features/lyrics/domain/lyrics_validator.dart';

void main() {
  group('Lyrics Accuracy, Discovery & Matching Reliability Tests', () {
    test('1. Veezha Veera (Tamil, Sai Abhyankkar) rejects Hindi dubbed candidate (Ritesh G Rao)', () {
      final result = LyricsValidator.evaluateMatch(
        queryTrackName: 'Veezha Veera',
        queryArtistName: 'Sai Abhyankkar',
        queryDuration: const Duration(seconds: 236),
        candidateTrackName: 'Veezha Veera',
        candidateArtistName: 'Ritesh G Rao',
        candidateDuration: const Duration(seconds: 236),
      );

      // Conflicting artists must be vetoed
      expect(result.isValid, isFalse);
      expect(result.confidence, equals(0.0));
      expect(result.artistScore, equals(0.0));
    });

    test('2. Veezha Veera (Tamil, Sai Abhyankkar) accepts authentic Tamil candidate', () {
      final result = LyricsValidator.evaluateMatch(
        queryTrackName: 'Veezha Veera',
        queryArtistName: 'Sai Abhyankkar',
        queryDuration: const Duration(seconds: 236),
        candidateTrackName: 'Veezha Veera',
        candidateArtistName: 'Sai Abhyankkar',
        candidateDuration: const Duration(seconds: 236),
      );

      expect(result.isValid, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.90));
      expect(result.artistScore, equals(1.0));
      expect(result.titleScore, equals(1.0));
    });

    test('3. FA FA FA by Sai Abhyankkar rejects Fa-Fa-Fa by Datarock', () {
      final result = LyricsValidator.evaluateMatch(
        queryTrackName: 'FA FA FA',
        queryArtistName: 'Sai Abhyankkar & Dhanush',
        queryDuration: const Duration(seconds: 184),
        candidateTrackName: 'Fa-Fa-Fa',
        candidateArtistName: 'Datarock',
        candidateDuration: const Duration(seconds: 180),
      );

      expect(result.isValid, isFalse);
      expect(result.confidence, equals(0.0));
    });

    test('4. O.M Special Duty acronym normalization generates OM Special Duty', () {
      final normalized = LyricsTitleNormalizer.normalizeAcronyms('O.M Special Duty');
      expect(normalized, equals('OM Special Duty'));

      final variants = LyricsTitleNormalizer.extractVariants('O.M Special Duty');
      expect(variants, contains('OM Special Duty'));

      final candidates = LyricsSearchQueryBuilder.buildCandidates(
        title: 'O.M Special Duty (Tamil)',
        artist: 'Sai Abhyankkar & Dhanush',
      );

      final titles = candidates.map((c) => c.trackName).toList();
      expect(titles.any((t) => t.contains('OM Special Duty')), isTrue);
    });

    test('5. Urugi Urugi original rejects reprise version', () {
      final result = LyricsValidator.evaluateMatch(
        queryTrackName: 'Urugi Urugi',
        queryArtistName: 'Siddhu Kumar',
        queryDuration: const Duration(seconds: 236),
        candidateTrackName: 'Urugi Urugi - Reprise',
        candidateArtistName: 'Siddhu Kumar',
        candidateDuration: const Duration(seconds: 236),
      );

      expect(result.isValid, isFalse);
      expect(result.confidence, equals(0.0));
      expect(result.reason, contains('Version modifier mismatch'));
    });

    test('6. Composite artist "Sai Abhyankkar & Dhanush" decomposes and matches primary artist', () {
      final split = LyricsTitleNormalizer.splitArtists('Sai Abhyankkar & Dhanush');
      expect(split, contains('Sai Abhyankkar'));
      expect(split, contains('Dhanush'));

      final result = LyricsValidator.evaluateMatch(
        queryTrackName: 'FA FA FA',
        queryArtistName: 'Sai Abhyankkar & Dhanush',
        queryDuration: const Duration(seconds: 184),
        candidateTrackName: 'FA FA FA',
        candidateArtistName: 'Sai Abhyankkar',
        candidateDuration: const Duration(seconds: 184),
      );

      expect(result.isValid, isTrue);
      expect(result.confidence, greaterThanOrEqualTo(0.85));
    });

    test('7. Indic native scripts are preserved by normalizer', () {
      final tamil = 'வீழா வீரா';
      final cleaned = LyricsTitleNormalizer.normalize(tamil);
      expect(cleaned, equals('வீழா வீரா'));

      final mixed = 'ஜோ (Official Video)';
      final cleanedMixed = LyricsTitleNormalizer.normalize(mixed);
      expect(cleanedMixed, equals('ஜோ'));
    });

    test('8. Candidate with confidence below 0.75 is rejected', () {
      final result = LyricsValidator.evaluateMatch(
        queryTrackName: 'Blue Hour',
        queryArtistName: 'TXT',
        queryDuration: const Duration(seconds: 210),
        candidateTrackName: 'Blue Hour (Instrumental)',
        candidateArtistName: 'Different Artist',
        candidateDuration: const Duration(seconds: 260),
      );

      expect(result.isValid, isFalse);
      expect(result.confidence, lessThan(0.75));
    });

    test('9. Language tag conflict vetoes mismatching candidate', () {
      final result = LyricsValidator.evaluateMatch(
        queryTrackName: 'O.M Special Duty [Tamil]',
        queryArtistName: 'Sai Abhyankkar',
        queryDuration: const Duration(seconds: 102),
        candidateTrackName: 'O.M Special Duty [Hindi]',
        candidateArtistName: 'Sai Abhyankkar',
        candidateDuration: const Duration(seconds: 102),
      );

      expect(result.isValid, isFalse);
      expect(result.confidence, equals(0.0));
      expect(result.languageScore, equals(0.0));
    });
  });
}
