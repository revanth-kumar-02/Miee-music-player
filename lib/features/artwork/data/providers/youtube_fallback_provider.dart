import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';

/// Primary online artwork provider for YouTube Music content.
/// Utilizes the authentic stream thumbnail or derives the deterministic
/// high-quality YouTube image URL from the video ID.
class YouTubeFallbackProvider implements ArtworkProvider {
  const YouTubeFallbackProvider();

  @override
  String get id => 'youtube';

  @override
  ArtworkSource get source => ArtworkSource.youtube;

  @override
  bool get isEnabled => true;

  @override
  int get priority => 2;

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    String? thumb = query.fallbackThumbnailUrl;

    if (thumb == null || thumb.trim().isEmpty) {
      final vid = query.youtubeVideoId ?? (query.isYoutube ? query.id.replaceFirst('youtube_', '').trim() : null);
      if (vid != null && RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(vid)) {
        thumb = 'https://i.ytimg.com/vi/$vid/hqdefault.jpg';
      }
    }

    if (thumb != null && thumb.trim().isNotEmpty) {
      return ResolvedArtwork(
        imageUrl: thumb.trim(),
        source: ArtworkSource.youtube,
        confidence: 0.85,
        attribution: 'YouTube Music',
        resolvedAt: DateTime.now(),
      );
    }
    return null;
  }
}
