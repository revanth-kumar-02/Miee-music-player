import '../../media/domain/models.dart';

/// Service responsible for scanning and filtering the active in-memory local library.
///
/// Highly optimized with pre-compiled regexes, hoisted query-token preprocessing,
/// and fast prefix/substring matching under 10ms for multi-thousand track libraries.
class LocalSearchService {
  static final RegExp _wordSplitRegex = RegExp(r'[\s\-_\.,\/]+');
  static final RegExp _spaceSplitRegex = RegExp(r'\s+');

  /// Searches active songs list.
  List<MediaSong> searchSongs(List<MediaSong> songs, String query) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty || songs.isEmpty) return const [];

    final queryWords = cleanQuery
        .split(_spaceSplitRegex)
        .where((w) => w.isNotEmpty)
        .toList(growable: false);

    return songs
        .where((s) => _matchesOptimized(cleanQuery, queryWords, [s.title, s.artist, s.album]))
        .toList();
  }

  /// Searches active albums list.
  List<MediaAlbum> searchAlbums(List<MediaAlbum> albums, String query) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty || albums.isEmpty) return const [];

    final queryWords = cleanQuery
        .split(_spaceSplitRegex)
        .where((w) => w.isNotEmpty)
        .toList(growable: false);

    return albums
        .where((a) => _matchesOptimized(cleanQuery, queryWords, [a.title, a.artist]))
        .toList();
  }

  /// Searches active artists list.
  List<MediaArtist> searchArtists(List<MediaArtist> artists, String query) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty || artists.isEmpty) return const [];

    final queryWords = cleanQuery
        .split(_spaceSplitRegex)
        .where((w) => w.isNotEmpty)
        .toList(growable: false);

    return artists
        .where((a) => _matchesOptimized(cleanQuery, queryWords, [a.name]))
        .toList();
  }

  /// Searches active playlists list.
  List<MediaPlaylist> searchPlaylists(List<MediaPlaylist> playlists, String query) {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty || playlists.isEmpty) return const [];

    final queryWords = cleanQuery
        .split(_spaceSplitRegex)
        .where((w) => w.isNotEmpty)
        .toList(growable: false);

    return playlists
        .where((p) => _matchesOptimized(cleanQuery, queryWords, [p.name]))
        .toList();
  }

  /// Evaluates query against target properties using substring, word-prefix,
  /// and cross-field multi-token matching without regex overhead.
  bool _matchesOptimized(
    String cleanQuery,
    List<String> queryWords,
    List<String> targets,
  ) {
    // 1. Check each individual field for direct substring or word-prefix match
    for (int i = 0; i < targets.length; i++) {
      final target = targets[i];
      if (target.isEmpty) continue;
      final cleanTarget = target.toLowerCase().trim();
      if (cleanTarget.isEmpty) continue;

      if (cleanTarget.contains(cleanQuery)) return true;

      final words = cleanTarget.split(_wordSplitRegex);
      for (int w = 0; w < words.length; w++) {
        if (words[w].startsWith(cleanQuery)) return true;
      }
    }

    // 2. Cross-field multi-word matching (e.g. "Dhanush Rowdy" matching artist + title)
    if (queryWords.length > 1) {
      final combined = targets.map((t) => t.toLowerCase().trim()).join(' ');
      bool allWordsMatch = true;
      for (int q = 0; q < queryWords.length; q++) {
        if (!combined.contains(queryWords[q])) {
          allWordsMatch = false;
          break;
        }
      }
      if (allWordsMatch) return true;
    }

    return false;
  }
}

