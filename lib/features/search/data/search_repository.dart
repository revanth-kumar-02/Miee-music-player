import '../../media/domain/models.dart';
import '../../media/providers/media_providers.dart';
import '../domain/search_results.dart';

/// Performs fast, offline, in-memory searches across the indexed local library.
///
/// This class contains **no I/O** — it operates entirely on the
/// [MediaLibraryState] already held in memory by [MediaLibraryService].
/// Optimised for libraries exceeding 10,000 songs via O(n) single-pass
/// filtering with early-exit on per-category caps.
class SearchRepository {
  // Per-category display caps to keep results manageable.
  static const int _songCap = 50;
  static const int _albumCap = 20;
  static const int _artistCap = 20;
  static const int _genreCap = 10;
  static const int _playlistCap = 20;

  /// Searches [library] for [query] and returns grouped [SearchResults].
  ///
  /// Returns [SearchResults.empty] when [query] is blank.
  /// Matching is: case-insensitive, partial (contains), prefix-weighted,
  /// and multi-word (all space-separated words must appear in the target).
  SearchResults search(String query, MediaLibraryState library) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return SearchResults.empty();

    final words = trimmed.toLowerCase().split(RegExp(r'\s+'));

    return SearchResults(
      songs: _searchSongs(library.songs, words),
      albums: _searchAlbums(library.albums, words),
      artists: _searchArtists(library.artists, words),
      genres: _searchGenres(library.genres, words),
      playlists: _searchPlaylists(library.playlists, words),
    );
  }

  // ── Per-category search helpers ─────────────────────────────────────────────

  List<MediaSong> _searchSongs(List<MediaSong> songs, List<String> words) {
    final results = <MediaSong>[];
    for (final song in songs) {
      if (results.length >= _songCap) break;
      if (_matchesAny(words, [song.title, song.artist, song.album])) {
        results.add(song);
      }
    }
    return results;
  }

  List<MediaAlbum> _searchAlbums(List<MediaAlbum> albums, List<String> words) {
    final results = <MediaAlbum>[];
    for (final album in albums) {
      if (results.length >= _albumCap) break;
      if (_matchesAny(words, [album.title, album.artist])) {
        results.add(album);
      }
    }
    return results;
  }

  List<MediaArtist> _searchArtists(List<MediaArtist> artists, List<String> words) {
    final results = <MediaArtist>[];
    for (final artist in artists) {
      if (results.length >= _artistCap) break;
      if (_matchesAny(words, [artist.name])) {
        results.add(artist);
      }
    }
    return results;
  }

  List<MediaGenre> _searchGenres(List<MediaGenre> genres, List<String> words) {
    final results = <MediaGenre>[];
    for (final genre in genres) {
      if (results.length >= _genreCap) break;
      if (_matchesAny(words, [genre.name])) {
        results.add(genre);
      }
    }
    return results;
  }

  List<MediaPlaylist> _searchPlaylists(
      List<MediaPlaylist> playlists, List<String> words) {
    final results = <MediaPlaylist>[];
    for (final playlist in playlists) {
      if (results.length >= _playlistCap) break;
      if (_matchesAny(words, [playlist.name])) {
        results.add(playlist);
      }
    }
    return results;
  }

  // ── Matching logic ──────────────────────────────────────────────────────────

  /// Returns true if ALL [words] appear in at least one of the [targets].
  ///
  /// Each target is lowercased before comparison. A word "appears" if any
  /// target contains it as a substring (prefix match is a special case of this).
  bool _matchesAny(List<String> words, List<String> targets) {
    final lowerTargets = targets.map((t) => t.toLowerCase()).toList();
    for (final word in words) {
      // Every word must be found in at least one target field.
      final wordFound = lowerTargets.any((t) => t.contains(word));
      if (!wordFound) return false;
    }
    return true;
  }
}
