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

  // 18 centered, wider base heights forming a premium double-peak audio waveform pattern.
  static const List<double> _baseHeights = [
    12.0, 18.0, 26.0, 38.0, 46.0, 42.0, 32.0, 22.0, 16.0,
    16.0, 22.0, 32.0, 42.0, 46.0, 38.0, 26.0, 18.0, 12.0,
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
            size: const Size(double.infinity, 52.0),
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
    final fraction = (localX / width).clamp(0.0, 1.0);
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

    // Dynamically calculate bar width so bars span the entire width of the painter area
    const double gap = 4.0;
    final double barWidth = (size.width - (barCount - 1) * gap) / barCount;

    final paint = Paint()..style = PaintingStyle.fill;

    final animationValue = animation.value;

    for (int i = 0; i < barCount; i++) {
      // Determine active color status
      final barProgress = i / barCount;
      final isBarActive = barProgress <= activeProgress;
      paint.color = isBarActive ? activeColor : inactiveColor;

      // Phase offset for a wavy, rolling visual effect
      final phase = (i * 0.45) + (animationValue * 2.0 * math.pi);
      // Smooth oscillation between [0.35, 1.0] of base height
      final osc = 0.35 + 0.65 * math.sin(phase).abs();
      final height = baseHeights[i] * osc;

      // Center vertically within the painter canvas
      final left = i * (barWidth + gap);
      final top = (size.height - height) / 2.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, math.max(1.0, barWidth), height),
          const Radius.circular(99.0),
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
