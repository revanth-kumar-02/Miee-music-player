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
/// Follows Miee's Stitch design system with warm ivory surfaces, cocoa plum typography,
/// and tactile dusty rose playback affordances.
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Mixes',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.cocoaPlum,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tuned to your taste and listening habits',
                        style: GoogleFonts.geist(
                          fontSize: 12,
                          color: AppColors.mutedMauve,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Horizontal Mix Cards Shelf ──────────────────────────────
            SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: mixes.length,
                separatorBuilder: (_, __) => const SizedBox(width: 16),
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

/// Individual Daily Mix card widget.
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
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 156,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Artwork with Floating Play Button ─────────────────────
              SizedBox(
                width: 156,
                height: 156,
                child: Stack(
                  children: [
                    // Base Artwork
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _buildArtwork(context),
                    ),

                    // Subtle Bottom Vignette for depth
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 52,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(14),
                          ),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              AppColors.cocoaPlum.withValues(alpha: 0.35),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Floating Play Button Affordance
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Material(
                        color: AppColors.dustyRose,
                        shape: const CircleBorder(),
                        elevation: 3,
                        shadowColor: AppColors.cocoaPlum.withValues(alpha: 0.3),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onPlay,
                          child: const SizedBox(
                            width: 38,
                            height: 38,
                            child: Icon(
                              Icons.play_arrow_rounded,
                              size: 24,
                              color: AppColors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // ── Mix Title ─────────────────────────────────────────────
              Text(
                mix.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.cocoaPlum,
                ),
              ),
              const SizedBox(height: 2),

              // ── Mix Subtitle ──────────────────────────────────────────
              Text(
                mix.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.geist(
                  fontSize: 12,
                  color: AppColors.mutedMauve,
                ),
              ),
              const SizedBox(height: 2),

              // ── Track Count Badge ─────────────────────────────────────
              Text(
                '${mix.trackCount} tracks',
                style: GoogleFonts.geist(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.mutedMauve.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context) {
    if (mix.coverImageUrl != null && mix.coverImageUrl!.isNotEmpty) {
      return Image.network(
        mix.coverImageUrl!,
        width: 156,
        height: 156,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallbackGradientArtwork(),
      );
    }
    return _buildFallbackGradientArtwork();
  }

  Widget _buildFallbackGradientArtwork() {
    // Curated Stitch-aligned gradients for each mix slot
    final List<List<Color>> mixGradients = [
      // Mix 1: Dusty Rose & Deep Cocoa Plum (Favorites)
      [
        const Color(0xFFD78D9B),
        const Color(0xFFC77987),
        const Color(0xFF4A3036),
      ],
      // Mix 2: Soft Olive Sage & Oat Beige (Rotation)
      [
        const Color(0xFF7D8C71),
        const Color(0xFF9EA37E),
        const Color(0xFF384534),
      ],
      // Mix 3: Terracotta & Warm Soft Clay (Discovery)
      [
        const Color(0xFFD9826C),
        const Color(0xFFE9C9B7),
        const Color(0xFF5A3930),
      ],
    ];

    final gradientColors = mixGradients[index % mixGradients.length];

    return Container(
      width: 156,
      height: 156,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      child: Stack(
        children: [
          // Subtle decorative circle
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'MIX ${index + 1}',
                        style: GoogleFonts.geist(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                          color: AppColors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ),
                    Icon(
                      index == 0
                          ? Icons.favorite_rounded
                          : (index == 1 ? Icons.autorenew_rounded : Icons.explore_rounded),
                      size: 16,
                      color: AppColors.white.withValues(alpha: 0.85),
                    ),
                  ],
                ),
                Icon(
                  Icons.music_note_rounded,
                  size: 32,
                  color: AppColors.white.withValues(alpha: 0.9),
                ),
              ],
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
        // Skeleton Header
        Container(
          width: 130,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.oatBeige.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: 220,
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.oatBeige.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 16),

        // Skeleton Cards
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, __) => SizedBox(
              width: 156,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 156,
                    height: 156,
                    decoration: BoxDecoration(
                      color: AppColors.oatBeige.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 110,
                    height: 14,
                    decoration: BoxDecoration(
                      color: AppColors.oatBeige.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 140,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.oatBeige.withValues(alpha: 0.4),
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

/// Contained error view with a subtle retry action.
class _DailyMixesError extends StatelessWidget {
  final VoidCallback onRetry;

  const _DailyMixesError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.oatBeige.withValues(alpha: 0.7),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.softClay.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.refresh_rounded,
              size: 20,
              color: AppColors.cocoaPlum,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Mixes temporarily unavailable',
                  style: GoogleFonts.geist(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.cocoaPlum,
                  ),
                ),
                Text(
                  'Tap to try refreshing your mixes',
                  style: GoogleFonts.geist(
                    fontSize: 11,
                    color: AppColors.mutedMauve,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.dustyRose,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
