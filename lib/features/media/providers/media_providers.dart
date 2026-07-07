import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/media_repository_impl.dart';
import '../domain/media_repository.dart';
import '../domain/models.dart';

/// State wrapper for the Media Discovery library state.
class MediaLibraryState {
  final bool isLoading;
  final bool hasPermission;
  final String? errorMessage;
  final List<MediaSong> songs;
  final List<MediaAlbum> albums;
  final List<MediaArtist> artists;
  final List<MediaGenre> genres;
  final List<MediaPlaylist> playlists;
  final List<MediaFolder> folders;

  const MediaLibraryState({
    required this.isLoading,
    required this.hasPermission,
    this.errorMessage,
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.genres = const [],
    this.playlists = const [],
    this.folders = const [],
  });

  factory MediaLibraryState.initial() => const MediaLibraryState(
        isLoading: false,
        hasPermission: false,
      );

  MediaLibraryState copyWith({
    bool? isLoading,
    bool? hasPermission,
    String? errorMessage,
    List<MediaSong>? songs,
    List<MediaAlbum>? albums,
    List<MediaArtist>? artists,
    List<MediaGenre>? genres,
    List<MediaPlaylist>? playlists,
    List<MediaFolder>? folders,
  }) {
    return MediaLibraryState(
      isLoading: isLoading ?? this.isLoading,
      hasPermission: hasPermission ?? this.hasPermission,
      errorMessage: errorMessage,
      songs: songs ?? this.songs,
      albums: albums ?? this.albums,
      artists: artists ?? this.artists,
      genres: genres ?? this.genres,
      playlists: playlists ?? this.playlists,
      folders: folders ?? this.folders,
    );
  }
}

/// Service class responsible for requesting permissions, orchestrating scans,
/// and updating Riverpod states.
class MediaLibraryService extends StateNotifier<MediaLibraryState> {
  final MediaRepository _repository;

  MediaLibraryService(this._repository) : super(MediaLibraryState.initial()) {
    // Proactively check and request permissions and trigger the scan on startup
    scanDevice();
  }

  /// Request permissions and scan the local device for music folders and files.
  Future<void> scanDevice({bool forceRefresh = false}) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final hasPerm = await _repository.checkAndRequestPermissions();
      if (!hasPerm) {
        state = state.copyWith(
          isLoading: false,
          hasPermission: false,
          errorMessage: 'Storage permission was denied.',
        );
        return;
      }

      final songs = await _repository.getSongs(forceRefresh: forceRefresh);
      final albums = await _repository.getAlbums(forceRefresh: forceRefresh);
      final artists = await _repository.getArtists(forceRefresh: forceRefresh);
      final genres = await _repository.getGenres(forceRefresh: forceRefresh);
      final playlists = await _repository.getPlaylists(forceRefresh: forceRefresh);
      final folders = await _repository.getFolders(forceRefresh: forceRefresh);

      state = state.copyWith(
        isLoading: false,
        hasPermission: true,
        songs: songs,
        albums: albums,
        artists: artists,
        genres: genres,
        playlists: playlists,
        folders: folders,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An error occurred during scan: $e',
      );
    }
  }
}

// 1. Dependency Injection Repository Provider
final mediaRepositoryProvider = Provider<MediaRepository>((ref) {
  return MediaRepositoryImpl();
});

// 2. State Orchestrator Provider
final mediaLibraryServiceProvider =
    StateNotifierProvider<MediaLibraryService, MediaLibraryState>((ref) {
  final repo = ref.watch(mediaRepositoryProvider);
  return MediaLibraryService(repo);
});

// 3. Songs Provider
final songsProvider = Provider<List<MediaSong>>((ref) {
  return ref.watch(mediaLibraryServiceProvider).songs;
});

// 4. Albums Provider
final albumsProvider = Provider<List<MediaAlbum>>((ref) {
  return ref.watch(mediaLibraryServiceProvider).albums;
});

// 5. Artists Provider
final artistsProvider = Provider<List<MediaArtist>>((ref) {
  return ref.watch(mediaLibraryServiceProvider).artists;
});

// 6. Genres Provider
final genresProvider = Provider<List<MediaGenre>>((ref) {
  return ref.watch(mediaLibraryServiceProvider).genres;
});

// 7. Playlists Provider
final playlistsProvider = Provider<List<MediaPlaylist>>((ref) {
  return ref.watch(mediaLibraryServiceProvider).playlists;
});

// 8. Folders Provider
final foldersProvider = Provider<List<MediaFolder>>((ref) {
  return ref.watch(mediaLibraryServiceProvider).folders;
});

// 9. Permission State Provider
final permissionStateProvider = Provider<bool>((ref) {
  return ref.watch(mediaLibraryServiceProvider).hasPermission;
});

// 10. Loading State Provider
final loadingStateProvider = Provider<bool>((ref) {
  return ref.watch(mediaLibraryServiceProvider).isLoading;
});

// 11. Error State Provider
final errorStateProvider = Provider<String?>((ref) {
  return ref.watch(mediaLibraryServiceProvider).errorMessage;
});
