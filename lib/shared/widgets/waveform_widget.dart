import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Reusable Waveform Widget.
/// Renders a series of vertical bars representing track amplitude.
/// Supports interactive scrubbing and updates colored states based on progress.
class WaveformWidget extends StatelessWidget {
  /// Playback progress fraction from 0.0 to 1.0.
  final double activeProgress;

  /// Optional list of heights for the waveform bars.
  /// If null, a standard pattern of 32 bars is used.
  final List<double>? barHeights;

  /// Callback when the user taps or drags to scrub playback.
  final ValueChanged<double>? onScrub;

  /// Custom active track color. Defaults to [AppColors.primary].
  final Color? activeColor;

  /// Custom inactive track color. Defaults to [AppColors.surfaceContainerHighest].
  final Color? inactiveColor;

  const WaveformWidget({
    super.key,
    required this.activeProgress,
    this.barHeights,
    this.onScrub,
    this.activeColor,
    this.inactiveColor,
  });

  // Default amplitude heights matching the Miee Now Playing visualizer layout
  static const List<double> _defaultHeights = [
    8.0, 12.0, 20.0, 16.0, 24.0, 32.0, 20.0, 36.0,
    40.0, 28.0, 16.0, 44.0, 32.0, 24.0, 48.0, 36.0,
    20.0, 28.0, 40.0, 24.0, 16.0, 32.0, 20.0, 12.0,
    24.0, 16.0, 28.0, 8.0, 20.0, 12.0, 16.0, 8.0,
  ];

  @override
  Widget build(BuildContext context) {
    final heights = barHeights ?? _defaultHeights;
    final totalBars = heights.length;

    final colorActive = activeColor ?? AppColors.primary;
    final colorInactive = inactiveColor ?? AppColors.surfaceContainerHighest;

    return GestureDetector(
      onHorizontalDragUpdate: (details) => _handleScrub(context, details.localPosition.dx),
      onTapDown: (details) => _handleScrub(context, details.localPosition.dx),
      child: Container(
        height: 52.0,
        width: double.infinity,
        color: Colors.transparent, // transparent canvas to catch gestures
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: Alignment.center,
          children: List.generate(totalBars, (index) {
            // Determine if this bar lies within the active progress region
            final barProgress = index / totalBars;
            final isBarActive = barProgress <= activeProgress;

            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                height: heights[index],
                decoration: BoxDecoration(
                  color: isBarActive ? colorActive : colorInactive,
                  borderRadius: BorderRadius.circular(99.0),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  void _handleScrub(BuildContext context, double localX) {
    if (onScrub == null) return;
    
    // Find the render box to compute width
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final width = renderBox.size.width;
    if (width <= 0) return;

    // Calculate scrub fraction clamped to 0.0 - 1.0
    final fraction = (localX / width).clamp(0.0, 1.0);
    onScrub!(fraction);
  }
}
