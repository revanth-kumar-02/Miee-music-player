import 'package:flutter/foundation.dart';

/// Comprehensive performance and quality diagnostic tracer for search workflows.
///
/// Traces:
///   - Query received
///   - Debounce completion
///   - Provider request start
///   - First response received
///   - Parsing completion
///   - Filtering completion
///   - First relevant result rendered
///   - Total initial search completion
///
/// Diagnostic prefix: `[SearchLatency]`
/// Uses monotonic stopwatch timing and unique request IDs.
/// Never logs authentication tokens, signed URLs, or personal data.
class SearchDiagnostics {
  static final SearchDiagnostics _instance = SearchDiagnostics._internal();
  factory SearchDiagnostics() => _instance;
  SearchDiagnostics._internal();

  SearchTiming? _activeTiming;
  int _totalSearches = 0;
  int _totalCacheHits = 0;

  double get globalCacheHitRate =>
      _totalSearches > 0 ? (_totalCacheHits / _totalSearches) : 0.0;

  /// Records when user inputs/types a search query.
  void recordInput({required String query, required int reqId}) {
    final now = DateTime.now();
    _totalSearches++;
    _activeTiming = SearchTiming(
      reqId: reqId,
      queryLength: query.trim().length,
      inputTime: now,
      stopwatch: Stopwatch()..start(),
    );
    debugPrint(
      '[SearchLatency] ── INPUT REGISTERED ── reqId=$reqId queryLen=${query.trim().length}',
    );
  }

