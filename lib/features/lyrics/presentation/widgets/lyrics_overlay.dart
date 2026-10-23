import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/audio/providers.dart';
import '../../../../core/audio/playback_state.dart';
import '../../../../shared/models/music_item.dart';
import '../../domain/lyrics_model.dart';
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
  int _currentLineIndex = -1;
  String? _lastTrackId;
  static const double _itemHeight = 70.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveLine(int index) {
    if (!_scrollController.hasClients || index < 0) return;

    final viewportHeight = _scrollController.position.viewportDimension;
    final targetOffset = (index * _itemHeight) - (viewportHeight / 2) + (_itemHeight / 2);

    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTrack =
        ref.watch(playerControllerProvider.select((s) => s.currentTrack)) ?? widget.track;

    // Reset line tracking if the song changed so stale state is never retained
    if (_lastTrackId != activeTrack.id) {
      _lastTrackId = activeTrack.id;
      _currentLineIndex = -1;
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

        return Container(
          decoration: BoxDecoration(
            color: AppColors.background.withValues(alpha: 0.85),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'LYRICS',
                      style: AppTypography.labelSmall.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      color: AppColors.onSurface,
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
                      color: AppColors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 13,
                          color: AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Unsynchronized lyrics',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.onSurfaceVariant,
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
                  padding: const EdgeInsets.symmetric(vertical: 40.0),
                  itemCount: lyricsData.length,
                  itemBuilder: (context, index) {
                    final line = lyricsData[index];
                    final isActive = isSynced && index == activeIndex;

                    return GestureDetector(
                      onTap: isSynced
                          ? () {
                              ref.read(playerControllerProvider.notifier).seek(line.time);
                            }
                          : null,
                      child: Container(
                        height: isSynced ? _itemHeight : null,
                        constraints: const BoxConstraints(minHeight: 52.0),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: 8.0,
                        ),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: isSynced
                              ? (isActive
                                  ? AppTypography.headlineMedium.copyWith(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.bold,
                                      height: 1.35,
                                    )
                                  : AppTypography.bodyLarge.copyWith(
                                      color: AppColors.onSurfaceVariant.withValues(alpha: 0.45),
                                      height: 1.35,
                                    ))
                              : AppTypography.bodyLarge.copyWith(
                                  color: AppColors.onSurface.withValues(alpha: 0.85),
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                ),
                          textAlign: TextAlign.center,
                          child: Text(
                            line.text,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
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
