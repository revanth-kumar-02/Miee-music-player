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

  /// Custom inactive track color. Defaults to [AppColors.oatBeige].
  final Color? inactiveColor;

  /// Total height of the waveform. Defaults to 32.0.
  final double height;

  const WaveformWidget({
    super.key,
    required this.isPlaying,
    required this.activeProgress,
    this.onScrub,
    this.activeColor,
    this.inactiveColor,
    this.height = 32.0,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @visibleForTesting
  AnimationController get animationController => _animationController;

  // 32 signature amplitude heights matching Miee's original visualizer layout
  static const List<double> _baseHeights = [
    8.0, 12.0, 20.0, 16.0, 24.0, 32.0, 20.0, 36.0,
    40.0, 28.0, 16.0, 44.0, 32.0, 24.0, 48.0, 36.0,
    20.0, 28.0, 40.0, 24.0, 16.0, 32.0, 20.0, 12.0,
    24.0, 16.0, 28.0, 8.0, 20.0, 12.0, 16.0, 8.0,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
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
        if (!_animationController.isAnimating) {
          _animationController.repeat();
        }
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
    final colorActive = widget.activeColor ?? AppColors.dustyRose;
    final colorInactive = widget.inactiveColor ?? AppColors.oatBeige;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => _handleScrub(width, details.localPosition.dx),
          onTapDown: (details) => _handleScrub(width, details.localPosition.dx),
          child: CustomPaint(
            size: Size(double.infinity, widget.height),
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

    final double effectiveWidth = size.width;
    final double startX = 0.0;

    if (barCount == 1) {
      final height = baseHeights[0];
      final paint = Paint()..style = PaintingStyle.fill..color = activeProgress > 0 ? activeColor : inactiveColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH((effectiveWidth - 4.0) / 2.0, (size.height - height) / 2.0, 4.0, height),
          const Radius.circular(2.0),
        ),
        paint,
      );
      return;
    }

    // Proportionally size bar width and gaps to cleanly fill effectiveWidth
    final double slotWidth = effectiveWidth / barCount;
    final double barWidth = (slotWidth * 0.52).clamp(2.5, 7.0);
    final double gap = (effectiveWidth - (barCount * barWidth)) / (barCount - 1);

    final paint = Paint()..style = PaintingStyle.fill;
    final animationValue = animation.value;

    for (int i = 0; i < barCount; i++) {
      final barProgress = i / (barCount - 1);
      final isBarActive = activeProgress > 0.0 && barProgress <= activeProgress;
      paint.color = isBarActive ? activeColor : inactiveColor;

      // Smooth oscillation offset per bar
      final phase = (i * 0.42) + (animationValue * 2.0 * math.pi);
      final osc = 0.45 + 0.55 * math.sin(phase).abs();
      final scale = (size.height / 48.0).clamp(0.2, 1.5);
      final height = (baseHeights[i] * osc * scale).clamp(2.5, size.height);

      final left = startX + i * (barWidth + gap);
      final top = (size.height - height) / 2.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, math.max(1.0, barWidth), height),
          Radius.circular(barWidth / 2.0),
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
