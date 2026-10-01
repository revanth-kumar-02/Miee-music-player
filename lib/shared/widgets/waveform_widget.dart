import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Reusable Waveform Widget.
/// Renders a series of vertical bars representing track amplitude.
/// Oscillates smoothly when playing and pauses in place when playback pauses.
/// Supports interactive scrubbing and updates colored states based on progress.
class WaveformWidget extends StatefulWidget {
  /// Whether the player is currently playing audio.
  final bool isPlaying;

  /// Playback progress fraction from 0.0 to 1.0.
  final double activeProgress;

  /// Callback when the user taps or drags to scrub playback.
  final ValueChanged<double>? onScrub;

  /// Custom active track color. Defaults to [AppColors.primary].
  final Color? activeColor;

  /// Custom inactive track color. Defaults to [AppColors.surfaceContainerHighest].
  final Color? inactiveColor;

  const WaveformWidget({
    super.key,
    required this.isPlaying,
    required this.activeProgress,
    this.onScrub,
    this.activeColor,
    this.inactiveColor,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  // 28 balanced base heights with tapered edges for a refined music-player waveform
  static const List<double> _baseHeights = [
    4.0, 6.0, 10.0, 15.0, 20.0, 25.0, 28.0, 24.0, 18.0, 13.0,
    15.0, 21.0, 26.0, 28.0, 24.0, 18.0, 14.0, 19.0, 25.0, 27.0,
    22.0, 16.0, 12.0, 15.0, 10.0, 6.0, 4.0, 3.0,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.isPlaying) {
      _animationController.repeat();
    }
  }

  @override
  void didUpdateWidget(WaveformWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _animationController.repeat();
      } else {
        _animationController.stop();
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorActive = widget.activeColor ?? AppColors.primary;
    final colorInactive = widget.inactiveColor ?? AppColors.surfaceContainerHighest;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => _handleScrub(width, details.localPosition.dx),
          onTapDown: (details) => _handleScrub(width, details.localPosition.dx),
          child: CustomPaint(
            size: const Size(double.infinity, 38.0),
            painter: _WaveformPainter(
              animation: _animationController,
              activeProgress: widget.activeProgress,
              baseHeights: _baseHeights,
              activeColor: colorActive,
              inactiveColor: colorInactive,
            ),
          ),
        );
      },
    );
  }

  void _handleScrub(double width, double localX) {
    if (widget.onScrub == null || width <= 0) return;
    const double gap = 3.0;
    const double maxBarWidth = 4.0;
    final barCount = _baseHeights.length;
    final totalGaps = (barCount - 1) * gap;
    final desiredWaveformWidth = barCount * maxBarWidth + totalGaps;
    final actualWaveformWidth = math.min(desiredWaveformWidth, width);
    final startX = (width - actualWaveformWidth) / 2.0;

    final fraction = ((localX - startX) / actualWaveformWidth).clamp(0.0, 1.0);
    widget.onScrub!(fraction);
  }
}

class _WaveformPainter extends CustomPainter {
  final Animation<double> animation;
  final double activeProgress;
  final List<double> baseHeights;
  final Color activeColor;
  final Color inactiveColor;

  _WaveformPainter({
    required this.animation,
    required this.activeProgress,
    required this.baseHeights,
    required this.activeColor,
    required this.inactiveColor,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final barCount = baseHeights.length;
    if (barCount == 0 || size.width <= 0) return;

    const double gap = 3.0;
    const double maxBarWidth = 4.0;
    final double totalGaps = (barCount - 1) * gap;

    // Calculate bar width and total waveform width to ensure it is centered and bounded
    final double maxAvailableForBars = size.width - totalGaps;
    final double barWidth = math.min(maxBarWidth, maxAvailableForBars / barCount);
    final double totalWaveformWidth = barCount * barWidth + totalGaps;
    final double startX = (size.width - totalWaveformWidth) / 2.0;

    final paint = Paint()..style = PaintingStyle.fill;
    final animationValue = animation.value;

    for (int i = 0; i < barCount; i++) {
      final barProgress = i / barCount;
      final isBarActive = barProgress <= activeProgress;
      paint.color = isBarActive ? activeColor : inactiveColor;

      // Smooth oscillation offset per bar
      final phase = (i * 0.4) + (animationValue * 2.0 * math.pi);
      final osc = 0.5 + 0.5 * math.sin(phase).abs();
      final height = baseHeights[i] * osc;

      final left = startX + i * (barWidth + gap);
      final top = (size.height - height) / 2.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, math.max(1.0, barWidth), height),
          const Radius.circular(2.0),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.activeProgress != activeProgress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
