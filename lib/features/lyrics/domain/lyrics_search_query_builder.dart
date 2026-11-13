import 'indic_transliterator.dart';
import 'lyrics_title_normalizer.dart';

/// Represents a targeted query candidate for lyrics providers (such as LRCLIB).
class SearchCandidate {
  final String trackName;
  final String artistName;
  final String? albumName;
  final String description;

  const SearchCandidate({
    required this.trackName,
    this.artistName = '',
    this.albumName,
    required this.description,
  });

  @override
  String toString() => '$description: "$trackName" (artist: "$artistName", album: "$albumName")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchCandidate &&
          runtimeType == other.runtimeType &&
          trackName.toLowerCase() == other.trackName.toLowerCase() &&
          artistName.toLowerCase() == other.artistName.toLowerCase() &&
          (albumName ?? '').toLowerCase() == (other.albumName ?? '').toLowerCase();

  @override
  int get hashCode =>
      trackName.toLowerCase().hashCode ^
      artistName.toLowerCase().hashCode ^
      (albumName ?? '').toLowerCase().hashCode;
}

/// Universal, multi-stage language-aware query candidate builder for song lyrics.
///
/// Implements the structured multi-stage matching sequence:
/// 1. Exact original title + artist.
/// 2. Normalized title + artist (stripping resolution tags like 8K/4K/HD, video tags, etc.).
/// 3. Normalized title + album + artist.
/// 4. Alternative title variants (e.g. parenthetical titles, multi-clause titles).
/// 5. Clean title only / Transliterated title fallbacks.
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

    void addCandidate(String t, String a, String desc, {String? alb}) {
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
      ));
    }

    // Determine if artist is a known record label or uploader channel
    final isChannel = _isRecordLabelOrChannel(artist);
    final cleanArtist = isChannel ? '' : _cleanArtistName(artist);
    final cleanAlbum = album?.trim().isNotEmpty == true ? album!.trim() : null;

    // Stage 1: Exact original title + artist
    final rawTrimmedTitle = LyricsTitleNormalizer.normalizeWhitespace(title);
    if (cleanArtist.isNotEmpty) {
      addCandidate(rawTrimmedTitle, cleanArtist, 'Stage 1: Exact original title + artist');
    }

    // Stage 2: Normalized title + artist
    final normalizedTitle = LyricsTitleNormalizer.normalize(title);
    if (cleanArtist.isNotEmpty && normalizedTitle.toLowerCase() != rawTrimmedTitle.toLowerCase()) {
      addCandidate(normalizedTitle, cleanArtist, 'Stage 2: Normalized title + artist');
    }

    // Stage 3: Normalized title + album + artist
    if (cleanAlbum != null && cleanAlbum.isNotEmpty && cleanArtist.isNotEmpty) {
      addCandidate(
        normalizedTitle,
        cleanArtist,
        'Stage 3: Normalized title + album + artist',
        alb: cleanAlbum,
      );
    }

    // Stage 4: Alternative title variants (parenthetical, clauses)
    final variants = LyricsTitleNormalizer.extractVariants(title);
    for (final variant in variants) {
      if (variant.toLowerCase() != normalizedTitle.toLowerCase() &&
          variant.toLowerCase() != rawTrimmedTitle.toLowerCase()) {
        if (cleanArtist.isNotEmpty) {
          addCandidate(variant, cleanArtist, 'Stage 4: Alternative title variant + artist');
        }
        addCandidate(variant, '', 'Stage 4: Alternative title variant only');
      }
    }

    // Stage 5: Indic transliteration fallbacks (LRCLIB indexes Indian tracks primarily by Latin names)
    if (IndicTransliterator.hasIndicScript(normalizedTitle)) {
      final transliterated = IndicTransliterator.transliterate(normalizedTitle);
      if (transliterated.isNotEmpty && transliterated.toLowerCase() != normalizedTitle.toLowerCase()) {
        if (cleanArtist.isNotEmpty) {
          addCandidate(transliterated, cleanArtist, 'Stage 5: Transliterated title + artist');
        }
        addCandidate(transliterated, '', 'Stage 5: Transliterated title only');
      }
    }

    // Stage 6: Clean title only (crucial when artist is a channel or uploader)
    addCandidate(normalizedTitle, '', 'Stage 6: Normalized title only');

    // Stage 7: Raw title candidate if provided
    if (rawTitle != null && rawTitle.trim().isNotEmpty && rawTitle != title) {
      final normRaw = LyricsTitleNormalizer.normalize(rawTitle);
      if (normRaw.isNotEmpty && normRaw.toLowerCase() != normalizedTitle.toLowerCase()) {
        if (cleanArtist.isNotEmpty) {
          addCandidate(normRaw, cleanArtist, 'Stage 7: Raw title + artist');
        }
        addCandidate(normRaw, '', 'Stage 7: Raw title only');
      }
    }

    return candidates.take(8).toList();
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
