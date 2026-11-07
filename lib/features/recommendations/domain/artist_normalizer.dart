class ArtistNormalizer {
  ArtistNormalizer._();

  static final RegExp _topicSuffix = RegExp(r'\s*-\s*topic$', caseSensitive: false);
  static final RegExp _vevoSuffix = RegExp(r'\s*vevo$', caseSensitive: false);
  static final RegExp _officialSuffix = RegExp(
    r'\s*(official(\s+(channel|music|video|audio))?|records|recordings|music|entertainment)$',
    caseSensitive: false,
  );
  static final RegExp _extraWhitespace = RegExp(r'\s+');
  static final RegExp _trailingSpecial = RegExp(r'[\s\-–—|,]+$');

  /// Normalizes an artist name to a clean, canonical representation.
  /// Example:
  /// - "Anirudh Ravichander - Topic" -> "Anirudh Ravichander"
  /// - "TaylorSwiftVEVO" -> "Taylor Swift"
  /// - "A.R. Rahman" -> "A.R. Rahman"
  static String normalize(String rawArtist) {
    if (rawArtist.trim().isEmpty) return '';

    String cleaned = rawArtist.trim();

    // Strip "- Topic" suffix common in auto-generated YouTube Music channels
    cleaned = cleaned.replaceAll(_topicSuffix, '').trim();

    // Specific case for joined VEVO names like "TaylorSwiftVEVO" or "ArianaGrandeVevo"
    if (cleaned.toLowerCase().endsWith('vevo') && cleaned.length > 4) {
      final withoutVevo = cleaned.substring(0, cleaned.length - 4).trim();
      cleaned = _splitCamelCase(withoutVevo);
    } else {
      cleaned = cleaned.replaceAll(_vevoSuffix, '').trim();
    }

    // Strip general noisy channel suffixes (official, music, records, etc.)
    cleaned = cleaned.replaceAll(_officialSuffix, '').trim();

    // Remove any trailing dashes, commas, or separators left after stripping
    cleaned = cleaned.replaceAll(_trailingSpecial, '').trim();

    // Normalize multiple whitespace characters
    cleaned = cleaned.replaceAll(_extraWhitespace, ' ');

    return cleaned.isNotEmpty ? cleaned : rawArtist.trim();
  }

  /// Splits joined PascalCase/camelCase strings into space-separated words.
  static String _splitCamelCase(String text) {
    if (text.isEmpty) return text;
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (i > 0 &&
          char.toUpperCase() == char &&
          char.toLowerCase() != char &&
          text[i - 1].toLowerCase() == text[i - 1] &&
          text[i - 1].toUpperCase() != text[i - 1]) {
        buffer.write(' ');
      }
      buffer.write(char);
    }
    return buffer.toString().trim();
  }

  /// Compares two artist names case-insensitively and after normalization.
  static bool areEquivalent(String artist1, String artist2) {
    final n1 = normalize(artist1).toLowerCase();
    final n2 = normalize(artist2).toLowerCase();
    if (n1.isEmpty || n2.isEmpty) return false;
    return n1 == n2;
  }
}

