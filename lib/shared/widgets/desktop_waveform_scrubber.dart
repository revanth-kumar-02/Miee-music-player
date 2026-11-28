import 'dart:math' as math;
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
  final String? trackKey;
  final List<double>? customRatios;

  static List<double> ratiosForTrack(
    String? trackId, {
    String? title,
    String? artist,
    int count = 60,
  }) {
    final seedInput =
        '${trackId ?? ''}|${(title ?? '').trim().toLowerCase()}|${(artist ?? '').trim().toLowerCase()}';
    if (seedInput == '||') {
      return _DiscreteWaveformScrubberState._barRatios;
    }
    var hash = 0x811c9dc5;
    for (var i = 0; i < seedInput.length; i++) {
      hash ^= seedInput.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    final rng = math.Random(hash);
    final phaseA = rng.nextDouble() * math.pi * 2;
    final phaseB = rng.nextDouble() * math.pi * 2;
    final freqA = 0.18 + rng.nextDouble() * 0.14;
    final freqB = 0.45 + rng.nextDouble() * 0.25;
    return List<double>.generate(count, (i) {
      final env = math.sin((i / math.max(1, count - 1)) * math.pi);
      final wave = 0.5 +
          0.26 * math.sin(i * freqA + phaseA) +
          0.22 * math.cos(i * freqB + phaseB);
      final jitter = (rng.nextDouble() - 0.5) * 0.24;
      return ((wave * (0.55 + 0.45 * env)) + jitter).clamp(0.22, 0.98);
    });
  }

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
    this.trackKey,
    this.customRatios,
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

  @override
  void didUpdateWidget(DiscreteWaveformScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trackKey != widget.trackKey) {
      _dragFraction = null;
    }
  }

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
    final ratios = widget.customRatios ?? _barRatios;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final count = ratios.length;
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
                  final barHeight = (ratios[index] * widget.height).clamp(4.0, widget.height);

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
