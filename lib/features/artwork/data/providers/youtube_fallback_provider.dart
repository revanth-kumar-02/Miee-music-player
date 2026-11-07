import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';

/// Last-resort fallback provider utilizing the stream's existing YouTube thumbnail.
class YouTubeFallbackProvider implements ArtworkProvider {
  @override
  String get id => 'youtube';

  @override
  ArtworkSource get source => ArtworkSource.youtube;

  @override
  bool get isEnabled => true;

  @override
  int get priority => 7;

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    final thumb = query.fallbackThumbnailUrl;
    if (thumb != null && thumb.trim().isNotEmpty) {
      return ResolvedArtwork(
        imageUrl: thumb.trim(),
        source: ArtworkSource.youtube,
        confidence: 0.5,
        attribution: 'YouTube Music',
        resolvedAt: DateTime.now(),
      );
    }
    return null;
  }
}

