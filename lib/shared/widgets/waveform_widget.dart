import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Reusable Nordic Cobalt Waveform Widget.
///
/// Renders vertical amplitude bars representing audio playback.
/// Supports smooth playback progress coloring, interactive tap/drag scrubbing,
/// and subtle live oscillation when audio is playing.
class WaveformWidget extends StatefulWidget {
  /// Whether audio is actively playing.
  final bool isPlaying;

  /// Playback progress fraction from 0.0 to 1.0.
  final double activeProgress;

  /// Callback when user taps or drags across the waveform to seek.
  final ValueChanged<double>? onScrub;

  /// Active track / played region color. Defaults to [AppColors.electricCobalt].
  final Color? activeColor;

  /// Inactive track / unplayed region color. Defaults to [AppColors.paleConcrete].
  final Color? inactiveColor;

  /// Total height of the waveform. Defaults to 40.0.
  final double height;

  /// Number of vertical amplitude bars to render. Defaults to 46.
  final int barCount;

  /// Custom bar heights sequence if provided.
  final List<double>? customHeights;

  const WaveformWidget({
    super.key,
    required this.isPlaying,
    required this.activeProgress,
    this.onScrub,
    this.activeColor,
    this.inactiveColor,
    this.height = 40.0,
    this.barCount = 46,
    this.customHeights,
  });

  @override
  State<WaveformWidget> createState() => _WaveformWidgetState();
}

class _WaveformWidgetState extends State<WaveformWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;

  @visibleForTesting
  AnimationController get animationController => _animationController;

  // Curated deterministic 48-bar amplitude curve matching the Nordic Cobalt Now Playing reference
  static const List<double> _defaultHeights = [
    10.0, 14.0, 18.0, 12.0, 24.0, 32.0, 28.0, 40.0,
    48.0, 36.0, 22.0, 38.0, 52.0, 60.0, 44.0, 30.0,
    50.0, 64.0, 42.0, 26.0, 38.0, 48.0, 56.0, 34.0,
    22.0, 42.0, 58.0, 68.0, 52.0, 38.0, 24.0, 36.0,
    44.0, 30.0, 18.0, 28.0, 36.0, 24.0, 16.0, 22.0,
    18.0, 14.0, 20.0, 16.0, 12.0, 10.0, 8.0, 6.0,
  ];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
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
    final colorActive = widget.activeColor ?? AppColors.electricCobalt;
    final colorInactive = widget.inactiveColor ?? AppColors.paleConcrete;
    final heights = widget.customHeights ?? _defaultHeights;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => _handleScrub(width, details.localPosition.dx),
          onTapDown: (details) => _handleScrub(width, details.localPosition.dx),
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(width, widget.height),
              painter: _WaveformPainter(
                animation: _animationController,
                activeProgress: widget.activeProgress.clamp(0.0, 1.0),
                baseHeights: heights,
                activeColor: colorActive,
                inactiveColor: colorInactive,
                targetBarCount: widget.barCount,
              ),
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
  final int targetBarCount;

  _WaveformPainter({
    required this.animation,
    required this.activeProgress,
    required this.baseHeights,
    required this.activeColor,
    required this.inactiveColor,
    required this.targetBarCount,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final int count = targetBarCount.clamp(12, 64);
    if (count <= 0 || size.width <= 0) return;

    final double effectiveWidth = size.width;
    final double slotWidth = effectiveWidth / count;
    final double barWidth = (slotWidth * 0.50).clamp(2.0, 5.0);
    final double gap = (effectiveWidth - (count * barWidth)) / math.max(1, count - 1);
    final Radius cornerRadius = Radius.circular(barWidth / 2.0);

    // Max reference height in list is ~68
    final double scale = (size.height / 68.0).clamp(0.2, 1.2);

    final Paint activePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = activeColor;
    final Paint inactivePaint = Paint()
      ..style = PaintingStyle.fill
      ..color = inactiveColor;

    final animationValue = animation.value;
    final double animPhaseBase = animationValue * 2.0 * math.pi;

    for (int i = 0; i < count; i++) {
      final double barProgress = count > 1 ? i / (count - 1) : 0.0;
      final bool isBarActive = activeProgress > 0.0 && barProgress <= activeProgress;
      final paint = isBarActive ? activePaint : inactivePaint;

      // Select base height from list with wrap
      final double rawBase = baseHeights[i % baseHeights.length];

      // Subtle dynamic oscillation when playing (small breathing movement)
      final double phase = (i * 0.35) + animPhaseBase;
      final double osc = 0.85 + 0.15 * math.sin(phase).abs();
      final double height = (rawBase * osc * scale).clamp(3.0, size.height);

      final double left = i * (barWidth + gap);
      final double top = (size.height - height) / 2.0;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, barWidth, height),
          cornerRadius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.activeProgress != activeProgress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.targetBarCount != targetBarCount;
  }
}
