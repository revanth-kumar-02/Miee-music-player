import '../domain/library_filter_policy.dart';
import '../domain/media_repository.dart';
import '../domain/models.dart';

/// No-op implementation of [MediaRepository] for Web browsers where
/// local file-system scanning is not supported.
class WebMediaRepository implements MediaRepository {
  @override
  Future<bool> checkAndRequestPermissions() async => true;

  @override
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async => const [];

  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async => const [];

  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async => const [];

  @override
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false}) async => const [];

  @override
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false}) async => const [];

  @override
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false}) async => const [];

  @override
  Future<LibraryFolderPreferences> getFolderPreferences() async =>
      const LibraryFolderPreferences();

  @override
  Future<void> saveFolderPreferences(LibraryFolderPreferences preferences) async {}
}
