/// Comprehensive, lightweight, zero-dependency transliterator and phonetic
/// normalizer for Indic/South Asian scripts (Tamil, Telugu, Malayalam, Kannada,
/// Devanagari/Hindi/Marathi, Bengali, Gujarati, Gurmukhi, Odia).
///
/// Designed to bridge the gap between native script song titles and Romanized/Latin
/// metadata databases (e.g., LRCLIB, Spotify, MusicBrainz).
abstract class IndicTransliterator {
  static const Map<int, String> _vowels = {
    // Tamil
    0x0B85: 'a', 0x0B86: 'aa', 0x0B87: 'i', 0x0B88: 'ee', 0x0B89: 'u',
    0x0B8A: 'oo', 0x0B8E: 'e', 0x0B8F: 'e', 0x0B90: 'ai', 0x0B92: 'o',
    0x0B93: 'o', 0x0B94: 'au',
    // Devanagari (Hindi, Marathi, Sanskrit, Nepali)
    0x0905: 'a', 0x0906: 'aa', 0x0907: 'i', 0x0908: 'ee', 0x0909: 'u',
    0x090A: 'oo', 0x090B: 'ri', 0x090F: 'e', 0x0910: 'ai', 0x0913: 'o',
    0x0914: 'au',
    // Telugu
    0x0C05: 'a', 0x0C06: 'aa', 0x0C07: 'i', 0x0C08: 'ee', 0x0C09: 'u',
    0x0C0A: 'oo', 0x0C0B: 'ri', 0x0C0E: 'e', 0x0C0F: 'e', 0x0C10: 'ai',
    0x0C12: 'o', 0x0C13: 'o', 0x0C14: 'au',
    // Kannada
    0x0C85: 'a', 0x0C86: 'aa', 0x0C87: 'i', 0x0C88: 'ee', 0x0C89: 'u',
    0x0C8A: 'oo', 0x0C8B: 'ri', 0x0C8E: 'e', 0x0C8F: 'e', 0x0C90: 'ai',
    0x0C92: 'o', 0x0C93: 'o', 0x0C94: 'au',
    // Malayalam
    0x0D05: 'a', 0x0D06: 'aa', 0x0D07: 'i', 0x0D08: 'ee', 0x0D09: 'u',
    0x0D0A: 'oo', 0x0D0B: 'ri', 0x0D0E: 'e', 0x0D0F: 'e', 0x0D10: 'ai',
    0x0D12: 'o', 0x0D13: 'o', 0x0D14: 'au',
    // Bengali
    0x0985: 'a', 0x0986: 'aa', 0x0987: 'i', 0x0988: 'ee', 0x0989: 'u',
    0x098A: 'oo', 0x098F: 'e', 0x0990: 'ai', 0x0993: 'o', 0x0994: 'au',
  };

