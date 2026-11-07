import '../../../shared/models/music_item.dart';
import '../../history/domain/listening_event.dart';
import '../domain/artist_normalizer.dart';
import '../domain/music_language_service.dart';
import '../domain/user_taste_profile.dart';

/// Deterministic scoring breakdown for recommendation candidates.
class CandidateScore {
  final MusicItem track;
  final double languageScore;
  final double artistScore;
  final double chartScore;
  final double fatiguePenalty;
  final double skipPenalty;
  final double totalScore;

  const CandidateScore({
    required this.track,
    required this.languageScore,
    required this.artistScore,
    required this.chartScore,
    required this.fatiguePenalty,
    required this.skipPenalty,
    required this.totalScore,
  });

  @override
  String toString() =>
      'CandidateScore(${track.title} by ${track.artist}: total=$totalScore [lang=$languageScore, artist=$artistScore, chart=$chartScore, fatigue=-$fatiguePenalty, skip=-$skipPenalty])';
}

/// Shared deterministic recommendation scorer.
///
/// Implements the formula:
///   FinalScore = LanguageScore + ArtistScore + ChartScore - FatiguePenalty - SkipPenalty
///
/// Guarantees:
/// 1. Language scoring: Primary (+60), Secondary (+40), Mismatch (-30), Unknown (0).
/// 2. Artist affinity scoring: (ArtistAffinity - 0.50) * 160.
///    - Differentiates preferred (>0.50), unseen (0.50 -> 0), and disliked (<0.50 -> negative).
///    - Example: 0.90 -> +64, 0.75 -> +40, 0.50 -> 0, 0.25 -> -40.
/// 3. Chart popularity scoring: Rank 1 (+30) to Rank 50 (+5) linear interpolation, unranked (0).
/// 4. Track fatigue penalty: Played within 24h (-100), within 7d (-50), >7d (0).
/// 5. Skip penalty: -80 if track was skipped >= 2 times within recent 14-day window.
class RecommendationScorer {
  final Duration skipWindow;

  const RecommendationScorer({
    this.skipWindow = const Duration(days: 14),
  });

  /// Evaluates and scores [track] deterministically against user taste, charts, and history.
  CandidateScore scoreCandidate({
    required MusicItem track,
    required UserTasteProfile tasteProfile,
    required List<String> preferredLanguages,
    required Map<String, int> chartRanks,
    required List<ListeningEvent> recentHistory,
    DateTime? now,
  }) {
    final referenceTime = now ?? DateTime.now();

    final langScore = computeLanguageScore(
      track: track,
      preferredLanguages: preferredLanguages,
    );

    final artistScore = computeArtistScore(
      track: track,
      tasteProfile: tasteProfile,
    );

    final chartScore = computeChartScore(
      track: track,
      chartRanks: chartRanks,
    );

    final fatiguePenalty = computeFatiguePenalty(
      track: track,
      history: recentHistory,
      referenceTime: referenceTime,
    );

    final skipPenalty = computeSkipPenalty(
      track: track,
      history: recentHistory,
      referenceTime: referenceTime,
    );

    final total = langScore + artistScore + chartScore - fatiguePenalty - skipPenalty;

    return CandidateScore(
      track: track,
      languageScore: langScore,
      artistScore: artistScore,
      chartScore: chartScore,
      fatiguePenalty: fatiguePenalty,
      skipPenalty: skipPenalty,
      totalScore: double.parse(total.toStringAsFixed(2)),
    );
  }

  /// Calculates language alignment score:
  /// - Primary language (preferredLanguages[0]): +60
  /// - Secondary language (preferredLanguages[1..]): +40
  /// - Mismatch (known language not in user preferences): -30
  /// - Unknown language: 0
  double computeLanguageScore({
    required MusicItem track,
    required List<String> preferredLanguages,
  }) {
    if (preferredLanguages.isEmpty) return 0.0;

    final detected = MusicLanguageService.detectLanguage(
      track.title,
      artist: track.artist,
    );

    if (detected == 'Unknown') return 0.0;

    final primary = preferredLanguages.first.toLowerCase().trim();
    final detLower = detected.toLowerCase().trim();

    if (detLower == primary) {
      return 60.0;
    }

    final isSecondary = preferredLanguages
        .skip(1)
        .any((l) => l.toLowerCase().trim() == detLower);

    if (isSecondary) {
      return 40.0;
    }

    // Language mismatch: candidate is confirmed to be in an unselected/non-preferred language
    return -30.0;
  }

  /// Calculates artist preference score:
  /// Uses Phase 2 centered sigmoid affinity where 0.50 is the neutral baseline.
  /// To avoid boosting every unseen artist, the score is centered around 0.50:
  ///   ArtistScore = (Affinity - 0.50) * 160
  ///
  /// Examples:
  /// - Neutral/Unseen (0.50): (0.50 - 0.50) * 160 = 0.0
  /// - High affinity (0.90): (0.90 - 0.50) * 160 = +64.0
  /// - Liked artist (0.75): (0.75 - 0.50) * 160 = +40.0
  /// - Disliked artist (0.25): (0.25 - 0.50) * 160 = -40.0
  ///
  /// Note: When scaled directly as Affinity * 80, unseen artists with default 0.50 get +40,
  /// artificially dominating fresh discovery. Centering preserves positive rewards for
  /// preferred artists, negative penalties for disliked artists, and zero artificial bias
  /// for unknown artists.
  double computeArtistScore({
    required MusicItem track,
    required UserTasteProfile tasteProfile,
  }) {
    final affinity = tasteProfile.getArtistAffinity(track.artist);
    final score = (affinity - UserTasteProfile.neutralAffinity) * 160.0;
    return double.parse(score.toStringAsFixed(2));
  }

