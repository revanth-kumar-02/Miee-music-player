import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../shared/models/mock_data.dart';
import '../../../shared/widgets/widgets.dart';

/// Miee Now Playing Screen.
/// Renders standard layout carrying large artwork focal point, song detail flanked actions,
/// dynamic waveform tracking bar, and playback Circular FAB controls row.
class PlayerPage extends StatelessWidget {
  const PlayerPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Standard blur background image asset from Stitch design
    const blurBackingUrl =
        'https://lh3.googleusercontent.com/aida-public/AB6AXuDsvbTq_rvOYIWQHTtwfGgGxpSZUZm8kO3nvN7lfYVNfk-cGWM35yMOPkW6OEk9D1s62CepfmQ02pQqARysXN_1Kc2-qQePzedelwZgVzymBXk3Sof3e55AiIhH_Wg-FSM8Sp6WxlNkJTPieV_Kc54vLGXXnklt9AKy0joAhjONkgM2k1t_k13bqt5IFJSmNQJTp0aj0lpYGJeKRO0bgUGRc-Ho-YIYphLW6mER7-7yU5hCJu5nx9qHgIe-vLlm6vPiTN7QNCotu1dv';

    return Scaffold(
      body: Stack(
        children: [
          // 1. Monochromatic Album Cover Blur Background layer
          Positioned.fill(
            child: Opacity(
              opacity: 0.4,
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage(blurBackingUrl),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          // Glassmorphic overlay backdrop filter
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80.0, sigmaY: 80.0),
                child: Container(
                  color: AppColors.background.withOpacity(0.8),
                ),
              ),
            ),
          ),

          // 2. Foreground content scaffold
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  // Now Playing Header AppBar
                  AppHeader(
                    title: 'Now Playing',
                    titleWidget: Text(
                      'NOW PLAYING',
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    leading: IconButton(
                      icon: const Icon(Icons.expand_more),
                      onPressed: () => context.pop(),
                      splashRadius: 20.0,
                    ),
                    actions: [
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: IconButton(
                          icon: const Icon(Icons.queue_music),
                          onPressed: () => context.push('/queue'),
                          splashRadius: 20.0,
                        ),
                      ),
                    ],
                  ),

                  // Main content column
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.marginMobile,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Large album cover artwork centered
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final artworkSize = constraints.maxWidth * 0.8;
                              return Center(
                                child: AlbumArtwork(
                                  imageUrl: MockData.featuredTrack.imageUrl,
                                  size: artworkSize,
                                  borderRadius: BorderRadius.circular(32.0),
                                  hasShadow: true,
                                ),
                              );
                            },
                          ),

                          // Song Information flanked by favorite and options buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.favorite_border),
                                color: AppColors.onSurfaceVariant,
                                onPressed: () {},
                                splashRadius: 20.0,
                              ),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      MockData.featuredTrack.title,
                                      style: AppTypography.headlineLargeMobile.copyWith(
                                        color: AppColors.onSurface,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    AppSpacing.heightXs,
                                    Text(
                                      MockData.featuredTrack.artist,
                                      style: AppTypography.bodyMedium.copyWith(
                                        color: AppColors.onSurfaceVariant,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.more_horiz),
                                color: AppColors.onSurfaceVariant,
                                onPressed: () {},
                                splashRadius: 20.0,
                              ),
                            ],
                          ),

                          // Symmetrical Waveform & Progress display
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Waveform progress tracker
                              const FractionallySizedBox(
                                widthFactor: 0.85,
                                child: WaveformWidget(
                                  activeProgress: 0.37, // styled progress match
                                ),
                              ),
                              AppSpacing.heightSm,
                              // Duration stamps
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.between,
                                  children: [
                                    Text('1:04', style: AppTypography.labelSmall),
                                    Text('2:52', style: AppTypography.labelSmall),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          // Playback circular control rows
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            child: PlaybackControls(
                              isPlaying: false,
                              isShuffleActive: false,
                              isRepeatActive: false,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bottom padding spacer above device safe areas
                  AppSpacing.heightLg,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
