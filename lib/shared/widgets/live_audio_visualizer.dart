import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Live audio visualizer with animated vertical bars for the Miee player.
///
/// ## Features
/// - Slow-motion multi-sine wave animation for smooth and gentle transitions.
/// - Progress-based coloring: bars before current position are dark, remaining are light.
/// - Gestures: tap or drag to scrub/seek playback.
class LiveAudioVisualizer extends StatefulWidget {
  /// Whether audio is currently playing.
  final bool isPlaying;

  /// Stable track identifier to seed per-bar properties.
  final String? trackId;

  /// Playback progress fraction 0.0 → 1.0.
  final double progress;

  /// Called with fraction 0.0–1.0 when the user taps or drags.
  final ValueChanged<double>? onScrub;

  /// Number of animated bars.
  final int barCount;

  /// Total widget height.
  final double height;

  /// Color of played bars. Defaults to [AppColors.onSurface].
  final Color? barColor;

  /// Color of unplayed bars. Defaults to [AppColors.surfaceContainerHighest].
  final Color? restColor;

  const LiveAudioVisualizer({
    super.key,
    required this.isPlaying,
    required this.progress,
    this.trackId,
    this.onScrub,
    this.barCount = 24,
    this.height = 60.0,
    this.barColor,
    this.restColor,
  });

  @override
  State<LiveAudioVisualizer> createState() => _LiveAudioVisualizerState();
}

