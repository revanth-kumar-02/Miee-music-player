import 'indic_transliterator.dart';
import 'lyrics_title_normalizer.dart';

/// Represents a targeted query candidate for lyrics providers (such as LRCLIB).
class SearchCandidate {
  final String trackName;
  final String artistName;
  final String? albumName;
  final String description;
  final String originalQueryArtist;
  final String? languageTag;
  final String? versionModifier;

  const SearchCandidate({
    required this.trackName,
    this.artistName = '',
    this.albumName,
    required this.description,
    this.originalQueryArtist = '',
    this.languageTag,
    this.versionModifier,
  });

  bool get isTitleOnlyQuery => artistName.isEmpty;

  @override
  String toString() =>
      '$description: "$trackName" (artist: "$artistName", origArtist: "$originalQueryArtist", album: "$albumName", lang: "$languageTag", ver: "$versionModifier")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchCandidate &&
          runtimeType == other.runtimeType &&
          trackName.toLowerCase() == other.trackName.toLowerCase() &&
          artistName.toLowerCase() == other.artistName.toLowerCase() &&
          (albumName ?? '').toLowerCase() == (other.albumName ?? '').toLowerCase() &&
          (languageTag ?? '').toLowerCase() == (other.languageTag ?? '').toLowerCase() &&
          (versionModifier ?? '').toLowerCase() == (other.versionModifier ?? '').toLowerCase();

  @override
  int get hashCode =>
      trackName.toLowerCase().hashCode ^
      artistName.toLowerCase().hashCode ^
      (albumName ?? '').toLowerCase().hashCode ^
      (languageTag ?? '').toLowerCase().hashCode ^
      (versionModifier ?? '').toLowerCase().hashCode;
}

