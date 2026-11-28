import '../../onboarding/domain/artist_model.dart';
import '../../youtube/domain/youtube_model.dart';
import 'search_deduplicator.dart';

/// Evaluates relevance between search queries and music candidate items.
///
/// Prevents irrelevant search results (e.g., Apple iTunes returning unrelated
/// global tracks like Sia or Drake for queries like "OM All Songs Tamil") from
/// leaking into search results or being misidentified as canonical tracks.
class QueryRelevanceEvaluator {
  /// Common collection / discography stop words that indicate intent rather than
  /// track titles.
  static final Set<String> collectionStopWords = {
    'all',
    'song',
    'songs',
    'hit',
    'hits',
    'jukebox',
    'album',
    'audio',
    'video',
    'collection',
    'discography',
    'best',
    'top',
    'full',
    'ost',
    'theme',
    'track',
    'tracks',
    'of',
    'the',
  };

  /// Common language markers that indicate target language / regional music.
  static final Set<String> languageMarkers = {
    'tamil',
    'telugu',
    'hindi',
    'malayalam',
    'kannada',
    'punjabi',
    'bengali',
    'marathi',
    'english',
    'spanish',
    'korean',
    'japanese',
  };

  /// Detects whether the query has collection / jukebox / discography intent.
  static bool isCollectionQuery(String query) {
    final lower = query.toLowerCase();
    final tokens = _tokenize(lower);
    for (final token in tokens) {
      if (token == 'all' ||
          token == 'songs' ||
          token == 'jukebox' ||
          token == 'discography' ||
          token == 'hits' ||
          token == 'hit' ||
          token == 'collection') {
        return true;
      }
    }
    return lower.contains('all song') ||
        lower.contains('all songs') ||
        lower.contains('audio songs') ||
        lower.contains('video songs') ||
        lower.contains('best of');
  }

  /// Extracts core search entities by removing collection stopwords while
  /// preserving language markers and primary keywords.
  static String extractCoreEntity(String query) {
    final tokens = _tokenize(query.toLowerCase());
    final core = tokens.where((t) => !collectionStopWords.contains(t)).toList();
    if (core.isEmpty) return query.trim();
    return core.join(' ');
  }

  /// Tokenizes a string into alphanumeric lower-case words, including collapsed
  /// single-letter initials (e.g. 'a', 'r' produces 'ar' to match 'AR Rahman' vs 'A.R. Rahman').
  /// Supports Unicode letters, marks, and numbers.
  static List<String> _tokenize(String input) {
    final words = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final combined = <String>[...words];
    for (int i = 0; i < words.length - 1; i++) {
      if (words[i].length == 1 && words[i + 1].length == 1) {
        combined.add('${words[i]}${words[i + 1]}');
      }
    }
    return combined;
  }

