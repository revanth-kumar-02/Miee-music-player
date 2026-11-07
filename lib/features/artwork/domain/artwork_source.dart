/// Enumerates the deterministic origin of an artwork resolution result in Miee.
enum ArtworkSource {
  /// Extracted from local file tags or Android MediaStore. Highest priority.
  local,

  /// Resolved through MusicBrainz metadata matching.
  musicBrainz,

  /// Retrieved from the Cover Art Archive using a verified Release MBID.
  coverArtArchive,

  /// Resolved from Deezer catalog search.
  deezer,

  /// Optional artist/album provider (disabled by default, requires API key).
  fanart,

  /// Conditional provider (disabled by default, strict licensing requirements).
  itunes,

  /// Last-resort fallback: YouTube thumbnail from stream metadata.
  youtube,

  /// Deterministic neutral Miee fallback when no reliable artwork exists.
  neutralFallback,
}

extension ArtworkSourceExtension on ArtworkSource {
  String get displayName {
    switch (this) {
      case ArtworkSource.local:
        return 'Local Storage';
      case ArtworkSource.musicBrainz:
        return 'MusicBrainz';
      case ArtworkSource.coverArtArchive:
        return 'Cover Art Archive';
      case ArtworkSource.deezer:
        return 'Deezer';
      case ArtworkSource.fanart:
        return 'Fanart.tv';
      case ArtworkSource.itunes:
        return 'Apple iTunes';
      case ArtworkSource.youtube:
        return 'YouTube Music';
      case ArtworkSource.neutralFallback:
        return 'Miee Neutral Fallback';
    }
  }
}

