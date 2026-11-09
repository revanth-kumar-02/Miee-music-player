import '../../media/domain/models.dart';
import '../../onboarding/data/artist_discovery_repository.dart';
import '../../onboarding/domain/artist_model.dart';
import '../../youtube/domain/youtube_model.dart';
import 'online_playlist.dart';
import 'music_suggestion.dart';

export 'music_suggestion.dart';

/// Immutable typed container representing the unified search page state.
class SearchState {
  /// The active text search query.
  final String query;

  /// The active category filter tab: 'All', 'Songs', 'Artists', 'Albums', or 'Playlists'.
  final String activeFilter;

  /// Auto-complete suggestions retrieved from YouTube Explode / history.
  final List<String> suggestions;

  /// Music-first live suggestions (artists, songs, albums, playlists) matching Spotify experience.
  final List<MusicSuggestion> liveSuggestions;

  /// Loading indicator for live music suggestions.
  final bool isSuggestionsLoading;

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

  /// Matching verified online artist entities from Deezer / Curated.
  final List<ArtistModel> onlineArtists;

  /// Matching verified online album entities from Deezer.
  final List<ArtistAlbum> onlineAlbums;

  /// Matching verified online playlists from YouTube Music.
  final List<OnlinePlaylist> onlinePlaylists;

  /// Loading status of the local library scan.
  final bool isLocalLoading;

  /// Loading status of the online YouTube API query.
  final bool isYouTubeLoading;

  /// Loading status of the online artist/album resolution.
  final bool isArtistsLoading;

  /// Loading status of the online playlists query.
  final bool isPlaylistsLoading;

  /// Error message, if any network/API issues occur during query resolution.
  final String? errorMessage;

  const SearchState({
    this.query = '',
    this.activeFilter = 'All',
    this.suggestions = const [],
    this.liveSuggestions = const [],
    this.isSuggestionsLoading = false,
    this.recentSearches = const [],
    this.localSongs = const [],
    this.localAlbums = const [],
    this.localArtists = const [],
    this.localPlaylists = const [],
    this.youtubeResults = const [],
    this.onlineArtists = const [],
    this.onlineAlbums = const [],
    this.onlinePlaylists = const [],
    this.isLocalLoading = false,
    this.isYouTubeLoading = false,
    this.isArtistsLoading = false,
    this.isPlaylistsLoading = false,
    this.errorMessage,
  });

  SearchState copyWith({
    String? query,
    String? activeFilter,
    List<String>? suggestions,
    List<MusicSuggestion>? liveSuggestions,
    bool? isSuggestionsLoading,
    List<String>? recentSearches,
    List<MediaSong>? localSongs,
    List<MediaAlbum>? localAlbums,
    List<MediaArtist>? localArtists,
    List<MediaPlaylist>? localPlaylists,
    List<YouTubeVideo>? youtubeResults,
    List<ArtistModel>? onlineArtists,
    List<ArtistAlbum>? onlineAlbums,
    List<OnlinePlaylist>? onlinePlaylists,
    bool? isLocalLoading,
    bool? isYouTubeLoading,
    bool? isArtistsLoading,
    bool? isPlaylistsLoading,
    String? errorMessage,
  }) {
    return SearchState(
      query: query ?? this.query,
      activeFilter: activeFilter ?? this.activeFilter,
      suggestions: suggestions ?? this.suggestions,
      liveSuggestions: liveSuggestions ?? this.liveSuggestions,
      isSuggestionsLoading: isSuggestionsLoading ?? this.isSuggestionsLoading,
      recentSearches: recentSearches ?? this.recentSearches,
      localSongs: localSongs ?? this.localSongs,
      localAlbums: localAlbums ?? this.localAlbums,
      localArtists: localArtists ?? this.localArtists,
      localPlaylists: localPlaylists ?? this.localPlaylists,
      youtubeResults: youtubeResults ?? this.youtubeResults,
      onlineArtists: onlineArtists ?? this.onlineArtists,
      onlineAlbums: onlineAlbums ?? this.onlineAlbums,
      onlinePlaylists: onlinePlaylists ?? this.onlinePlaylists,
      isLocalLoading: isLocalLoading ?? this.isLocalLoading,
      isYouTubeLoading: isYouTubeLoading ?? this.isYouTubeLoading,
      isArtistsLoading: isArtistsLoading ?? this.isArtistsLoading,
      isPlaylistsLoading: isPlaylistsLoading ?? this.isPlaylistsLoading,
      errorMessage: errorMessage,
    );
  }

  /// Combined loading state indicator.
  bool get isLoading =>
      isLocalLoading || isYouTubeLoading || isArtistsLoading || isPlaylistsLoading;

  /// Convenience helper checking query presence.
  bool get hasQuery => query.trim().isNotEmpty;

  /// Total count of matching songs (local + online).
  int get totalSongsCount => localSongs.length + youtubeResults.length;

  /// Total count of matching artists (local + online).
  int get totalArtistsCount => localArtists.length + onlineArtists.length;

  /// Total count of matching albums (local + online).
  int get totalAlbumsCount => localAlbums.length + onlineAlbums.length;

  /// Total count of matching playlists (local + online).
  int get totalPlaylistsCount => localPlaylists.length + onlinePlaylists.length;

  /// True only when all local and online search results lists are empty.
  bool get isEmpty =>
      localSongs.isEmpty &&
      localAlbums.isEmpty &&
      localArtists.isEmpty &&
      localPlaylists.isEmpty &&
      youtubeResults.isEmpty &&
      onlineArtists.isEmpty &&
      onlineAlbums.isEmpty &&
      onlinePlaylists.isEmpty;
}
