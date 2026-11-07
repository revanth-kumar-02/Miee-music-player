import 'artwork_query.dart';
import 'artwork_source.dart';
import 'resolved_artwork.dart';

/// Contract for all artwork providers participating in Miee's artwork resolution pipeline.
abstract class ArtworkProvider {
  /// Unique identifier of this provider (e.g. 'local', 'musicbrainz', 'deezer').
  String get id;

  /// The category/source of artwork returned by this provider.
  ArtworkSource get source;

  /// Whether this provider is enabled by user configuration or system policy.
  bool get isEnabled;

  /// Lower number = higher priority in the resolution pipeline.
  int get priority;

  /// Attempts to resolve high-quality artwork for the given [query].
  ///
  /// Returns [ResolvedArtwork] if a reliable, validated match is found,
  /// or `null` to yield to subsequent providers in the pipeline.
  Future<ResolvedArtwork?> resolve(ArtworkQuery query);
}

