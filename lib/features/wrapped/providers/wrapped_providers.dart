import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/adapters/playback_history_entry.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../profile/presentation/profile_controller.dart';
import '../data/wrapped_service.dart';
import '../domain/wrapped_models.dart';

/// Selected timeframe filter for Wrapped: 'year', 'month', 'anniversary', or 'all'
final wrappedTimeframeProvider = StateProvider<String>((ref) => 'year');

/// Target year for annual recaps (defaults to current year)
final wrappedTargetYearProvider = StateProvider<int>((ref) => DateTime.now().year);

/// Whether the user has explicitly requested sample demo mode
final wrappedForceSampleProvider = StateProvider<bool>((ref) => false);

/// Override for simulated account start date (useful for automated testing or debugging)
final wrappedSimulatedAccountStartDateProvider = StateProvider<DateTime?>((ref) => null);

/// Force eligibility toggle for review/testing
final wrappedForceEligibleProvider = StateProvider<bool>((ref) => false);

/// Selected anniversary year being viewed by user (null = latest completed year)
final wrappedSelectedAnniversaryYearProvider = StateProvider<int?>((ref) => null);

/// Stream provider that listens to playback history box mutations for reactive recap recomputation
final playbackHistoryWatcherProvider = StreamProvider<BoxEvent>((ref) {
  if (Hive.isBoxOpen(HiveBoxes.playbackHistory)) {
    return Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory).watch();
  }
  return const Stream.empty();
});

/// Authoritative account creation timestamp provider
final accountStartDateProvider = Provider<DateTime>((ref) {
  final simulated = ref.watch(wrappedSimulatedAccountStartDateProvider);
  if (simulated != null) return simulated;

  final profile = ref.watch(profileProvider);
  final persistentDate = WrappedService.getAccountStartDate();

  if (profile.createdDate.isBefore(persistentDate)) {
    return profile.createdDate;
  }
  return persistentDate;
});

/// Computes the current user's eligibility and 1-year anniversary milestone state
final wrappedEligibilityProvider = Provider<WrappedEligibility>((ref) {
  final startDate = ref.watch(accountStartDateProvider);
  final forceEligible = ref.watch(wrappedForceEligibleProvider);
  final activeYear = ref.watch(wrappedSelectedAnniversaryYearProvider);

  return WrappedEligibility.compute(
    accountStartDate: startDate,
    activeYearOverride: activeYear,
    forceEligible: forceEligible,
  );
});

/// Provides the computed [WrappedSummary] based on real history and active filters.
final wrappedSummaryProvider = Provider<WrappedSummary>((ref) {
  final timeframe = ref.watch(wrappedTimeframeProvider);
  final targetYear = ref.watch(wrappedTargetYearProvider);
  final forceSample = ref.watch(wrappedForceSampleProvider);
  final eligibility = ref.watch(wrappedEligibilityProvider);

  // Automatically recompute when new playback history entries arrive
  ref.watch(playbackHistoryWatcherProvider);

  DateTime? startDate;
  DateTime? endDate;

  // When eligible and viewing the annual milestone recap, bound to the completed anniversary year
  if (eligibility.isEligible && (timeframe == 'year' || timeframe == 'anniversary')) {
    final k = eligibility.activeYear;
    startDate = (k == 1)
        ? eligibility.accountStartDate
        : WrappedEligibility.anniversaryForYear(eligibility.accountStartDate, k - 1);
    endDate = WrappedEligibility.anniversaryForYear(eligibility.accountStartDate, k);
  }

  return WrappedService.computeSummary(
    timeframe: timeframe,
    targetYear: targetYear,
    startDate: startDate,
    endDate: endDate,
    anniversaryYear: eligibility.activeYear,
    forceSample: forceSample,
  );
});
