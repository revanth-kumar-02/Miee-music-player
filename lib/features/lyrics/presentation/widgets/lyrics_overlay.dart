import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
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
          return _buildEmptyState('No lyrics available for this song.');
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
                          const Icon(
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
      loading: () => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1B20),
              borderRadius: BorderRadius.circular(24.0),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 32,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFE5C396)),
                  ),
                ),
                const SizedBox(height: 18.0),
                Text(
                  'Searching lyrics...',
                  style: GoogleFonts.geist(
                    fontSize: 15.0,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFFF6F6F4),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
      error: (err, _) => _buildErrorState(err),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1B20),
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Champagne accent icon container
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5C396).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE5C396).withValues(alpha: 0.30),
                    width: 1.0,
                  ),
                ),
                child: const Icon(
                  Icons.lyrics_outlined,
                  size: 28.0,
                  color: Color(0xFFE5C396),
                ),
              ),
              const SizedBox(height: 18.0),
              // Heading
              Text(
                'No lyrics available for this song',
                style: GoogleFonts.geist(
                  fontSize: 17.0,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF6F6F4),
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              // Description
              Text(
                'We checked multiple title variants and providers.',
                style: GoogleFonts.geist(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFA1A1AA),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24.0),
              // Back to Player button
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    widget.onClose();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF272930),
                    foregroundColor: const Color(0xFFF6F6F4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14.0),
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.10),
                        width: 1.0,
                      ),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Back to Player',
                    style: GoogleFonts.geist(
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFF6F6F4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(Object err) {
    final isNetwork = err.toString().toLowerCase().contains('socket') ||
        err.toString().toLowerCase().contains('connect') ||
        err.toString().toLowerCase().contains('timeout') ||
        err.toString().toLowerCase().contains('network');

    final title = isNetwork
        ? 'Network Connection Issue'
        : 'Lyrics Service Temporarily Unavailable';
    final subtitle = isNetwork
        ? 'Please check your internet connection and try again.'
        : 'Could not connect to the lyrics service right now.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28.0),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 360),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1B20),
            borderRadius: BorderRadius.circular(24.0),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.40),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5C396).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFE5C396).withValues(alpha: 0.30),
                    width: 1.0,
                  ),
                ),
                child: Icon(
                  isNetwork ? Icons.wifi_off_outlined : Icons.cloud_off_outlined,
                  size: 28.0,
                  color: const Color(0xFFE5C396),
                ),
              ),
              const SizedBox(height: 18.0),
              Text(
                title,
                style: GoogleFonts.geist(
                  fontSize: 17.0,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF6F6F4),
                  letterSpacing: -0.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8.0),
              Text(
                subtitle,
                style: GoogleFonts.geist(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFA1A1AA),
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24.0),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          ref.invalidate(lyricsProvider(widget.track));
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF6F6F4),
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1.0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.0),
                          ),
                        ),
                        child: Text(
                          'Retry',
                          style: GoogleFonts.geist(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFF6F6F4),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.onClose();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF272930),
                          foregroundColor: const Color(0xFFF6F6F4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14.0),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.10),
                              width: 1.0,
                            ),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Back to Player',
                          style: GoogleFonts.geist(
                            fontSize: 14.0,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFF6F6F4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
