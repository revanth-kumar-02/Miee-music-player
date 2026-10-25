import 'package:flutter/material.dart';
import '../../app/theme/web_colors.dart';

/// Interactive Discrete Waveform Scrubber.
/// Renders 60 vertical amplitude bars matching the Miee Editorial Web/Desktop design system.
/// Active bars are painted in [MieeWebColors.waveformPlayed] (#6E0D25) and unplayed bars in [MieeWebColors.waveformNeutral] (#D5CDD0).
/// Supports instantaneous tap and drag scrubbing.
class DiscreteWaveformScrubber extends StatefulWidget {
  final double progress;
  final bool isPlaying;
  final ValueChanged<double> onSeek;
  final double height;
  final double barWidth;
  final double barSpacing;
  final Color? playedColor;
  final Color? unplayedColor;

  const DiscreteWaveformScrubber({
    super.key,
    required this.progress,
    required this.isPlaying,
    required this.onSeek,
    this.height = 28.0,
    this.barWidth = 3.0,
    this.barSpacing = 2.5,
    this.playedColor,
    this.unplayedColor,
  });

  @override
  State<DiscreteWaveformScrubber> createState() => _DiscreteWaveformScrubberState();
}

class _DiscreteWaveformScrubberState extends State<DiscreteWaveformScrubber> {
  // 60 calibrated signature amplitude ratios from 07_desktop_miee_now_playing.html
  static const List<double> _barRatios = [
    0.24, 0.38, 0.52, 0.32, 0.68, 0.58, 0.80, 0.94, 0.82, 0.46,
    0.56, 0.90, 0.70, 0.42, 0.76, 0.96, 0.84, 0.60, 0.44, 0.78,
    0.98, 0.72, 0.60, 0.88, 0.80, 0.62, 0.50, 0.82, 0.92, 0.65,
    0.38, 0.70, 0.84, 0.54, 0.46, 0.72, 0.95, 0.68, 0.48, 0.62,
    0.85, 0.76, 0.52, 0.65, 0.82, 0.72, 0.55, 0.36, 0.66, 0.84,
    0.60, 0.44, 0.70, 0.48, 0.34, 0.56, 0.40, 0.26, 0.48, 0.36,
  ];

  double? _dragFraction;

  void _handleSeek(double localX, double totalWidth) {
    if (totalWidth <= 0) return;
    final fraction = (localX / totalWidth).clamp(0.0, 1.0);
    setState(() => _dragFraction = fraction);
    widget.onSeek(fraction);
  }

  @override
  Widget build(BuildContext context) {
    final effectiveProgress = (_dragFraction ?? widget.progress).clamp(0.0, 1.0);
    final activeColor = widget.playedColor ?? MieeWebColors.waveformPlayed;
    final inactiveColor = widget.unplayedColor ?? MieeWebColors.waveformNeutral;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final count = _barRatios.length;
        final activeIndex = (effectiveProgress * count).round();

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _handleSeek(details.localPosition.dx, totalWidth),
            onHorizontalDragStart: (details) => _handleSeek(details.localPosition.dx, totalWidth),
            onHorizontalDragUpdate: (details) => _handleSeek(details.localPosition.dx, totalWidth),
            onHorizontalDragEnd: (_) => setState(() => _dragFraction = null),
            onHorizontalDragCancel: () => setState(() => _dragFraction = null),
            child: SizedBox(
              height: widget.height,
              width: totalWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(count, (index) {
                  final isPlayed = index < activeIndex;
                  final barHeight = (_barRatios[index] * widget.height).clamp(4.0, widget.height);

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: widget.barWidth,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: isPlayed ? activeColor : inactiveColor,
                      borderRadius: BorderRadius.circular(widget.barWidth / 2),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}
