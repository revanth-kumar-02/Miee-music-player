import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/providers.dart';
import '../../../playlists/domain/playlist_model.dart';
import '../../../playlists/providers/playlist_providers.dart';
import '../../../recommendations/domain/daily_mix.dart';
import '../../../recommendations/presentation/daily_mix_playback_helper.dart';
import '../../../recommendations/providers/daily_mix_providers.dart';

/// The Desktop "Crates & Mixes" studio catalog view.
/// Styled strictly to Midnight Velvet standards with vinyl record motifs,
/// dark card surfaces (#1A181E), and Ember/Champagne accents.
class DesktopCratesView extends ConsumerWidget {
  const DesktopCratesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dailyMixAsync = ref.watch(dailyMixSnapshotProvider);
    final playlists = ref.watch(allPlaylistsProvider);

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
                      'CRATES & MIXES',
                      style: MidnightVelvetTokens.fontDisplayLarge.copyWith(
                        fontSize: 26,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Personalized daily rotations and curated vinyl record crates',
                      style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                        color: MidnightVelvetTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: MidnightVelvetTokens.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MidnightVelvetTokens.hairlineRim,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: MidnightVelvetTokens.amberChampagne,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'DAILY AUTO-CURATION ACTIVE',
                        style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                          fontSize: 10,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // ── Section 1: Daily Mixes (Vinyl Motif) ───────────────────
            Text(
              'DAILY MIXES',
              style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                fontSize: 15,
                letterSpacing: 1.2,
                color: MidnightVelvetTokens.textMuted,
              ),
            ),
            const SizedBox(height: 14),

            dailyMixAsync.when(
              data: (snapshot) {
                final mixes = snapshot.mixes;
                if (mixes.isEmpty) {
                  return _buildEmptyState(
                      'Generating your daily mixes based on your listening habits...');
                }
                return SizedBox(
                  height: 230,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: mixes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 20),
                    itemBuilder: (context, index) {
                      final mix = mixes[index];
                      return _buildDailyMixCard(context, ref, mix, index);
                    },
                  ),
                );
              },
              loading: () => const SizedBox(
                height: 230,
                child: Center(
                  child: CircularProgressIndicator(
                    color: MidnightVelvetTokens.primaryEmber,
                  ),
                ),
              ),
              error: (err, _) =>
                  _buildEmptyState('Daily mixes currently unavailable.'),
            ),

            const SizedBox(height: 40),

            // ── Section 2: Curated Record Crates ───────────────────────
            Text(
              'CURATED CRATES',
              style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                fontSize: 15,
                letterSpacing: 1.2,
                color: MidnightVelvetTokens.textMuted,
              ),
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: _buildCrateTile(
                    title: 'Late Night Velvet',
                    subtitle: 'Deep ambient, downtempo, and midnight focus',
                    trackCount: '24 Tracks',
                    color: const Color(0xFF8B5CF6),
                    icon: Icons.nightlife_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCrateTile(
                    title: 'Studio Pure Direct',
                    subtitle:
                        'Bit-perfect lossless masters and acoustic recordings',
                    trackCount: '32 Tracks',
                    color: MidnightVelvetTokens.amberChampagne,
                    icon: Icons.graphic_eq_rounded,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCrateTile(
                    title: 'Deep Obsidian Focus',
                    subtitle: 'Minimal techno, synthwave, and rhythm flow',
                    trackCount: '18 Tracks',
                    color: MidnightVelvetTokens.primaryEmber,
                    icon: Icons.bolt_rounded,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 40),

            // ── Section 3: User Playlists ─────────────────────────────
            if (playlists.isNotEmpty) ...[
              Text(
                'YOUR CRATES & PLAYLISTS',
                style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                  fontSize: 15,
                  letterSpacing: 1.2,
                  color: MidnightVelvetTokens.textMuted,
                ),
              ),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.4,
                ),
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return _buildPlaylistCard(context, ref, playlist);
                },
              ),
              const SizedBox(height: 40),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDailyMixCard(
    BuildContext context,
    WidgetRef ref,
    DailyMix mix,
    int index,
  ) {
    final colors = [
      const Color(0xFF1E1A24),
      const Color(0xFF16202E),
      const Color(0xFF241C1E),
    ];
    final accents = [
      MidnightVelvetTokens.primaryEmber,
      MidnightVelvetTokens.amberChampagne,
      const Color(0xFF06B6D4),
    ];
    final cardColor = colors[index % colors.length];
    final accent = accents[index % accents.length];

    return InkWell(
      onTap: () =>
          ref.read(playerControllerProvider.notifier).playDailyMix(mix),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MidnightVelvetTokens.hairlineRim,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vinyl Graphic with Center Label
            Container(
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0D0C0F),
                border: Border.all(
                  color: accent.withValues(alpha: 0.4),
                  width: 2.0,
                ),
              ),
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.8),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.black,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Text(
              mix.title,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: MidnightVelvetTokens.textDisplay,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              '${mix.tracks.length} tracks • ${mix.subtitle}',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: MidnightVelvetTokens.textMuted,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCrateTile({
    required String title,
    required String subtitle,
    required String trackCount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: color.withValues(alpha: 0.3),
                width: 1.0,
              ),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: MidnightVelvetTokens.textDisplay,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: MidnightVelvetTokens.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            trackCount,
            style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
              fontSize: 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaylistCard(
    BuildContext context,
    WidgetRef ref,
    PlaylistModel playlist,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: MidnightVelvetTokens.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.queue_music_rounded,
              color: MidnightVelvetTokens.amberChampagne,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  playlist.name,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: MidnightVelvetTokens.textDisplay,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${playlist.tracks.length} tracks',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: MidnightVelvetTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
      ),
      child: Center(
        child: Text(
          message,
          style: MidnightVelvetTokens.fontBodyMedium.copyWith(
            color: MidnightVelvetTokens.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
