/// Types of music entities supported in Spotify-inspired live autocomplete.
enum SuggestionType {
  artist,
  song,
  album,
  playlist,
  searchQuery,
}

/// Strongly-typed domain model representing a music-first live suggestion item.
class MusicSuggestion {
  final String id;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final SuggestionType type;
  final dynamic entity;

  const MusicSuggestion({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.type,
    this.entity,
  });

  /// Human-readable entity type badge label matching Spotify (e.g. "Artist", "Song · Lana Del Rey").
  String get typeLabel {
    switch (type) {
      case SuggestionType.artist:
        return 'Artist';
      case SuggestionType.song:
        return (subtitle != null && subtitle!.isNotEmpty) ? 'Song · $subtitle' : 'Song';
      case SuggestionType.album:
        return (subtitle != null && subtitle!.isNotEmpty) ? 'Album · $subtitle' : 'Album';
      case SuggestionType.playlist:
        return (subtitle != null && subtitle!.isNotEmpty) ? 'Playlist · $subtitle' : 'Playlist';
      case SuggestionType.searchQuery:
        return 'Search';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicSuggestion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'MusicSuggestion($type: "$title", subtitle: "$subtitle")';
}