  /// Records when input debounce timer completes and execution starts.
  void recordDebounceComplete(int reqId) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.debounceCompletedTime = DateTime.now();
    t.debounceDurationMs = t.stopwatch.elapsedMilliseconds;
    debugPrint('[SearchLatency] Debounce Completed: +${t.debounceDurationMs}ms (reqId=$reqId)');
  }

  /// Records start of local database/library query.
  void recordLocalQueryStart(int reqId) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.localQueryStartTime = DateTime.now();
    t.localStartMs = t.stopwatch.elapsedMilliseconds;
  }

  /// Records completion of local database/library query.
  void recordLocalQueryEnd(int reqId, {required int resultCount}) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.localQueryEndTime = DateTime.now();
    final elapsed = t.stopwatch.elapsedMilliseconds;
    t.localDurationMs = elapsed - t.localStartMs;
    t.localResultsCount = resultCount;
    debugPrint(
      '[SearchLatency] Local Library Search: ${t.localDurationMs}ms (results=$resultCount, reqId=$reqId)',
    );
  }

  /// Records start of remote YouTube search query.
  void recordYouTubeRequestStart(int reqId, {int resultsRequested = 20}) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.youtubeRequestStartTime = DateTime.now();
    t.youtubeStartMs = t.stopwatch.elapsedMilliseconds;
    t.resultsRequested = resultsRequested;
    t.providerRequestsMade++;
  }

  /// Records when first network byte/response from provider arrives.
  void recordFirstResponseReceived(int reqId) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.firstResponseTime = DateTime.now();
    t.timeToFirstResponseMs = t.stopwatch.elapsedMilliseconds - t.youtubeStartMs;
    debugPrint('[SearchLatency] Provider First Response: +${t.timeToFirstResponseMs}ms (reqId=$reqId)');
  }

  /// Records completion of parsing provider response items.
  void recordParsingEnd(int reqId, {required int itemsParsed}) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.parsingDurationMs = t.stopwatch.elapsedMilliseconds - (t.youtubeStartMs + t.timeToFirstResponseMs);
    t.resultsReceived = itemsParsed;
    debugPrint('[SearchLatency] Parsing Completed: ${t.parsingDurationMs}ms (items=$itemsParsed, reqId=$reqId)');
  }

  /// Records filtering & deduplication completion with breakdown.
  void recordFilteringEnd(
    int reqId, {
    required int relevantResults,
    required int irrelevantFiltered,
    required int duplicatesRemoved,
  }) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.filteringEndTime = DateTime.now();
    t.relevantResults = relevantResults;
    t.irrelevantFiltered = irrelevantFiltered;
    t.duplicatesRemoved = duplicatesRemoved;
    debugPrint(
      '[SearchLatency] Filtering Completed (relevant=$relevantResults, filtered=$irrelevantFiltered, duplicatesRemoved=$duplicatesRemoved, reqId=$reqId)',
    );
  }

  /// Records completion of remote YouTube search query.
  void recordYouTubeRequestEnd(
    int reqId, {
    required int resultCount,
    required bool fromCache,
    required bool success,
  }) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.youtubeRequestEndTime = DateTime.now();
    final elapsed = t.stopwatch.elapsedMilliseconds;
    t.youtubeDurationMs = elapsed - t.youtubeStartMs;
    t.isYouTubeCacheHit = fromCache;
    if (fromCache) _totalCacheHits++;
    debugPrint(
      '[SearchLatency] YouTube Request ${success ? "SUCCESS" : "FAILED"}: ${t.youtubeDurationMs}ms (fromCache=$fromCache, results=$resultCount, reqId=$reqId)',
    );
  }

  /// Records completion of metadata enrichment.
  void recordEnrichmentEnd(int reqId, {required int durationMs, required int enrichedCount}) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.enrichmentDurationMs = durationMs;
    debugPrint(
      '[SearchLatency] Metadata Enrichment: ${durationMs}ms (enriched=$enrichedCount, reqId=$reqId)',
    );
  }

  /// Records when first relevant result is delivered to UI.
  void recordFirstResultRendered(int reqId) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId || t.timeToFirstResultMs > 0) return;
    t.timeToFirstResultMs = t.stopwatch.elapsedMilliseconds;
    debugPrint('[SearchLatency] First Relevant Result Rendered: ${t.timeToFirstResultMs}ms (reqId=$reqId)');
  }

  /// Records when results are committed to state and ready for UI rendering.
  void recordResultsDelivered(int reqId, {required int totalResults}) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.deliveredTime = DateTime.now();
    t.totalLatencyMs = t.stopwatch.elapsedMilliseconds;
    if (t.timeToFirstResultMs == 0 && totalResults > 0) {
      t.timeToFirstResultMs = t.totalLatencyMs;
    }

    final hitRatePercent = (globalCacheHitRate * 100).toStringAsFixed(1);

    debugPrint(
      '[SearchLatency] ── SEARCH COMPLETED ──\n'
      '  • Request ID:          $reqId\n'
      '  • Time to 1st Result:  ${t.timeToFirstResultMs}ms\n'
      '  • Total Latency:       ${t.totalLatencyMs}ms\n'
      '  • Local Scan:          ${t.localDurationMs}ms (results=${t.localResultsCount})\n'
      '  • YouTube Request:     ${t.youtubeDurationMs}ms (cacheHit: ${t.isYouTubeCacheHit})\n'
      '  • Results Requested:   ${t.resultsRequested}\n'
      '  • Results Received:    ${t.resultsReceived}\n'
      '  • Relevant Results:    ${t.relevantResults}\n'
      '  • Irrelevant Filtered: ${t.irrelevantFiltered}\n'
      '  • Duplicates Removed:  ${t.duplicatesRemoved}\n'
      '  • Requests Made:       ${t.providerRequestsMade}\n'
      '  • Global Cache Rate:   $hitRatePercent%\n'
      '  • Total Results UI:    $totalResults',
    );
  }

  @visibleForTesting
  SearchTiming? get activeTiming => _activeTiming;

  @visibleForTesting
  void reset() {
    _activeTiming = null;
    _totalSearches = 0;
    _totalCacheHits = 0;
  }
}

class SearchTiming {
  final int reqId;
  final int queryLength;
  final DateTime inputTime;
  final Stopwatch stopwatch;

  DateTime? debounceCompletedTime;
  DateTime? localQueryStartTime;
  DateTime? localQueryEndTime;
  DateTime? youtubeRequestStartTime;
  DateTime? firstResponseTime;
  DateTime? filteringEndTime;
  DateTime? youtubeRequestEndTime;
  DateTime? deliveredTime;

  int debounceDurationMs = 0;
  int localStartMs = 0;
  int localDurationMs = 0;
  int localResultsCount = 0;
  int youtubeStartMs = 0;
  int youtubeDurationMs = 0;
  int timeToFirstResponseMs = 0;
  int parsingDurationMs = 0;
  int timeToFirstResultMs = 0;
  int enrichmentDurationMs = 0;
  int totalLatencyMs = 0;

  int resultsRequested = 0;
  int resultsReceived = 0;
  int relevantResults = 0;
  int irrelevantFiltered = 0;
  int duplicatesRemoved = 0;
  int providerRequestsMade = 0;

  bool isYouTubeCacheHit = false;

  SearchTiming({
    required this.reqId,
    required this.queryLength,
    required this.inputTime,
    Stopwatch? stopwatch,
  }) : stopwatch = stopwatch ?? (Stopwatch()..start());
}
