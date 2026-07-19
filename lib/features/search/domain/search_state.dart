import '../../media/domain/models.dart';
import '../../youtube/domain/youtube_model.dart';

/// Immutable typed container representing the complete search page state.
class SearchState {
  /// The active text search query.
  final String query;

  /// Auto-complete suggestions retrieved from YouTube Explode.
  final List<String> suggestions;

  /// History of recent queries stored persistently in Hive.
  final List<String> recentSearches;

  /// Matching local media songs.
  final List<MediaSong> localSongs;

  /// Matching local media albums.
  final List<MediaAlbum> localAlbums;

  /// Matching local media artists.
  final List<MediaArtist> localArtists;

  /// Matching local media playlists.
  final List<MediaPlaylist> localPlaylists;

  /// Matching online music videos from YouTube.
  final List<YouTubeVideo> youtubeResults;

  /// Loading status of the local library scan.
  final bool isLocalLoading;

  /// Loading status of the online YouTube API query.
  final bool isYouTubeLoading;

  /// Error message, if any network/API issues occur during query resolution.
  final String? errorMessage;

  const SearchState({
    this.query = '',
    this.suggestions = const [],
    this.recentSearches = const [],
    this.localSongs = const [],
    this.localAlbums = const [],
    this.localArtists = const [],
    this.localPlaylists = const [],
    this.youtubeResults = const [],
    this.isLocalLoading = false,
    this.isYouTubeLoading = false,
    this.errorMessage,
  });

  SearchState copyWith({
    String? query,
    List<String>? suggestions,
    List<String>? recentSearches,
    List<MediaSong>? localSongs,
    List<MediaAlbum>? localAlbums,
    List<MediaArtist>? localArtists,
    List<MediaPlaylist>? localPlaylists,
    List<YouTubeVideo>? youtubeResults,
    bool? isLocalLoading,
    bool? isYouTubeLoading,
    String? errorMessage,
  }) {
    return SearchState(
      query: query ?? this.query,
      suggestions: suggestions ?? this.suggestions,
      recentSearches: recentSearches ?? this.recentSearches,
      localSongs: localSongs ?? this.localSongs,
      localAlbums: localAlbums ?? this.localAlbums,
      localArtists: localArtists ?? this.localArtists,
      localPlaylists: localPlaylists ?? this.localPlaylists,
      youtubeResults: youtubeResults ?? this.youtubeResults,
      isLocalLoading: isLocalLoading ?? this.isLocalLoading,
      isYouTubeLoading: isYouTubeLoading ?? this.isYouTubeLoading,
      errorMessage: errorMessage,
    );
  }

  /// Combined loading state indicator.
  bool get isLoading => isLocalLoading || isYouTubeLoading;

  /// Convenience helper checking query presence.
  bool get hasQuery => query.trim().isNotEmpty;

  /// True only when all local and YouTube search results lists are empty.
  bool get isEmpty =>
      localSongs.isEmpty &&
      localAlbums.isEmpty &&
      localArtists.isEmpty &&
      localPlaylists.isEmpty &&
      youtubeResults.isEmpty;
}