  /// Calculates chart popularity score:
  /// For rank 1..50:
  ///   Rank 1: +30
  ///   Rank 50: +5
  ///   Linear interpolation: 30.0 - ((rank - 1) / 49.0) * 25.0
  /// For rank > 50 or unranked: 0.0
  double computeChartScore({
    required MusicItem track,
    required Map<String, int> chartRanks,
  }) {
    final cleanId = track.id.startsWith('youtube_')
        ? track.id.replaceFirst('youtube_', '')
        : track.id;

    final normKey = '${track.title.toLowerCase().trim()}|${track.artist.toLowerCase().trim()}';

    final rank = chartRanks[cleanId] ??
        chartRanks[track.id] ??
        chartRanks[normKey];

    if (rank == null || rank < 1 || rank > 50) {
      return 0.0;
    }

    if (rank == 1) return 30.0;
    if (rank == 50) return 5.0;

    final score = 30.0 - ((rank - 1) / 49.0) * 25.0;
    return double.parse(score.toStringAsFixed(2));
  }

  /// Calculates track fatigue penalty based on listening history recency:
  /// - Played within 24 hours: 100.0 (penalty subtracted from score)
  /// - Played within 7 days: 50.0
  /// - Older than 7 days or not played: 0.0
  ///
  /// Avoids double-counting multiple history events: uses most recent play.
  double computeFatiguePenalty({
    required MusicItem track,
    required List<ListeningEvent> history,
    required DateTime referenceTime,
  }) {
    if (history.isEmpty) return 0.0;

    final targetId = track.id.startsWith('youtube_')
        ? track.id.replaceFirst('youtube_', '')
        : track.id;

    final targetTitle = track.title.toLowerCase().trim();
    final targetArtist = ArtistNormalizer.normalize(track.artist).toLowerCase().trim();

    DateTime? mostRecentPlay;

    for (final e in history) {
      final eId = e.trackId.startsWith('youtube_')
          ? e.trackId.replaceFirst('youtube_', '')
          : e.trackId;

      final isMatch = (eId.isNotEmpty && eId == targetId) ||
          (e.title.toLowerCase().trim() == targetTitle &&
              ArtistNormalizer.normalize(e.artist).toLowerCase().trim() == targetArtist);

      if (isMatch) {
        if (mostRecentPlay == null || e.timestamp.isAfter(mostRecentPlay)) {
          mostRecentPlay = e.timestamp;
        }
      }
    }

    if (mostRecentPlay == null) return 0.0;

    final diff = referenceTime.difference(mostRecentPlay);
    if (diff.isNegative) {
      // Future timestamp safe fallback
      return 100.0;
    }

    if (diff <= const Duration(hours: 24)) {
      return 100.0;
    } else if (diff <= const Duration(days: 7)) {
      return 50.0;
    }

    return 0.0;
  }

  /// Calculates negative skip penalty:
  /// Applies 80.0 penalty if track was skipped >= 2 times within recent window (14 days).
  ///
  /// Requirements:
  /// 1. Genuine skip events only (eventType == ListeningEventType.skip).
  /// 2. Deduplicates repeated event IDs.
  /// 3. Older skips outside window (>14 days) are excluded.
  double computeSkipPenalty({
    required MusicItem track,
    required List<ListeningEvent> history,
    required DateTime referenceTime,
  }) {
    if (history.isEmpty) return 0.0;

    final targetId = track.id.startsWith('youtube_')
        ? track.id.replaceFirst('youtube_', '')
        : track.id;

    final targetTitle = track.title.toLowerCase().trim();
    final targetArtist = ArtistNormalizer.normalize(track.artist).toLowerCase().trim();

    final seenEventIds = <String>{};
    int recentSkipCount = 0;

    for (final e in history) {
      if (e.eventType != ListeningEventType.skip) continue;

      if (e.id.isNotEmpty) {
        if (seenEventIds.contains(e.id)) continue;
        seenEventIds.add(e.id);
      }

      final diff = referenceTime.difference(e.timestamp);
      if (diff.isNegative) continue; // Ignore future desynced timestamps for skip penalties
      if (diff > skipWindow) continue; // Outside recent window

      final eId = e.trackId.startsWith('youtube_')
          ? e.trackId.replaceFirst('youtube_', '')
          : e.trackId;

      final isMatch = (eId.isNotEmpty && eId == targetId) ||
          (e.title.toLowerCase().trim() == targetTitle &&
              ArtistNormalizer.normalize(e.artist).toLowerCase().trim() == targetArtist);

      if (isMatch) {
        recentSkipCount++;
        if (recentSkipCount >= 2) {
          return 80.0;
        }
      }
    }

    return 0.0;
  }
}
