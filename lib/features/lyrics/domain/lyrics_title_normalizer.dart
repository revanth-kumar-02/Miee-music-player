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
    r'[\(\[\{](?:[^\)\]\}]*(?:official|video|audio|lyric|lyrics|lyrical|remaster|hd|4k|8k|uhd|fhd|1080p|720p|fps|teaser|trailer|promo|song|mv|prod\.|feat\.|ft\.)[^\)\]\}]*)[\)\]\}]',
    caseSensitive: false,
  );

  /// Pattern matching regional Indian and international language tags.
  static final RegExp _languageTagRegex = RegExp(
    r'[\(\[\{]\s*(tamil|telugu|hindi|malayalam|kannada|punjabi|bengali|marathi|english|spanish|korean|japanese)(?:\s+(?:song|version|audio|video|track))?\s*[\)\]\}]',
    caseSensitive: false,
  );

  /// Key version modifiers that alter the actual recording/lyrics composition.
  static const List<String> versionModifiers = [
    'reprise',
    'acoustic',
    'unplugged',
    'live',
    'remix',
    'lofi',
    'slowed',
    'reverb',
    'cover',
    'instrumental',
    'radio edit',
  ];

  /// Detects and extracts language tag from title or subtitle (e.g. "[Tamil]" -> "tamil").
  static String? extractLanguageTag(String title) {
    final match = _languageTagRegex.firstMatch(title);
    if (match != null) {
      return match.group(1)?.toLowerCase();
    }
    return null;
  }

  /// Detects whether the title contains a specific version modifier (e.g. "reprise").
  static String? extractVersionModifier(String title) {
    final lower = title.toLowerCase();
    for (final modifier in versionModifiers) {
      final reg = RegExp(r'\b' + RegExp.escape(modifier) + r'\b');
      if (reg.hasMatch(lower)) {
        return modifier;
      }
    }
    return null;
  }

  /// Normalizes acronym punctuation (e.g., "O.M" -> "OM", "K.G.F" -> "KGF", "A.R." -> "AR").
  static String normalizeAcronyms(String text) {
    if (text.isEmpty) return text;
    // Replace sequences of single letter followed by period, e.g. "O.M." or "O.M"
    return text.replaceAllMapped(
      RegExp(r'\b([a-zA-Z])\.([a-zA-Z])(?:\.([a-zA-Z]))?(?:\.([a-zA-Z]))?\b'),
      (match) {
        final g1 = match.group(1) ?? '';
        final g2 = match.group(2) ?? '';
        final g3 = match.group(3) ?? '';
        final g4 = match.group(4) ?? '';
        return '$g1$g2$g3$g4';
      },
    );
  }

  /// Splits composite artist strings into discrete individual artists.
  /// Handles delimiters like `&`, `,`, `feat.`, `ft.`, `and`, `featuring`, `/`, `vs`.
  /// The primary artist is guaranteed to be at index 0.
  static List<String> splitArtists(String artist) {
    if (artist.isEmpty) return [];

    final clean = stripInvisibleChars(artist);
    // Split by common collaborator delimiters
    final parts = clean.split(
      RegExp(r'\s*(?:&|,|\/|\||\band\b|\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bvs\.?\b)\s*', caseSensitive: false),
    );

    final results = <String>[];
    final seen = <String>{};

    for (final part in parts) {
      final trimmed = normalizeWhitespace(part.replaceAll(RegExp(r'[\(\)\[\]\{\}]'), ''));
      if (trimmed.isNotEmpty && seen.add(trimmed.toLowerCase())) {
        results.add(trimmed);
      }
    }

    return results.isNotEmpty ? results : [clean.trim()];
  }

  /// Normalizes a display track title for lyrics matching.
  ///
  /// Preserves the core song title and returns a clean, canonical string suitable
  /// for querying lyrics providers.
  static String normalize(String title) {
    if (title.isEmpty) return '';

    var t = stripInvisibleChars(title);

    // 1. Remove bracketed/parenthesized promotional noise
    t = t.replaceAll(_bracketNoiseRegex, ' ');

    // 2. Remove language tags from the query title (preserved in metadata via extractLanguageTag)
    t = t.replaceAll(_languageTagRegex, ' ');

    // 3. Remove video / format / promotional keywords
    t = t.replaceAll(_videoNoiseRegex, ' ');

    // 4. Remove resolution suffixes (8k, 4k, 2k, hd, uhd, fhd, 1080p, etc.)
    t = t.replaceAll(_resolutionRegex, ' ');

    // 5. Clean dangling separators left after noise removal
    t = _cleanDanglingClauses(t);

    // 6. Strip leading/trailing hyphens, colons, pipes, and delimiters
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

    // Also add acronym-normalized variant if it differs (e.g. "O.M Special Duty" -> "OM Special Duty")
    final acronymNorm = normalizeAcronyms(normalized);
    if (acronymNorm.toLowerCase() != normalized.toLowerCase()) {
      add(acronymNorm);
    }

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
            final acronymInside = normalizeAcronyms(normInside);
            if (acronymInside.toLowerCase() != normInside.toLowerCase()) {
              add(acronymInside);
            }
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
        final ac = normalizeAcronyms(clause);
        if (ac.toLowerCase() != clause.toLowerCase()) {
          add(ac);
        }
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
