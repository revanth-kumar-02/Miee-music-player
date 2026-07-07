import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/track.dart';
import '../../../shared/widgets/widgets.dart';

/// Miee Playing Queue screen.
/// Observes current playing track and upcoming queue list from [playerControllerProvider].
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenSize = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final playbackState = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final queueManager = ref.watch(queueManagerProvider);

    final currentTrack = playbackState.currentTrack;
    final isPlaying = playbackState.status == PlaybackStatus.playing;

    final queueList = queueManager.queue;
    final activeIndex = queueManager.currentIndex;

    // Remaining tracks in queue following the active index
    final upcomingList = activeIndex >= 0 && activeIndex < queueList.length
        ? queueList.sublist(activeIndex + 1)
        : queueList;

    // Simulated Now Playing background cover URL
    final simulatedCoverUrl = currentTrack?.imageUrl ??
        'https://lh3.googleusercontent.com/aida-public/AB6AXuDAC6tJm3nZhSGqIOKjl0S003HV0Gn0UHctE2JMK_FEyKgZQX7CFOVHTG2cB9YFtr1yCUcSOirzoTdENtI5zCzxWKkmrIiZo7yqJAWYmHDpYTbnHm538CqwSvnSa7bJb2DpfFRNfKh317H4LJT4Z0DHjPVfR7ENuErZAQe577iwgx8sVRSQzdr5Xn5RJR6bNhNItA9sGOkN1gGzrnLECKATtkuGvxKDY0I4OZ4rMwJX_KtVETCA6xW7-QIRueuaXtsKb0ge6IZumSYY';

    return Scaffold(
      body: Stack(
        children: [
          // 1. Simulated Dimmed Now Playing Backing Layer
          Positioned.fill(
            child: Container(
              color: AppColors.surfaceContainerHigh,
              child: Opacity(
                opacity: 0.4,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12.0),
                        child: Image.network(
                          simulatedCoverUrl,
                          width: 256.0,
                          height: 256.0,
                          fit: BoxFit.cover,
                        ),
                      ),
                      AppSpacing.heightLg,
                      Text(
                        currentTrack?.title ?? 'No Track',
                        style: AppTypography.headlineMedium.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                      AppSpacing.heightXs,
                      Text(
                        currentTrack?.artist ?? 'Unknown Artist',
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Dark Dim Overlay with Close Gesture
          Positioned.fill(
            child: GestureDetector(
              onTap: () => context.pop(),
              child: Container(
                color: Colors.black.withOpacity(0.4),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
                  child: const SizedBox.shrink(),
                ),
              ),
            ),
          ),

          // 2. Bottom Sheet Modal Container (75% height)
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: screenSize.height * 0.75,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLowest, // `#ffffff`
                borderRadius: AppRadius.radiusSheetTop, // 32px top corners
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000), // rgba(0, 0, 0, 0.08)
                    offset: Offset(0, -8),
                    blurRadius: 30,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppRadius.radiusSheetTop,
                child: Stack(
                  children: [
                    // Main Scrollable Queue List
                    Positioned.fill(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.marginMobile,
                        ),
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 2.1 Drag Indicator Handle
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.md,
                                  bottom: AppSpacing.sm,
                                ),
                                child: Container(
                                  width: 48.0,
                                  height: 6.0,
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(99.0),
                                  ),
                                ),
                              ),
                            ),

                            // 2.2 Sheet Title Header
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.between,
                                children: [
                                  Text(
                                    'Playing Queue',
                                    style: AppTypography.headlineLargeMobile.copyWith(
                                      color: AppColors.onSurface,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close),
                                    color: AppColors.onSurface,
                                    onPressed: () => context.pop(),
                                    splashRadius: 20.0,
                                  ),
                                ],
                              ),
                            ),
                            AppSpacing.heightMd,

                            // 2.3 "Now Playing" Spotlight Row
                            if (currentTrack != null) ...[
                              const SectionHeader(
                                title: 'Now Playing',
                                isUppercase: true,
                              ),
                              AppSpacing.heightMd,
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: AppRadius.radiusXl,
                                ),
                                child: SongTile(
                                  imageUrl: currentTrack.imageUrl,
                                  title: currentTrack.title,
                                  artist: currentTrack.artist,
                                  duration: currentTrack.duration,
                                  isPlaying: isPlaying, // Activates EQ animation
                                  onTap: () {},
                                  onMoreTap: () {},
                                ),
                              ),
                              AppSpacing.heightLg,
                            ],

                            // 2.4 "Next Up" List
                            if (upcomingList.isNotEmpty) ...[
                              const SectionHeader(
                                title: 'Next Up',
                                isUppercase: true,
                              ),
                              AppSpacing.heightMd,
                              _buildUpcomingQueueList(upcomingList, controller),
                            ],

                            // Footer bottom spacer (Clear Queue button offset)
                            SizedBox(height: 90.0 + bottomInset),
                          ],
                        ),
                      ),
                    ),

                    // 3. Sticky Clear Queue Button Footer
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 90.0 + bottomInset,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.surfaceContainerLowest,
                              AppColors.surfaceContainerLowest.withOpacity(0.95),
                              AppColors.surfaceContainerLowest.withOpacity(0.0),
                            ],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            stops: const [0.0, 0.6, 1.0],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: bottomInset + AppSpacing.md,
                          ),
                          child: TextButton(
                            onPressed: () => controller.clearQueue(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xl,
                                vertical: AppSpacing.md,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(99.0),
                              ),
                              foregroundColor: AppColors.onSurfaceVariant,
                            ),
                            child: Text(
                              'CLEAR QUEUE',
                              style: AppTypography.labelMedium.copyWith(
                                color: AppColors.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingQueueList(List<Track> upcomingList, PlayerController controller) {
    return Column(
      children: List.generate(upcomingList.length, (index) {
        final track = upcomingList[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              // Drag Indicator handle icon on the left
              const Icon(
                Icons.drag_indicator,
                color: AppColors.onSurfaceVariant,
                size: 20.0,
              ),
              AppSpacing.widthSm,
              Expanded(
                child: SongTile(
                  imageUrl: track.imageUrl,
                  title: track.title,
                  artist: track.artist,
                  duration: track.duration,
                  isPlaying: false,
                  onTap: () => controller.playTrack(track),
                  onMoreTap: () {},
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
