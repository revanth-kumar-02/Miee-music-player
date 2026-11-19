import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../core/audio/player_controller.dart';
import '../../../../core/audio/providers.dart';
import '../../../../features/artwork/presentation/miee_artwork_image.dart';
import '../../../../features/library/providers/library_providers.dart';
import '../../../../shared/models/music_item.dart';

enum QueueViewTab {
  sessionQueue,
  recentPressings,
}

class SessionQueueView extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final bool isCompact;

  const SessionQueueView({
    super.key,
    this.onClose,
    this.isCompact = false,
  });

  @override
  ConsumerState<SessionQueueView> createState() => _SessionQueueViewState();
}

class _SessionQueueViewState extends ConsumerState<SessionQueueView> {
  QueueViewTab _activeTab = QueueViewTab.sessionQueue;
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final queueManager = ref.watch(queueManagerProvider);
    final queue = queueManager.queue;
    final activeIndex = queueManager.currentIndex;
    final controller = ref.read(playerControllerProvider.notifier);
    final isPlaying = ref.watch(playerControllerProvider.select((s) => s.status == PlaybackStatus.playing));

    return Container(
      decoration: MidnightVelvetTokens.glassPanel(
        radius: 16.0,
        surfaceColor: MidnightVelvetTokens.surfaceCard,
        borderColor: MidnightVelvetTokens.hairlineRim,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Top Console Bar (Tabs & Queue Actions)
          _buildHeaderBar(queue.length, controller),

          const Divider(
            height: 1,
            thickness: 1,
            color: MidnightVelvetTokens.hairlineRim,
          ),

          // 2. Main Tab Body Content
          Expanded(
            child: _activeTab == QueueViewTab.sessionQueue
                ? _buildQueueList(queue, activeIndex, isPlaying, controller)
                : _buildRecentPressingsList(controller),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(int queueCount, PlayerController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          // Tab Switchers (scrollable if drawer is narrow)
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _buildTabPill(
                    title: 'SESSION QUEUE',
                    badgeCount: queueCount,
                    isSelected: _activeTab == QueueViewTab.sessionQueue,
                    onTap: () => setState(() => _activeTab = QueueViewTab.sessionQueue),
                  ),
                  const SizedBox(width: 8),
                  _buildTabPill(
                    title: 'RECENT PRESSINGS',
                    isSelected: _activeTab == QueueViewTab.recentPressings,
                    onTap: () => setState(() => _activeTab = QueueViewTab.recentPressings),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Actions on right (Clear Queue / Close)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_activeTab == QueueViewTab.sessionQueue && queueCount > 0)
                IconButton(
                  onPressed: () => controller.clearQueue(),
                  tooltip: 'Clear Queue',
                  icon: const Icon(
                    Icons.clear_all_rounded,
                    size: 18,
                    color: MidnightVelvetTokens.textSecondary,
                  ),
                  splashRadius: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed: widget.onClose,
                  tooltip: 'Close Queue',
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: MidnightVelvetTokens.textSecondary,
                  ),
                  splashRadius: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill({
    required String title,
    int? badgeCount,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: MidnightVelvetTokens.surfaceCardHover,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? MidnightVelvetTokens.surfaceElevated : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: MidnightVelvetTokens.hairlineRimHighlight, width: 1.0)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: MidnightVelvetTokens.fontLabelSmall.copyWith(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? MidnightVelvetTokens.textDisplay
                    : MidnightVelvetTokens.textMuted,
                letterSpacing: 0.05 * 11,
              ),
            ),
            if (badgeCount != null && badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? MidnightVelvetTokens.primaryEmber
                      : MidnightVelvetTokens.canvasBase,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$badgeCount',
                  style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                    fontSize: 9,
                    color: isSelected ? Colors.white : MidnightVelvetTokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueueList(
    List<MusicItem> queue,
    int activeIndex,
    bool isPlaying,
    PlayerController controller,
  ) {
    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 48,
              color: MidnightVelvetTokens.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'SESSION QUEUE IS EMPTY',
              style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                fontSize: 14,
                letterSpacing: 0.06 * 14,
                color: MidnightVelvetTokens.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Select a record crate or track to spin up the session queue.',
              style: MidnightVelvetTokens.fontBodyMedium.copyWith(fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      itemCount: queue.length,
      // ignore: deprecated_member_use
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex--;
        controller.reorderQueue(oldIndex, newIndex);
      },
      itemBuilder: (context, index) {
        final track = queue[index];
        final isActive = index == activeIndex;
        final isHovered = _hoveredIndex == index;

        return MouseRegion(
          key: ValueKey('queue_track_${track.id}_$index'),
          onEnter: (_) => setState(() => _hoveredIndex = index),
          onExit: (_) => setState(() => _hoveredIndex = null),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isActive
                  ? MidnightVelvetTokens.surfaceCardHover
                  : isHovered
                      ? MidnightVelvetTokens.surfaceCardHover.withValues(alpha: 0.5)
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: isActive
                  ? Border.all(color: MidnightVelvetTokens.amberChampagne.withValues(alpha: 0.3), width: 1.0)
                  : null,
            ),
            child: Row(
              children: [
                // 1. Index / Active Equalizer
                SizedBox(
                  width: 32,
                  child: isActive && isPlaying
                      ? const Icon(
                          Icons.graphic_eq_rounded,
                          size: 16,
                          color: MidnightVelvetTokens.amberChampagne,
                        )
                      : Text(
                          '#${(index + 1).toString().padLeft(2, '0')}',
                          style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                            fontSize: 11,
                            color: isActive
                                ? MidnightVelvetTokens.amberChampagne
                                : MidnightVelvetTokens.textMuted,
                          ),
                        ),
                ),

                const SizedBox(width: 8),

                // 2. Album Cover (40px)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: MieeArtworkImage(
                      musicItem: track,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),

                const SizedBox(width: 14),

                // 3. Track Title & Artist
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        track.displayTitle,
                        style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                          fontSize: 13,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
                          color: isActive
                              ? MidnightVelvetTokens.amberChampagne
                              : MidnightVelvetTokens.textDisplay,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                          fontSize: 11,
                          color: MidnightVelvetTokens.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 4. Quality Telemetry Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MidnightVelvetTokens.canvasBase,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: MidnightVelvetTokens.hairlineRim,
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    _resolveTrackQualityBadge(track),
                    style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                      fontSize: 9,
                      color: MidnightVelvetTokens.textSecondary,
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // 5. Monospace Duration
                SizedBox(
                  width: 45,
                  child: Text(
                    track.duration.isNotEmpty ? track.duration : '3:30',
                    style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                      fontSize: 11,
                      color: MidnightVelvetTokens.textSecondary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),

                const SizedBox(width: 8),

                // 6. Action Controls: Play / Remove
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        isActive && isPlaying
                            ? Icons.pause_circle_filled_rounded
                            : Icons.play_circle_fill_rounded,
                        size: 20,
                        color: isActive
                            ? MidnightVelvetTokens.primaryEmber
                            : MidnightVelvetTokens.textSecondary,
                      ),
                      tooltip: isActive && isPlaying ? 'Pause' : 'Play',
                      onPressed: () {
                        if (isActive) {
                          controller.togglePlayPause();
                        } else {
                          controller.skipToQueueItem(index);
                        }
                      },
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 16,
                        color: MidnightVelvetTokens.textMuted,
                      ),
                      tooltip: 'Remove from Queue',
                      onPressed: () => controller.removeTrackAt(index),
                      splashRadius: 16,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(width: 8),

                // 7. Drag Reorder Handle
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: MidnightVelvetTokens.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentPressingsList(PlayerController controller) {
    final recentAsync = ref.watch(recentlyPlayedProvider);

    return recentAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(
          color: MidnightVelvetTokens.amberChampagne,
          strokeWidth: 2,
        ),
      ),
      error: (e, _) => Center(
        child: Text(
          'Error loading session history',
          style: MidnightVelvetTokens.fontBodyMedium.copyWith(color: MidnightVelvetTokens.primaryEmber),
        ),
      ),
      data: (history) {
        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 48,
                  color: MidnightVelvetTokens.textMuted.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'NO RECENT PRESSINGS YET',
                  style: MidnightVelvetTokens.fontSectionTitle.copyWith(
                    fontSize: 14,
                    letterSpacing: 0.06 * 14,
                    color: MidnightVelvetTokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tracks played during this session will be recorded here.',
                  style: MidnightVelvetTokens.fontBodyMedium.copyWith(fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          itemCount: history.length,
          itemBuilder: (context, index) {
            final entry = history[index];
            final track = entry.track.toTrack();

            return Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Album Cover (40px)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 40,
                      height: 40,
                      child: MieeArtworkImage(
                        musicItem: track,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                  const SizedBox(width: 14),

                  // Track Title & Artist
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          track.displayTitle,
                          style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: MidnightVelvetTokens.textDisplay,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                            fontSize: 11,
                            color: MidnightVelvetTokens.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Play Button
                  IconButton(
                    icon: const Icon(
                      Icons.play_circle_outline_rounded,
                      size: 20,
                      color: MidnightVelvetTokens.textDisplay,
                    ),
                    tooltip: 'Play Now',
                    onPressed: () => controller.playTrack(track),
                    splashRadius: 16,
                  ),

                  // Add to Queue Button
                  IconButton(
                    icon: const Icon(
                      Icons.add_to_queue_rounded,
                      size: 18,
                      color: MidnightVelvetTokens.amberChampagne,
                    ),
                    tooltip: 'Add to Queue',
                    onPressed: () => controller.addTrackToQueue(track),
                    splashRadius: 16,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _resolveTrackQualityBadge(MusicItem item) {
    final lower = item.filePath.toLowerCase();
    if (lower.endsWith('.flac')) return 'FLAC 24/96';
    if (lower.endsWith('.wav')) return 'WAV PCM';
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return 'AAC 256K';
    if (lower.endsWith('.mp3')) return 'MP3 320K';
    if (item.isYoutube) return 'AAC 160K';
    return 'STUDIO';
  }
}
