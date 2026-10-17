import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_metadata_cleaner.dart';

void main() {
  group('Universal Song Title Normalization Across All Artists and Languages', () {
    test('1. Strips leading @handle with zero-width space in pipe-delimited title (Vizhi Veekura)', () {
      const raw = '​@SaiAbhyankkar - Vizhi Veekura (Music Video)| Saanve Megghana| Sai Smriti|Adesh| Thejo| Think Indie';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Think Music India',
        reliableArtist: 'Sai Abhyankkar',
      );
      expect(res.title, equals('Vizhi Veekura'));
      expect(res.artist, equals('Sai Abhyankkar'));
      expect(res.rawTitle, equals(raw));
    });

    test('2. Strips leading @handle with zero-width space in hyphen-only title', () {
      const raw = '​@SaiAbhyankkar - Vizhi Veekura';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Think Music India',
        reliableArtist: 'Sai Abhyankkar',
      );
      expect(res.title, equals('Vizhi Veekura'));
      expect(res.artist, equals('Sai Abhyankkar'));
    });

    test('3. Strips leading @handle in Pavazha Malli pipe format', () {
      const raw = '@SaiAbhyankkar - Pavazha Malli (Music Video) | Kayadu | Shruti Haasan | Vivek | Thejo | Think Indie';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Think Music India',
        reliableArtist: 'Sai Abhyankkar',
      );
      expect(res.title, equals('Pavazha Malli'));
      expect(res.artist, equals('Sai Abhyankkar'));
    });

    test('4. Preserves legitimate @ within song title (Look @ Me)', () {
      const raw = 'Look @ Me';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'XXXTentacion',
        reliableArtist: 'XXXTentacion',
      );
      expect(res.title, equals('Look @ Me'));
      expect(res.artist, equals('XXXTentacion'));
    });

    test('5. Preserves legitimate hyphenated subtitle (Pink Floyd - Breathe - In the Air)', () {
      const raw = 'Pink Floyd - Breathe - In the Air';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Pink Floyd',
        reliableArtist: 'Pink Floyd',
      );
      expect(res.title, equals('Breathe - In the Air'));
      expect(res.artist, equals('Pink Floyd'));
    });

    test('6. Preserves legitimate version/part modifier (Shine On You Crazy Diamond - Part 1)', () {
      const raw = 'Pink Floyd - Shine On You Crazy Diamond - Part 1';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Pink Floyd',
        reliableArtist: 'Pink Floyd',
      );
      expect(res.title, equals('Shine On You Crazy Diamond - Part 1'));
      expect(res.artist, equals('Pink Floyd'));
    });

    test('7. Strips uploader channel prefix when matching channel', () {
      const raw = 'Sony Music South - Aalaporaan Thamizhan | Mersal';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Sony Music South',
        reliableArtist: 'A. R. Rahman',
      );
      expect(res.title, equals('Aalaporaan Thamizhan'));
      expect(res.artist, equals('A. R. Rahman'));
    });

    test('8. Strips Tamil uploader prefix script-agnostically without hardcoded artist lists', () {
      const raw = 'ஹாரிஸ் ஜெயராஜ் - வசீகரா';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'ஹாரிஸ் ஜெயராஜ்',
        reliableArtist: 'ஹாரிஸ் ஜெயராஜ்',
      );
      expect(res.title, equals('வசீகரா'));
      expect(res.artist, equals('ஹாரிஸ் ஜெயராஜ்'));
    });

    test('9. Preserves hyphenated title without space (Catch-22)', () {
      const raw = 'Catch-22';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Unknown Channel',
      );
      expect(res.title, equals('Catch-22'));
      expect(res.artist, equals('Unknown Channel'));
    });

    test('10. Safely handles empty or whitespace-only title input', () {
      const raw = '   ';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Some Channel',
      );
      expect(res.title, equals(''));
    });

    test('11. Strips Hindi uploader prefix script-agnostically without hardcoded artist lists', () {
      const raw = 'ए. आर. रहमान - जय हो';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'ए. आर. रहमान',
        reliableArtist: 'ए. आर. रहमान',
      );
      expect(res.title, equals('जय हो'));
      expect(res.artist, equals('ए. आर. रहमान'));
    });

    test('12. Separates Telugu uploader channel cleanly without hardcoding', () {
      const raw = 'ఆదిత్య మ్యూజిక్ - సామజవరగమన';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'ఆదిత్య మ్యూజిక్',
      );
      expect(res.title, equals('సామజవరగమన'));
      expect(res.artist, equals('ఆదిత్య మ్యూజిక్'));
    });

    test('13. Strips duplicate or repeated leading handles cleanly', () {
      const raw = '@SaiAbhyankkar - @SaiAbhyankkar - Vizhi Veekura';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Think Music India',
        reliableArtist: 'Sai Abhyankkar',
      );
      expect(res.title, equals('Vizhi Veekura'));
      expect(res.artist, equals('Sai Abhyankkar'));
    });

    test('14. Separates artist and featured credit cleanly (Justin Bieber ft. Ludacris - Baby)', () {
      const raw = 'Justin Bieber ft. Ludacris - Baby';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'JustinBieberVEVO',
        reliableArtist: 'Justin Bieber',
      );
      expect(res.title, equals('Baby'));
      expect(res.artist, equals('Justin Bieber'));
    });

    test('15. Never fabricates artist credits when metadata is missing or ambiguous', () {
      const raw = 'Random Uploader Studio - Beautiful Sunrise';
      final res = YouTubeMetadataCleaner.clean(
        rawTitle: raw,
        rawChannel: 'Random Uploader Studio',
      );
      expect(res.title, equals('Beautiful Sunrise'));
      expect(res.artist, equals('Random Uploader Studio'));
    });
  });
}
