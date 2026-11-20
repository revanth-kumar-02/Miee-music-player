import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/player_controller.dart';
import '../../../../core/audio/providers.dart';
import '../../../artwork/presentation/miee_artwork_image.dart';
import '../../../library/providers/library_providers.dart';

/// The Desktop "Heavy Rotation" view.
/// Displays favorite/liked tracks in an audiophile crate table format
/// strictly adhering to Midnight Velvet design tokens.
class DesktopHeavyRotationView extends ConsumerWidget {
  const DesktopHeavyRotationView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
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
                      'HEAVY ROTATION',
                      style: MidnightVelvetTokens.fontDisplayLarge.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${favorites.length} Master Pressings in frequent rotation',
                      style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                        color: MidnightVelvetTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (favorites.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: () {
                      ref.read(playerControllerProvider.notifier).setQueue(
                            favorites,
                            startIndex: 0,
                            playingFrom: 'Heavy Rotation',
                          );
                    },
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 20),
                    label: Text(
                      'SPIN ROTATION',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                        letterSpacing: 1.0,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MidnightVelvetTokens.primaryEmber,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 28),

            // ── Table Header ──────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: MidnightVelvetTokens.hairlineRim,
                    width: 1.0,
                  ),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      '#',
                      style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 4,
                    child: Text(
                      'TITLE',
                      style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'ARTIST',
                      style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'ALBUM',
                      style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      'TIME',
                      style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                        fontSize: 10,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

            // ── Track Rows ────────────────────────────────────────────
            if (favorites.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 60),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.favorite_border_rounded,
                        size: 48,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No Tracks in Heavy Rotation',
                        style: MidnightVelvetTokens.fontSectionTitle,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Heart tracks across your session to pin them to your primary console rotation.',
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
                itemCount: favorites.length,
                itemBuilder: (context, index) {
                  final track = favorites[index];
                  final isCurrent = currentTrack?.id == track.id;

                  return InkWell(
                    onTap: () {
                      ref.read(playerControllerProvider.notifier).setQueue(
                            favorites,
                            startIndex: index,
                            playingFrom: 'Heavy Rotation',
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
                              explicitUrl: track.effectiveArtworkUrl,
                              width: 36,
                              height: 36,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: Text(
                              track.displayTitle,
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
                              track.artist,
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
                              track.album ?? 'Single',
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
                              track.duration,
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
