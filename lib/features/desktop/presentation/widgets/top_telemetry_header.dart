import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/midnight_velvet_tokens.dart';
import '../../../../features/profile/providers/profile_providers.dart';
import '../../../../core/audio/providers.dart';

class TopTelemetryHeader extends ConsumerWidget {
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final ValueChanged<String>? onSearchSubmitted;
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  const TopTelemetryHeader({
    super.key,
    this.searchController,
    this.searchFocusNode,
    this.onSearchSubmitted,
    this.onBack,
    this.onForward,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentUserProfileProvider);
    final displayName = profile?.displayName ?? 'Audiophile';
    final currentTrack = ref.watch(playerControllerProvider).currentTrack;

    return Container(
      height: MidnightVelvetTokens.telemetryHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: MidnightVelvetTokens.surfaceLayer1,
        border: Border(
          bottom: BorderSide(
            color: MidnightVelvetTokens.hairlineRim,
            width: 1.0,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: MidnightVelvetTokens.glassBlurSigma,
            sigmaY: MidnightVelvetTokens.glassBlurSigma,
          ),
          child: Row(
            children: [
              // 1. History Back/Forward Nav
              _buildNavButton(Icons.chevron_left_rounded, onBack),
              const SizedBox(width: 8),
              _buildNavButton(Icons.chevron_right_rounded, onForward),

              const SizedBox(width: 24),

              // 2. Search Studio Index Input
              Expanded(
                child: Container(
                  height: 42,
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: MidnightVelvetTokens.surfaceCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MidnightVelvetTokens.hairlineRim,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: MidnightVelvetTokens.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          onSubmitted: onSearchSubmitted,
                          style: MidnightVelvetTokens.fontBodyMedium.copyWith(
                            color: MidnightVelvetTokens.textDisplay,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search artists, tracks, or soundscapes...',
                            hintStyle: MidnightVelvetTokens.fontBodyMedium.copyWith(
                              color: MidnightVelvetTokens.textMuted,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
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
                          '⌘K',
                          style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                            fontSize: 10,
                            color: MidnightVelvetTokens.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 24),

              // 3. Audio Stream Quality Telemetry Badge
              _buildStreamQualityBadge(currentTrack),

              const SizedBox(width: 16),

              // 4. User Profile Capsule
              _buildUserProfileBadge(displayName),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(IconData icon, VoidCallback? onPressed) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        hoverColor: MidnightVelvetTokens.surfaceCardHover,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: MidnightVelvetTokens.surfaceCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: MidnightVelvetTokens.hairlineRim,
              width: 0.8,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: MidnightVelvetTokens.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildStreamQualityBadge(dynamic track) {
    if (track == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: MidnightVelvetTokens.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: MidnightVelvetTokens.hairlineRim,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.sensors_off_rounded,
              size: 14,
              color: MidnightVelvetTokens.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              'DAC STANDBY • 44.1 KHZ',
              style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
                fontSize: 10,
                color: MidnightVelvetTokens.textMuted,
              ),
            ),
          ],
        ),
      );
    }

    final path = track.filePath.toString().toLowerCase();
    final bool isFlac = path.endsWith('.flac') || track.title.toString().toLowerCase().contains('flac');
    final bool isWav = path.endsWith('.wav');
    final bool isAac = path.endsWith('.m4a') || path.endsWith('.aac');
    final bool isMp3 = path.endsWith('.mp3');
    final bool isYt = track.isYoutube == true;

    String label;
    bool isLossless = false;

    if (isFlac) {
      label = 'FLAC LOSSLESS • PCM DIRECT';
      isLossless = true;
    } else if (isWav) {
      label = 'WAV PCM • UNCOMPRESSED';
      isLossless = true;
    } else if (isAac) {
      label = 'AAC • 256 KBPS / 44.1 KHZ';
    } else if (isMp3) {
      label = 'MP3 • 320 KBPS / 44.1 KHZ';
    } else if (isYt) {
      label = 'STREAM • OPUS 160 KBPS';
    } else {
      label = 'DIRECT STREAM • 44.1 KHZ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLossless
              ? MidnightVelvetTokens.amberChampagne.withValues(alpha: 0.5)
              : MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.graphic_eq_rounded,
            size: 14,
            color: isLossless
                ? MidnightVelvetTokens.amberChampagne
                : MidnightVelvetTokens.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: MidnightVelvetTokens.fontMonoTelemetry.copyWith(
              fontSize: 10,
              color: isLossless
                  ? MidnightVelvetTokens.amberChampagne
                  : MidnightVelvetTokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserProfileBadge(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: MidnightVelvetTokens.surfaceCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: MidnightVelvetTokens.hairlineRim,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: MidnightVelvetTokens.primaryEmber,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U',
              style: MidnightVelvetTokens.fontMonoTimecode.copyWith(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: MidnightVelvetTokens.fontBodyMedium.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: MidnightVelvetTokens.textDisplay,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: MidnightVelvetTokens.textSecondary,
          ),
        ],
      ),
    );
  }
}
