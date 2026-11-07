import 'dart:math' as math;
import '../../history/domain/listening_event.dart';
import 'artist_normalizer.dart';
import 'user_taste_profile.dart';

/// Deterministic User Taste Profile and Affinity Calculator.
///
/// Implements exponential time decay based on a half-life:
///   weight_decayed = w * e^(-lambda * ageInDays)
///   lambda = ln(2) / halfLifeDays
///
/// Normalizes raw affinity into a [0.0, 1.0] range using a centered
/// logistic sigmoid function:
///   sigma(A) = 1 / (1 + e^(-k * A))  (with default k = 0.5)
///
/// Guarantees:
/// 1. Neutral baseline at sigma(0.0) = 0.50.
/// 2. Positive plays (completed/partial) yield raw > 0 -> affinity in (0.50, 1.0].
/// 3. Negative skips yield raw < 0 -> affinity in [0.0, 0.50).
/// 4. Negative feedback is preserved and penalizes candidate ranking rather
///    than being erased to 0.0.
/// 5. Asymptotically bounded in [0.0, 1.0], immune to NaN and division by zero.
class AffinityCalculator {
  final double halfLifeDays;
  final double sigmoidScale;

  const AffinityCalculator({
    this.halfLifeDays = 14.0,
    this.sigmoidScale = 0.5,
  }) : assert(halfLifeDays > 0, 'halfLifeDays must be greater than zero');

  /// Lambda constant derived from the half-life: ln(2) / T_half
  double get lambda => math.ln2 / halfLifeDays;

  /// Calculates the time-decay factor for an event with age in days.
  /// Events occurring in the future (ageDays < 0) are clamped to 1.0 (no future amplification).
  double decayFactor(double ageDays) {
    if (ageDays <= 0) return 1.0;
    return math.exp(-lambda * ageDays);
  }

  /// Normalizes a raw real-valued affinity score into [0.0, 1.0]
  /// via a centered sigmoid.
  double normalize(double rawAffinity) {
    if (rawAffinity.isNaN) return UserTasteProfile.neutralAffinity;
    if (rawAffinity == double.infinity) return 1.0;
    if (rawAffinity == double.negativeInfinity) return 0.0;
    // Cap exponent magnitude to prevent floating-point overflow (-700 to 700)
    final z = (-sigmoidScale * rawAffinity).clamp(-50.0, 50.0);
    final val = 1.0 / (1.0 + math.exp(z));
    return double.parse(val.toStringAsFixed(4));
  }

  /// Calculates the raw time-decayed affinity for a list of listening events
  /// evaluated at [referenceTime] (defaults to DateTime.now()).
  double calculateRawAffinity(
    List<ListeningEvent> events, {
    DateTime? referenceTime,
  }) {
    if (events.isEmpty) return 0.0;
    final now = referenceTime ?? DateTime.now();

    double total = 0.0;
    for (final e in events) {
      final diffMs = now.difference(e.timestamp).inMilliseconds;
      final ageDays = (diffMs / (1000.0 * 60 * 60 * 24)).clamp(0.0, 3650.0);
      final decay = decayFactor(ageDays);
      total += e.weight * decay;
    }
    return total;
  }

  /// Computes a complete [UserTasteProfile] from historical listening events.
  UserTasteProfile computeTasteProfile(
    String userId,
    List<ListeningEvent> events, {
    DateTime? referenceTime,
  }) {
    if (events.isEmpty) {
      return UserTasteProfile.empty(userId);
    }

    final now = referenceTime ?? DateTime.now();

    // 1. Deduplicate events by event ID if present (prefer latest timestamp)
    final seenIds = <String>{};
    final uniqueEvents = <ListeningEvent>[];
    for (final e in events) {
      if (e.id.isNotEmpty) {
        if (seenIds.contains(e.id)) continue;
        seenIds.add(e.id);
      }
      uniqueEvents.add(e);
    }

    // 2. Group events by normalized artist and by language
    final artistEvents = <String, List<ListeningEvent>>{};
    final langEvents = <String, List<ListeningEvent>>{};

    for (final e in uniqueEvents) {
      final normArtist = ArtistNormalizer.normalize(e.artist).toLowerCase();
      if (normArtist.isNotEmpty) {
        artistEvents.putIfAbsent(normArtist, () => []).add(e);
      }

      if (e.language != null && e.language!.trim().isNotEmpty) {
        final normLang = e.language!.trim().toLowerCase();
        langEvents.putIfAbsent(normLang, () => []).add(e);
      }
    }

    // 3. Compute normalized affinities for each artist
    final artistAffinities = <String, double>{};
    for (final entry in artistEvents.entries) {
      final raw = calculateRawAffinity(entry.value, referenceTime: now);
      artistAffinities[entry.key] = normalize(raw);
    }

    // 4. Compute normalized affinities for each language
    final languageAffinities = <String, double>{};
    for (final entry in langEvents.entries) {
      final raw = calculateRawAffinity(entry.value, referenceTime: now);
      languageAffinities[entry.key] = normalize(raw);
    }

    return UserTasteProfile(
      userId: userId,
      artistAffinities: artistAffinities,
      languageAffinities: languageAffinities,
      lastUpdated: now,
      eventsProcessedCount: uniqueEvents.length,
      version: 1,
    );
  }
}
