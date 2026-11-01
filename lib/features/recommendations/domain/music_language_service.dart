import 'dart:math' as math;
import '../../../shared/models/music_item.dart';
import '../../history/domain/listening_event.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../profile/domain/user_profile.dart';

/// Service responsible for conservative music language detection,
/// user listening-language preference aggregation, and language-aware
/// recommendation ranking.
class MusicLanguageService {
  /// Detects the language of a track using:
  /// 1. Unicode script detection (Tamil, Telugu, Devanagari/Hindi, Malayalam, Kannada, Punjabi, Bengali, Korean, Japanese).
  /// 2. Explicit keywords / brackets / language tags in title or channel title (e.g., "[Tamil]", "(Telugu)", "Hindi Song").
  /// 3. Curated single-language artist catalogs (only if the artist strictly records in ONE language).
  ///
  /// Returns 'Unknown' if the language cannot be determined conservatively.
  /// Never assumes multilingual artists record in only one language.
  static String detectLanguage(
    String title, {
    String artist = '',
    String? channelTitle,
  }) {
    final lowerTitle = title.toLowerCase();
    final lowerArtist = artist.toLowerCase();
    final lowerChannel = (channelTitle ?? '').toLowerCase();
    final combined = '$lowerTitle $lowerArtist $lowerChannel';

    // 1. Script detection (Strongest signal)
    if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(title)) return 'Tamil';
    if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(title)) return 'Telugu';
    if (RegExp(r'[\u0900-\u097F]').hasMatch(title)) return 'Hindi';
    if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(title)) return 'Malayalam';
    if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(title)) return 'Kannada';
    if (RegExp(r'[\u0A00-\u0A7F]').hasMatch(title)) return 'Punjabi';
    if (RegExp(r'[\u0980-\u09FF]').hasMatch(title)) return 'Bengali';
    if (RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]').hasMatch(title)) return 'Korean';
    if (RegExp(r'[\u3040-\u30FF]').hasMatch(title)) return 'Japanese';

    // 2. Explicit keyword tags with word boundaries in title
    if (RegExp(r'\b(tamil|tamizh)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Tamil';
    }
    if (RegExp(r'\b(telugu)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Telugu';
    }
    if (RegExp(r'\b(hindi|bollywood)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Hindi';
    }
    if (RegExp(r'\b(malayalam)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Malayalam';
    }
    if (RegExp(r'\b(kannada)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Kannada';
    }
    if (RegExp(r'\b(punjabi)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Punjabi';
    }
    if (RegExp(r'\b(bengali|bangla)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Bengali';
    }
    if (RegExp(r'\b(english)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'English';
    }
    if (RegExp(r'\b(k-pop|kpop)\b', caseSensitive: false).hasMatch(combined)) {
      return 'Korean';
    }
    if (RegExp(r'\b(spanish|español|latino)\b', caseSensitive: false).hasMatch(lowerTitle)) {
      return 'Spanish';
    }

    // 3. Known single-language artist check (strictly conservative)
    final artistLanguages = _getKnownArtistLanguages(artist);
    if (artistLanguages.length == 1) {
      return artistLanguages.first;
    }

    // Unknown or unclassified
    return 'Unknown';
  }

  /// Retrieves known languages for curated artists from the discovery catalog.
  static List<String> _getKnownArtistLanguages(String artistName) {
    if (artistName.trim().isEmpty) return const [];
    final clean = artistName.trim().toLowerCase();

    for (final a in DeezerArtistRepository.staticCuratedArtists) {
      if (a.name.toLowerCase().trim() == clean) {
        return a.languages;
      }
    }
    return const [];
  }

  /// Determines if an artist is known to perform in [targetLang].
  static bool isArtistMultilingualInLang(String artistName, String targetLang) {
    final languages = _getKnownArtistLanguages(artistName);
    return languages.any((l) => l.toLowerCase() == targetLang.toLowerCase());
  }

  /// Calculates the user's preferred music languages using evidence in order:
  /// 1. Explicit preferences stored in [UserProfile.preferredLanguages].
  /// 2. Aggregate listening history weighted by duration and repeated plays.
  /// 3. Returns empty list if no reliable history exists (no hardcoded bias).
  static List<String> getPreferredLanguages({
    required List<ListeningEvent> history,
    UserProfile? profile,
  }) {
    // 1. Explicit preference check
    if (profile != null && profile.preferredLanguages.isNotEmpty) {
      return List<String>.from(profile.preferredLanguages);
    }

    // 2. Listening history aggregation
    if (history.isEmpty) return const [];

    final Map<String, double> scores = {};

    for (final event in history) {
      // Exclude short accidental clicks or skipped plays
      if (event.listenedSec < 10) continue;
      if (event.durationSec > 30 && event.completionRatio < 0.15) continue;

      final lang = detectLanguage(event.title, artist: event.artist);
      if (lang == 'Unknown') continue;

      // Base play weight + duration factor
      final durationMinutes = event.listenedSec / 60.0;
      final playScore = 1.0 + math.min(durationMinutes, 4.0);

      scores[lang] = (scores[lang] ?? 0.0) + playScore;
    }

    if (scores.isEmpty) return const [];

    // Sort by score descending
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topScore = sorted.first.value;

    // Retain top language and any secondary language that has >= 25% of top score
    final result = <String>[];
    for (final entry in sorted) {
      if (entry.value >= topScore * 0.25) {
        result.add(entry.key);
      }
    }

    return result;
  }

  /// Calculates a ranking score for a candidate track based on the user's [preferredLanguages].
  ///
  /// - Top preferred language match: +60 points
  /// - Secondary preferred language match: +40 points
  /// - Unknown language: +0 points (neutral, neither boosted nor penalized)
  /// - Known mismatch language: -30 points (ranked lower than preferred and unknown, but preserved)
  static double scoreTrack(
    MusicItem track,
    List<String> preferredLanguages, {
    double baseRank = 100.0,
  }) {
    if (preferredLanguages.isEmpty) {
      return baseRank;
    }

    final lang = detectLanguage(track.title, artist: track.artist);

    if (lang == 'Unknown') {
      return baseRank;
    }

    final topLang = preferredLanguages.first;
    if (lang.toLowerCase() == topLang.toLowerCase()) {
      return baseRank + 60.0;
    }

    if (preferredLanguages.skip(1).any((l) => l.toLowerCase() == lang.toLowerCase())) {
      return baseRank + 40.0;
    }

    // Mismatched known language
    return baseRank - 30.0;
  }

  /// Normalizes track key for deduplication.
  static String normalizeTrackKey(String title, String artist) {
    // Strip common tags: (From "..."), [Tamil], - Official, (Lyric Video), etc.
    final cleanTitle = title
        .toLowerCase()
        .replaceAll(RegExp(r'\[.*?\]|\(.*?\)|\|.*$|\-.*$'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '')
        .trim();
    final cleanArtist = artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
    return '$cleanTitle|$cleanArtist';
  }

  /// Reranks a list of candidate [tracks] according to user's [preferredLanguages],
  /// preserving order for tied scores and strictly preventing empty lists.
  static List<MusicItem> rankAndDeduplicate(
    List<MusicItem> tracks,
    List<String> preferredLanguages, {
    int? limit,
  }) {
    if (tracks.isEmpty) return const [];

    final scored = <({MusicItem track, double score, int originalIndex})>[];
    for (int i = 0; i < tracks.length; i++) {
      final t = tracks[i];
      // YouTube relevance provides initial descending base score
      final baseScore = 100.0 - (i * 1.5);
      final finalScore = scoreTrack(t, preferredLanguages, baseRank: baseScore);
      scored.add((track: t, score: finalScore, originalIndex: i));
    }

    // Sort by final score descending; break ties with original index
    scored.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) return cmp;
      return a.originalIndex.compareTo(b.originalIndex);
    });

    final result = <MusicItem>[];
    final seenIds = <String>{};
    final seenKeys = <String>{};

    for (final item in scored) {
      final t = item.track;
      final key = normalizeTrackKey(t.title, t.artist);
      if (seenIds.add(t.id) && seenKeys.add(key)) {
        result.add(t);
        if (limit != null && result.length >= limit) break;
      }
    }

    return result;
  }
}