  /// Checks whether [token] matches as a complete word/token in [candidateTokens]
  /// or with strict word-boundary matching in [candidateCombined].
  ///
  /// Prevents short tokens (<= 3 chars such as 'om', 'dj', 'in', 'on') from
  /// matching substrings of unrelated words (e.g., 'om' inside 'from', 'tom', 'homeland').
  /// Generates conservative phonetic/transliteration keys for Romanized
  /// multilingual song tokens (e.g. "paathi" <-> "pathi", "naan" <-> "naa")
  /// while preserving strict isolation for short tokens (< 3 chars).
  static Set<String> transliterationKeys(String token) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) return const {};
    final keys = <String>{t};
    if (t.length < 3) return keys;

    // Indic long-vowel nasal ending: "naan" <-> "naa", "thaan" <-> "thaa"
    if (t.endsWith('aan') && t.length >= 4) {
      keys.add(t.substring(0, t.length - 1));
    } else if (t.endsWith('aa') && t.length >= 3) {
      keys.add('${t}n');
    }

    // Collapse consecutive doubled letters (e.g. "paathi" -> "pathi",
    // "vaanam" -> "vanam") only for tokens >= 4 chars whose collapsed form >= 3 chars.
    if (t.length >= 4) {
      final collapsed = t.replaceAllMapped(
        RegExp(r'([\p{L}\p{N}])\1+', unicode: true),
        (m) => m.group(1)!,
      );
      if (collapsed.length >= 3) {
        keys.add(collapsed);
        if (t.endsWith('aan') && collapsed.endsWith('an')) {
          keys.add('${collapsed.substring(0, collapsed.length - 1)}a');
        }
      }
    }

    return keys;
  }

  static bool _matchesToken(
    String token,
    Set<String> candidateTokens,
    String candidateCombined,
  ) {
    if (candidateTokens.contains(token)) return true;
    final tokenKeys = transliterationKeys(token);
    for (final cand in candidateTokens) {
      final candKeys = transliterationKeys(cand);
      if (tokenKeys.any(candKeys.contains)) {
        return true;
      }
    }
    if (token.length <= 3) {
      // Short tokens must match as whole tokens to avoid accidental sub-word matches
      return false;
    }
    // For longer tokens (>= 4 chars), allow word-boundary matching
    final pattern = RegExp(
      r'(^|\s|[^\p{L}\p{N}\p{M}])' +
          RegExp.escape(token) +
          r'($|\s|[^\p{L}\p{N}\p{M}])',
      unicode: true,
    );
    return pattern.hasMatch(candidateCombined);
  }

  /// Known artist spelling variants and canonical aliases for multilingual/global artists.
  static final Map<String, Set<String>> _artistAliasGroups = {
    'arrahman': {
      'a r rahman',
      'ar rahman',
      'a r rehman',
      'ar rehman',
      'rahman'
    },
    'anirudhravichander': {'anirudh ravichander', 'anirudh'},
    'yuvanshankarraja': {'yuvan shankar raja', 'yuvan', 'ysr'},
    'spbalasubrahmanyam': {
      's p balasubrahmanyam',
      'sp balasubrahmanyam',
      'spb'
    },
    'ilaiyaraaja': {'ilaiyaraaja', 'ilaiyaraja', 'ilayaraja'},
    'saiabhyankkar': {'sai abhyankkar', 'sai abhyankar'},
    'santhoshnarayanan': {'santhosh narayanan', 'sana'},
    'arijitsingh': {'arijit singh', 'arijit'},
    'shreyaghoshal': {'shreya ghoshal'},
    'harrisjayaraj': {'harris jayaraj'},
    'gvprakashkumar': {'g v prakash kumar', 'gv prakash kumar', 'gv prakash'},
  };

  static String _normArtistKey(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'\s*-\s*topic\s*$', caseSensitive: false), '')
      .replaceAll(RegExp(r'[\.\,\-\–\—]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static String _compactAlphaNum(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  static Set<String> expandArtistAliases(String artistName) {
    final norm = _normArtistKey(artistName);
    final compact = _compactAlphaNum(norm);
    final result = <String>{
      if (norm.isNotEmpty) norm,
      if (compact.isNotEmpty) compact
    };
    for (final entry in _artistAliasGroups.entries) {
      if (entry.key == compact ||
          entry.value.any((a) => a == norm || _compactAlphaNum(a) == compact)) {
        result.add(entry.key);
        result.addAll(entry.value);
        result.addAll(entry.value.map(_compactAlphaNum));
      }
    }
    return result;
  }

  /// Splits featured and collaborating artist strings into individual credited artists,
  /// always keeping the intact full artist name first (preserves bands like "She & Him").
  static List<String> extractCreditedArtists(String artistField) {
    final clean = artistField.trim();
    if (clean.isEmpty) return const [];
    final credits = <String>[clean];
    final splitRegex = RegExp(
      r'\s*(?:,|/|&|\||\bfeat\.?\b|\bft\.?\b|\bfeaturing\b|\bwith\b|\bx\b|\bvs\.?)\s*',
      caseSensitive: false,
    );
    if (splitRegex.hasMatch(clean)) {
      for (final part in clean.split(splitRegex)) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty && !credits.contains(trimmed)) {
          credits.add(trimmed);
        }
      }
    }
    return credits;
  }

  /// Checks whether [candidateArtistField] matches [expectedArtist] via exact match,
  /// normalized match, alias expansion, or collaborating/featured credit match.
  static bool matchesCreditedArtist(
    String candidateArtistField,
    String expectedArtist, {
    String? titleOrCredits,
  }) {
    final cleanExpected = _normArtistKey(expectedArtist);
    if (cleanExpected.isEmpty) return false;
    final expectedAliases = expandArtistAliases(cleanExpected);

    final creditedList = extractCreditedArtists(candidateArtistField);
    for (final credit in creditedList) {
      final normCredit = _normArtistKey(credit);
      final compactCredit = _compactAlphaNum(normCredit);
      if (normCredit.isEmpty) continue;
      if (expectedAliases.contains(normCredit) ||
          (compactCredit.isNotEmpty &&
              expectedAliases.contains(compactCredit))) {
        return true;
      }
    }

    // Check explicit featured/collaboration credits embedded in song title
    // (e.g. "Song (feat. ArtistName)", "Song - Movie | Music: ArtistName")
    if (titleOrCredits != null && titleOrCredits.trim().isNotEmpty) {
      final titleNorm = _normArtistKey(titleOrCredits);
      for (final alias in expectedAliases) {
        if (alias.length < 3) continue;
        final escaped = RegExp.escape(alias);
        final creditContextPattern = RegExp(
          '(?:\\b(?:feat\\.?|ft\\.?|featuring|with|by|music|composer|singer|singers)\\b[^\\|\\)]*\\b$escaped\\b|\\b$escaped\\b\\s*(?:,|&|x|\\|))',
          caseSensitive: false,
        );
        if (creditContextPattern.hasMatch(titleNorm)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Evaluates whether [candidate] has sufficient semantic relevance to [query],
  /// enforcing artist relevance whenever [expectedArtist] is targeted by the query.
  static bool isCandidateRelevant(
    YouTubeVideo candidate, {
    required String query,
    QueryIntent? intent,
    String? expectedArtist,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return true;

    final queryTokens = _tokenize(cleanQuery);
    if (queryTokens.isEmpty) return true;

    // Filter query tokens into core tokens (excluding generic collection words)
    final coreTokens =
        queryTokens.where((t) => !collectionStopWords.contains(t)).toList();
    final effectiveTokens = coreTokens.isNotEmpty ? coreTokens : queryTokens;

    final candidateTitle =
        (candidate.canonicalTitle ?? candidate.title).toLowerCase();
    final candidateArtist =
        (candidate.canonicalArtist ?? candidate.channelTitle).toLowerCase();
    final candidateRawArtist =
        (candidate.rawChannelTitle ?? candidate.channelTitle).toLowerCase();
    final candidateRawTitle =
        (candidate.rawTitle ?? candidate.title).toLowerCase();
    final candidateAlbum = (candidate.albumName ?? '').toLowerCase();

    // Strict artist gate when caller identified an explicit artist target for this query:
    // Matching title tokens alone cannot override an unrelated artist.
    if (expectedArtist != null && expectedArtist.trim().isNotEmpty) {
      final artistMatched = matchesCreditedArtist(
            candidateArtist,
            expectedArtist,
            titleOrCredits: candidateRawTitle,
          ) ||
          (candidateRawArtist != candidateArtist &&
              matchesCreditedArtist(
                candidateRawArtist,
                expectedArtist,
                titleOrCredits: candidateRawTitle,
              ));
      if (!artistMatched) {
        return false;
      }
    }

    final candidateTokens = {
      ..._tokenize(candidateTitle),
      ..._tokenize(candidateArtist),
      ..._tokenize(candidateAlbum),
    };

    final candidateCombined =
        '$candidateTitle $candidateArtist $candidateAlbum';

    // 1. Exact or substring match of entire query in title/artist
    if (candidateTitle.contains(cleanQuery) ||
        candidateArtist.contains(cleanQuery)) {
      return true;
    }

    // 2. Exact match of core entity
    final coreEntity = extractCoreEntity(cleanQuery);
    if (coreEntity.isNotEmpty &&
        (candidateTitle.contains(coreEntity) ||
            candidateArtist.contains(coreEntity))) {
      return true;
    }

    // 3. Token containment check
    int matchCount = 0;
    for (final token in effectiveTokens) {
      if (_matchesToken(token, candidateTokens, candidateCombined)) {
        matchCount++;
      }
    }

    // If query has language marker (e.g. "tamil"), require strong coverage of non-language tokens
    final queryHasLanguage =
        effectiveTokens.any((t) => languageMarkers.contains(t));
    if (queryHasLanguage && effectiveTokens.length > 1) {
      final nonLangTokens =
          effectiveTokens.where((t) => !languageMarkers.contains(t)).toList();
      if (nonLangTokens.isEmpty) return true;
      int nonLangMatches = 0;
      for (final t in nonLangTokens) {
        if (_matchesToken(t, candidateTokens, candidateCombined)) {
          nonLangMatches++;
        }
      }
      final required =
          nonLangTokens.length == 1 ? 1 : (nonLangTokens.length * 0.65).ceil();
      return nonLangMatches >= required;
    }

    // For single-word queries, direct token match or substring match required
    if (effectiveTokens.length == 1) {
      final singleToken = effectiveTokens.first;
      return _matchesToken(singleToken, candidateTokens, candidateCombined) ||
          candidateTitle.contains(singleToken) ||
          candidateArtist.contains(singleToken);
    }

    // For multi-token queries (>= 2 effective tokens):
    if (effectiveTokens.length >= 2) {
      // Deduplicate repeated chorus words (e.g. "pathi nee pathi naa" -> ['pathi', 'nee', 'naa'])
      final uniqueTokens = <String>[];
      for (final t in effectiveTokens) {
        if (!uniqueTokens.contains(t)) {
          uniqueTokens.add(t);
        }
      }
      int uniqueMatchCount = 0;
      for (final t in uniqueTokens) {
        if (_matchesToken(t, candidateTokens, candidateCombined)) {
          uniqueMatchCount++;
        }
      }

      if (uniqueTokens.length == 1) {
        return uniqueMatchCount >= 1;
      }

      final firstToken = uniqueTokens.first;
      final hasFirstToken =
          _matchesToken(firstToken, candidateTokens, candidateCombined);

      // If the candidate has 100% full query coverage, it is unconditionally relevant
      if (uniqueMatchCount >= uniqueTokens.length) {
        return true;
      }

      // If missing the leading entity token, reject unless it's a generic collection stopword
      // or the candidate explicitly matches expectedArtist / alias
      if (!hasFirstToken && !collectionStopWords.contains(firstToken)) {
        return false;
      }

      // Require >= 65% of effective tokens (prevents 1-of-2 partial token collisions)
      return uniqueMatchCount >= (uniqueTokens.length * 0.65).ceil();
    }

    return matchCount >= (effectiveTokens.length / 2).ceil();
  }

  /// Checks whether [candidate] has 100% token coverage for the effective tokens in [query]
  /// across its title, artist, or album.
  static bool hasFullQueryCoverage(
    YouTubeVideo candidate, {
    required String query,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return true;
    final queryTokens = _tokenize(cleanQuery);
    final coreTokens =
        queryTokens.where((t) => !collectionStopWords.contains(t)).toList();
    final effectiveTokens = coreTokens.isNotEmpty ? coreTokens : queryTokens;
    if (effectiveTokens.isEmpty) return true;

    final candidateTitle =
        (candidate.canonicalTitle ?? candidate.title).toLowerCase();
    final candidateArtist =
        (candidate.canonicalArtist ?? candidate.channelTitle).toLowerCase();
    final candidateAlbum = (candidate.albumName ?? '').toLowerCase();
    final candidateCombined =
        '$candidateTitle $candidateArtist $candidateAlbum';
    final candidateTokens = {
      ..._tokenize(candidateTitle),
      ..._tokenize(candidateArtist),
      ..._tokenize(candidateAlbum),
    };

    for (final token in effectiveTokens) {
      if (!_matchesToken(token, candidateTokens, candidateCombined)) {
        return false;
      }
    }
    return true;
  }

  /// Validates whether a candidate artist is genuinely relevant to the query.
  /// Avoids raw short-substring collisions while supporting full names, multi-artist
  /// credits, and known artist aliases.
  static bool isArtistRelevant(String artistName, {required String query}) {
    final cleanQuery = _normArtistKey(query);
    final artistNorm = _normArtistKey(artistName);

    if (cleanQuery.isEmpty || artistNorm.isEmpty) return false;
    if (matchesCreditedArtist(artistName, cleanQuery)) return true;

    final queryTokens = _tokenize(cleanQuery);
    final coreTokens =
        queryTokens.where((t) => !collectionStopWords.contains(t)).toList();
    final effectiveTokens = coreTokens.isNotEmpty ? coreTokens : queryTokens;
    if (effectiveTokens.isEmpty) return false;

    final artistTokens = _tokenize(artistNorm).toSet();

    // Check exact/alias token match when query is a single word (never substring/prefix collision like "Aria" -> "Ariana")
    if (effectiveTokens.length == 1) {
      final qTok = effectiveTokens.first;
      return artistTokens.contains(qTok);
    }

    // For multi-word queries (e.g. "Lana Del Rey"), require all core tokens
    // to appear in artistTokens (or query itself contains the artist's full name)
    final allInArtist = effectiveTokens.every((t) => artistTokens.contains(t));
    if (allInArtist) return true;

    final artistCore = artistTokens.where((t) => t.length >= 2).toList();
    if (artistCore.isNotEmpty &&
        artistCore.every((t) => effectiveTokens.contains(t))) {
      return true;
    }

    return false;
  }

  /// Identifies if [query] directly targets a specific verified artist from [artists]
  /// (or curated catalog), returning that canonical artist name if matched.
  static String? detectTargetedArtist(
    String query,
    List<ArtistModel> artists,
  ) {
    final cleanQuery = _normArtistKey(query);
    if (cleanQuery.isEmpty || cleanQuery.length < 3) return null;
    if (isCollectionQuery(cleanQuery)) return null;

    final queryAliases = expandArtistAliases(cleanQuery);
    for (final artist in artists) {
      final normArtist = _normArtistKey(artist.name);
      final compactArtist = _compactAlphaNum(normArtist);
      if (queryAliases.contains(normArtist) ||
          (compactArtist.isNotEmpty && queryAliases.contains(compactArtist))) {
        return artist.name;
      }
    }
    return null;
  }
}
