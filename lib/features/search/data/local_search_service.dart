import '../../media/domain/models.dart';

/// Service responsible for scanning and filtering the active in-memory local library.
class LocalSearchService {
  /// Searches active songs list.
  List<MediaSong> searchSongs(List<MediaSong> songs, String query) {
    if (query.trim().isEmpty) return const [];
    return songs.where((s) => _fuzzyMatch(query, [s.title, s.artist, s.album])).toList();
  }

  /// Searches active albums list.
  List<MediaAlbum> searchAlbums(List<MediaAlbum> albums, String query) {
    if (query.trim().isEmpty) return const [];
    return albums.where((a) => _fuzzyMatch(query, [a.title, a.artist])).toList();
  }

  /// Searches active artists list.
  List<MediaArtist> searchArtists(List<MediaArtist> artists, String query) {
    if (query.trim().isEmpty) return const [];
    return artists.where((a) => _fuzzyMatch(query, [a.name])).toList();
  }

  /// Searches active playlists list.
  List<MediaPlaylist> searchPlaylists(List<MediaPlaylist> playlists, String query) {
    if (query.trim().isEmpty) return const [];
    return playlists.where((p) => _fuzzyMatch(query, [p.name])).toList();
  }

  /// Helper evaluating Jaro-Winkler-like subsequence matches against target properties.
  bool _fuzzyMatch(String query, List<String> targets) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) return false;

    for (final target in targets) {
      final cleanTarget = target.toLowerCase();

      // Substring match
      if (cleanTarget.contains(cleanQuery)) return true;

      // Subsequence fuzzy match (matches characters in order, allowing typos/gap fillings)
      int queryIndex = 0;
      for (int i = 0; i < cleanTarget.length; i++) {
        if (cleanTarget[i] == cleanQuery[queryIndex]) {
          queryIndex++;
          if (queryIndex == cleanQuery.length) return true;
        }
      }
    }
    return false;
  }
}
