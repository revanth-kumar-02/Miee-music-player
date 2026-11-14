import 'package:flutter/foundation.dart';

/// Lightweight performance diagnostic tracer for song search workflows.
///
/// Traces:
///   - User input received
///   - Debounce elapsed
///   - Local library scan duration
///   - YouTube Music API request duration
///   - Metadata enrichment duration
///   - UI results delivery and latency
///
/// Diagnostic prefix: `[SearchLatency]`
/// Never logs authentication tokens, signed URLs, or personal data.
class SearchDiagnostics {
  static final SearchDiagnostics _instance = SearchDiagnostics._internal();
  factory SearchDiagnostics() => _instance;
  SearchDiagnostics._internal();

  SearchTiming? _activeTiming;

  /// Records when user inputs/types a search query.
  void recordInput({required String query, required int reqId}) {
    final now = DateTime.now();
    _activeTiming = SearchTiming(
      reqId: reqId,
      queryLength: query.trim().length,
      inputTime: now,
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
    final delayMs = t.debounceCompletedTime!.difference(t.inputTime).inMilliseconds;
    debugPrint('[SearchLatency] Debounce Completed: +${delayMs}ms (reqId=$reqId)');
  }

  /// Records start of local database/library query.
  void recordLocalQueryStart(int reqId) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.localQueryStartTime = DateTime.now();
  }

  /// Records completion of local database/library query.
  void recordLocalQueryEnd(int reqId, {required int resultCount}) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.localQueryEndTime = DateTime.now();
    final durationMs = t.localQueryStartTime != null
        ? t.localQueryEndTime!.difference(t.localQueryStartTime!).inMilliseconds
        : 0;
    t.localDurationMs = durationMs;
    debugPrint(
      '[SearchLatency] Local Library Search: ${durationMs}ms (results=$resultCount, reqId=$reqId)',
    );
  }

  /// Records start of remote YouTube search query.
  void recordYouTubeRequestStart(int reqId) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.youtubeRequestStartTime = DateTime.now();
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
    final durationMs = t.youtubeRequestStartTime != null
        ? t.youtubeRequestEndTime!.difference(t.youtubeRequestStartTime!).inMilliseconds
        : 0;
    t.youtubeDurationMs = durationMs;
    t.isYouTubeCacheHit = fromCache;
    debugPrint(
      '[SearchLatency] YouTube Request ${success ? "SUCCESS" : "FAILED"}: ${durationMs}ms (fromCache=$fromCache, results=$resultCount, reqId=$reqId)',
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

  /// Records when results are committed to state and ready for UI rendering.
  void recordResultsDelivered(int reqId, {required int totalResults}) {
    final t = _activeTiming;
    if (t == null || t.reqId != reqId) return;
    t.deliveredTime = DateTime.now();
    final totalLatencyMs = t.deliveredTime!.difference(t.inputTime).inMilliseconds;
    t.totalLatencyMs = totalLatencyMs;

    debugPrint(
      '[SearchLatency] ── SEARCH COMPLETED ──\n'
      '  • Request ID:      $reqId\n'
      '  • Local Scan:      ${t.localDurationMs}ms\n'
      '  • YouTube Request: ${t.youtubeDurationMs}ms (cacheHit: ${t.isYouTubeCacheHit})\n'
      '  • Enrichment:      ${t.enrichmentDurationMs}ms\n'
      '  • Total Latency:   ${totalLatencyMs}ms\n'
      '  • Total Results:   $totalResults',
    );
  }

  @visibleForTesting
  SearchTiming? get activeTiming => _activeTiming;
}

class SearchTiming {
  final int reqId;
  final int queryLength;
  final DateTime inputTime;
  DateTime? debounceCompletedTime;
  DateTime? localQueryStartTime;
  DateTime? localQueryEndTime;
  DateTime? youtubeRequestStartTime;
  DateTime? youtubeRequestEndTime;
  DateTime? deliveredTime;
  int localDurationMs = 0;
  int youtubeDurationMs = 0;
  int enrichmentDurationMs = 0;
  int totalLatencyMs = 0;
  bool isYouTubeCacheHit = false;

  SearchTiming({
    required this.reqId,
    required this.queryLength,
    required this.inputTime,
  });
}

