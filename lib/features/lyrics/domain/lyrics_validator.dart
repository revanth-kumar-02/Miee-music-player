import 'dart:math';
import 'indic_transliterator.dart';

/// Rigorous candidate validator to prevent false positives and verify that
/// returned lyrics legitimately correspond to the active track.
class LyricsValidator {
  static const _versionSubtitleNoise = [
    'acoustic',
    'live',
    'remix',
    'version',
    'remastered',
    'reprise',
    'original',
    'lofi',
    'slowed',
    'reverb',
    'soundtrack',
    'theme',
    'instrumental',
    'edit',
    'radio edit',
  ];

  /// Validates whether [candidateTrackName] from a lyrics provider is a genuine
  /// match for [queryTrackName].
  ///
  /// If duration information is provided, validates that durations do not wildly
  /// diverge.
  static bool validate({
    required String queryTrackName,
    required String candidateTrackName,
    Duration? queryDuration,
    Duration? candidateDuration,
  }) {
    // 1. Duration check
    if (queryDuration != null &&
        candidateDuration != null &&
        queryDuration.inSeconds > 0 &&
        candidateDuration.inSeconds > 0) {
      final diff = (queryDuration.inSeconds - candidateDuration.inSeconds).abs();
      // Allow up to 45 seconds tolerance for YouTube audio (intro dialogues / outro credits)
      if (diff > 45) {
        return false;
      }
    }

    final normQuery = _cleanTitle(queryTrackName);
    final normCand = _cleanTitle(candidateTrackName);

    if (normQuery.isEmpty || normCand.isEmpty) return false;

    // 2. Exact match
    if (normQuery == normCand) return true;

    // 3. Subtitle / parenthetical version match:
    // e.g. "Arabic Kuthu" matching "Arabic Kuthu - Halamithi Habibo"
    // or "Oo Solriya" matching "Oo Solriya (From Pushpa)"
    final coreCand = _stripVersionSubtitle(normCand);
    final coreQuery = _stripVersionSubtitle(normQuery);

    if (coreCand == coreQuery) return true;
    if (coreCand == normQuery || coreQuery == normCand) return true;

    // 4. Indic Script Comparison (Transliteration & Phonetic Stemming)
    final hasIndicQuery = IndicTransliterator.hasIndicScript(normQuery);
    final hasIndicCand = IndicTransliterator.hasIndicScript(normCand);

    if (hasIndicQuery || hasIndicCand) {
      final latinQuery = hasIndicQuery ? IndicTransliterator.transliterate(normQuery) : normQuery;
      final latinCand = hasIndicCand ? IndicTransliterator.transliterate(normCand) : normCand;

      final stemQuery = IndicTransliterator.phoneticStem(latinQuery);
      final stemCand = IndicTransliterator.phoneticStem(latinCand);

      if (stemQuery == stemCand) return true;
      if (_fuzzySimilarity(stemQuery, stemCand) >= 0.70) return true;

      final coreStemQ = IndicTransliterator.phoneticStem(_stripVersionSubtitle(latinQuery));
      final coreStemC = IndicTransliterator.phoneticStem(_stripVersionSubtitle(latinCand));
      if (coreStemQ == coreStemC) return true;
      if (_fuzzySimilarity(coreStemQ, coreStemC) >= 0.70) return true;

      // Prefix match on stems (e.g. "u solriya" inside "u solriya u u solriya from pushpa")
      if (stemCand.startsWith('$stemQuery ') || stemQuery.startsWith('$stemCand ') ||
          coreStemC.startsWith('$coreStemQ ') || coreStemQ.startsWith('$coreStemC ')) {
        return true;
      }

      // Token overlap on phonetic stems
      final qTokens = coreStemQ.split(' ').where((w) => w.length > 1).toSet();
      final cTokens = coreStemC.split(' ').where((w) => w.length > 1).toSet();
      if (qTokens.isNotEmpty && cTokens.isNotEmpty && qTokens.difference(cTokens).isEmpty) {
        return true;
      }
    }

    // 5. Token analysis and Substring Protection
    // Single-word titles (e.g. "Yellow", "Starboy") must NOT match completely
    // different songs that happen to contain that word (e.g. "Black and Yellow", "Stargirl")
    final qTokens = normQuery.split(' ').where((w) => w.length > 1).toSet();
    final cTokens = normCand.split(' ').where((w) => w.length > 1).toSet();

    if (qTokens.isEmpty || cTokens.isEmpty) return false;

    // If candidate starts with the exact query title followed by a delimiter or subtitle:
    // e.g. "Arabic Kuthu - Halamithi Habibo" starts with "Arabic Kuthu"
    if (normCand.startsWith('$normQuery ') || normCand.startsWith('$coreQuery ')) {
      return true;
    }
    if (normQuery.startsWith('$normCand ') || normQuery.startsWith('$coreCand ')) {
      return true;
    }

    // Token overlap: compute Jaccard index
    final intersection = qTokens.intersection(cTokens).length;
    final union = qTokens.union(cTokens).length;
    final jaccard = union > 0 ? (intersection / union) : 0.0;

    // If query has only 1 token, require exact match (prevent "Yellow" -> "Black and Yellow")
    if (qTokens.length == 1) {
      if (cTokens.length == 1 && jaccard == 1.0) return true;
      // If candidate has subtitles like "(From ...)", check against core
      final coreTokens = coreCand.split(' ').where((w) => w.length > 1).toSet();
      return coreTokens.length == 1 && coreTokens.contains(qTokens.first);
    }

    // For multi-token queries, require high token overlap (>= 0.65)
    if (jaccard >= 0.65) return true;

    // 6. Fuzzy string similarity fallback
    return _fuzzySimilarity(normQuery, normCand) >= 0.80;
  }

  static String _cleanTitle(String s) {
    var str = s.toLowerCase();
    // Strip invisible characters
    str = str.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    // Replace punctuation with space
    str = str.replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ');
    str = str.replaceAll(RegExp(r'\s+'), ' ').trim();
    return str;
  }

  static String _stripVersionSubtitle(String s) {
    var str = s;
    for (final noise in _versionSubtitleNoise) {
      str = str.replaceAll(RegExp('\\b$noise\\b', caseSensitive: false), ' ');
    }
    // Strip "from <movie>"
    str = str.replaceAll(RegExp(r'\bfrom\s+[a-z0-9\s]+', caseSensitive: false), ' ');
    str = str.replaceAll(RegExp(r'\s+'), ' ').trim();
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
