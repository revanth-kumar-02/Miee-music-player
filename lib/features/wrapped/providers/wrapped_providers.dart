import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/adapters/playback_history_entry.dart';
import '../../../core/storage/hive_boxes.dart';
import '../data/wrapped_service.dart';
import '../domain/wrapped_models.dart';

/// Selected timeframe filter for Wrapped: 'year', 'month', or 'all'
final wrappedTimeframeProvider = StateProvider<String>((ref) => 'year');

/// Target year for annual recaps (defaults to current year)
final wrappedTargetYearProvider = StateProvider<int>((ref) => DateTime.now().year);

/// Whether the user has explicitly requested sample demo mode
final wrappedForceSampleProvider = StateProvider<bool>((ref) => false);

/// Stream provider that listens to playback history box mutations for reactive recap recomputation
final playbackHistoryWatcherProvider = StreamProvider<BoxEvent>((ref) {
  if (Hive.isBoxOpen(HiveBoxes.playbackHistory)) {
    return Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory).watch();
  }
  return const Stream.empty();
});

/// Provides the computed [WrappedSummary] based on real history and active filters.
final wrappedSummaryProvider = Provider<WrappedSummary>((ref) {
  final timeframe = ref.watch(wrappedTimeframeProvider);
  final targetYear = ref.watch(wrappedTargetYearProvider);
  final forceSample = ref.watch(wrappedForceSampleProvider);

  // Automatically recompute when new playback history entries arrive
  ref.watch(playbackHistoryWatcherProvider);

  return WrappedService.computeSummary(
    timeframe: timeframe,
    targetYear: targetYear,
    forceSample: forceSample,
  );
});
