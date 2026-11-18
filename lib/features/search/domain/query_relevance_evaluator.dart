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
  static List<String> _tokenize(String input) {
    final words = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
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

  /// Evaluates whether [candidate] has sufficient semantic relevance to [query].
  ///
  /// Returns `true` if the candidate matches the query's primary entities, or `false`
  /// if it is an unrelated fallback result (e.g., partial-keyword catalog hits).
  static bool isCandidateRelevant(
    YouTubeVideo candidate, {
    required String query,
    QueryIntent? intent,
  }) {
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return true;

    final queryTokens = _tokenize(cleanQuery);
    if (queryTokens.isEmpty) return true;

    // Filter query tokens into core tokens (excluding generic collection words)
    final coreTokens = queryTokens.where((t) => !collectionStopWords.contains(t)).toList();
    final effectiveTokens = coreTokens.isNotEmpty ? coreTokens : queryTokens;

    final candidateTitle = (candidate.canonicalTitle ?? candidate.title).toLowerCase();
    final candidateArtist = (candidate.canonicalArtist ?? candidate.channelTitle).toLowerCase();
    final candidateAlbum = (candidate.albumName ?? '').toLowerCase();

    final candidateTokens = {
      ..._tokenize(candidateTitle),
      ..._tokenize(candidateArtist),
      ..._tokenize(candidateAlbum),
    };

    final candidateCombined = '$candidateTitle $candidateArtist $candidateAlbum';

    // 1. Exact or substring match of entire query in title/artist
    if (candidateTitle.contains(cleanQuery) || candidateArtist.contains(cleanQuery)) {
      return true;
    }

    // 2. Exact match of core entity
    final coreEntity = extractCoreEntity(cleanQuery);
    if (coreEntity.isNotEmpty &&
        (candidateTitle.contains(coreEntity) || candidateArtist.contains(coreEntity))) {
      return true;
    }

    // 3. Token containment check
    // If the query has multiple core tokens (e.g. "om", "tamil"), at least 1 significant core token
    // must be present in the candidate. If language marker is present in query, candidate should not
    // completely contradict it.
    int matchCount = 0;
    for (final token in effectiveTokens) {
      if (candidateTokens.contains(token) || candidateCombined.contains(token)) {
        matchCount++;
      }
    }

    // If query has language marker (e.g. "tamil"), check if candidate explicitly contains it
    // or if the core entity matches.
    final queryHasLanguage = effectiveTokens.any((t) => languageMarkers.contains(t));
    if (queryHasLanguage && effectiveTokens.length > 1) {
      // Must match at least the non-language entity token (e.g. "om")
      final nonLangTokens = effectiveTokens.where((t) => !languageMarkers.contains(t)).toList();
      final hasNonLangMatch = nonLangTokens.any((t) =>
          candidateTokens.contains(t) || candidateCombined.contains(t));

      if (!hasNonLangMatch) {
        return false;
      }
      return true;
    }

    // For single-word queries, direct token match or substring match required
    if (effectiveTokens.length == 1) {
      final singleToken = effectiveTokens.first;
      return candidateTokens.contains(singleToken) ||
          candidateTitle.contains(singleToken) ||
          candidateArtist.contains(singleToken);
    }

    // For multi-token queries (>= 2 effective tokens):
    // If the query contains an entity prefix/subject (the first core token),
    // and the candidate matches only trailing words while COMPLETELY missing the entity prefix
    // (e.g. query "om first strike" matching "first strike" by "Luis M" but missing "om"),
    // the candidate is an unrelated catalogue homonym and must be rejected.
    if (effectiveTokens.length >= 2) {
      final firstToken = effectiveTokens.first;
      final hasFirstToken =
          candidateTokens.contains(firstToken) || candidateCombined.contains(firstToken);

      // If the candidate has 100% full query coverage, it is unconditionally relevant
      if (matchCount >= effectiveTokens.length) {
        return true;
      }

      // If missing the leading entity token, reject unless it's a generic collection stopword
      if (!hasFirstToken && !collectionStopWords.contains(firstToken)) {
        return false;
      }

      // Require at least 50% of effective tokens
      return matchCount >= (effectiveTokens.length / 2).ceil();
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
      if (!candidateTokens.contains(token) &&
          !candidateCombined.contains(token)) {
        return false;
      }
    }
    return true;
  }

  /// Validates whether a candidate artist is genuinely relevant to the query.
  static bool isArtistRelevant(String artistName, {required String query}) {
    final cleanQuery = query.trim().toLowerCase();
    final artistLower = artistName.trim().toLowerCase();

    if (cleanQuery.isEmpty || artistLower.isEmpty) return false;
    if (artistLower.contains(cleanQuery) || cleanQuery.contains(artistLower)) return true;

    final queryTokens = _tokenize(cleanQuery);
    final coreTokens = queryTokens.where((t) => !collectionStopWords.contains(t)).toList();
    final artistTokens = _tokenize(artistLower);

    for (final t in coreTokens) {
      if (artistTokens.contains(t)) return true;
    }
    return false;
  }
}