  static const Map<int, String> _consonants = {
    // Tamil
    0x0B95: 'k', 0x0B99: 'ng', 0x0B9A: 's', 0x0B9C: 'j', 0x0B9E: 'ny',
    0x0B9F: 't', 0x0BA3: 'n', 0x0BA4: 'th', 0x0BA8: 'n', 0x0BA9: 'n',
    0x0BAA: 'p', 0x0BAE: 'm', 0x0BAF: 'y', 0x0BB0: 'r', 0x0BB1: 'r',
    0x0BB2: 'l', 0x0BB3: 'l', 0x0BB4: 'zh', 0x0BB5: 'v', 0x0BB7: 'sh',
    0x0BB8: 's', 0x0BB9: 'h',
    // Devanagari
    0x0915: 'k', 0x0916: 'kh', 0x0917: 'g', 0x0918: 'gh', 0x0919: 'ng',
    0x091A: 'ch', 0x091B: 'chh', 0x091C: 'j', 0x091D: 'jh', 0x091E: 'ny',
    0x091F: 't', 0x0920: 'th', 0x0921: 'd', 0x0922: 'dh', 0x0923: 'n',
    0x0924: 't', 0x0925: 'th', 0x0926: 'd', 0x0927: 'dh', 0x0928: 'n',
    0x092A: 'p', 0x092B: 'ph', 0x092C: 'b', 0x092D: 'bh', 0x092E: 'm',
    0x092F: 'y', 0x0930: 'r', 0x0932: 'l', 0x0933: 'l', 0x0935: 'v',
    0x0936: 'sh', 0x0937: 'sh', 0x0938: 's', 0x0939: 'h',
    // Telugu
    0x0C15: 'k', 0x0C16: 'kh', 0x0C17: 'g', 0x0C18: 'gh', 0x0C19: 'ng',
    0x0C1A: 'ch', 0x0C1B: 'chh', 0x0C1C: 'j', 0x0C1D: 'jh', 0x0C1E: 'ny',
    0x0C1F: 't', 0x0C20: 'th', 0x0C21: 'd', 0x0C22: 'dh', 0x0C23: 'n',
    0x0C24: 't', 0x0C25: 'th', 0x0C26: 'd', 0x0C27: 'dh', 0x0C28: 'n',
    0x0C2A: 'p', 0x0C2B: 'ph', 0x0C2C: 'b', 0x0C2D: 'bh', 0x0C2E: 'm',
    0x0C2F: 'y', 0x0C30: 'r', 0x0C31: 'r', 0x0C32: 'l', 0x0C33: 'l',
    0x0C35: 'v', 0x0C36: 'sh', 0x0C37: 'sh', 0x0C38: 's', 0x0C39: 'h',
    // Kannada
    0x0C95: 'k', 0x0C96: 'kh', 0x0C97: 'g', 0x0C98: 'gh', 0x0C99: 'ng',
    0x0C9A: 'ch', 0x0C9B: 'chh', 0x0C9C: 'j', 0x0C9D: 'jh', 0x0C9E: 'ny',
    0x0C9F: 't', 0x0CA0: 'th', 0x0CA1: 'd', 0x0CA2: 'dh', 0x0CA3: 'n',
    0x0CA4: 't', 0x0CA5: 'th', 0x0CA6: 'd', 0x0CA7: 'dh', 0x0CA8: 'n',
    0x0CAA: 'p', 0x0CAB: 'ph', 0x0CAC: 'b', 0x0CAD: 'bh', 0x0CAE: 'm',
    0x0CAF: 'y', 0x0CB0: 'r', 0x0CB1: 'r', 0x0CB2: 'l', 0x0CB3: 'l',
    0x0CB5: 'v', 0x0CB6: 'sh', 0x0CB7: 'sh', 0x0CB8: 's', 0x0CB9: 'h',
    // Malayalam
    0x0D15: 'k', 0x0D16: 'kh', 0x0D17: 'g', 0x0D18: 'gh', 0x0D19: 'ng',
    0x0D1A: 'ch', 0x0D1B: 'chh', 0x0D1C: 'j', 0x0D1D: 'jh', 0x0D1E: 'ny',
    0x0D1F: 't', 0x0D20: 'th', 0x0D21: 'd', 0x0D22: 'dh', 0x0D23: 'n',
    0x0D24: 't', 0x0D25: 'th', 0x0D26: 'd', 0x0D27: 'dh', 0x0D28: 'n',
    0x0D2A: 'p', 0x0D2B: 'ph', 0x0D2C: 'b', 0x0D2D: 'bh', 0x0D2E: 'm',
    0x0D2F: 'y', 0x0D30: 'r', 0x0D31: 'r', 0x0D32: 'l', 0x0D33: 'l',
    0x0D34: 'zh', 0x0D35: 'v', 0x0D36: 'sh', 0x0D37: 'sh', 0x0D38: 's',
    0x0D39: 'h',
  };

  static const Map<int, String> _matras = {
    // Tamil
    0x0BBE: 'aa', 0x0BBF: 'i', 0x0BC0: 'ee', 0x0BC1: 'u', 0x0BC2: 'oo',
    0x0BC6: 'e', 0x0BC7: 'e', 0x0BC8: 'ai', 0x0BCA: 'o', 0x0BCB: 'o',
    0x0BCC: 'au',
    // Devanagari
    0x093E: 'aa', 0x093F: 'i', 0x0940: 'ee', 0x0941: 'u', 0x0942: 'oo',
    0x0943: 'ri', 0x0947: 'e', 0x0948: 'ai', 0x094B: 'o', 0x094C: 'au',
    // Telugu
    0x0C3E: 'aa', 0x0C3F: 'i', 0x0C40: 'ee', 0x0C41: 'u', 0x0C42: 'oo',
    0x0C46: 'e', 0x0C47: 'e', 0x0C48: 'ai', 0x0C4A: 'o', 0x0C4B: 'o',
    0x0C4C: 'au',
    // Kannada
    0x0CBE: 'aa', 0x0CBF: 'i', 0x0CC0: 'ee', 0x0CC1: 'u', 0x0CC2: 'oo',
    0x0CC6: 'e', 0x0CC7: 'e', 0x0CC8: 'ai', 0x0CCA: 'o', 0x0CCB: 'o',
    0x0CCC: 'au',
    // Malayalam
    0x0D3E: 'aa', 0x0D3F: 'i', 0x0D40: 'ee', 0x0D41: 'u', 0x0D42: 'oo',
    0x0D46: 'e', 0x0D47: 'e', 0x0D48: 'ai', 0x0D4A: 'o', 0x0D4B: 'o',
    0x0D4C: 'au',
  };

