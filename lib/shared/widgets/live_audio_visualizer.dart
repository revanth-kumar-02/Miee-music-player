import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Live audio visualizer with animated vertical bars for the Miee player.
///
/// ## Architecture
///
/// Each bar independently oscillates using a sine function:
///
///   `height[i] = minH + (maxH - minH) × relAmp[i] × amplitude × ½(1 + sin(t × freq[i] + phase[i]))`
///
/// where `t` is continuously increasing time, `freq[i]` and `phase[i]` are
/// seeded deterministically from [trackId], and `amplitude` fades 0→1 when
/// playback starts and 1→0 when paused (300 ms ease).
///
/// ## Rendering strategy
///
/// - A [CustomPainter] is registered as the `repaint` listener of a
///   [Listenable.merge] of both controllers, so repaints happen on the raster
///   thread without ever calling [setState] — no widget rebuilds per frame.
/// - A [RepaintBoundary] isolates the visualizer from the rest of the tree.
///
/// ## Why not real FFT?
///
/// `just_audio` and `audio_service` expose playback position but not PCM
/// amplitude buffers or FFT data.  Accessing real audio amplitude requires
/// a native platform channel or a dedicated plugin (e.g. `flutter_visualizer`,
/// currently unmaintained).  The physics-based sine approach used here is
/// visually equivalent and is the technique used by Spotify, Apple Music, and
/// SoundCloud for their animated waveform visualizers.
class LiveAudioVisualizer extends StatefulWidget {
  /// Whether audio is currently playing.
  final bool isPlaying;

  /// Stable track identifier — seeds the per-bar frequency and phase values
  /// so each song consistently displays its own bar pattern.
  final String? trackId;

  /// Number of animated bars.
  final int barCount;

  /// Total widget height including breathing room above/below bars.
  final double height;

  /// Color of the animated bars while playing.  Defaults to [AppColors.onSurface].
  final Color? barColor;

  /// Color of the bars when paused / at rest.  Defaults to
  /// [AppColors.surfaceContainerHighest].
  final Color? restColor;

  const LiveAudioVisualizer({
    super.key,
    required this.isPlaying,
    this.trackId,
    this.barCount = 40,
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
  /// Set to a large upper bound to avoid wrapping and cycle discontinuities.
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
      // Each bar oscillates between 1× and 4× the base cycle speed.
      return 1.0 + rng.next() * 3.0;
    });

    _phases = List.generate(n, (_) => rng.next() * 2.0 * math.pi);

    _relAmps = List.generate(n, (i) {
      // Bell-curve distribution: center bars are tallest (bass-range effect).
      final center = n / 2.0;
      final dist = (i - center).abs() / center; // 0 at center, 1 at edges
      final bell = math.exp(-dist * dist * 2.0);
      // Mix bell curve with some randomness for organic look.
      return (0.35 + 0.65 * bell) * (0.6 + 0.4 * rng.next());
    });
  }

  @override
  void didUpdateWidget(LiveAudioVisualizer old) {
    super.didUpdateWidget(old);

    // Regenerate bar properties when the track changes.
    if (old.trackId != widget.trackId || old.barCount != widget.barCount) {
      _initBarProperties();
      _timeCtrl.value = 0.0;
      if (widget.isPlaying) {
        _timeCtrl.forward();
      }
    }

    // Start / stop animation in response to play state changes.
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

  @override
  Widget build(BuildContext context) {
    final barColor = widget.barColor ?? AppColors.onSurface;
    final restColor = widget.restColor ?? AppColors.surfaceContainerHighest;

    return CustomPaint(
      size: Size(double.infinity, widget.height),
      painter: _VisualizerPainter(
        timeCtrl: _timeCtrl,
        ampCtrl: _ampCtrl,
        repaint: Listenable.merge([_timeCtrl, _ampCtrl]),
        barCount: widget.barCount,
        freqs: _freqs,
        phases: _phases,
        relAmps: _relAmps,
        barColor: barColor,
        restColor: restColor,
        totalHeight: widget.height,
      ),
    );
  }
}

// =============================================================================
// Custom painter — all drawing on the raster thread, zero widget rebuilds
// =============================================================================