class _LiveAudioVisualizerState extends State<LiveAudioVisualizer>
    with TickerProviderStateMixin {
  /// Drives the continuously-advancing time value for bar oscillation.
  late AnimationController _timeCtrl;

  /// Fades bar amplitude 0 → 1 when playing starts, 1 → 0 when pausing.
  late AnimationController _ampCtrl;
  static const _fadeDuration = Duration(milliseconds: 350);

  // Per-bar properties seeded from trackId.
  late List<double> _freqs;    // angular frequency multiplier per bar
  late List<double> _phases;   // phase offset per bar (radians)
  late List<double> _relAmps;  // relative amplitude per bar (0.0–1.0)

  @override
  void initState() {
    super.initState();

    _initBarProperties();

    // Use a very large upper bound (100,000 seconds) so that the animation
    // value grows continuously without wrapping, preventing periodic jumps.
    _timeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 100000),
      upperBound: 100000.0,
    );

    _ampCtrl = AnimationController(vsync: this, duration: _fadeDuration);

    if (widget.isPlaying) {
      _timeCtrl.forward();
      _ampCtrl.forward();
    }
  }

  void _initBarProperties() {
    final id = widget.trackId ?? '';
    final n = widget.barCount;

    // Seed an LCG RNG from the track ID string.
    int seed = 0x4B1D;
    for (final c in id.codeUnits) {
      seed = (seed * 31 + c) & 0xFFFFFFFF;
    }
    final rng = _LcgRandom(seed);

    _freqs = List.generate(n, (_) {
      // Slow-mo: very low frequency multipliers for smooth, gentle oscillation
      return 0.2 + rng.next() * 0.4;
    });

    _phases = List.generate(n, (_) => rng.next() * 2.0 * math.pi);

    _relAmps = List.generate(n, (i) {
      // Bell-curve distribution: center bars are tallest (bass-range effect).
      final center = n / 2.0;
      final dist = (i - center).abs() / center;
      final bell = math.exp(-dist * dist * 2.0);
      return (0.45 + 0.55 * bell) * (0.7 + 0.3 * rng.next());
    });
  }

  @override
  void didUpdateWidget(LiveAudioVisualizer old) {
    super.didUpdateWidget(old);

    if (old.trackId != widget.trackId || old.barCount != widget.barCount) {
      _initBarProperties();
      _timeCtrl.value = 0.0;
      if (widget.isPlaying) {
        _timeCtrl.forward();
      }
    }

    if (widget.isPlaying && !old.isPlaying) {
      _timeCtrl.forward();
      _ampCtrl.forward();
    } else if (!widget.isPlaying && old.isPlaying) {
      _ampCtrl.reverse().whenCompleteOrCancel(() {
        if (!widget.isPlaying && mounted) {
          _timeCtrl.stop();
        }
      });
    }
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _ampCtrl.dispose();
    super.dispose();
  }

  void _handleGesture(double localX, BoxConstraints constraints) {
    if (widget.onScrub == null) return;
    final fraction = (localX / constraints.maxWidth).clamp(0.0, 1.0);
    widget.onScrub!(fraction);
  }

  @override
  Widget build(BuildContext context) {
    final barColor = widget.barColor ?? AppColors.onSurface;
    final restColor = widget.restColor ?? AppColors.surfaceContainerHighest;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _handleGesture(d.localPosition.dx, constraints),
          onHorizontalDragStart: (d) => _handleGesture(d.localPosition.dx, constraints),
          onHorizontalDragUpdate: (d) => _handleGesture(d.localPosition.dx, constraints),
          child: CustomPaint(
            size: Size(double.infinity, widget.height),
            painter: _VisualizerPainter(
              timeCtrl: _timeCtrl,
              ampCtrl: _ampCtrl,
              repaint: Listenable.merge([_timeCtrl, _ampCtrl]),
              progress: widget.progress,
              barCount: widget.barCount,
              freqs: _freqs,
              phases: _phases,
              relAmps: _relAmps,
              barColor: barColor,
              restColor: restColor,
              totalHeight: widget.height,
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// Custom painter — all drawing on the raster thread, zero widget rebuilds
// =============================================================================

class _VisualizerPainter extends CustomPainter {
  final AnimationController timeCtrl;
  final AnimationController ampCtrl;
  final double progress;
  final int barCount;
  final List<double> freqs;
  final List<double> phases;
  final List<double> relAmps;
  final Color barColor;
  final Color restColor;
  final double totalHeight;

  static const _minH = 4.0;   // minimum bar height (px)
  static const _maxH = 44.0;  // maximum bar height (px)
  static const _gap = 5.0;    // gap between bars (px) - cleaner spacing
  static const _barRadius = Radius.circular(99.0);

  _VisualizerPainter({
    required this.timeCtrl,
    required this.ampCtrl,
    required Listenable repaint,
    required this.progress,
    required this.barCount,
    required this.freqs,
    required this.phases,
    required this.relAmps,
    required this.barColor,
    required this.restColor,
    required this.totalHeight,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (barCount == 0) return;

    final barW = (size.width - _gap * (barCount - 1)) / barCount;
    if (barW <= 0) return;

    final paint = Paint()..style = PaintingStyle.fill;
    final t = timeCtrl.value * 2.0 * math.pi;
    final amplitude = ampCtrl.value;

    final activeBarIndex = (progress * barCount).clamp(0.0, barCount.toDouble());

    for (var i = 0; i < barCount; i++) {
      // Oscillation: value in [0, 1] for this bar at current time.
      final osc = 0.5 * (1.0 + math.sin(t * freqs[i] + phases[i]));

      // Active bar height (amplitude fades 0→1 with playback state).
      final activeH = _minH + (_maxH - _minH) * relAmps[i] * osc;
      const restH = _minH + 1.0;

      final h = restH + (activeH - restH) * amplitude;
      final left = i * (barW + _gap);
      final top = (totalHeight - h) / 2.0;

      // Check if bar is in the played region
      final isPlayed = i < activeBarIndex;
      final Color targetColor;

      if (i == activeBarIndex.floor() && activeBarIndex < barCount) {
        final frac = activeBarIndex - activeBarIndex.floor();
        targetColor = Color.lerp(restColor, barColor, frac)!;
      } else {
        targetColor = isPlayed ? barColor : restColor;
      }

      // Blend based on pause/play amplitude
      paint.color = Color.lerp(restColor, targetColor, amplitude)!;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barW, h),
          _barRadius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VisualizerPainter old) {
    return old.progress != progress ||
        old.barCount != barCount ||
        old.barColor != barColor ||
        old.restColor != restColor ||
        old.totalHeight != totalHeight ||
        old.freqs != freqs ||
        old.phases != phases ||
        old.relAmps != relAmps;
  }
}

// =============================================================================
// Tiny seeded LCG for deterministic per-track bar properties
// =============================================================================

class _LcgRandom {
  int _state;
  _LcgRandom(this._state);

  double next() {
    _state = (_state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return (_state & 0xFFFFFF) / 0x1000000;
  }
}
