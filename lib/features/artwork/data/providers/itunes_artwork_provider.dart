import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';

/// Conditional Apple iTunes Search API artwork provider.
///
/// MUST remain disabled by default (`isEnabled = false`) to strictly satisfy
/// Apple's promotional-content usage and commercial attribution requirements.
class ItunesArtworkProvider implements ArtworkProvider {
  @override
  final bool isEnabled;

  const ItunesArtworkProvider({
    this.isEnabled = false,
  });

  @override
  String get id => 'itunes';

  @override
  ArtworkSource get source => ArtworkSource.itunes;

  @override
  int get priority => 6;

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    // Strictly disabled by default pending legal/licensing verification
    if (!isEnabled) {
      return null;
    }

    return null;
  }
}