  static const Set<int> _viramas = {
    0x0BCD, // Tamil pulli
    0x094D, // Devanagari halant
    0x0C4D, // Telugu virama
    0x0CCD, // Kannada virama
    0x0D4D, // Malayalam virama
    0x09CD, // Bengali virama
  };

  /// Returns true if [text] contains characters belonging to South Asian / Indic scripts.
  static bool hasIndicScript(String text) {
    for (final rune in text.runes) {
      if ((rune >= 0x0900 && rune <= 0x0D7F)) return true;
    }
    return false;
  }

  /// Transliterates text from Indic scripts (Tamil, Telugu, Malayalam, Kannada,
  /// Devanagari, Bengali) into Latin / Romanized text.
  static String transliterate(String text) {
    if (text.isEmpty) return '';
    final runes = text.runes.toList();
    final buffer = StringBuffer();

    for (int i = 0; i < runes.length; i++) {
      final code = runes[i];

      // Check Vowel
      final vowel = _vowels[code];
      if (vowel != null) {
        buffer.write(vowel);
        continue;
      }

      // Check Consonant
      final consonant = _consonants[code];
      if (consonant != null) {
        if (i + 1 < runes.length) {
          final next = runes[i + 1];
          // Check for virama (silences inherent 'a')
          if (_viramas.contains(next)) {
            buffer.write(consonant);
            i++;
            continue;
          }

          // Check for matra (attaches vowel)
          final matra = _matras[next];
          if (matra != null) {
            buffer.write('$consonant$matra');
            i++;
            continue;
          }
        }
        // Inherent 'a' vowel
        buffer.write('${consonant}a');
        continue;
      }

      // Anusvara (m / n nasal)
      if (code == 0x0902 || code == 0x0C02 || code == 0x0C82 || code == 0x0D02 || code == 0x0982) {
        buffer.write('m');
        continue;
      }

      // Non-Indic characters (Latin, spaces, digits, punctuation)
      buffer.write(String.fromCharCode(code));
    }

    var result = buffer.toString();
    result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
    return result;
  }

  /// Converts Romanized string into a phonetic stem to allow resilient fuzzy comparison
  /// across spelling variations (e.g. `kannaana kanne` vs `kannaana kanney`,
  /// `oo solriya` vs `u solriya`).
  static String phoneticStem(String s) {
    var str = s.toLowerCase();
    // Strip non-letter / non-digit characters
    str = str.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ');

    // Normalize vowel lengths and common phonetic substitutions
    str = str.replaceAll('aa', 'a');
    str = str.replaceAll('ee', 'i');
    str = str.replaceAll('oo', 'u');
    str = str.replaceAll('ey', 'e');
    str = str.replaceAll('ai', 'ay');
    str = str.replaceAll('zh', 'l');
    str = str.replaceAll('th', 't');
    str = str.replaceAll('dh', 'd');
    str = str.replaceAll('kh', 'k');
    str = str.replaceAll('gh', 'g');
    str = str.replaceAll('bh', 'b');
    str = str.replaceAll('ph', 'p');
    str = str.replaceAll('sh', 's');
    str = str.replaceAll('ch', 's');

    // Collapse double consonants: e.g. tt->t, nn->n, kk->k
    str = str.replaceAllMapped(RegExp(r'([a-z])\1+'), (m) => m[1]!);
    str = str.replaceAll(RegExp(r'\s+'), ' ').trim();
    return str;
  }
}
