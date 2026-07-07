import '../../media/domain/models.dart';

/// Immutable typed container for grouped local search results.
///
/// Each category holds a list of matching domain models.
/// Result lists are pre-capped at a sensible display limit inside
/// [SearchRepository] so this model never holds unbounded data.
class SearchResults {
  /// Matching songs (capped at 50).
  final List<MediaSong> songs;

  /// Matching albums (capped at 20).
  final List<MediaAlbum> albums;

  /// Matching artists (capped at 20).
  final List<MediaArtist> artists;

  /// Matching genres (capped at 10).
  final List<MediaGenre> genres;

  /// Matching playlists (capped at 20).
  final List<MediaPlaylist> playlists;

  const SearchResults({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.genres = const [],
    this.playlists = const [],
  });

  /// Returns an empty [SearchResults] instance.
  factory SearchResults.empty() => const SearchResults();

  /// True when every category list is empty.
  bool get isEmpty =>
      songs.isEmpty &&
      albums.isEmpty &&
      artists.isEmpty &&
      genres.isEmpty &&
      playlists.isEmpty;

  bool get isNotEmpty => !isEmpty;

  /// Total count across all categories.
  int get totalCount =>
      songs.length + albums.length + artists.length + genres.length + playlists.length;
}
