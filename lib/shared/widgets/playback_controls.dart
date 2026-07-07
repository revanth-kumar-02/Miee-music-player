import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';

/// Reusable Playback Controls row.
/// Hosts Shuffle, Skip Previous, Play/Pause large circular FAB, Skip Next, and Repeat buttons.
class PlaybackControls extends StatelessWidget {
  /// Controls the visual state of the play/pause icon.
  final bool isPlaying;

  /// Toggles active styling on the shuffle button. Defaults to false.
  final bool isShuffleActive;

  /// Toggles active styling on the repeat button. Defaults to false.
  final bool isRepeatActive;

  /// Callback when play/pause circle is tapped.
  final VoidCallback? onPlayPauseTap;

  /// Callback when skip previous button is tapped.
  final VoidCallback? onPrevTap;

  /// Callback when skip next button is tapped.
  final VoidCallback? onNextTap;

  /// Callback when shuffle icon button is tapped.
  final VoidCallback? onShuffleTap;

  /// Callback when repeat icon button is tapped.
  final VoidCallback? onRepeatTap;

  const PlaybackControls({
    super.key,
    required this.isPlaying,
    this.isShuffleActive = false,
    this.isRepeatActive = false,
    this.onPlayPauseTap,
    this.onPrevTap,
    this.onNextTap,
    this.onShuffleTap,
    this.onRepeatTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Shuffle Button
        IconButton(
          icon: Icon(
            Icons.shuffle,
            color: isShuffleActive ? AppColors.accentIndigo : AppColors.onSurfaceVariant,
            size: 24.0,
          ),
          onPressed: onShuffleTap,
          splashRadius: 24.0,
        ),
        // Previous Button
        IconButton(
          icon: const Icon(
            Icons.skip_previous,
            color: AppColors.onBackground,
            size: 36.0,
          ),
          onPressed: onPrevTap,
          splashRadius: 28.0,
        ),
        // Play/Pause Large Circle FAB
        GestureDetector(
          onTap: onPlayPauseTap,
          child: Container(
            width: 64.0,
            height: 64.0,
            decoration: const BoxDecoration(
              color: AppColors.inverseSurface, // `#313030`
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x29000000), // shadow for high floating buttons
                  offset: Offset(0, 8),
                  blurRadius: 24,
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 40.0,
            ),
          ),
        ),
        // Next Button
        IconButton(
          icon: const Icon(
            Icons.skip_next,
            color: AppColors.onBackground,
            size: 36.0,
          ),
          onPressed: onNextTap,
          splashRadius: 28.0,
        ),
        // Repeat Button
        IconButton(
          icon: Icon(
            Icons.repeat,
            color: isRepeatActive ? AppColors.accentIndigo : AppColors.onSurfaceVariant,
            size: 24.0,
          ),
          onPressed: onRepeatTap,
          splashRadius: 24.0,
        ),
      ],
    );
  }
}
