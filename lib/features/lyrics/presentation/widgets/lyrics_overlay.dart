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
    final lyricsAsync = ref.watch(lyricsProvider(widget.track));
    final playerState = ref.watch(playerControllerProvider);
    final currentPosition = playerState.position;

    return lyricsAsync.when(
      data: (lyrics) {
        if (lyrics.isEmpty) {
          return _buildEmptyState("No lyrics available for this song.");
        }

        // Find current line index based on playback position
        int activeIndex = -1;
        for (int i = 0; i < lyrics.length; i++) {
          if (currentPosition >= lyrics[i].time) {
            activeIndex = i;
          } else {
            break;
          }
        }

        // Scroll to active line when it changes
        if (activeIndex != _currentLineIndex) {
          _currentLineIndex = activeIndex;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToActiveLine(activeIndex);
          });
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
              const Divider(height: 1),

              // Lyrics List View
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 40.0),
                  itemCount: lyrics.length,
                  itemBuilder: (context, index) {
                    final line = lyrics[index];
                    final isActive = index == activeIndex;

                    return GestureDetector(
                      onTap: () {
                        ref.read(playerControllerProvider.notifier).seekTo(line.time);
                      },
                      child: Container(
                        height: _itemHeight,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 300),
                          style: isActive
                              ? AppTypography.headlineMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                )
                              : AppTypography.titleLarge.copyWith(
                                  color: AppColors.onSurfaceVariant.withValues(alpha: 0.5),
                                ),
                          textAlign: TextAlign.center,
                          child: Text(
                            line.text,
                            maxLines: 2,
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
          Icon(Icons.music_off_outlined, size: 48.0, color: AppColors.onSurfaceVariant.withValues(alpha: 0.3)),
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
