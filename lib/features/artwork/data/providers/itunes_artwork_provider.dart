import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';
import '../../../metadata/data/itunes_metadata_service.dart';

/// Primary Apple iTunes Search API artwork provider.
///
/// Resolves high-resolution studio album artwork (`600x600bb.jpg`) from Apple's
/// catalogue CDN when a confident metadata match is found.
class ItunesArtworkProvider implements ArtworkProvider {
  final ItunesMetadataService? _metadataService;

  @override
  final bool isEnabled;

  const ItunesArtworkProvider({
    this.isEnabled = true,
    ItunesMetadataService? metadataService,
  }) : _metadataService = metadataService;

  @override
  String get id => 'itunes';

  @override
  ArtworkSource get source => ArtworkSource.itunes;

  @override
  int get priority => 1;

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    if (!isEnabled) {
      return null;
    }

    try {
      final service = _metadataService ?? ItunesMetadataService();
      final durationStr = query.durationMs != null
          ? '${query.durationMs! ~/ 60000}:${((query.durationMs! % 60000) ~/ 1000).toString().padLeft(2, '0')}'
          : null;

      final match = await service.matchCandidate(
        rawTitle: query.title,
        rawArtist: query.artist,
        durationStr: durationStr,
        album: query.album,
      );

      if (match.isConfident &&
          match.highResArtworkUrl != null &&
          match.highResArtworkUrl!.isNotEmpty) {
        return ResolvedArtwork(
          imageUrl: match.highResArtworkUrl!,
          source: ArtworkSource.itunes,
          confidence: match.confidence,
          attribution: 'Apple iTunes',
          width: 600,
          height: 600,
          isLocal: false,
          resolvedAt: DateTime.now(),
        );
      }
    } catch (_) {}

    return null;
  }
}
