import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../core/audio/providers.dart';
import '../../../recommendations/domain/daily_mix.dart';
import '../../../recommendations/presentation/daily_mix_playback_helper.dart';
import '../../../recommendations/providers/daily_mix_providers.dart';

/// Home screen section displaying deterministic personalized Daily Mixes.
///
/// Designed to match Nordic Cobalt Reference Screen 1:
/// - "Daily Mixes" bold header with "See All >" link
/// - Compact square vinyl-record motif cards (Mix 1: Obsidian, Mix 2: Cobalt, Mix 3: Steel)
/// - Clean typography labels underneath
class DailyMixesSection extends ConsumerWidget {
  const DailyMixesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(dailyMixSnapshotProvider);

    return snapshotAsync.when(
      data: (snapshot) {
        final mixes = snapshot.mixes;
        if (mixes.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section Header ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Mixes',
                        style: GoogleFonts.geist(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.denseObsidian,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tuned to your taste and listening habits',
                        style: GoogleFonts.geist(
                          fontSize: 12,
                          color: AppColors.industrialSteel,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'See All >',
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.industrialSteel,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Horizontal Mix Cards Shelf ──────────────────────────────
            SizedBox(
              height: 204,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: mixes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final mix = mixes[index];
                  return _DailyMixCard(
                    mix: mix,
                    index: index,
                    onPlay: () {
                      ref.read(playerControllerProvider.notifier).playDailyMix(mix);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const _DailyMixesSkeleton(),
      error: (error, _) => _DailyMixesError(
        onRetry: () => ref.read(dailyMixSnapshotProvider.notifier).refresh(),
      ),
    );
  }
}

/// Individual Daily Mix card widget matching the vinyl artwork motif.
class _DailyMixCard extends StatelessWidget {
  final DailyMix mix;
  final int index;
  final VoidCallback onPlay;

  const _DailyMixCard({
    required this.mix,
    required this.index,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${mix.title}, ${mix.subtitle}, ${mix.trackCount} tracks',
      button: true,
      child: GestureDetector(
        onTap: onPlay,
        child: SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Vinyl Record Artwork Container ────────────────────────
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.denseObsidian.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildVinylArtwork(),
                ),
              ),
              const SizedBox(height: 8),

              // ── Mix Title ─────────────────────────────────────────────
              Text(
                mix.title,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.geist(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.denseObsidian,
                ),
              ),
              const SizedBox(height: 2),

              // ── Subtitle ──────────────────────────────────────────────
              Text(
                mix.subtitle,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.geist(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.industrialSteel,
                ),
              ),
              const SizedBox(height: 1),

              // ── Track Count ───────────────────────────────────────────
              Text(
                '${mix.trackCount} tracks',
                textAlign: TextAlign.center,
                style: GoogleFonts.geist(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: AppColors.industrialSteel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVinylArtwork() {
    // Curated Nordic Cobalt colors for the 3 mix slots:
    // Mix 1: Obsidian Charcoal
    // Mix 2: Electric Cobalt Blue
    // Mix 3: Steel Slate Grey
    final List<Color> bgColors = [
      const Color(0xFF1B242C), // Obsidian Dark Teal-Charcoal
      AppColors.electricCobalt, // Electric Cobalt
      const Color(0xFF334155), // Slate Steel
    ];

    final bgColor = bgColors[index % bgColors.length];

    return Container(
      color: bgColor,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Vinyl outer groove ring
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 1.0,
              ),
            ),
          ),
          // Vinyl middle groove ring
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 1.0,
              ),
            ),
          ),
          // Vinyl Center White Label
          Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bgColor,
                ),
              ),
            ),
          ),
          // Floating Circular Play Button
          Positioned(
            right: 6,
            bottom: 6,
            child: Material(
              color: AppColors.electricCobalt,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPlay,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmer/skeleton placeholder while Daily Mixes are computing or loading from disk.
class _DailyMixesSkeleton extends StatelessWidget {
  const _DailyMixesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 110,
          height: 18,
          decoration: BoxDecoration(
            color: AppColors.paleConcrete,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 14),
            itemBuilder: (_, __) => SizedBox(
              width: 110,
              child: Column(
                children: [
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      color: AppColors.paleConcrete,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 70,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.paleConcrete,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Contained error view with retry action.
class _DailyMixesError extends StatelessWidget {
  final VoidCallback onRetry;

  const _DailyMixesError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.paleConcrete,
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.refresh_rounded,
            size: 20,
            color: AppColors.denseObsidian,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Daily Mixes temporarily unavailable',
              style: GoogleFonts.geist(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.denseObsidian,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.electricCobalt,
            ),
            child: Text(
              'Retry',
              style: GoogleFonts.geist(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
