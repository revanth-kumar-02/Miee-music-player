import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/wrapped_service.dart';
import '../domain/wrapped_models.dart';

/// Selected timeframe filter for Wrapped: 'year', 'month', or 'all'
final wrappedTimeframeProvider = StateProvider<String>((ref) => 'year');

/// Whether the user has toggled sample demo mode
final wrappedForceSampleProvider = StateProvider<bool>((ref) => false);

/// Provides the computed [WrappedSummary] based on history and active filters.
final wrappedSummaryProvider = Provider<WrappedSummary>((ref) {
  final timeframe = ref.watch(wrappedTimeframeProvider);
  final forceSample = ref.watch(wrappedForceSampleProvider);

  return WrappedService.computeSummary(
    timeframe: timeframe,
    forceSample: forceSample,
  );
});
