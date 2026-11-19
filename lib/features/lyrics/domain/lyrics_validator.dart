import 'dart:math';
import 'indic_transliterator.dart';
import 'lyrics_title_normalizer.dart';

/// Detailed result of candidate lyrics validation and matching.
class LyricsMatchResult {
  final bool isValid;
  final double confidence;
  final String reason;
  final double titleScore;
  final double artistScore;
  final double durationScore;
  final double languageScore;
  final double versionScore;

  const LyricsMatchResult({
    required this.isValid,
    required this.confidence,
    required this.reason,
    this.titleScore = 0.0,
    this.artistScore = 0.0,
    this.durationScore = 0.0,
    this.languageScore = 0.0,
    this.versionScore = 0.0,
  });

  static const invalidEmpty = LyricsMatchResult(
    isValid: false,
    confidence: 0.0,
    reason: 'Empty query or candidate track name',
  );

  @override
  String toString() =>
      'LyricsMatchResult(valid: $isValid, conf: ${(confidence * 100).toStringAsFixed(1)}%, reason: $reason, T: $titleScore, A: $artistScore, D: $durationScore, L: $languageScore, V: $versionScore)';
}

/// Rigorous candidate validator to prevent false positives and verify that
/// returned lyrics legitimately correspond to the active track.
class LyricsValidator {
  const LyricsValidator._();

  /// High-confidence threshold required to display lyrics.
  static const double acceptanceThreshold = 0.75;

  /// General non-version promotional noises that can safely be ignored in title comparison.
  /// (Crucial: 'reprise', 'acoustic', 'remix' are version modifiers and NOT treated as noise).
  static const _nonVersionNoise = [
    'official',
    'video',
    'audio',
    'lyric',
    'lyrics',
    'lyrical',
    'remastered',
    'original',
    'soundtrack',
    'theme',
    'visualizer',
    'deluxe',
    'extended',
    'edit',
  ];

