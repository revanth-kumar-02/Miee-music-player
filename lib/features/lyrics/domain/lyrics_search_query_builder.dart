import 'indic_transliterator.dart';

/// Represents a targeted query candidate for lyrics providers (such as LRCLIB).
class SearchCandidate {
  final String trackName;
  final String artistName;
  final String description;

  const SearchCandidate({
    required this.trackName,
    this.artistName = '',
    required this.description,
  });

  @override
  String toString() => '$description: "$trackName" (artist: "$artistName")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchCandidate &&
          runtimeType == other.runtimeType &&
          trackName.toLowerCase() == other.trackName.toLowerCase() &&
          artistName.toLowerCase() == other.artistName.toLowerCase();

  @override
  int get hashCode => trackName.toLowerCase().hashCode ^ artistName.toLowerCase().hashCode;
}

/// Universal, language-aware query candidate builder for song lyrics.
///
/// Handles:
/// - English, Tamil, Telugu, Malayalam, Hindi, Kannada, and other multilingual tracks.
/// - Bilingual parentheses (e.g. "Kannaana Kanney (கண்ணான கண்ணே)").
/// - Delimited clauses (e.g. "Arabic Kuthu - Video Song | Beast | Sun TV").
/// - Uploader channels and record labels filtering (e.g. "Sony Music South", "Sun TV").
/// - Phonetic Indic transliteration fallbacks for native script titles.
class LyricsSearchQueryBuilder {
  static const _channelKeywords = [
    'sony music',
    'sun tv',
    'think music',
    't-series',
    'tseries',
    'saregama',
    'lahari music',
    'zee music',
    'aditya music',
    'speed audio',
    'muzik247',
    'tips official',
    'yrf',
    'times music',
    'topic',
    'vevo',
    'official channel',
    'records',
    'recordings',
  ];

  static List<SearchCandidate> buildCandidates({
    required String title,
    required String artist,
    String? rawTitle,
  }) {
    final candidates = <SearchCandidate>[];
    final seen = <String>{};

    void addCandidate(String t, String a, String desc) {
      final cleanT = _normalizeWhitespace(_stripInvisibleChars(t));
      final cleanA = _normalizeWhitespace(_stripInvisibleChars(a));
      if (cleanT.isEmpty) return;

      final key = '${cleanT.toLowerCase()}|${cleanA.toLowerCase()}';
      if (!seen.add(key)) return;

      candidates.add(SearchCandidate(
        trackName: cleanT,
        artistName: cleanA,
        description: desc,
      ));
    }

    // Determine if artist is a known record label or uploader channel
    final isChannel = _isRecordLabelOrChannel(artist);
    final cleanArtist = isChannel ? '' : _cleanArtistName(artist);

    // 1. Check for bilingual or alternate title inside parentheses: e.g. "Song (பாடல்)" or "பாடல் (Song)"
    String outerTitle = title;
    final parenTitles = <String>[];

    final parenRegex = RegExp(r'\(([^)]+)\)|\[([^\]]+)\]');
    final matches = parenRegex.allMatches(title);
    for (final m in matches) {
      final inside = (m.group(1) ?? m.group(2) ?? '').trim();
      if (inside.isNotEmpty && !_isVideoNoise(inside)) {
        // If it starts with 'From "' or 'from "', extract movie context
        final fromMatch = RegExp(r'^(?:from\s+["\x27]?)([^"\x27\)]+)', caseSensitive: false).firstMatch(inside);
        if (fromMatch == null) {
          parenTitles.add(_stripVideoNoise(inside));
        }
      }
    }

    // Strip bracketed text to get clean outer title
    outerTitle = outerTitle.replaceAll(parenRegex, ' ');
    outerTitle = _stripVideoNoise(outerTitle);

    // 2. Check for multi-clause title (e.g. "Song - Video | Movie | Singer")
    String? firstClause;
    if (outerTitle.contains('|') || outerTitle.contains('•') || outerTitle.contains('//') || outerTitle.contains(' - ') || outerTitle.contains(' – ')) {
      final clauses = outerTitle
          .split(RegExp(r'(\||•|\/\/|\s+[-–—]\s+)'))
          .map(_stripVideoNoise)
          .where((s) => s.isNotEmpty && !_isVideoNoise(s))
          .toList();

      if (clauses.isNotEmpty) {
        firstClause = clauses.first;
      }
    }

    final primarySongTitle = (firstClause != null && firstClause.isNotEmpty)
        ? firstClause
        : (outerTitle.isNotEmpty ? outerTitle : _stripVideoNoise(title));

    // Priority 1: Primary song title with verified artist
    if (cleanArtist.isNotEmpty) {
      addCandidate(primarySongTitle, cleanArtist, 'Primary (title + artist)');
    }

    // Priority 2: Primary song title alone (crucial for YouTube tracks where artist tag is a channel/label)
    addCandidate(primarySongTitle, '', 'Clean title only');

    // Priority 3: Parenthetical alternate title (e.g. Romanized version of native title or vice-versa)
    for (final alt in parenTitles) {
      if (cleanArtist.isNotEmpty) {
        addCandidate(alt, cleanArtist, 'Parenthetical title + artist');
      }
      addCandidate(alt, '', 'Parenthetical title only');
    }

    // Priority 4: If title is in native Indic script (Tamil, Telugu, Malayalam, Hindi, Kannada, etc.),
    // generate phonetic transliterated Latin title (LRCLIB indexes Indian tracks primarily by Latin names)
    if (IndicTransliterator.hasIndicScript(primarySongTitle)) {
      final transliterated = IndicTransliterator.transliterate(primarySongTitle);
      if (transliterated.isNotEmpty && transliterated != primarySongTitle) {
        if (cleanArtist.isNotEmpty) {
          addCandidate(transliterated, cleanArtist, 'Transliterated title + artist');
        }
        addCandidate(transliterated, '', 'Transliterated title only');
      }
    }

    // Priority 5: If rawTitle was provided and differs meaningfully from current title
    if (rawTitle != null && rawTitle.trim().isNotEmpty && rawTitle != title) {
      final cleanRaw = _stripVideoNoise(rawTitle.replaceAll(parenRegex, ' '));
      if (cleanRaw.isNotEmpty && cleanRaw != primarySongTitle) {
        addCandidate(cleanRaw, cleanArtist, 'Raw title candidate');
      }
    }

    return candidates.take(6).toList();
  }