/// Universal, multi-stage language-aware query candidate builder for song lyrics.
///
/// Implements the structured multi-stage matching sequence:
/// 1. Exact original title + composite artist.
/// 2. Normalized title + primary artist (extracted from composite artist strings).
/// 3. Acronym-normalized title (e.g. "O.M" -> "OM") + primary artist.
/// 4. Normalized title + album + artist.
/// 5. Alternative title variants (parenthetical subtitles, clauses).
/// 6. Indic script transliterated title fallbacks.
/// 7. Title-only queries with strict preserved artist verification.
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
    String? album,
    String? rawTitle,
  }) {
    final candidates = <SearchCandidate>[];
    final seen = <String>{};

    final langTag = LyricsTitleNormalizer.extractLanguageTag(rawTitle ?? title);
    final versionMod = LyricsTitleNormalizer.extractVersionModifier(rawTitle ?? title);

    // Determine if artist is a known record label or uploader channel
    final isChannel = _isRecordLabelOrChannel(artist);
    final cleanArtist = isChannel ? '' : _cleanArtistName(artist);
    final cleanAlbum = album?.trim().isNotEmpty == true ? album!.trim() : null;

    // Split composite artist strings to find primary artist
    final splitArtists = cleanArtist.isNotEmpty ? LyricsTitleNormalizer.splitArtists(cleanArtist) : <String>[];
    final primaryArtist = splitArtists.isNotEmpty ? splitArtists.first : cleanArtist;

    void addCandidate(
      String t,
      String a,
      String desc, {
      String? alb,
    }) {
      final cleanT = LyricsTitleNormalizer.normalizeWhitespace(LyricsTitleNormalizer.stripInvisibleChars(t));
      final cleanA = LyricsTitleNormalizer.normalizeWhitespace(LyricsTitleNormalizer.stripInvisibleChars(a));
      final cleanAlb = alb != null
          ? LyricsTitleNormalizer.normalizeWhitespace(LyricsTitleNormalizer.stripInvisibleChars(alb))
          : null;
      if (cleanT.isEmpty) return;

      final key = '${cleanT.toLowerCase()}|${cleanA.toLowerCase()}|${(cleanAlb ?? '').toLowerCase()}';
      if (!seen.add(key)) return;

      candidates.add(SearchCandidate(
        trackName: cleanT,
        artistName: cleanA,
        albumName: cleanAlb?.isNotEmpty == true ? cleanAlb : null,
        description: desc,
        originalQueryArtist: cleanArtist,
        languageTag: langTag,
        versionModifier: versionMod,
      ));
    }

    // Stage 1: Exact original title + composite artist
    final rawTrimmedTitle = LyricsTitleNormalizer.normalizeWhitespace(title);
    if (cleanArtist.isNotEmpty) {
      addCandidate(rawTrimmedTitle, cleanArtist, 'Stage 1: Exact original title + composite artist');
    }

    // Stage 2: Normalized title + primary artist
    final normalizedTitle = LyricsTitleNormalizer.normalize(title);
    if (primaryArtist.isNotEmpty) {
      addCandidate(normalizedTitle, primaryArtist, 'Stage 2: Normalized title + primary artist');
      if (cleanArtist != primaryArtist) {
        addCandidate(normalizedTitle, cleanArtist, 'Stage 2b: Normalized title + full composite artist');
      }
    }

    // Stage 3: Acronym-normalized title (e.g. "O.M Special Duty" -> "OM Special Duty")
    final acronymTitle = LyricsTitleNormalizer.normalizeAcronyms(normalizedTitle);
    if (acronymTitle.toLowerCase() != normalizedTitle.toLowerCase()) {
      if (primaryArtist.isNotEmpty) {
        addCandidate(acronymTitle, primaryArtist, 'Stage 3: Acronym normalized title + primary artist');
      }
      addCandidate(acronymTitle, '', 'Stage 3b: Acronym normalized title query');
    }

    // Stage 4: Normalized title + album + primary artist
    if (cleanAlbum != null && cleanAlbum.isNotEmpty && primaryArtist.isNotEmpty) {
      addCandidate(
        normalizedTitle,
        primaryArtist,
        'Stage 4: Normalized title + album + artist',
        alb: cleanAlbum,
      );
    }

    // Stage 5: Alternative title variants (parenthetical subtitles, clauses)
    final variants = LyricsTitleNormalizer.extractVariants(title);
    for (final variant in variants) {
      if (variant.toLowerCase() != normalizedTitle.toLowerCase() &&
          variant.toLowerCase() != rawTrimmedTitle.toLowerCase() &&
          variant.toLowerCase() != acronymTitle.toLowerCase()) {
        if (primaryArtist.isNotEmpty) {
          addCandidate(variant, primaryArtist, 'Stage 5: Alternative title variant + primary artist');
        }
        addCandidate(variant, '', 'Stage 5b: Alternative title variant query');
      }
    }

    // Stage 6: Indic transliteration fallbacks (LRCLIB indexes Indian tracks primarily by Latin names)
    if (IndicTransliterator.hasIndicScript(normalizedTitle)) {
      final transliterated = IndicTransliterator.transliterate(normalizedTitle);
      if (transliterated.isNotEmpty && transliterated.toLowerCase() != normalizedTitle.toLowerCase()) {
        if (primaryArtist.isNotEmpty) {
          addCandidate(transliterated, primaryArtist, 'Stage 6: Transliterated title + primary artist');
        }
        addCandidate(transliterated, '', 'Stage 6b: Transliterated title query');
      }
    }

    // Stage 7: Clean title only (crucial fallback, still carries originalQueryArtist for verification)
    addCandidate(normalizedTitle, '', 'Stage 7: Normalized title query (with artist verification)');

    // Stage 8: Raw title candidate if provided and distinct
    if (rawTitle != null && rawTitle.trim().isNotEmpty && rawTitle != title) {
      final normRaw = LyricsTitleNormalizer.normalize(rawTitle);
      if (normRaw.isNotEmpty &&
          normRaw.toLowerCase() != normalizedTitle.toLowerCase() &&
          normRaw.toLowerCase() != acronymTitle.toLowerCase()) {
        if (primaryArtist.isNotEmpty) {
          addCandidate(normRaw, primaryArtist, 'Stage 8: Raw title + primary artist');
        }
        addCandidate(normRaw, '', 'Stage 8b: Raw title query');
      }
    }

    return candidates.take(10).toList();
  }

  static String _cleanArtistName(String artist) {
    var a = LyricsTitleNormalizer.stripInvisibleChars(artist);
    a = a.replaceAll(RegExp(r'\b(topic|vevo|official)\b', caseSensitive: false), '');
    a = a.replaceAll(RegExp(r'\s+'), ' ').trim();
    return a;
  }

  static bool _isRecordLabelOrChannel(String artist) {
    final lower = artist.toLowerCase();
    return _channelKeywords.any((kw) => lower.contains(kw));
  }
}
