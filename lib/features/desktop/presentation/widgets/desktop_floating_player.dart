import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/providers.dart';
import '../../../artwork/presentation/miee_artwork_image.dart';

/// The floating, pill-shaped music player positioned near the bottom centre
/// of the application, strictly reproducing the First Reference Image.
///
/// Features:
/// - Smoked-glass acrylic pill with soft border and shadow (Width: ~670px, Height: 64px)
/// - Circular album artwork on the left + track title & artist
/// - Subtle shuffle control
/// - Central warm amber/rose gradient waveform + progress scrubber with amber playhead dot + dual timecodes
/// - Tactile Previous, circular Play/Pause, and Next controls
class DesktopFloatingPlayer extends ConsumerWidget {
  final VoidCallback? onOpenNowSpinning;
  final VoidCallback? onToggleQueue;

  const DesktopFloatingPlayer({
    super.key,
    this.onOpenNowSpinning,
    this.onToggleQueue,
  });

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final currentTrack = playbackState.currentTrack;
    final isPlaying = playbackState.status == PlaybackStatus.playing;
    final position = playbackState.position;
    final duration = playbackState.duration;

    final totalMs = duration.inMilliseconds > 0 ? duration.inMilliseconds.toDouble() : 1.0;
    final progress = (position.inMilliseconds / totalMs).clamp(0.0, 1.0);

