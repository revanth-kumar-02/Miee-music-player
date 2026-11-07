import '../../domain/artwork_provider_interface.dart';
import '../../domain/artwork_query.dart';
import '../../domain/artwork_source.dart';
import '../../domain/resolved_artwork.dart';

/// Optional Fanart.tv provider for album and artist artwork.
///
/// MUST remain disabled by default (`isEnabled = false`).
/// Requires an injected API key from secure user configuration.
class FanartArtworkProvider implements ArtworkProvider {
  final String? apiKey;
  @override
  final bool isEnabled;

  const FanartArtworkProvider({
    this.apiKey,
    this.isEnabled = false,
  });

  @override
  String get id => 'fanart';

  @override
  ArtworkSource get source => ArtworkSource.fanart;

  @override
  int get priority => 5;

  @override
  Future<ResolvedArtwork?> resolve(ArtworkQuery query) async {
    // Strictly guard: disabled by default, never execute without explicit enabled flag and key
    if (!isEnabled || apiKey == null || apiKey!.trim().isEmpty) {
      return null;
    }

    // Awaiting production credentials and verified rights
    return null;
  }
}