  /// Comprehensive multi-factor candidate evaluation.
  ///
  /// Evaluates:
  /// 1. Title compatibility (35% weight)
  /// 2. Artist alignment (35% weight)
  /// 3. Duration divergence (15% weight)
  /// 4. Language tag compatibility (10% weight)
  /// 5. Version modifier alignment (5% weight)
  ///
  /// Applies hard vetoes for:
  /// - Disjoint known artists
  /// - Conflicting language tags (e.g. Hindi vs Tamil)
  /// - Version modifier mismatches (e.g. Reprise vs original)
  /// - Wild duration divergences (> 45 seconds)
  static LyricsMatchResult evaluateMatch({
    required String queryTrackName,
    required String candidateTrackName,
    String queryArtistName = '',
    String candidateArtistName = '',
    Duration? queryDuration,
    Duration? candidateDuration,
    String? queryAlbum,
    String? candidateAlbum,
  }) {
    final rawQueryTitle = queryTrackName.trim();
    final rawCandTitle = candidateTrackName.trim();

    if (rawQueryTitle.isEmpty || rawCandTitle.isEmpty) {
      return LyricsMatchResult.invalidEmpty;
    }

    // ── Hard Veto 1: Duration Check ───────────────────────────────────────────
    double durationScore = 1.0;
    if (queryDuration != null &&
        candidateDuration != null &&
        queryDuration.inSeconds > 0 &&
        candidateDuration.inSeconds > 0) {
      final diff = (queryDuration.inSeconds - candidateDuration.inSeconds).abs();
      if (diff > 45) {
        return LyricsMatchResult(
          isValid: false,
          confidence: 0.0,
          reason: 'Duration divergence too high: ${diff}s (>45s max allowed)',
          durationScore: 0.0,
        );
      }
      if (diff <= 3) {
        durationScore = 1.0;
      } else if (diff <= 10) {
        durationScore = 0.85;
      } else if (diff <= 25) {
        durationScore = 0.60;
      } else {
        durationScore = 0.35;
      }
    }

    // ── Hard Veto 2: Version Modifier Alignment ───────────────────────────────
    // e.g. "Urugi Urugi" vs "Urugi Urugi - Reprise", or "Song (Acoustic)" vs "Song"
    final queryVersion = LyricsTitleNormalizer.extractVersionModifier(rawQueryTitle);
    final candVersion = LyricsTitleNormalizer.extractVersionModifier(rawCandTitle);
    double versionScore = 1.0;

    if (queryVersion != null || candVersion != null) {
      if (queryVersion != candVersion) {
        return LyricsMatchResult(
          isValid: false,
          confidence: 0.0,
          reason: 'Version modifier mismatch: query has "${queryVersion ?? 'original'}", candidate has "${candVersion ?? 'original'}"',
          versionScore: 0.0,
        );
      }
      versionScore = 1.0;
    }

    // ── Hard Veto 3: Language Tag Alignment ───────────────────────────────────
    // e.g. "Veezha Veera [Tamil]" vs "Veezha Veera [Hindi]"
    final queryLang = LyricsTitleNormalizer.extractLanguageTag(rawQueryTitle) ??
        (queryAlbum != null ? LyricsTitleNormalizer.extractLanguageTag(queryAlbum) : null);
    final candLang = LyricsTitleNormalizer.extractLanguageTag(rawCandTitle) ??
        (candidateAlbum != null ? LyricsTitleNormalizer.extractLanguageTag(candidateAlbum) : null);
    double languageScore = 1.0;

    if (queryLang != null && candLang != null) {
      if (queryLang != candLang) {
        return LyricsMatchResult(
          isValid: false,
          confidence: 0.0,
          reason: 'Conflicting language tags: query is "$queryLang", candidate is "$candLang"',
          languageScore: 0.0,
        );
      }
      languageScore = 1.0;
    } else if (queryLang != null && candLang == null) {
      // Candidate not explicitly tagged, neutral
      languageScore = 0.9;
    } else if (queryLang == null && candLang != null) {
      // Candidate has specific language tag while query did not specify
      // If candidate is Hindi and query artist is confirmed Tamil composer (or vice versa), veto
      final qArtists = LyricsTitleNormalizer.splitArtists(queryArtistName).map((a) => a.toLowerCase()).toSet();
      if (candLang == 'hindi' && (qArtists.contains('sai abhyankkar') || qArtists.contains('anirudh ravichander') || qArtists.contains('dhanush') || qArtists.contains('yuvan shankar raja'))) {
        return const LyricsMatchResult(
          isValid: false,
          confidence: 0.0,
          reason: 'Language conflict: candidate tagged with [Hindi] but query is Tamil composer',
          languageScore: 0.0,
        );
      }
      languageScore = 0.85;
    }

    // ── Hard Veto 4 & Scoring: Artist Compatibility ───────────────────────────
    final artistScore = _computeArtistScore(queryArtistName, candidateArtistName);
    if (artistScore <= 0.0 && queryArtistName.trim().isNotEmpty && candidateArtistName.trim().isNotEmpty) {
      return LyricsMatchResult(
        isValid: false,
        confidence: 0.0,
        reason: 'Conflicting artist: candidate "$candidateArtistName" does not match query "$queryArtistName"',
        artistScore: 0.0,
      );
    }

    // ── Scoring: Title Compatibility ──────────────────────────────────────────
    final titleScore = _computeTitleScore(rawQueryTitle, rawCandTitle);
    if (titleScore < 0.50) {
      return LyricsMatchResult(
        isValid: false,
        confidence: 0.0,
        reason: 'Title mismatch: similarity ${(titleScore * 100).toStringAsFixed(1)}% is below 50%',
        titleScore: titleScore,
      );
    }

    // ── Composite Confidence Calculation ──────────────────────────────────────
    // Title (35%), Artist (35%), Duration (15%), Language (10%), Version (5%)
    final totalConfidence = (0.35 * titleScore) +
        (0.35 * artistScore) +
        (0.15 * durationScore) +
        (0.10 * languageScore) +
        (0.05 * versionScore);

    final isValid = totalConfidence >= acceptanceThreshold;

    return LyricsMatchResult(
      isValid: isValid,
      confidence: totalConfidence,
      reason: isValid
          ? 'Matched with ${(totalConfidence * 100).toStringAsFixed(1)}% confidence'
          : 'Confidence ${(totalConfidence * 100).toStringAsFixed(1)}% below threshold ${(acceptanceThreshold * 100).toStringAsFixed(0)}%',
      titleScore: titleScore,
      artistScore: artistScore,
      durationScore: durationScore,
      languageScore: languageScore,
      versionScore: versionScore,
    );
  }