    return Container(
      width: 670,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xD916141B), // Softer smoked dark velvet glass
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: const Color(0x1AFFEBF0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 28,
            offset: const Offset(0, 10),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: MidnightVelvetTokens.primaryEmber.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: MidnightVelvetTokens.glassBlurSigma,
            sigmaY: MidnightVelvetTokens.glassBlurSigma,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                // ── 1. Circular Album Art & Track Meta (Left) ───────────
                GestureDetector(
                  onTap: onOpenNowSpinning,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0x26FFEBF0),
                        width: 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: MidnightVelvetTokens.primaryEmber.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: (currentTrack != null && currentTrack.effectiveArtworkUrl.isNotEmpty)
                          ? MieeArtworkImage(
                              explicitUrl: currentTrack.effectiveArtworkUrl,
                              fit: BoxFit.cover,
                              placeholder: _buildDefaultDiscArt(),
                              errorWidget: _buildDefaultDiscArt(),
                            )
                          : _buildDefaultDiscArt(),
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Track Title & Artist + Shuffle underneath
                SizedBox(
                  width: 105,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTrack?.displayTitle ?? 'Mieeemile',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFECE7E2),
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        currentTrack?.artist ?? 'Rose·Smber',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF9E9793),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      GestureDetector(
                        onTap: () => controller.toggleShuffle(),
                        child: Icon(
                          Icons.shuffle_rounded,
                          size: 13,
                          color: playbackState.isShuffleEnabled
                              ? MidnightVelvetTokens.primaryEmber
                              : const Color(0xFF6B656F),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 6),

                // ── 2. Central Waveform & Timecode Scrubber (Center) ────
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Amber-to-Rose Glowing Gradient Waveform
                      SizedBox(
                        height: 20,
                        child: _buildGradientWaveform(progress, isPlaying),
                      ),
                      const SizedBox(height: 3),

                      // Linear Scrubber + Dual Timecodes + Amber Playhead Dot
                      Row(
                        children: [
                          Text(
                            _formatDuration(position),
                            style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                              fontSize: 9,
                              color: const Color(0xFF78716C),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) {
                                _handleSeek(context, details.localPosition.dx, totalMs, controller);
                              },
                              child: SizedBox(
                                height: 8,
                                child: CustomPaint(
                                  painter: _MiniScrubberPainter(
                                    progress: progress,
                                    activeColor: const Color(0xFFF59E0B), // Radiant amber playhead
                                    inactiveColor: const Color(0x30FFEBF0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            duration.inSeconds > 0 ? _formatDuration(duration) : '4:38',
                            style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                              fontSize: 9,
                              color: const Color(0xFF78716C),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ── 3. Transport Controls (Right) ───────────────────────
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Skip Previous
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded),
                      iconSize: 18,
                      color: const Color(0xFFECE7E2),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => controller.previous(),
                    ),

                    const SizedBox(width: 6),

                    // Circular Play/Pause Button
                    InkWell(
                      onTap: () => controller.togglePlayPause(),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF28222E),
                          border: Border.all(
                            color: const Color(0x26FFEBF0),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isPlaying
                                  ? MidnightVelvetTokens.glowEmberLow
                                  : Colors.transparent,
                              blurRadius: 10,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            size: 20,
                            color: const Color(0xFFECE7E2),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 6),

                    // Skip Next
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded),
                      iconSize: 18,
                      color: const Color(0xFFECE7E2),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => controller.next(),
                    ),

                    if (onToggleQueue != null) ...[
                      const SizedBox(width: 2),
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded),
                        iconSize: 14,
                        color: const Color(0xFF5A5460),
                        tooltip: 'Session Queue',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        onPressed: onToggleQueue,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultDiscArt() {
    return Image.asset(
      'assets/images/player_cover_disc.png',
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF5A2A32), Color(0xFF2C1418), Color(0xFF140A0D)],
          ),
        ),
        child: Center(
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Color(0xFFE5A96A),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.music_note_rounded,
                size: 10,
                color: Colors.black,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleSeek(
    BuildContext context,
    double localX,
    double totalMs,
    dynamic controller,
  ) {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box != null && box.size.width > 0) {
      final ratio = (localX / box.size.width).clamp(0.0, 1.0);
      final targetMs = (ratio * totalMs).round();
      controller.seek(Duration(milliseconds: targetMs));
    }
  }

  Widget _buildGradientWaveform(double progress, bool isPlaying) {
    const barCount = 52;
    // Master waveform profile with authentic organic crest variation matching reference
    final heights = [
      0.30, 0.40, 0.55, 0.70, 0.85, 0.95, 1.00, 0.92,
      0.80, 0.65, 0.50, 0.40, 0.52, 0.68, 0.82, 0.94,
      0.90, 0.78, 0.62, 0.72, 0.85, 0.75, 0.58, 0.68,
      0.82, 0.72, 0.58, 0.45, 0.55, 0.70, 0.82, 0.68,
      0.52, 0.38, 0.48, 0.60, 0.72, 0.58, 0.45, 0.35,
      0.45, 0.55, 0.42, 0.32, 0.42, 0.50, 0.38, 0.28,
      0.38, 0.45, 0.30, 0.20,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final barWidth = math.max(1.5, (totalWidth / barCount) - 1.6);

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final barProgress = i / barCount;
            final isPlayed = barProgress <= progress;
            final normalizedHeight = heights[i % heights.length];
            final barHeight = 3.5 + (normalizedHeight * 16.5);

            // Radiant Champagne Amber to Glowing Coral Rose gradient
            final color = Color.lerp(
              const Color(0xFFFFD54F), // Bright luminous champagne gold / amber
              MidnightVelvetTokens.primaryEmber, // Glowing coral rose
              i / barCount,
            )!;

            return Container(
              width: barWidth,
              height: barHeight,
              decoration: BoxDecoration(
                color: isPlayed ? color : color.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(1.5),
                boxShadow: isPlayed
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.55),
                          blurRadius: 4,
                          spreadRadius: 0.5,
                        ),
                      ]
                    : null,
              ),
            );
          }),
        );
      },
    );
  }
}

class _MiniScrubberPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _MiniScrubberPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final trackPaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Draw full inactive track
    canvas.drawLine(Offset(0, y), Offset(size.width, y), trackPaint);

    final activeWidth = (size.width * progress).clamp(0.0, size.width);
    if (activeWidth > 0) {
      // Draw active progress line
      canvas.drawLine(Offset(0, y), Offset(activeWidth, y), activePaint);

      // Draw subtle amber playhead dot matching reference
      final dotPaint = Paint()
        ..color = activeColor
        ..style = PaintingStyle.fill;

      final dotShadowPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

      canvas.drawCircle(Offset(activeWidth, y), 3.0, dotShadowPaint);
      canvas.drawCircle(Offset(activeWidth, y), 3.0, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MiniScrubberPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
