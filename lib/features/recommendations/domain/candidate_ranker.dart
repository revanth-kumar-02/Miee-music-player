import '../../../shared/models/music_item.dart';
import '../../history/domain/listening_event.dart';
import '../../search/domain/search_deduplicator.dart';
import '../domain/recommendation_diversity_filter.dart';
import '../domain/recommendation_scorer.dart';
import '../domain/user_taste_profile.dart';

/// Unified candidate ranking engine combining deduplication, deterministic
/// scoring, and diversity filtering.
class CandidateRanker {
  final RecommendationScorer scorer;
  final RecommendationDiversityFilter diversityFilter;

  const CandidateRanker({
    this.scorer = const RecommendationScorer(),
    this.diversityFilter = const RecommendationDiversityFilter(),
  });

  /// Scores, deduplicates, and ranks candidate tracks deterministically.
  List<MusicItem> rankCandidates({
    required List<MusicItem> candidates,
    required UserTasteProfile tasteProfile,
    required List<String> preferredLanguages,
    required Map<String, int> chartRanks,
    required List<ListeningEvent> recentHistory,
    required int limit,
    Set<String>? excludedTrackIds,
    Set<String>? excludedRecordingKeys,
    DateTime? now,
  }) {
    if (candidates.isEmpty || limit <= 0) return const [];

    final referenceTime = now ?? DateTime.now();

    // 1. Canonical deduplication of candidate pool
    final seenIds = <String>{...?excludedTrackIds};
    final seenKeys = <String>{...?excludedRecordingKeys};
    final uniqueCandidates = <MusicItem>[];

    for (final track in candidates) {
      final cleanId = track.id.startsWith('youtube_')
          ? track.id.replaceFirst('youtube_', '')
          : track.id;

      if (cleanId.isEmpty || seenIds.contains(cleanId) || seenIds.contains(track.id)) {
        continue;
      }

      final recKey = SearchDeduplicator.computeRecordingKey(track);
      if (seenKeys.contains(recKey)) {
        continue;
      }

      seenIds.add(cleanId);
      seenIds.add(track.id);
      seenKeys.add(recKey);
      uniqueCandidates.add(track);
    }

    if (uniqueCandidates.isEmpty) return const [];

    // 2. Compute deterministic scores for each candidate
    final scored = uniqueCandidates.map((track) {
      return scorer.scoreCandidate(
        track: track,
        tasteProfile: tasteProfile,
        preferredLanguages: preferredLanguages,
        chartRanks: chartRanks,
        recentHistory: recentHistory,
        now: referenceTime,
      );
    }).toList();

    // 3. Apply diversity filtering, soundtrack constraints, and familiar/discovery mix
    return diversityFilter.filterAndInterleave(
      scoredCandidates: scored,
      tasteProfile: tasteProfile,
      limit: limit,
    );
  }
}

