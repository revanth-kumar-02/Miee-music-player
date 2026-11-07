import '../../../shared/models/music_item.dart';
import '../domain/artist_normalizer.dart';
import '../domain/user_taste_profile.dart';
import 'recommendation_scorer.dart';

/// Configuration for recommendation diversity and familiar/discovery mix.
class DiversityConfig {
  /// Maximum allowed tracks for a single normalized artist per section/shelf.
  final int maxTracksPerArtist;

  /// Target proportion of familiar tracks (e.g. 0.70 for 70%).
  final double targetFamiliarRatio;

  /// Affinity threshold above which an artist is classified as familiar.
  final double familiarAffinityThreshold;

  const DiversityConfig({
    this.maxTracksPerArtist = 2,
    this.targetFamiliarRatio = 0.70,
    this.familiarAffinityThreshold = 0.52,
  }) : assert(maxTracksPerArtist >= 1, 'maxTracksPerArtist must be >= 1'),
       assert(targetFamiliarRatio >= 0.0 && targetFamiliarRatio <= 1.0,
           'targetFamiliarRatio must be between 0.0 and 1.0');
}

/// Applies deterministic diversity filtering, artist limits, soundtrack grouping,
/// and familiar/discovery balancing.
class RecommendationDiversityFilter {
  final DiversityConfig config;

  const RecommendationDiversityFilter({
    this.config = const DiversityConfig(),
  });

  /// Filters and interleaves scored candidates to respect diversity constraints:
  /// 1. Maximum [maxTracksPerArtist] tracks per normalized artist.
  /// 2. Maximum 1 track per identifiable film/album soundtrack where reliable metadata exists.
  /// 3. Balanced target of familiar vs discovery candidates (default 70/30).
  /// 4. Fallback safe: if filtered list is too small, fills quota safely with highest scored items.
  List<MusicItem> filterAndInterleave({
    required List<CandidateScore> scoredCandidates,
    required UserTasteProfile tasteProfile,
    required int limit,
  }) {
    if (scoredCandidates.isEmpty || limit <= 0) return const [];

    // 1. Sort all candidates by totalScore descending.
    // Deterministic tie-breaking on track title and id.
    final sorted = List<CandidateScore>.from(scoredCandidates)
      ..sort((a, b) {
        final cmp = b.totalScore.compareTo(a.totalScore);
        if (cmp != 0) return cmp;
        final titleCmp = a.track.title.compareTo(b.track.title);
        if (titleCmp != 0) return titleCmp;
        return a.track.id.compareTo(b.track.id);
      });

    // 2. Classify candidates into Familiar (affinity > threshold) and Discovery (<= threshold)
    final familiarPool = <CandidateScore>[];
    final discoveryPool = <CandidateScore>[];

    for (final cs in sorted) {
      final affinity = tasteProfile.getArtistAffinity(cs.track.artist);
      if (affinity > config.familiarAffinityThreshold) {
        familiarPool.add(cs);
      } else {
        discoveryPool.add(cs);
      }
    }

    final selected = <CandidateScore>[];
    final artistCount = <String, int>{};
    final seenSoundtracks = <String>{};

    bool canAdd(CandidateScore cs) {
      final normArtist = ArtistNormalizer.normalize(cs.track.artist).toLowerCase().trim();
      final currentArtistCount = artistCount[normArtist] ?? 0;
      if (currentArtistCount >= config.maxTracksPerArtist) {
        return false;
      }

      final soundtrackKey = _extractSoundtrackKey(cs.track);
      if (soundtrackKey != null && seenSoundtracks.contains(soundtrackKey)) {
        return false;
      }

      return true;
    }

    void addCandidate(CandidateScore cs) {
      final normArtist = ArtistNormalizer.normalize(cs.track.artist).toLowerCase().trim();
      artistCount[normArtist] = (artistCount[normArtist] ?? 0) + 1;
      final soundtrackKey = _extractSoundtrackKey(cs.track);
      if (soundtrackKey != null) {
        seenSoundtracks.add(soundtrackKey);
      }
      selected.add(cs);
    }

    // 3. Target counts for familiar vs discovery
    final targetFamiliarCount = (limit * config.targetFamiliarRatio).round();

    int familiarAdded = 0;
    int fIdx = 0;
    int dIdx = 0;

    // Interleave matching target ratio (e.g. 70/30 ~ roughly 2-3 familiar, 1 discovery)
    while (selected.length < limit && (fIdx < familiarPool.length || dIdx < discoveryPool.length)) {
      bool tryFamiliar = (familiarAdded < targetFamiliarCount || dIdx >= discoveryPool.length) &&
          fIdx < familiarPool.length;

      if (tryFamiliar) {
        final cand = familiarPool[fIdx++];
        if (canAdd(cand)) {
          addCandidate(cand);
          familiarAdded++;
        }
      } else if (dIdx < discoveryPool.length) {
        final cand = discoveryPool[dIdx++];
        if (canAdd(cand)) {
          addCandidate(cand);
        }
      } else {
        break;
      }
    }

    // 4. Safe Backfill: If interleave did not yield enough tracks due to pool imbalance,
    // backfill from remaining candidates while strictly respecting artist and soundtrack caps.
    // If no remaining candidate satisfies diversity limits, return the diverse subset (fewer tracks)
    // rather than silently exceeding artist or soundtrack caps.
    if (selected.length < limit) {
      final selectedIds = selected.map((s) => s.track.id).toSet();
      for (final cs in sorted) {
        if (selected.length >= limit) break;
        if (selectedIds.contains(cs.track.id)) continue;

        if (canAdd(cs)) {
          addCandidate(cs);
          selectedIds.add(cs.track.id);
        }
      }
    }

    return selected.map((s) => s.track).toList();
  }

  static final RegExp _soundtrackRegex = RegExp(
    r'[\(\[\{]\s*(?:from\s+|ost\s+|motion picture\s+)?["\x27]?([^()\[\]{}]+?)["\x27]?\s*(?:ost|soundtrack|original motion picture soundtrack)?[\)\]\}]',
    caseSensitive: false,
  );

  /// Extracts reliable movie / album soundtrack key from track title where present.
  /// Looks for explicit patterns like: "Song Name (From Movie)", "Song [From Movie]",
  /// or "(Movie Original Soundtrack)".
  /// Returns null if no reliable soundtrack pattern is detected (never guesses).
  static String? _extractSoundtrackKey(MusicItem track) {
    final title = track.title;
    final match = _soundtrackRegex.firstMatch(title);

    if (match != null && match.groupCount >= 1) {
      final rawMovie = match.group(1)?.toLowerCase().trim() ?? '';
      // Ensure it's not a generic tag like (audio), (video), (lyrics), (official)
      if (rawMovie.isNotEmpty &&
          !rawMovie.contains('official') &&
          !rawMovie.contains('lyrics') &&
          !rawMovie.contains('audio') &&
          !rawMovie.contains('video') &&
          !rawMovie.contains('teaser') &&
          !rawMovie.contains('trailer') &&
          rawMovie.length >= 3) {
        return rawMovie;
      }
    }
    return null;
  }
}
