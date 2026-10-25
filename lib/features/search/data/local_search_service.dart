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

  /// Evaluates query against target properties using substring, word-prefix,
  /// and multi-token matching, completely avoiding loose subsequence false-positives.
  bool _fuzzyMatch(String query, List<String> targets) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) return false;

    for (final target in targets) {
      final cleanTarget = target.toLowerCase().trim();
      if (cleanTarget.isEmpty) continue;

      // 1. Direct Substring match
      if (cleanTarget.contains(cleanQuery)) return true;

      // 2. Word-prefix match: does any individual word start with query?
      final words = cleanTarget.split(RegExp(r'[\s\-_\.,\/]+'));
      if (words.any((w) => w.startsWith(cleanQuery))) return true;

      // 3. Multi-word query: all query words must match somewhere in target
      final queryWords = cleanQuery.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      if (queryWords.length > 1 && queryWords.every((qw) => cleanTarget.contains(qw))) {
        return true;
      }
    }
    return false;
  }
}