  static String _cleanArtistName(String artist) {
    var a = _stripInvisibleChars(artist);
    a = a.replaceAll(RegExp(r'\b(topic|vevo|official)\b', caseSensitive: false), '');
    a = a.replaceAll(RegExp(r'\s+'), ' ').trim();
    return a;
  }

  static bool _isRecordLabelOrChannel(String artist) {
    final lower = artist.toLowerCase();
    return _channelKeywords.any((kw) => lower.contains(kw));
  }

  static bool _isVideoNoise(String s) {
    final lower = s.toLowerCase();
    return RegExp(
      r'\b(official\s+music\s+video|official\s+video|official\s+audio|official|music\s+video|video|audio|lyric\s+video|lyrics|lyrical|visualizer|mv|hd|4k|4k\s+uhd|remastered|full\s+song|video\s+song|audio\s+song|full\s+video|teaser|trailer|promo)\b',
      caseSensitive: false,
    ).hasMatch(lower);
  }

  static String _stripVideoNoise(String title) {
    var t = _stripInvisibleChars(title);
    t = t.replaceAll(
      RegExp(
        r'\b(official\s+music\s+video|official\s+video|official\s+audio|music\s+video|lyric\s+video|lyrics|lyrical|visualizer|mv|hd|4k|4k\s+uhd|remastered|full\s+song|video\s+song|audio\s+song|full\s+video\s+song|full\s+video)\b',
        caseSensitive: false,
      ),
      '',
    );
    // Strip trailing/leading punctuation, hyphens, and delimiters
    t = t.replaceAll(RegExp(r'^[\s\-\–\—\|\:\/\•]+|[\s\-\–\—\|\:\/\•]+$'), '');
    t = _normalizeWhitespace(t);
    return t;
  }

  static String _stripInvisibleChars(String s) {
    return s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
  }

  static String _normalizeWhitespace(String s) {
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
