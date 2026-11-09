import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/models/music_item.dart';
import '../domain/artwork_query.dart';
import '../domain/resolved_artwork.dart';
import 'artwork_providers.dart';

/// Universal artwork presentation widget for Miee.
///
/// Dispatches queries through the deterministic [ArtworkResolver] and renders
/// local files, verified online covers, YouTube thumbnails, or Nordic Cobalt neutral fallbacks.
class MieeArtworkImage extends ConsumerWidget {
  final MusicItem? musicItem;
  final ArtworkQuery? query;
  final String? explicitUrl;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const MieeArtworkImage({
    super.key,
    this.musicItem,
    this.query,
    this.explicitUrl,
    this.width,
    this.height,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final effectiveBorderRadius = borderRadius ?? BorderRadius.circular(8);

    // Build the query
    final effectiveQuery = query ??
        (musicItem != null ? ArtworkQuery.fromMusicItem(musicItem!) : null);

    // If explicitUrl is given and no query can be constructed, render directly
    if (effectiveQuery == null) {
      if (explicitUrl != null && explicitUrl!.isNotEmpty) {
        return _renderDirectImage(context, explicitUrl!, effectiveBorderRadius);
      }
      return _buildNeutralFallback(context, effectiveBorderRadius);
    }

    final asyncArtwork = ref.watch(resolvedArtworkProvider(effectiveQuery));

    return asyncArtwork.when(
      data: (artwork) {
        return _renderResolvedArtwork(
          context,
          artwork,
          effectiveBorderRadius,
          effectiveQuery,
        );
      },
      loading: () {
        // While resolving, display the fallback thumbnail if available or neutral placeholder
        if (effectiveQuery.fallbackThumbnailUrl != null &&
            effectiveQuery.fallbackThumbnailUrl!.isNotEmpty) {
          return _renderDirectImage(
            context,
            effectiveQuery.fallbackThumbnailUrl!,
            effectiveBorderRadius,
          );
        }
        return placeholder ?? _buildPlaceholder(context, effectiveBorderRadius);
      },
      error: (_, __) {
        if (effectiveQuery.fallbackThumbnailUrl != null &&
            effectiveQuery.fallbackThumbnailUrl!.isNotEmpty) {
          return _renderDirectImage(
            context,
            effectiveQuery.fallbackThumbnailUrl!,
            effectiveBorderRadius,
          );
        }
        return errorWidget ?? _buildNeutralFallback(context, effectiveBorderRadius);
      },
    );
  }

  Widget _renderResolvedArtwork(
    BuildContext context,
    ResolvedArtwork artwork,
    BorderRadius radius,
    ArtworkQuery effectiveQuery,
  ) {
    if (artwork.isNeutralFallback || artwork.imageUrl.isEmpty) {
      // Prioritize the track's authentic stream thumbnail or explicit URL
      // over the neutral icon whenever available
      if (effectiveQuery.fallbackThumbnailUrl != null &&
          effectiveQuery.fallbackThumbnailUrl!.isNotEmpty) {
        return _renderDirectImage(
          context,
          effectiveQuery.fallbackThumbnailUrl!,
          radius,
        );
      }
      if (explicitUrl != null && explicitUrl!.isNotEmpty) {
        return _renderDirectImage(context, explicitUrl!, radius);
      }
      return _buildNeutralFallback(context, radius);
    }

    return _renderDirectImage(context, artwork.imageUrl, radius);
  }

  Widget _renderDirectImage(BuildContext context, String pathOrUrl, BorderRadius radius) {
    final isNetwork = pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');
    final isAsset = pathOrUrl.startsWith('assets/');

    Widget imageWidget;
    if (isNetwork) {
      imageWidget = Image.network(
        pathOrUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? _buildNeutralFallback(context, radius);
        },
      );
    } else if (isAsset) {
      imageWidget = Image.asset(
        pathOrUrl,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? _buildNeutralFallback(context, radius);
        },
      );
    } else {
      String cleanPath;
      try {
        cleanPath = pathOrUrl.startsWith('file://')
            ? (Uri.tryParse(pathOrUrl)?.toFilePath() ?? pathOrUrl.replaceFirst('file://', ''))
            : pathOrUrl;
      } catch (_) {
        cleanPath = pathOrUrl.replaceFirst('file://', '');
      }
      final file = File(cleanPath);

      imageWidget = Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) {
          return errorWidget ?? _buildNeutralFallback(context, radius);
        },
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: width,
        height: height,
        color: AppColors.paleConcrete,
        child: imageWidget,
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, BorderRadius radius) {
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: width,
        height: height,
        color: AppColors.paleConcrete,
        child: const Center(
          child: Icon(
            Icons.music_note_rounded,
            color: AppColors.industrialSteel,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildNeutralFallback(BuildContext context, BorderRadius radius) {
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: width,
        height: height,
        color: AppColors.paleConcrete,
        child: Center(
          child: Icon(
            Icons.album_rounded,
            color: AppColors.industrialSteel.withValues(alpha: 0.6),
            size: (width != null && height != null) ? (width! * 0.4).clamp(16.0, 48.0) : 28.0,
          ),
        ),
      ),
    );
  }
}

