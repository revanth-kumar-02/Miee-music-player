import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Interactive playback waveform for Miee.
///
/// - Bar heights are generated deterministically from [trackId] so the same
///   song always shows the same shape, but different songs look different.
/// - [progress] drives which bars are "played" (dark) vs "remaining" (light).
/// - Supports tap and horizontal drag to seek (calls [onScrub] with 0.0–1.0).
/// - Uses a [CustomPainter] so every repaint is done on the raster thread and
///   never triggers widget rebuilds — safe to drive from an [AnimationController]
///   at 60 FPS.
class PlaybackWaveform extends StatefulWidget {
  /// Playback progress fraction 0.0 → 1.0.
  final double progress;

  /// Whether audio is currently playing.  When false the seek cursor still
  /// renders but the smooth-scroll animation is not needed.
  final bool isPlaying;

  /// Stable identifier for the current track — used to seed the bar heights.
  /// Pass an empty string or null when no track is loaded.
  final String? trackId;

  /// Called with a fraction 0.0–1.0 when the user taps or drags.
  final ValueChanged<double>? onScrub;

  /// Height of the waveform canvas.
  final double height;

  /// Number of bars to render.
  final int barCount;

  /// Color of played bars.  Defaults to [AppColors.onSurface].
  final Color? playedColor;

  /// Color of remaining bars.  Defaults to [AppColors.surfaceContainerHighest].
  final Color? remainingColor;

  const PlaybackWaveform({
    super.key,
    required this.progress,
    required this.isPlaying,
    this.trackId,
    this.onScrub,
    this.height = 56.0,
    this.barCount = 50,
    this.playedColor,
    this.remainingColor,
  });

  @override
  State<PlaybackWaveform> createState() => _PlaybackWaveformState();
}