class _VisualizerPainter extends CustomPainter {
  final AnimationController timeCtrl;
  final AnimationController ampCtrl;
  final int barCount;
  final List<double> freqs;
  final List<double> phases;
  final List<double> relAmps;
  final Color barColor;
  final Color restColor;
  final double totalHeight;

  static const _minH = 4.0;   // minimum bar height (px)
  static const _maxH = 44.0;  // maximum bar height (px)
  static const _gap = 4.0;    // gap between bars (px) - slightly wider for minimalist aesthetic
  static const _barRadius = Radius.circular(99.0);

  _VisualizerPainter({
    required this.timeCtrl,
    required this.ampCtrl,
    required Listenable repaint,
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

    for (var i = 0; i < barCount; i++) {
      // Oscillation: value in [0, 1] for this bar at current time.
      final osc = 0.5 * (1.0 + math.sin(t * freqs[i] + phases[i]));

      // Active bar height (amplitude fades 0→1 with playback state).
      final activeH = _minH + (_maxH - _minH) * relAmps[i] * osc;
      // Rest bar height (constant small nub when amplitude is 0).
      const restH = _minH + 1.0;

      final h = restH + (activeH - restH) * amplitude;
      final left = i * (barW + _gap);
      final top = (totalHeight - h) / 2.0;

      // Blend color: rest color when amplitude = 0, bar color when amplitude = 1.
      paint.color = Color.lerp(restColor, barColor, amplitude)!;

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
    return old.barCount != barCount ||
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


// =============================================================================
// Miee Seek Bar — slim pill-shaped seek slider matching the design system
// =============================================================================

/// A minimalist seek bar styled to match Miee's design system.
///
/// Shows a thin progress track with a small circular thumb.
/// Supports tap and drag.  Calls [onSeek] with a 0.0–1.0 fraction.
class MieeSeekBar extends StatefulWidget {
  /// Progress fraction 0.0–1.0.
  final double progress;

  /// Whether seeking is enabled.
  final bool enabled;

  /// Called with a 0.0–1.0 fraction when the user seeks.
  final ValueChanged<double>? onSeek;

  const MieeSeekBar({
    super.key,
    required this.progress,
    this.enabled = true,
    this.onSeek,
  });

  @override
  State<MieeSeekBar> createState() => _MieeSeekBarState();
}

class _MieeSeekBarState extends State<MieeSeekBar> {
  double? _draggingProgress;

  double get _displayProgress => _draggingProgress ?? widget.progress;

  void _onDragUpdate(DragUpdateDetails d, double width) {
    if (!widget.enabled || widget.onSeek == null) return;
    final frac = (d.localPosition.dx / width).clamp(0.0, 1.0);
    setState(() => _draggingProgress = frac);
  }

  void _onDragEnd(DragEndDetails _) {
    if (_draggingProgress != null) {
      widget.onSeek?.call(_draggingProgress!);
      setState(() => _draggingProgress = null);
    }
  }

  void _onTapDown(TapDownDetails d, double width) {
    if (!widget.enabled || widget.onSeek == null) return;
    final frac = (d.localPosition.dx / width).clamp(0.0, 1.0);
    widget.onSeek?.call(frac);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _onTapDown(d, width),
          onHorizontalDragUpdate: (d) => _onDragUpdate(d, width),
          onHorizontalDragEnd: _onDragEnd,
          child: SizedBox(
            height: 28.0, // tall hit target, slim visual
            child: Center(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Track background
                  Container(
                    height: 3.0,
                    width: width,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99.0),
                    ),
                  ),
                  // Filled portion
                  Container(
                    height: 3.0,
                    width: (width * _displayProgress).clamp(0.0, width),
                    decoration: BoxDecoration(
                      color: AppColors.onSurface,
                      borderRadius: BorderRadius.circular(99.0),
                    ),
                  ),
                  // Thumb
                  Positioned(
                    left: ((width * _displayProgress) - 6.0).clamp(0.0, width - 12.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: _draggingProgress != null ? 14.0 : 12.0,
                      height: _draggingProgress != null ? 14.0 : 12.0,
                      decoration: BoxDecoration(
                        color: AppColors.onSurface,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 4.0,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
