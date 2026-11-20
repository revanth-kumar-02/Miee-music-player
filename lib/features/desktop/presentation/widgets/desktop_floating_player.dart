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
      width: 580,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xD916141B), // Softer smoked dark velvet glass
        borderRadius: BorderRadius.circular(14), // Modern square rounded rectangle container
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
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: MidnightVelvetTokens.glassBlurSigma,
            sigmaY: MidnightVelvetTokens.glassBlurSigma,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              children: [
                // ── 1. Square Album Art & Track Meta (Left) ─────────────
                GestureDetector(
                  onTap: onOpenNowSpinning,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
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
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
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

                // ── 2. Central Waveform & Dual Timecodes (Center) ───────
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: 236,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Radiant Half-Yellow / Half-Red Glowing Waveform (Tappable for seeking)
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (details) {
                                  final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                                  final targetMs = (ratio * totalMs).round();
                                  controller.seek(Duration(milliseconds: targetMs));
                                },
                                child: SizedBox(
                                  height: 22,
                                  child: _buildGradientWaveform(progress, isPlaying),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 3),

                          // Dual Timecodes (Playback line removed)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                                  fontSize: 9,
                                  color: const Color(0xFF78716C),
                                ),
                              ),
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

  Widget _buildGradientWaveform(double progress, bool isPlaying) {
    const barCount = 44;
    // Authentic organic waveform silhouette extracted directly from the reference
    const heights = [
      0.09, 0.12, 0.22, 0.34, 0.41, 0.59, 0.72, 0.88,
      0.84, 0.81, 0.78, 0.72, 0.78, 0.81, 0.81, 0.75,
      0.66, 0.69, 0.75, 0.81, 0.94, 1.00, 1.00, 0.97,
      0.91, 0.84, 0.81, 0.69, 0.56, 0.53, 0.50, 0.53,
      0.62, 0.56, 0.47, 0.38, 0.31, 0.28, 0.44, 0.56,
      0.47, 0.34, 0.25, 0.31,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final barWidth = math.max(1.8, (totalWidth / barCount) - 2.5);

        // At 0:00 or start, illuminate the entire waveform with radiant reference colors
        final effectiveProgress = progress <= 0.02 ? 1.0 : progress;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List.generate(barCount, (i) {
            final t = i / (barCount - 1);
            final barProgress = i / barCount;
            final isPlayed = barProgress <= effectiveProgress;
            final normalizedHeight = heights[i % heights.length];
            final barHeight = math.max(3.0, 3.0 + (normalizedHeight * 17.0));

            // Pure half-yellow (0 to ~48%) and half-red (~52% to 100%) gradient calibration
            final Color color;
            if (t < 0.48) {
              // Radiant champagne-amber yellow
              color = Color.lerp(
                const Color(0xFFFFD54F),
                const Color(0xFFF59E0B),
                t / 0.48,
              )!;
            } else if (t > 0.52) {
              // Radiant coral-rose to intense ruby ember red
              color = Color.lerp(
                const Color(0xFFFF3366),
                const Color(0xFFD32F2F),
                (t - 0.52) / 0.48,
              )!;
            } else {
              // Smooth midpoint transition
              color = Color.lerp(
                const Color(0xFFF59E0B),
                const Color(0xFFFF3366),
                (t - 0.48) / 0.04,
              )!;
            }

            return Container(
              width: barWidth,
              height: barHeight,
              decoration: BoxDecoration(
                color: isPlayed ? color : color.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(1.5),
                boxShadow: isPlayed
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.65),
                          blurRadius: 5,
                          spreadRadius: 0.6,
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
