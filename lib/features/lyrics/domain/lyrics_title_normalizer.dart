/// Intelligent, conservative title normalization utility specifically tailored for
/// lyrics matching across local, streaming, and YouTube Music audio sources.
///
/// Designed to strip resolution tags, promotional video suffixes, format labels,
/// and video clutter without removing meaningful words or numbers from genuine
/// song titles (e.g., "7 Years", "21 Guns", "1999", "3", "Song 2").
class LyricsTitleNormalizer {
  const LyricsTitleNormalizer._();

  /// Suffix patterns that denote resolution or video format labels.
  /// Matches standalone tokens or trailing phrases like:
  /// - `8K`, `4K`, `2K`, `HD`, `FHD`, `UHD`, `1080p`, `720p`, `4K UHD`, `8K 60FPS`
  static final RegExp _resolutionRegex = RegExp(
    r'\b(?:8k|4k|2k|hd|fhd|uhd|1080p|720p|4k\s*uhd|8k\s*60fps|60fps|hdr)\b',
    caseSensitive: false,
  );

  /// Suffix patterns that denote video, audio, release, or promotional tags.
  static final RegExp _videoNoiseRegex = RegExp(
    r'\b(?:official\s+music\s+video|official\s+lyric\s+video|official\s+lyrical\s+video|'
    r'official\s+video\s+song|official\s+video|official\s+audio|official\s+track|'
    r'official\s+teaser|official\s+trailer|music\s+video|lyrical\s+video|lyrics\s+video|'
    r'lyric\s+video|video\s+song|full\s+video\s+song|full\s+video|full\s+song|'
    r'audio\s+song|full\s+audio|visualizer|remastered|extended\s+version|'
    r'deluxe\s+edition|deluxe\s+version|teaser|trailer|promo|'
    r'vertical\s+video|studio\s+version|album\s+version)\b',
    caseSensitive: false,
  );

  /// Bracketed and parenthesized noise patterns.
  static final RegExp _bracketNoiseRegex = RegExp(
    r'[\(\[\{](?:[^\)\]\}]*(?:official|video|audio|lyric|lyrics|lyrical|remaster|remix|version|hd|4k|8k|uhd|fhd|1080p|720p|fps|teaser|trailer|promo|song|mv|prod\.|feat\.|ft\.)[^\)\]\}]*)[\)\]\}]',
    caseSensitive: false,
  );

  /// Normalizes a display track title for lyrics matching.
  ///
  /// Preserves the core song title and returns a clean, canonical string suitable
  /// for querying lyrics providers.
  ///
  /// Examples:
  /// - `Kadhal En Kadhal - 8K` -> `Kadhal En Kadhal`
  /// - `Song Name 4K` -> `Song Name`
  /// - `Song Name HD` -> `Song Name`
  /// - `Song Name (Official Video)` -> `Song Name`
  /// - `Song Name [Remastered]` -> `Song Name`
  /// - `Song Name Lyrical Video` -> `Song Name`
  /// - `7 Years` -> `7 Years` (meaningful numbers preserved)
  /// - `21 Guns` -> `21 Guns` (meaningful numbers preserved)
  /// - `1999` -> `1999` (meaningful numbers preserved)
  static String normalize(String title) {
    if (title.isEmpty) return '';

    var t = stripInvisibleChars(title);

    // 1. Remove bracketed/parenthesized promotional noise
    t = t.replaceAll(_bracketNoiseRegex, ' ');

    // 2. Remove video / format / promotional keywords
    t = t.replaceAll(_videoNoiseRegex, ' ');

    // 3. Remove resolution suffixes (8k, 4k, 2k, hd, uhd, fhd, 1080p, etc.)
    t = t.replaceAll(_resolutionRegex, ' ');

    // 4. If the title contains multi-clause separators like ' - ' or ' | ' or ' / '
    // check if trailing or preceding clauses were left empty or contain only noise
    t = _cleanDanglingClauses(t);

    // 5. Strip leading/trailing hyphens, colons, pipes, and delimiters
    t = t.replaceAll(RegExp(r'^[\s\-\–\—\|\:\/\•]+|[\s\-\–\—\|\:\/\•]+$'), '');

    t = normalizeWhitespace(t);

    // Safety fallback: if normalization stripped everything (unlikely), return original stripped
    return t.isNotEmpty ? t : normalizeWhitespace(stripInvisibleChars(title));
  }

  /// Extracts alternative title variants for multi-stage matching.
  /// Returns a list of candidate variants in priority order, deduplicated.
  static List<String> extractVariants(String title) {
    final variants = <String>[];
    final seen = <String>{};

    void add(String s) {
      final clean = normalizeWhitespace(stripInvisibleChars(s));
      if (clean.isNotEmpty && seen.add(clean.toLowerCase())) {
        variants.add(clean);
      }
    }

    final normalized = normalize(title);
    add(normalized);

    // Check parenthetical sub-titles: e.g. "Title (Subtitle)" or "Title (from Movie)"
    final parenRegex = RegExp(r'\(([^)]+)\)|\[([^\]]+)\]');
    for (final m in parenRegex.allMatches(title)) {
      final inside = (m.group(1) ?? m.group(2) ?? '').trim();
      if (inside.isNotEmpty && !isPromotionalNoise(inside)) {
        // Strip movie prefixes like "From 'Movie'"
        final fromMatch = RegExp(r'^(?:from\s+["\x27]?)([^"\x27\)]+)', caseSensitive: false).firstMatch(inside);
        if (fromMatch == null) {
          final normInside = normalize(inside);
          if (normInside.isNotEmpty) {
            add(normInside);
          }
        }
      }
    }

    // Check delimited clauses: e.g. "Song - Movie" or "Artist - Song"
    if (title.contains('|') || title.contains('•') || title.contains('//') || title.contains(' - ') || title.contains(' – ')) {
      final clauses = title
          .split(RegExp(r'(\||•|\/\/|\s+[-–—]\s+)'))
          .map(normalize)
          .where((s) => s.isNotEmpty && !isPromotionalNoise(s))
          .toList();

      for (final clause in clauses) {
        add(clause);
      }
    }

    return variants;
  }

  /// Checks if a string consists entirely of promotional or technical noise.
  static bool isPromotionalNoise(String s) {
    var clean = normalize(s);
    return clean.isEmpty;
  }

  /// Strips dangling separators left after noise removal.
  static String _cleanDanglingClauses(String s) {
    var res = s;
    // Replace patterns like " - - " or " | | " or " - " at end/beginning
    res = res.replaceAll(RegExp(r'\s+[-–—\|]\s*[-–—\|]\s+'), ' - ');
    res = res.replaceAll(RegExp(r'\s+[-–—\|]\s*$'), '');
    res = res.replaceAll(RegExp(r'^\s*[-–—\|]\s+'), '');
    return res;
  }

  /// Strips Unicode zero-width or invisible characters.
  static String stripInvisibleChars(String s) {
    return s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  }

  /// Collapses consecutive whitespace to a single space.
  static String normalizeWhitespace(String s) {
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

