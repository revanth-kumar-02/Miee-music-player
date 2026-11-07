import '../domain/artwork_query.dart';

/// Deterministic validation and matching engine for artwork candidates.
///
/// Ensures candidate metadata from online providers strictly matches the
/// requested track before any album artwork is accepted.
class ArtworkMatchValidator {
  const ArtworkMatchValidator();

  /// Normalized tokens that indicate specialized versions.
  static const List<String> _versionTags = [
    'remix',
    'live',
    'acoustic',
    'instrumental',
    'orchestral',
    'cover',
    'karaoke',
    'slowed',
    'reverb',
    'deluxe',
    'remastered',
    'radio edit',
    'extended',
    'sped up',
  ];

  /// Validates whether a candidate track/album matches the target [query].
  ///
  /// Returns a confidence score between 0.0 and 1.0, or 0.0 if the match is rejected.
  double validateMatch({
    required ArtworkQuery query,
    required String candidateTitle,
    required String candidateArtist,
    String? candidateAlbum,
    String? candidateIsrc,
    int? candidateDurationMs,
  }) {
    // 1. Exact ISRC match has highest confidence
    if (query.isrc != null &&
        candidateIsrc != null &&
        query.isrc!.trim().isNotEmpty &&
        candidateIsrc.trim().isNotEmpty) {
      if (query.isrc!.trim().toUpperCase() == candidateIsrc.trim().toUpperCase()) {
        return 1.0;
      }
    }

    final qTitleNorm = normalize(query.title);
    final cTitleNorm = normalize(candidateTitle);
    final qArtistNorm = normalize(query.artist);
    final cArtistNorm = normalize(candidateArtist);

    // 2. Strict Version Guard:
    // Reject candidate if one contains a version tag (e.g. remix, live) and the other does not.
    if (!_isVersionCompatible(query.title, candidateTitle)) {
      return 0.0;
    }

    // 3. Artist Matching:
    // Check if primary artists match
    final artistMatches = _matchArtist(qArtistNorm, cArtistNorm);
    if (!artistMatches) {
      return 0.0; // Strictly reject different artists even if song titles match!
    }

    // 4. Title Matching
    final titleSimilarity = _calculateSimilarity(qTitleNorm, cTitleNorm);
    if (titleSimilarity < 0.75) {
      return 0.0;
    }

    // 5. Calculate final confidence
    double confidence = 0.85;

    // Boost if album matches
    if (query.album != null &&
        query.album!.trim().isNotEmpty &&
        candidateAlbum != null &&
        candidateAlbum.trim().isNotEmpty) {
      final qAlbumNorm = normalize(query.album!);
      final cAlbumNorm = normalize(candidateAlbum);
      if (_calculateSimilarity(qAlbumNorm, cAlbumNorm) > 0.80) {
        confidence = 0.95;
      }
    }

    // Adjust for title similarity nuance
    if (titleSimilarity > 0.95 && confidence < 0.95 && query.album == null) {
      confidence = 0.90;
    }

    // Optional duration check if available (within 10 seconds difference)
    if (query.durationMs != null && candidateDurationMs != null) {
      final diff = (query.durationMs! - candidateDurationMs).abs();
      if (diff > 15000) {
        // Discrepancy greater than 15s strongly suggests a different edit/recording
        return 0.0;
      }
    }

    return confidence;
  }

  /// Normalizes a string by lowercasing, stripping punctuation, extra spaces,
  /// and common release metadata words.
  static String normalize(String text) {
    var s = text.toLowerCase();
    // Remove content inside parenthesis or brackets
    s = s.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    s = s.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    // Remove common featuring indicators
    s = s.replaceAll(RegExp(r'\b(feat|ft|featuring|with)\b.*'), ' ');
    // Keep only alphanumeric characters and spaces
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    // Collapse spaces
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Checks if versions are compatible (e.g. neither has un-shared version tags).
  bool _isVersionCompatible(String titleA, String titleB) {
    final lowerA = titleA.toLowerCase();
    final lowerB = titleB.toLowerCase();

    for (final tag in _versionTags) {
      final hasA = lowerA.contains(tag);
      final hasB = lowerB.contains(tag);

      // If one is a remix/live/acoustic and the other is not, they are NOT compatible
      if (hasA != hasB) {
        return false;
      }
    }
    return true;
  }

  /// Checks if candidate artist is compatible with query artist.
  bool _matchArtist(String artistA, String artistB) {
    if (artistA.isEmpty || artistB.isEmpty) return false;
    if (artistA == artistB) return true;

    // Check substring or token containment (e.g., "Taylor Swift" vs "Taylor Swift, Post Malone")
    final tokensA = artistA.split(' ').where((t) => t.isNotEmpty).toSet();
    final tokensB = artistB.split(' ').where((t) => t.isNotEmpty).toSet();

    if (tokensA.containsAll(tokensB) || tokensB.containsAll(tokensA)) {
      return true;
    }

    return _calculateSimilarity(artistA, artistB) >= 0.80;
  }

  /// Jaccard & Levenshtein hybrid similarity between 0.0 and 1.0.
  double _calculateSimilarity(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;

    final tokensA = a.split(' ').where((t) => t.isNotEmpty).toSet();
    final tokensB = b.split(' ').where((t) => t.isNotEmpty).toSet();

    final intersection = tokensA.intersection(tokensB).length;
    final union = tokensA.union(tokensB).length;
    final jaccard = union == 0 ? 0.0 : intersection / union;

    final levDist = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    final levSim = maxLen == 0 ? 1.0 : 1.0 - (levDist / maxLen);

    return (jaccard * 0.4) + (levSim * 0.6);
  }

  int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i < v0.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = (s.codeUnitAt(i) == t.codeUnitAt(j)) ? 0 : 1;
        final a = v1[j] + 1;
        final b = v0[j + 1] + 1;
        final c = v0[j] + cost;
        v1[j + 1] = a < b ? (a < c ? a : c) : (b < c ? b : c);
      }
      for (int j = 0; j < v0.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[t.length];
  }

  /// Validates candidate image format, aspect ratio, and minimum dimensions.
  bool validateImageDimensions({int? width, int? height, int minDimension = 150}) {
    if (width == null || height == null) {
      return true; // Unknown dimensions are evaluated at runtime by image loader
    }
    if (width < minDimension || height < minDimension) {
      return false;
    }

    // Verify aspect ratio is roughly square (0.80 to 1.25)
    final ratio = width / height;
    if (ratio < 0.75 || ratio > 1.30) {
      return false;
    }

    return true;
  }
}

