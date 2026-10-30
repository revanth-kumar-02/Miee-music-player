import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/audio/providers.dart';
import '../../../../shared/models/music_item.dart';
import '../../providers/lyrics_providers.dart';

class LyricsOverlay extends ConsumerStatefulWidget {
  final MusicItem track;
  final VoidCallback onClose;

  const LyricsOverlay({
    super.key,
    required this.track,
    required this.onClose,
  });

  @override
  ConsumerState<LyricsOverlay> createState() => _LyricsOverlayState();
}

class _LyricsOverlayState extends ConsumerState<LyricsOverlay> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};
  int _currentLineIndex = -1;
  String? _lastTrackId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLine(int index) {
    if (!_scrollController.hasClients || index < 0) return;

    final key = _lineKeys[index];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        alignment: 0.42,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      final viewportHeight = _scrollController.position.viewportDimension;
      final targetOffset = (index * 68.0) - (viewportHeight * 0.42);
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final freshKey = _lineKeys[index];
        if (freshKey?.currentContext != null) {
          Scrollable.ensureVisible(
            freshKey!.currentContext!,
            alignment: 0.42,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTrack =
        ref.watch(playerControllerProvider.select((s) => s.currentTrack)) ?? widget.track;

    // Reset line tracking if the song changed so stale state is never retained
    if (_lastTrackId != activeTrack.id) {
      _lastTrackId = activeTrack.id;
      _currentLineIndex = -1;
      _lineKeys.clear();
    }

    final lyricsAsync = ref.watch(lyricsProvider(activeTrack));
    final currentPosition = ref.watch(playerControllerProvider.select((s) => s.position));

    return lyricsAsync.when(
      data: (lyricsData) {
        if (lyricsData.isEmpty) {
          return _buildEmptyState("No lyrics available for this song.");
        }

        final isSynced = lyricsData.isSynced;
        int activeIndex = -1;

        if (isSynced) {
          for (int i = 0; i < lyricsData.length; i++) {
            if (currentPosition >= lyricsData[i].time) {
              activeIndex = i;
            } else {
              break;
            }
          }

          if (activeIndex != _currentLineIndex) {
            _currentLineIndex = activeIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scrollToActiveLine(activeIndex);
            });
          }
        }

        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
          child: Container(
            color: AppColors.vanillaCream,
            child: Column(
              children: [
                // Top drag pill
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10.0, bottom: 4.0),
                    decoration: BoxDecoration(
                      color: AppColors.oatBeige,
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.marginMobile,
                    vertical: AppSpacing.xs,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'LYRICS',
                        style: AppTypography.labelSmall.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.0,
                          color: AppColors.mutedMauve,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        color: AppColors.cocoaPlum,
                        onPressed: widget.onClose,
                        splashRadius: 20.0,
                      ),
                    ],
                  ),
                ),

                // Unsynchronized indicator badge if timing is unavailable
                if (!isSynced)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cocoaPlum.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 13,
                            color: AppColors.mutedMauve,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Unsynchronized lyrics',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.mutedMauve,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Lyrics List View
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    cacheExtent: 4000.0,
                    padding: EdgeInsets.only(
                      top: 16.0,
                      bottom: MediaQuery.of(context).padding.bottom + 80.0,
                    ),
                    itemCount: lyricsData.length,
                    itemBuilder: (context, index) {
                      final line = lyricsData[index];
                      final isActive = isSynced && index == activeIndex;
                      final itemKey = _lineKeys.putIfAbsent(index, () => GlobalKey());

                      return GestureDetector(
                        key: itemKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: isSynced
                            ? () {
                                HapticFeedback.lightImpact();
                                ref.read(playerControllerProvider.notifier).seek(line.time);
                              }
                            : null,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 52.0),
                          alignment: Alignment.center,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 3.0,
                          ),
                          padding: EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: isActive ? 14.0 : 10.0,
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 300),
                            style: isSynced
                                ? (isActive
                                    ? AppTypography.headlineMedium.copyWith(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.bold,
                                        height: 1.45,
                                      )
                                    : AppTypography.bodyLarge.copyWith(
                                        color: AppColors.cocoaPlum.withValues(alpha: 0.40),
                                        fontWeight: FontWeight.w500,
                                        height: 1.4,
                                      ))
                                : AppTypography.bodyLarge.copyWith(
                                    color: AppColors.cocoaPlum.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                            textAlign: TextAlign.center,
                            child: Text(
                              line.text,
                              textAlign: TextAlign.center,
                              softWrap: true,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _buildEmptyState("Failed to load lyrics: $err"),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.music_off_outlined,
            size: 48.0,
            color: AppColors.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12.0),
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16.0),
          TextButton(
            onPressed: widget.onClose,
            child: const Text('Back to Player'),
          )
        ],
      ),
    );
  }
}
