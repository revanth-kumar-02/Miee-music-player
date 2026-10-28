import 'package:flutter/foundation.dart';

/// Structured, sanitized playback performance and latency diagnostic tracer.
///
/// Traces every phase of track selection:
/// Home song tap → selected-track handling → queue update → stream resolution
/// → audio source creation → player load → confirmed playing state.
///
/// Never logs credentials, cookies, tokens, or personal information.
class PlaybackDiagnostics {
  static final PlaybackDiagnostics _instance = PlaybackDiagnostics._internal();
  factory PlaybackDiagnostics() => _instance;
  PlaybackDiagnostics._internal();

  /// Holds in-flight diagnostic timestamps for the active request.
  TrackTiming? _activeTiming;

  /// Starts tracing a user song tap.
  void recordTap({
    required String trackId,
    required String title,
    required bool isYoutube,
  }) {
    final sanitizedId = _sanitizeId(trackId);
    final now = DateTime.now();
    _activeTiming = TrackTiming(
      sanitizedId: sanitizedId,
      sourceType: isYoutube ? 'YouTube' : 'Local',
      tapTime: now,
    );

    debugPrint(
      '[PlaybackLatency] ── TAP REGISTERED ── id=$sanitizedId source=${_activeTiming!.sourceType} title="$title"',
    );
  }

  /// Records when the UI updates the selected track and queue.
  void recordSelectedTrackUpdated(String trackId) {
    final t = _activeTiming;
    if (t == null || t.sanitizedId != _sanitizeId(trackId)) return;
    t.selectedUpdateTime = DateTime.now();
    final delayMs = t.selectedUpdateTime!.difference(t.tapTime).inMilliseconds;
    debugPrint(
      '[PlaybackLatency] UI Feedback & Queue Updated: +${delayMs}ms (id=${t.sanitizedId})',
    );
  }

  /// Records the start of stream resolution (for YouTube tracks).
  void recordStreamResolutionStart(String trackId) {
    final t = _activeTiming;
    if (t == null || t.sanitizedId != _sanitizeId(trackId)) return;
    t.resolutionStartTime = DateTime.now();
  }

  /// Records the end of stream resolution.
  void recordStreamResolutionEnd(String trackId, {required bool fromCache, required bool success}) {
    final t = _activeTiming;
    if (t == null || t.sanitizedId != _sanitizeId(trackId)) return;
    t.resolutionEndTime = DateTime.now();
    final durationMs = t.resolutionStartTime != null
        ? t.resolutionEndTime!.difference(t.resolutionStartTime!).inMilliseconds
        : 0;
    t.resolutionDurationMs = durationMs;
    t.isCacheHit = fromCache;

    debugPrint(
      '[PlaybackLatency] Stream Resolution ${success ? "SUCCESS" : "FAILED"}: ${durationMs}ms (cacheHit=$fromCache) (id=${t.sanitizedId})',
    );
  }

  /// Records the start of audio player source loading.
  void recordPlayerLoadStart(String trackId) {
    final t = _activeTiming;
    if (t == null || t.sanitizedId != _sanitizeId(trackId)) return;
    t.playerLoadStartTime = DateTime.now();
  }

  /// Records the completion of audio player source loading.
  void recordPlayerLoadEnd(String trackId, {required bool success}) {
    final t = _activeTiming;
    if (t == null || t.sanitizedId != _sanitizeId(trackId)) return;
    t.playerLoadEndTime = DateTime.now();
    final durationMs = t.playerLoadStartTime != null
        ? t.playerLoadEndTime!.difference(t.playerLoadStartTime!).inMilliseconds
        : 0;
    t.playerLoadDurationMs = durationMs;

    debugPrint(
      '[PlaybackLatency] Audio Source Loaded: ${durationMs}ms (success=$success) (id=${t.sanitizedId})',
    );
  }

  /// Records the confirmed playing state (`playing == true` and `processingState == ready`).
  void recordConfirmedPlaying(String trackId) {
    final t = _activeTiming;
    if (t == null || t.sanitizedId != _sanitizeId(trackId)) return;
    if (t.confirmedPlayingTime != null) return; // Only log first playing event

    t.confirmedPlayingTime = DateTime.now();
    final totalLatencyMs = t.confirmedPlayingTime!.difference(t.tapTime).inMilliseconds;
    t.totalLatencyMs = totalLatencyMs;

    final tapToUiMs = t.selectedUpdateTime != null
        ? t.selectedUpdateTime!.difference(t.tapTime).inMilliseconds
        : 0;

    debugPrint(
      '[PlaybackLatency] ── PLAYBACK CONFIRMED ──\n'
      '  • Track ID:          ${t.sanitizedId}\n'
      '  • Source:            ${t.sourceType}\n'
      '  • Tap -> UI Update:  ${tapToUiMs}ms\n'
      '  • Stream Resolution: ${t.resolutionDurationMs}ms (cached: ${t.isCacheHit})\n'
      '  • Player Load:       ${t.playerLoadDurationMs}ms\n'
      '  • Total Tap->Play:   ${totalLatencyMs}ms',
    );
  }

  /// Records an error during loading.
  void recordError(String trackId, String error) {
    final t = _activeTiming;
    if (t == null || t.sanitizedId != _sanitizeId(trackId)) return;
    final elapsedMs = DateTime.now().difference(t.tapTime).inMilliseconds;
    debugPrint(
      '[PlaybackLatency] ── ERROR AFTER ${elapsedMs}ms ── id=${t.sanitizedId}: $error',
    );
  }

  /// Helper to return current active timing for testing/asserting metrics.
  TrackTiming? get activeTiming => _activeTiming;

  String _sanitizeId(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '');
  }
}

class TrackTiming {
  final String sanitizedId;
  final String sourceType;
  final DateTime tapTime;
  DateTime? selectedUpdateTime;
  DateTime? resolutionStartTime;
  DateTime? resolutionEndTime;
  DateTime? playerLoadStartTime;
  DateTime? playerLoadEndTime;
  DateTime? confirmedPlayingTime;
  int resolutionDurationMs = 0;
  int playerLoadDurationMs = 0;
  int totalLatencyMs = 0;
  bool isCacheHit = false;

  TrackTiming({
    required this.sanitizedId,
    required this.sourceType,
    required this.tapTime,
  });
}