  /// Backward-compatible boolean validation helper.
  static bool validate({
    required String queryTrackName,
    required String candidateTrackName,
    String queryArtistName = '',
    String candidateArtistName = '',
    Duration? queryDuration,
    Duration? candidateDuration,
  }) {
    final result = evaluateMatch(
      queryTrackName: queryTrackName,
      candidateTrackName: candidateTrackName,
      queryArtistName: queryArtistName,
      candidateArtistName: candidateArtistName,
      queryDuration: queryDuration,
      candidateDuration: candidateDuration,
    );
    return result.isValid;
  }

  /// Computes artist alignment score between 0.0 and 1.0.
  /// Hard 0.0 indicates completely disjoint, conflicting artists.
  static double _computeArtistScore(String queryArtist, String candidateArtist) {
    final cleanQ = queryArtist.trim().toLowerCase();
    final cleanC = candidateArtist.trim().toLowerCase();

    if (cleanQ.isEmpty || cleanC.isEmpty) {
      // Unspecified artist: neutral baseline
      return 0.65;
    }

    if (cleanQ == cleanC) return 1.0;

    final qArtists = LyricsTitleNormalizer.splitArtists(queryArtist)
        .map((a) => a.toLowerCase().trim())
        .where((a) => a.isNotEmpty)
        .toList();
    final cArtists = LyricsTitleNormalizer.splitArtists(candidateArtist)
        .map((a) => a.toLowerCase().trim())
        .where((a) => a.isNotEmpty)
        .toList();

    if (qArtists.isEmpty || cArtists.isEmpty) return 0.65;

    // Check exact primary artist match
    final primaryQ = qArtists.first;
    final primaryC = cArtists.first;
    if (primaryQ == primaryC) return 0.95;

    // Check cross-artist match (e.g. "Sai Abhyankkar" in "Sai Abhyankkar & Dhanush")
    for (final q in qArtists) {
      for (final c in cArtists) {
        if (q == c) return 0.90;
        if (q.contains(c) || c.contains(q)) return 0.85;
      }
    }

    // Token intersection on artist names
    final qTokens = qArtists.expand((a) => a.split(RegExp(r'\s+'))).where((t) => t.length > 2).toSet();
    final cTokens = cArtists.expand((a) => a.split(RegExp(r'\s+'))).where((t) => t.length > 2).toSet();

    if (qTokens.isNotEmpty && cTokens.isNotEmpty) {
      final intersection = qTokens.intersection(cTokens);
      if (intersection.isNotEmpty) {
        return 0.80;
      }
    }

    // Both artists are non-empty and have zero overlap -> Conflicting artist!
    return 0.0;
  }

