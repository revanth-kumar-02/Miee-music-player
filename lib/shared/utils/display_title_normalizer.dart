/// Universal display-title normalization utility for Miee.
///
/// Produces clean, elegant song titles across the player, mini-player,
/// search results, queue, notifications, and home-screen widgets.
///
/// Features:
/// 1. Strips promotional hashtags (e.g. `#D25`, `#VIP`, `#Shorts`, or truncated `#V...`).
/// 2. Strips resolution badges (e.g. `8K Ultra HD`, `4K UHD`, `1080p`, `720p`)
///    without affecting genuine song titles with numbers (e.g. `24K Magic`, `7 Years`, `21 Guns`).
/// 3. Strips video clutter and format labels (e.g. `Official Video`, `Full Video Song`,
///    `Lyrical Video`, `Lyrics`, `Visualizer`, `MV`) while strictly preserving
///    legitimate musical versions (`(Live)`, `(Remix)`, `(Acoustic)`, `(Radio Edit)`).
/// 4. Preserves Tamil, Hindi, Telugu, Malayalam, and all non-Latin Unicode scripts.
/// 5. Idempotent: `normalize(normalize(title)) == normalize(title)`.
class DisplayTitleNormalizer {
  const DisplayTitleNormalizer._();

  // Invisible Unicode characters: zero-width spaces, BOM, directional markers
  static final RegExp _invisibleCharsRegex = RegExp(
    r'[\u200B-\u200D\uFEFF\u200E\u200F\u202A-\u202E\u2060]',
  );

  // Hashtags: e.g. #D25, #VIP, #Tamil, or truncated hashtag fragments like #V... or #D25...
  static final RegExp _hashtagRegex = RegExp(
    r'#\S*(?:\.{2,3})?',
    caseSensitive: false,
  );

  // Resolution and quality suffixes:
  // Matches standalone 4k, 8k, 2k, 1080p, 720p, ultra hd, fhd, uhd, 60fps, hdr
  // (Word boundary \b ensures '24K Magic' is preserved because '24k' does not match \b4k\b)
  static final RegExp _resolutionRegex = RegExp(
    r'\b(?:8k\s*ultra\s*hd|8k\s*uhd|8k|4k\s*ultra\s*hd|4k\s*uhd|4k|2k|ultra\s*hd|fhd|uhd|1080p|720p|60fps|hdr)\b',
    caseSensitive: false,
  );

  // Video format and promotional fluff keywords
  static final RegExp _videoNoiseRegex = RegExp(
    r'\b(?:official\s+music\s+video|official\s+lyric\s+video|official\s+lyrical\s+video|'
    r'official\s+video\s+song|official\s+video|official\s+audio|official\s+track|'
    r'official\s+teaser|official\s+trailer|music\s+video|lyrical\s+video\s+song|'
    r'lyrical\s+video|lyrics\s+video|lyric\s+video|video\s+song|full\s+video\s+song|'
    r'full\s+video|full\s+song|audio\s+song|full\s+audio|visualizer|'
    r'teaser|trailer|promo|vertical\s+video)\b',
    caseSensitive: false,
  );

  // Bracketed content regex: captures anything inside ( ), [ ], or { }
  static final RegExp _bracketRegex = RegExp(
    r'[\(\[\{]([^\)\]\}]*)[\)\]\}]',
  );

  /// Musical version keywords that MUST be preserved inside parenthetical brackets.
  static final RegExp _musicalVersionRegex = RegExp(
    r'\b(?:live|acoustic|unplugged|remix|mix|radio\s+edit|extended|instrumental|'
    r'orchestral|reprise|version|taylor\x27s\s+version|part\s*\d+|pt\.?\s*\d+|'
    r'vol\.?\s*\d+|side\s*[a-z0-9]+)\b',
    caseSensitive: false,
  );

