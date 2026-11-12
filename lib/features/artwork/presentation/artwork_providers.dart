import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/music_item.dart';
import '../data/artwork_resolver_impl.dart';
import '../data/providers/youtube_fallback_provider.dart';
import '../domain/artwork_query.dart';
import '../domain/resolved_artwork.dart';

/// Global provider for the central [ArtworkResolver] instance.
final artworkResolverProvider = Provider<ArtworkResolver>((ref) {
  final ytValidationDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 4),
    ),
  );
  return ArtworkResolver(
    youtubeFallbackProvider: YouTubeFallbackProvider(dio: ytValidationDio),
    cacheImagesLocally: true,
  );
});

/// Resolves artwork asynchronously for a given [ArtworkQuery].
final resolvedArtworkProvider =
    FutureProvider.family<ResolvedArtwork, ArtworkQuery>((ref, query) async {
  final resolver = ref.watch(artworkResolverProvider);
  return resolver.resolve(query);
});

/// Resolves artwork asynchronously for any [MusicItem] (MediaSong, YouTubeVideo, Track).
final resolvedArtworkFromItemProvider =
    FutureProvider.family<ResolvedArtwork, MusicItem>((ref, item) async {
  final resolver = ref.watch(artworkResolverProvider);
  final query = ArtworkQuery.fromMusicItem(item);
  return resolver.resolve(query);
});