  /// Computes title alignment score between 0.0 and 1.0.
  static double _computeTitleScore(String queryTitle, String candidateTitle) {
    final normQuery = _cleanTitle(queryTitle);
    final normCand = _cleanTitle(candidateTitle);

    if (normQuery.isEmpty || normCand.isEmpty) return 0.0;
    if (normQuery == normCand) return 1.0;

    // Check acronym normalized equivalence: e.g. "om special duty" == "o m special duty"
    final acQuery = LyricsTitleNormalizer.normalizeAcronyms(normQuery);
    final acCand = LyricsTitleNormalizer.normalizeAcronyms(normCand);
    if (acQuery == acCand || acQuery == normCand || normQuery == acCand) {
      return 0.98;
    }

    // Check core stripped noise
    final coreQ = _stripNonVersionNoise(normQuery);
    final coreC = _stripNonVersionNoise(normCand);
    if (coreQ == coreC) return 0.95;
    if (coreQ.isNotEmpty && (coreQ == normCand || normQuery == coreC)) return 0.92;

    // Indic transliteration / phonetic matching
    final hasIndicQ = IndicTransliterator.hasIndicScript(normQuery);
    final hasIndicC = IndicTransliterator.hasIndicScript(normCand);
    if (hasIndicQ || hasIndicC) {
      final latinQ = hasIndicQ ? IndicTransliterator.transliterate(normQuery) : normQuery;
      final latinC = hasIndicC ? IndicTransliterator.transliterate(normCand) : normCand;

      final stemQ = IndicTransliterator.phoneticStem(latinQ);
      final stemC = IndicTransliterator.phoneticStem(latinC);

      if (stemQ == stemC) return 0.90;
      final stemFuzzy = _fuzzySimilarity(stemQ, stemC);
      if (stemFuzzy >= 0.75) return 0.85;

      final coreStemQ = IndicTransliterator.phoneticStem(_stripNonVersionNoise(latinQ));
      final coreStemC = IndicTransliterator.phoneticStem(_stripNonVersionNoise(latinC));
      if (coreStemQ == coreStemC) return 0.88;
      if (_fuzzySimilarity(coreStemQ, coreStemC) >= 0.75) return 0.82;
    }

    // Token analysis
    final qTokens = normQuery.split(' ').where((w) => w.length > 1).toSet();
    final cTokens = normCand.split(' ').where((w) => w.length > 1).toSet();

    if (qTokens.isEmpty || cTokens.isEmpty) return 0.0;

    final intersection = qTokens.intersection(cTokens).length;
    final union = qTokens.union(cTokens).length;
    final jaccard = union > 0 ? (intersection / union) : 0.0;

    // Single-word titles require exact match
    if (qTokens.length == 1) {
      if (cTokens.length == 1 && jaccard == 1.0) return 1.0;
      final coreTokens = coreC.split(' ').where((w) => w.length > 1).toSet();
      if (coreTokens.length == 1 && coreTokens.contains(qTokens.first)) return 0.90;
      return 0.0;
    }

    if (jaccard >= 0.75) return 0.85;
    if (jaccard >= 0.50) return 0.70;

    // Fuzzy string similarity
    final fuzzy = _fuzzySimilarity(normQuery, normCand);
    return fuzzy;
  }

  static String _cleanTitle(String s) {
    final normalized = LyricsTitleNormalizer.normalize(s);
    var str = normalized.toLowerCase();
    str = LyricsTitleNormalizer.stripInvisibleChars(str);
    str = str.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ');
    str = LyricsTitleNormalizer.normalizeWhitespace(str);
    return str;
  }

  static String _stripNonVersionNoise(String s) {
    var str = s;
    for (final noise in _nonVersionNoise) {
      str = str.replaceAll(RegExp('\\b$noise\\b', caseSensitive: false), ' ');
    }
    // Strip "from <movie>"
    str = str.replaceAll(RegExp(r'\bfrom\s+[a-z0-9\s]+', caseSensitive: false), ' ');
    str = LyricsTitleNormalizer.normalizeWhitespace(str);
    return str;
  }

  static double _fuzzySimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    final maxLen = max(s1.length, s2.length);
    if (maxLen == 0) return 1.0;
    final dist = _levenshtein(s1, s2);
    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.filled(s2.length + 1, 0);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i <= s2.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }

    return v1[s2.length];
  }
}