  /// Video noise keywords that identify bracketed content as removable clutter.
  static final RegExp _bracketNoiseIndicatorRegex = RegExp(
    r'\b(?:official|video|audio|lyric|lyrics|lyrical|visualizer|mv|hd|4k|8k|'
    r'uhd|fhd|1080p|720p|fps|teaser|trailer|promo|song|remastered|full\s*song)\b',
    caseSensitive: false,
  );

  /// Normalizes a song title for clean UI presentation.
  static String normalize(String title) {
    if (title.trim().isEmpty) return '';

    var t = _stripInvisibleChars(_unescapeHtml(title.trim()));

    // 1. Remove promotional hashtags (e.g. "#D25 #VIP #V...")
    t = t.replaceAll(_hashtagRegex, ' ');

    // 2. Process bracketed clauses:
    // Remove if it's promotional/video noise unless it contains a legitimate musical version
    t = t.replaceAllMapped(_bracketRegex, (match) {
      final inside = (match.group(1) ?? '').trim();
      if (inside.isEmpty) return '';

      final isMusicalVersion = _musicalVersionRegex.hasMatch(inside);
      final hasNoise = _bracketNoiseIndicatorRegex.hasMatch(inside);

      if (isMusicalVersion && !hasNoise) {
        // Pure musical version e.g. "(Live)", "(Acoustic)", "(Remix)" -> PRESERVE
        return match.group(0)!;
      } else if (isMusicalVersion && hasNoise) {
        // Mixed e.g. "(Official Acoustic Video)" -> clean noise inside brackets to "(Acoustic)"
        var cleanedInside = inside
            .replaceAll(_videoNoiseRegex, ' ')
            .replaceAll(_resolutionRegex, ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        cleanedInside = cleanedInside.replaceAll(RegExp(r'^(?:official|hd|4k|video)\s*', caseSensitive: false), '').trim();
        return cleanedInside.isNotEmpty ? '($cleanedInside)' : '';
      } else if (hasNoise) {
        // Pure video noise e.g. "(Official 4K Video)", "[Full Video Song]" -> REMOVE
        return '';
      }

      // If it's not noise (e.g. movie/subtitle details), keep it
      return match.group(0)!;
    });

    // 3. Remove standalone resolution tags (e.g. "Song Name 8K Ultra HD" -> "Song Name")
    t = t.replaceAll(_resolutionRegex, ' ');

    // 4. Remove unbracketed video noise keywords (e.g. "Official Video", "Full Video Song")
    t = t.replaceAll(_videoNoiseRegex, ' ');

    // 5. Clean multi-clause delimiters (e.g. "Song Name | Full Video Song" -> "Song Name")
    t = _cleanDanglingClauses(t);

    // 6. Strip leading and trailing punctuation, dangling hyphens, pipes, colons, dots
    t = t.replaceAll(RegExp(r'^[\s\-\–\—\|\:\/\•\.\,]+|[\s\-\–\—\|\:\/\•\.\,]+$'), '').trim();

    // 7. Normalize consecutive whitespace
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

    return t.isNotEmpty ? t : title.trim();
  }

  static String _cleanDanglingClauses(String text) {
    var str = text;
    final clauseSeparators = RegExp(r'\s*(\||•|\/\/)\s*');
    if (clauseSeparators.hasMatch(str)) {
      final parts = str.split(clauseSeparators).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      final validParts = parts.where((p) {
        final lower = p.toLowerCase();
        return lower != 'official' &&
            lower != 'official video' &&
            lower != 'full video song' &&
            lower != 'video song' &&
            lower != 'lyrical' &&
            lower != 'lyrics' &&
            lower != '4k' &&
            lower != '8k' &&
            lower != 'hd';
      }).toList();

      if (validParts.isNotEmpty) {
        str = validParts.first; // The first primary clause is the song/track identity
      }
    }
    return str;
  }

  static String _stripInvisibleChars(String text) {
    return text.replaceAll(_invisibleCharsRegex, '').replaceAll('\u00A0', ' ');
  }

  static String _unescapeHtml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
