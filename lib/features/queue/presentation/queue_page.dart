import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/audio/playback_state.dart';
import '../../../core/audio/player_controller.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/widgets/widgets.dart';
import '../../playlists/presentation/widgets/add_to_playlist_sheet.dart';

/// Miee Playing Queue screen.
/// Observes current playing track and upcoming queue list from [playerControllerProvider].
class QueuePage extends ConsumerWidget {
  const QueuePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screenSize = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final currentTrack = ref.watch(playerControllerProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.status == PlaybackStatus.playing));
    final controller = ref.read(playerControllerProvider.notifier);
    final queueManager = ref.watch(queueManagerProvider);

    final queueList = queueManager.queue;
    final activeIndex = queueManager.currentIndex;

    // Remaining tracks in queue following the active index
    final upcomingList = activeIndex >= 0 && activeIndex < queueList.length
        ? queueList.sublist(activeIndex + 1)
        : queueList;

    // Real Now Playing background cover URL
    final coverUrl = currentTrack?.imageUrl;
    final hasValidCover = coverUrl != null && coverUrl.trim().isNotEmpty;

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
                        child: hasValidCover && coverUrl.startsWith('http')
                            ? Image.network(
                                coverUrl,
                                width: 256.0,
                                height: 256.0,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 256.0,
                                  height: 256.0,
                                  color: AppColors.surfaceContainerHigh,
                                  child: const Icon(
                                    Icons.music_note,
                                    color: AppColors.onSurfaceVariant,
                                    size: 64.0,
                                  ),
                                ),
                              )
                            : Container(
                                width: 256.0,
                                height: 256.0,
                                color: AppColors.surfaceContainerHigh,
                                child: const Icon(
                                  Icons.music_note,
                                  color: AppColors.onSurfaceVariant,
                                  size: 64.0,
                                ),
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
                color: Colors.black.withOpacity(0.55),
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
                    // Main Virtualized Scrollable Queue List
                    Positioned.fill(
                      child: ReorderableListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          AppSpacing.marginMobile,
                          0,
                          AppSpacing.marginMobile,
                          90.0 + bottomInset,
                        ),
                        buildDefaultDragHandles: false,
                        header: Column(
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
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              _buildNowPlayingHeader(
                                context,
                                currentTrack,
                                isPlaying,
                                controller,
                              ),
                              AppSpacing.heightLg,
                            ],

                            // 2.4 "Next Up" Section Header
                            if (upcomingList.isNotEmpty) ...[
                              const SectionHeader(
                                title: 'Next Up',
                                isUppercase: true,
                              ),
                              AppSpacing.heightMd,
                            ],
                          ],
                        ),
                        itemCount: upcomingList.length,
                        onReorder: (oldIndex, newIndex) {
                          final fullOldIndex = activeIndex + 1 + oldIndex;
                          final fullNewIndex = activeIndex + 1 + newIndex;
                          controller.reorderQueue(fullOldIndex, fullNewIndex);
                        },
                        itemBuilder: (context, index) {
                          final track = upcomingList[index];

                          return Padding(
                            key: ValueKey('queue_item_${track.id}_$index'),
                            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Row(
                              children: [
                                // Drag Indicator handle icon on the left
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 4.0),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: AppColors.onSurfaceVariant,
                                      size: 20.0,
                                    ),
                                  ),
                                ),
                                AppSpacing.widthSm,
                                Expanded(
                                  child: SongTile(
                                    imageUrl: track.imageUrl,
                                    title: track.title,
                                    artist: track.artist,
                                    duration: track.duration,
                                    isPlaying: false,
                                    onTap: () => controller.skipToQueueItem(activeIndex + 1 + index),
                                    trailingIcon: Icons.remove_circle_outline,
                                    onMoreTap: () {
                                      final fullIndex = activeIndex + 1 + index;
                                      controller.removeTrackAt(fullIndex);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Removed "${track.title}" from queue'),
                                          behavior: SnackBarBehavior.floating,
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    sourceBadge: _SourceBadge(isYoutube: track.isYoutube),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
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

  Widget _buildNowPlayingHeader(
    BuildContext context,
    MusicItem currentTrack,
    bool isPlaying,
    PlayerController controller,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final isLoading = ref.watch(playerControllerProvider.select((s) =>
            s.status == PlaybackStatus.loading ||
            s.status == PlaybackStatus.buffering));

        return Container(
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
        isPlaying: isPlaying,
        isActive: true,
        isLoading: isLoading,
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.push('/player');
          }
        },
        trailingWidget: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Play / Pause Action Button
            IconButton(
              icon: isLoading
                  ? const SizedBox(
                      width: 20.0,
                      height: 20.0,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    )
                  : Icon(
                      isPlaying
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded,
                      color: AppColors.primary,
                      size: 28.0,
                    ),
              onPressed: isLoading ? null : () => controller.togglePlayPause(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 20.0,
              tooltip: isLoading ? 'Loading' : (isPlaying ? 'Pause' : 'Play'),
            ),
            const SizedBox(width: 4.0),
            // Next Track Action Button
            IconButton(
              icon: const Icon(
                Icons.skip_next_rounded,
                color: AppColors.onSurfaceVariant,
                size: 24.0,
              ),
              onPressed: () => controller.next(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              splashRadius: 20.0,
              tooltip: 'Next Track',
            ),
            // More Options (Add to playlist sheet)
            IconButton(
              icon: const Icon(
                Icons.more_horiz,
                color: AppColors.onSurfaceVariant,
                size: 20.0,
              ),
              onPressed: () => showAddToPlaylistSheet(context, currentTrack),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              splashRadius: 20.0,
              tooltip: 'More Options',
            ),
          ],
        ),
        sourceBadge: _SourceBadge(isYoutube: currentTrack.isYoutube),
      ),
    );
      },
    );
  }
}

class _SourceBadge extends StatelessWidget {
  final bool isYoutube;

  const _SourceBadge({required this.isYoutube});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = isYoutube ? 'YouTube' : 'Local';
    final icon = isYoutube ? Icons.language : Icons.phone_android;

    final bgColor = isYoutube
        ? (isDark ? const Color(0xFF5D1D1D) : const Color(0xFFFFEBEE))
        : (isDark ? const Color(0xFF2E3B2E) : const Color(0xFFE8F5E9));

    final textColor = isYoutube
        ? (isDark ? const Color(0xFFFF8A80) : const Color(0xFFC62828))
        : (isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 10.0,
            color: textColor,
          ),
          const SizedBox(width: 4.0),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              fontSize: 8.0,
              fontWeight: FontWeight.bold,
              color: textColor,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

