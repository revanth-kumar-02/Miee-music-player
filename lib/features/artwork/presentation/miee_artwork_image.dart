import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../shared/models/music_item.dart';
import '../data/artwork_cache.dart';
import '../domain/artwork_query.dart';
import '../domain/artwork_source.dart';
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
        (musicItem != null
            ? ArtworkQuery.fromMusicItem(musicItem!, explicitUrl: explicitUrl)
            : (explicitUrl != null && explicitUrl!.isNotEmpty
                ? ArtworkQuery(
                    id: explicitUrl!,
                    title: '',
                    artist: '',
                    fallbackThumbnailUrl: explicitUrl,
                  )
                : null));

    // If no query could be formed, try direct explicit URL or neutral fallback
    if (effectiveQuery == null) {
      if (explicitUrl != null && explicitUrl!.isNotEmpty) {
        return _renderDirectImage(context, explicitUrl!, effectiveBorderRadius, null);
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
        // If query already carries high-res studio album artwork, render it immediately
        final albumCover = effectiveQuery.albumArtworkUrl;
        if (albumCover != null && albumCover.isNotEmpty && !albumCover.contains('ytimg.com')) {
          return _renderDirectImage(
            context,
            albumCover,
            effectiveBorderRadius,
            effectiveQuery,
            sourceLabel: 'Album Art',
          );
        }
        return placeholder ?? _buildPlaceholder(context, effectiveBorderRadius);
      },
      error: (_, __) {
        final albumCover = effectiveQuery.albumArtworkUrl;
        if (albumCover != null && albumCover.isNotEmpty && !albumCover.contains('ytimg.com')) {
          return _renderDirectImage(
            context,
            albumCover,
            effectiveBorderRadius,
            effectiveQuery,
            sourceLabel: 'Album Art',
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
    final isYtThumbnail = artwork.source == ArtworkSource.youtube ||
        artwork.imageUrl.contains('ytimg.com') ||
        artwork.imageUrl.contains('youtube.com');

    if (artwork.isNeutralFallback || artwork.imageUrl.isEmpty || isYtThumbnail) {
      if (effectiveQuery.albumArtworkUrl != null &&
          effectiveQuery.albumArtworkUrl!.isNotEmpty &&
          !effectiveQuery.albumArtworkUrl!.contains('ytimg.com')) {
        return _renderDirectImage(
          context,
          effectiveQuery.albumArtworkUrl!,
          radius,
          effectiveQuery,
          sourceLabel: 'Album Art',
        );
      }
      if (explicitUrl != null &&
          explicitUrl!.isNotEmpty &&
          !explicitUrl!.contains('ytimg.com') &&
          !explicitUrl!.contains('youtube.com') &&
          !explicitUrl!.contains('/vi/placeholder/')) {
        return _renderDirectImage(context, explicitUrl!, radius, effectiveQuery);
      }
      return _buildNeutralFallback(context, radius);
    }

    final sourceName = artwork.source.name;

    if (ArtworkCache.hasValidLocalFile(artwork.localCachedPath)) {
      return _renderDirectImage(
        context,
        artwork.localCachedPath!,
        radius,
        effectiveQuery,
        sourceLabel: sourceName,
      );
    }

    return _renderDirectImage(
      context,
      artwork.imageUrl,
      radius,
      effectiveQuery,
      sourceLabel: sourceName,
    );
  }

  Widget _renderDirectImage(
    BuildContext context,
    String pathOrUrl,
    BorderRadius radius,
    ArtworkQuery? query, {
    String? sourceLabel,
  }) {
    final isNetwork = pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://');
    final isAsset = pathOrUrl.startsWith('assets/');

    Widget imageWidget;
    if (isNetwork) {
      imageWidget = Image.network(
        pathOrUrl,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          // If a maxres or sd thumbnail failed (e.g. HTTP 404), seamlessly retry with hqdefault
          if (pathOrUrl.contains('maxresdefault.jpg') || pathOrUrl.contains('sddefault.jpg')) {
            final fallbackYt = pathOrUrl
                .replaceAll('maxresdefault.jpg', 'hqdefault.jpg')
                .replaceAll('sddefault.jpg', 'hqdefault.jpg');
            return Image.network(
              fallbackYt,
              width: width,
              height: height,
              fit: fit,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) {
                return errorWidget ?? _buildNeutralFallback(context, radius);
              },
            );
          }

          // If query has a fallback thumbnail that differs from the failed path
          final secondary = query?.fallbackThumbnailUrl;
          if (secondary != null &&
              secondary.isNotEmpty &&
              secondary != pathOrUrl &&
              !secondary.contains('/vi/placeholder/')) {
            return Image.network(
              secondary,
              width: width,
              height: height,
              fit: fit,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) {
                return errorWidget ?? _buildNeutralFallback(context, radius);
              },
            );
          }

          return errorWidget ?? _buildNeutralFallback(context, radius);
        },
      );
    } else if (isAsset) {
      imageWidget = Image.asset(
        pathOrUrl,
        width: width,
        height: height,
        fit: fit,
        gaplessPlayback: true,
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
        gaplessPlayback: true,
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            imageWidget,
            if (kDebugMode &&
                sourceLabel != null &&
                (width == null || width! >= 50) &&
                (height == null || height! >= 50))
              Positioned(
                bottom: 2,
                left: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    sourceLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
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
