import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';

/// Reusable Album Artwork component.
/// Displays cover art with optional shadows and overlay play buttons.
class AlbumArtwork extends StatelessWidget {
  /// The image source URL.
  final String imageUrl;

  /// Width and height of the square artwork.
  final double size;

  /// Custom border radius. Defaults to [AppRadius.radiusLg] (12px).
  final BorderRadius? borderRadius;

  /// Overlay a floating play button on the bottom right.
  final bool showPlayButton;

  /// Callback when the overlay play button is tapped.
  final VoidCallback? onPlayTap;

  /// Apply the default low-elevation shadow. Defaults to true.
  final bool hasShadow;

  const AlbumArtwork({
    super.key,
    required this.imageUrl,
    required this.size,
    this.borderRadius,
    this.showPlayButton = false,
    this.onPlayTap,
    this.hasShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveRadius = borderRadius ?? AppRadius.radiusLg;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: effectiveRadius,
        boxShadow: hasShadow ? AppShadows.shadowLow : null,
      ),
      child: Stack(
        children: [
          // The Artwork Image
          Positioned.fill(
            child: ClipRRect(
              borderRadius: effectiveRadius,
              child: imageUrl.startsWith('http')
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: AppColors.surfaceContainerHigh,
                        child: const Icon(
                          Icons.music_note,
                          color: AppColors.onSurfaceVariant,
                          size: 32.0,
                        ),
                      ),
                    )
                  : imageUrl.isNotEmpty
                      ? Image.file(
                          File(imageUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: AppColors.surfaceContainerHigh,
                            child: const Icon(
                              Icons.music_note,
                              color: AppColors.onSurfaceVariant,
                              size: 32.0,
                            ),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceContainerHigh,
                          child: const Icon(
                            Icons.music_note,
                            color: AppColors.onSurfaceVariant,
                            size: 32.0,
                          ),
                        ),
            ),
          ),
          // Play Button Overlay
          if (showPlayButton)
            Positioned(
              bottom: 8.0,
              right: 8.0,
              child: GestureDetector(
                onTap: onPlayTap,
                child: Container(
                  width: 40.0,
                  height: 40.0,
                  decoration: const BoxDecoration(
                    color: AppColors.onSurface,
                    shape: BoxShape.circle,
                    boxShadow: AppShadows.shadowHigh,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: AppColors.onPrimary,
                    size: 20.0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