class _PlaybackWaveformState extends State<PlaybackWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _ticker;

  /// Smoothed progress value written by the ticker and read by the painter.
  double _smoothProgress = 0.0;

  /// Bar heights for the current track — regenerated when trackId changes.
  late List<double> _barHeights;

  @override
  void initState() {
    super.initState();
    _barHeights = _generateBarHeights(widget.trackId, widget.barCount);
    _smoothProgress = widget.progress;

    _ticker = AnimationController(
      vsync: this,
      duration: const Duration(days: 1), // runs indefinitely
    );

    _ticker.addListener(_onTick);

    if (widget.isPlaying) {
      _ticker.forward();
    }
  }

  void _onTick() {
    // Lerp the displayed progress toward the real progress so transitions
    // between seek jumps animate smoothly rather than snapping.
    final target = widget.progress;
    final current = _smoothProgress;
    const lerpSpeed = 0.15; // fraction per frame — feels snappy but not jarring

    if ((target - current).abs() < 0.001) {
      if (_smoothProgress != target) {
        setState(() => _smoothProgress = target);
      }
    } else {
      setState(() {
        _smoothProgress = current + (target - current) * lerpSpeed;
      });
    }
  }

  @override
  void didUpdateWidget(PlaybackWaveform old) {
    super.didUpdateWidget(old);

    // Regenerate bar heights when the song changes.
    if (old.trackId != widget.trackId || old.barCount != widget.barCount) {
      _barHeights = _generateBarHeights(widget.trackId, widget.barCount);
    }

    // Start/stop the animation ticker based on play state.
    if (widget.isPlaying && !_ticker.isAnimating) {
      _ticker.forward(from: _ticker.value);
    } else if (!widget.isPlaying && _ticker.isAnimating) {
      _ticker.stop();
      // Still converge to the exact target when paused.
      if (mounted) setState(() => _smoothProgress = widget.progress);
    }
  }

  @override
  void dispose() {
    _ticker
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Bar-height generation
  // ---------------------------------------------------------------------------

  /// Generates [count] bar heights deterministically from [id].
  ///
  /// Uses a seeded LCG so the same track always produces the same waveform
  /// shape without requiring any file analysis.
  static List<double> _generateBarHeights(String? id, int count) {
    const minH = 4.0;
    const maxH = 44.0;

    // Compute a numeric seed from the string.
    int seed = 0x4b1d;
    final chars = (id ?? '').codeUnits;
    for (final c in chars) {
      seed = (seed * 31 + c) & 0xFFFFFFFF;
    }

    final rng = _LcgRandom(seed);
    final heights = <double>[];
    for (var i = 0; i < count; i++) {
      // Mix multiple samples so the distribution looks more like a real signal.
      final raw = (rng.next() + rng.next() + rng.next()) / 3.0;
      heights.add(minH + raw * (maxH - minH));
    }
    // Smooth with a simple 3-point moving average so bars don't spike wildly.
    final smoothed = List<double>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final prev = heights[math.max(0, i - 1)];
      final curr = heights[i];
      final next = heights[math.min(count - 1, i + 1)];
      smoothed[i] = (prev + curr * 2 + next) / 4.0;
    }
    return smoothed;
  }

  // ---------------------------------------------------------------------------
  // Gesture handling
  // ---------------------------------------------------------------------------

  void _handleGesture(double localX, BoxConstraints constraints) {
    if (widget.onScrub == null) return;
    final fraction = (localX / constraints.maxWidth).clamp(0.0, 1.0);
    widget.onScrub!(fraction);
    // Snap smooth progress immediately for instantaneous visual feedback.
    setState(() => _smoothProgress = fraction);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final played = widget.playedColor ?? AppColors.onSurface;
    final remaining = widget.remainingColor ?? AppColors.surfaceContainerHighest;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handleGesture(d.localPosition.dx, constraints),
          onHorizontalDragStart: (d) =>
              _handleGesture(d.localPosition.dx, constraints),
          onHorizontalDragUpdate: (d) =>
              _handleGesture(d.localPosition.dx, constraints),
          child: SizedBox(
            width: constraints.maxWidth,
            height: widget.height,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WaveformPainter(
                  barHeights: _barHeights,
                  progress: _smoothProgress,
                  playedColor: played,
                  remainingColor: remaining,
                  totalHeight: widget.height,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// CustomPainter
// =============================================================================

class _WaveformPainter extends CustomPainter {
  final List<double> barHeights;
  final double progress;
  final Color playedColor;
  final Color remainingColor;
  final double totalHeight;

  _WaveformPainter({
    required this.barHeights,
    required this.progress,
    required this.playedColor,
    required this.remainingColor,
    required this.totalHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (barHeights.isEmpty) return;

    final count = barHeights.length;
    const gap = 2.5; // px between bars
    final barW = (size.width - gap * (count - 1)) / count;
    if (barW <= 0) return;

    final playedPaint = Paint()
      ..color = playedColor
      ..style = PaintingStyle.fill;
    final remainingPaint = Paint()
      ..color = remainingColor
      ..style = PaintingStyle.fill;

    final activeBarIndex = (progress * count).clamp(0.0, count.toDouble());

    for (var i = 0; i < count; i++) {
      final isPlayed = i < activeBarIndex;

      // For the bar right at the boundary, partially blend played/remaining
      // so the cut-point feels smooth rather than binary.
      final Paint paint;
      if (i == activeBarIndex.floor() && activeBarIndex < count) {
        final frac = activeBarIndex - activeBarIndex.floor();
        final blended = Color.lerp(remainingColor, playedColor, frac)!;
        paint = Paint()
          ..color = blended
          ..style = PaintingStyle.fill;
      } else {
        paint = isPlayed ? playedPaint : remainingPaint;
      }

      final h = barHeights[i];
      final left = i * (barW + gap);
      final top = (totalHeight - h) / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barW, h),
        const Radius.circular(99),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) {
    return old.progress != progress ||
        old.playedColor != playedColor ||
        old.remainingColor != remainingColor ||
        old.barHeights != barHeights;
  }
}

// =============================================================================
// Tiny seeded LCG random for deterministic bar heights
// =============================================================================

class _LcgRandom {
  int _state;

  _LcgRandom(this._state);

  /// Returns a pseudo-random double in [0, 1).
  double next() {
    _state = (_state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_state & 0xFFFFFF) / 0x1000000;
  }
}
