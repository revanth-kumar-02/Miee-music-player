import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/utils/display_title_normalizer.dart';

void main() {
  group('DisplayTitleNormalizer Tests', () {
    test('1. Velai Illa Pattadhaari #D25 #V... -> Velai Illa Pattadhaari', () {
      const input = 'Velai Illa Pattadhaari #D25 #V...';
      final output = DisplayTitleNormalizer.normalize(input);
      expect(output, 'Velai Illa Pattadhaari');
    });

    test('2. Shape of You (Official 4K Video) -> Shape of You', () {
      const input = 'Shape of You (Official 4K Video)';
      final output = DisplayTitleNormalizer.normalize(input);
      expect(output, 'Shape of You');
    });

    test('3. Song Name 8K Ultra HD -> Song Name', () {
      const input = 'Song Name 8K Ultra HD';
      final output = DisplayTitleNormalizer.normalize(input);
      expect(output, 'Song Name');
    });

    test('4. Song Name | Full Video Song -> Song Name', () {
      const input = 'Song Name | Full Video Song';
      final output = DisplayTitleNormalizer.normalize(input);
      expect(output, 'Song Name');
    });

    test('5. A legitimate song containing the word Live is preserved', () {
      const input1 = 'Hotel California (Live)';
      expect(DisplayTitleNormalizer.normalize(input1), 'Hotel California (Live)');

      const input2 = 'Live and Let Die';
      expect(DisplayTitleNormalizer.normalize(input2), 'Live and Let Die');

      const input3 = 'Live to Rise';
      expect(DisplayTitleNormalizer.normalize(input3), 'Live to Rise');
    });

    test('6. A legitimate song containing Remix is preserved', () {
      const input1 = 'Levitating (Remix)';
      expect(DisplayTitleNormalizer.normalize(input1), 'Levitating (Remix)');

      const input2 = 'Ignition (Remix)';
      expect(DisplayTitleNormalizer.normalize(input2), 'Ignition (Remix)');

      const input3 = 'Save Your Tears (Remix)';
      expect(DisplayTitleNormalizer.normalize(input3), 'Save Your Tears (Remix)');
    });

    test('7. Meaningful numbers and alphanumeric titles are preserved', () {
      expect(DisplayTitleNormalizer.normalize('7 Years'), '7 Years');
      expect(DisplayTitleNormalizer.normalize('21 Guns'), '21 Guns');
      expect(DisplayTitleNormalizer.normalize('1999'), '1999');
      expect(DisplayTitleNormalizer.normalize('Song 2'), 'Song 2');
      expect(DisplayTitleNormalizer.normalize('3'), '3');
      expect(DisplayTitleNormalizer.normalize('24K Magic'), '24K Magic');
    });

    test('8. Tamil and other non-English regional titles are preserved', () {
      expect(DisplayTitleNormalizer.normalize('வாத்தி கமிங்'), 'வாத்தி கமிங்');
      expect(DisplayTitleNormalizer.normalize('நெஞ்சமே நெஞ்சமே'), 'நெஞ்சமே நெஞ்சமே');
      expect(DisplayTitleNormalizer.normalize('तुम ही हो'), 'तुम ही हो');
      expect(DisplayTitleNormalizer.normalize('கேசரியா'), 'கேசரியா');
      expect(DisplayTitleNormalizer.normalize('விருப்பம் #D25'), 'விருப்பம்');
    });

    test('9. A title that is already clean remains unchanged', () {
      expect(DisplayTitleNormalizer.normalize('Blinding Lights'), 'Blinding Lights');
      expect(DisplayTitleNormalizer.normalize('Starboy'), 'Starboy');
      expect(DisplayTitleNormalizer.normalize('As It Was'), 'As It Was');
    });

    test('10. Repeated normalization of the same title is idempotent', () {
      const inputs = [
        'Velai Illa Pattadhaari #D25 #V...',
        'Shape of You (Official 4K Video)',
        'Song Name 8K Ultra HD',
        'Song Name | Full Video Song',
        'Hotel California (Live)',
        'Levitating (Remix)',
        '24K Magic',
        'வாத்தி கமிங் #D50',
      ];

      for (final raw in inputs) {
        final once = DisplayTitleNormalizer.normalize(raw);
        final twice = DisplayTitleNormalizer.normalize(once);
        final thrice = DisplayTitleNormalizer.normalize(twice);

        expect(twice, once, reason: 'Failed idempotence on: $raw');
        expect(thrice, once, reason: 'Failed triple idempotence on: $raw');
      }
    });
  });
}
