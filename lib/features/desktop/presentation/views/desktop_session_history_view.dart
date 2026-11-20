import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/player_controller.dart';
import '../../../../core/audio/providers.dart';
import '../../../artwork/presentation/miee_artwork_image.dart';
import '../../../library/providers/library_providers.dart';

/// The Desktop "Session History" view.
/// Shows playback history entries strictly adhering to Midnight Velvet design tokens.
class DesktopSessionHistoryView extends ConsumerWidget {
  const DesktopSessionHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(recentlyPlayedProvider);
    final history = historyAsync.valueOrNull ?? [];
    final playbackState = ref.watch(playerControllerProvider);
    final currentTrack = playbackState.currentTrack;

    return Scaffold(
      backgroundColor: MidnightVelvetTokens.canvasBase,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Studio Header ─────────────────────────────────────────
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SESSION HISTORY',
                      style: MidnightVelvetTokens.fontDisplayLarge.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${history.length} Chronological pressings spun in this environment',
                      style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                        color: MidnightVelvetTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Track Rows ────────────────────────────────────────────
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        size: 48,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Session History Recorded',
                        style: MidnightVelvetTokens.fontSectionTitle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Playback events will populate here in real-time as masters are spun.',
                        style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                          color: MidnightVelvetTokens.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: history.length,
                itemBuilder: (context, index) {
                  final entry = history[index];
                  final track = entry.track.toTrack();
                  final isCurrent = currentTrack?.id == track.id;

                  return InkWell(
                    onTap: () {
                      ref.read(playerControllerProvider.notifier).setQueue(
                            [track],
                            startIndex: 0,
                            playingFrom: 'Session History',
                          );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isCurrent
                            ? MidnightVelvetTokens.primaryEmber.withValues(alpha: 0.1)
                            : Colors.transparent,
                        border: const Border(
                          bottom: BorderSide(
                            color: MidnightVelvetTokens.hairlineRimSubtle,
                            width: 1.0,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: isCurrent
                                ? const Icon(
                                    Icons.graphic_eq_rounded,
                                    size: 16,
                                    color: MidnightVelvetTokens.primaryEmber,
                                  )
                                : Text(
                                    '${index + 1}'.padLeft(2, '0'),
                                    style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                                      fontSize: 11,
                                      color: MidnightVelvetTokens.textMuted,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: MieeArtworkImage(
                              explicitUrl: entry.track.imageUrl,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: Text(
                              entry.track.title,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                color: isCurrent
                                    ? MidnightVelvetTokens.primaryEmber
                                    : MidnightVelvetTokens.textDisplay,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              entry.track.artist,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: MidnightVelvetTokens.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              'Master Stream',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: MidnightVelvetTokens.textMuted,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              entry.track.duration,
                              style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                                fontSize: 11,
                                color: MidnightVelvetTokens.textMuted,
                              ),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
