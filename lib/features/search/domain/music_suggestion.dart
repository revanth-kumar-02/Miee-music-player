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
  final bool isOnline;
  final String? source;

  const MusicSuggestion({
    required this.id,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.type,
    this.entity,
    this.isOnline = false,
    this.source,
  });

  /// Identifies the origin source label ('YouTube' or 'Local').
  String get sourceLabel => source ?? (isOnline ? 'YouTube' : 'Local');

  /// Human-readable entity type badge label matching Spotify (e.g. "Song · Lana Del Rey · YouTube").
  String get typeLabel {
    final prefix = switch (type) {
      SuggestionType.artist => (source != null && source!.isNotEmpty && !isOnline)
          ? 'Artist · $source'
          : 'Artist',
      SuggestionType.song => (subtitle != null && subtitle!.isNotEmpty)
          ? 'Song · $subtitle'
          : 'Song',
      SuggestionType.album => (subtitle != null && subtitle!.isNotEmpty)
          ? 'Album · $subtitle'
          : 'Album',
      SuggestionType.playlist => (subtitle != null && subtitle!.isNotEmpty)
          ? 'Playlist · $subtitle'
          : 'Playlist',
      SuggestionType.searchQuery => 'Search',
    };
    if (type != SuggestionType.searchQuery && source != null && source!.isNotEmpty && type != SuggestionType.artist) {
      return '$prefix · $source';
    }
    return prefix;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MusicSuggestion &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          sourceLabel == other.sourceLabel;

  @override
  int get hashCode => Object.hash(id, type, sourceLabel);

  @override
  String toString() => 'MusicSuggestion($type: "$title", subtitle: "$subtitle", source: "$sourceLabel")';
}
