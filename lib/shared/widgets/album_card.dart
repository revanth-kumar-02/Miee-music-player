import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_radius.dart';
import '../../app/theme/app_shadows.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import 'album_artwork.dart';

/// Layout variations for the Album Card.
enum AlbumCardVariant {
  /// Standard: Square cover artwork with metadata stacked below.
  standard,

  /// Bento Hero: Wide 2:1 card with background artwork and white text overlay.
  bentoHero,

  /// Bento Sub: Square card with a translucent white bottom overlay banner.
  bentoSub,
}

/// Reusable Album Card widget.
/// Implements standard, hero, and sub card layout variations.
class AlbumCard extends StatelessWidget {
  /// The image source URL.
  final String imageUrl;

  /// Main title of the album or playlist.
  final String title;

  /// Optional subtitle (artist, track count, or descriptor).
  final String? subtitle;

  /// Layout variant style. Defaults to [AlbumCardVariant.standard].
  final AlbumCardVariant variant;

  /// Callback when the card is tapped.
  final VoidCallback? onTap;

  /// Callback when the quick play button is tapped (used in standard variant).
  final VoidCallback? onPlayTap;

  /// Control standard variant play button visibility.
  final bool showPlayButton;

  const AlbumCard({
    super.key,
    required this.imageUrl,
    required this.title,
    this.subtitle,
    this.variant = AlbumCardVariant.standard,
    this.onTap,
    this.onPlayTap,
    this.showPlayButton = false,
  });

  @override
  Widget build(BuildContext context) {
    switch (variant) {
      case AlbumCardVariant.bentoHero:
        return _buildBentoHero(context);
      case AlbumCardVariant.bentoSub:
        return _buildBentoSub(context);
      case AlbumCardVariant.standard:
        return _buildStandard(context);
    }
  }

  Widget _buildStandard(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 140.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AlbumArtwork(
              imageUrl: imageUrl,
              size: 140.0,
              showPlayButton: showPlayButton,
              onPlayTap: onPlayTap,
            ),
            AppSpacing.heightSm,
            Text(
              title,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.onSurface,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle != null) ...[
              AppSpacing.heightXs,
              Text(
                subtitle!,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBentoHero(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 180.0,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: AppRadius.radiusLg,
          boxShadow: AppShadows.shadowLow,
        ),
        child: ClipRRect(
          borderRadius: AppRadius.radiusLg,
          child: Stack(
            children: [
              // Background Image
              Positioned.fill(
                child: _buildImageWidget(imageUrl),
              ),
              // Bottom Shadow Gradient
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.black.withOpacity(0.6),
                        Colors.transparent,
                      ],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                    ),
                  ),
                ),
              ),
              // Text Overlay
              Positioned(
                bottom: AppSpacing.md,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTypography.headlineMedium.copyWith(
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      AppSpacing.heightXs,
                      Text(
                        subtitle!,
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBentoSub(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.radiusLg,
            boxShadow: AppShadows.shadowLow,
          ),
          child: ClipRRect(
            borderRadius: AppRadius.radiusLg,
            child: Stack(
              children: [
                // Background Image
                Positioned.fill(
                  child: _buildImageWidget(imageUrl),
                ),
                // Bottom Translucent Banner
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: const ColorFilter.mode(
                        Colors.transparent,
                        BlendMode.multiply,
                      ),
                      child: Container(
                        color: Colors.white.withOpacity(0.9),
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        child: Text(
                          title,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
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
    );
  }

  Widget _buildFallbackImageContainer() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF111111), Color(0xFF2A2A2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.music_note,
          color: Colors.white54,
          size: 32.0,
        ),
      ),
    );
  }

  Widget _buildImageWidget(String path) {
    if (path.isEmpty) {
      return _buildFallbackImageContainer();
    }
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackImageContainer(),
      );
    } else {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildFallbackImageContainer(),
      );
    }
  }
}
