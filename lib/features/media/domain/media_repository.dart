import 'models.dart';

/// Repository interface responsible for checking/requesting storage permissions,
/// loading and organizing media assets, and caching scans.
abstract class MediaRepository {
  /// Request permissions dynamically for Android 13+ vs Android 12 and below.
  Future<bool> checkAndRequestPermissions();

  /// Discover all local song files on the device storage.
  Future<List<MediaSong>> getSongs({bool forceRefresh = false});

  /// Discover all albums on the device storage.
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false});

  /// Discover all artists on the device storage.
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false});

  /// Discover all genres on the device storage.
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false});

  /// Discover all local playlists.
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false});

  /// Organize discovered songs into parent folders.
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false});
}
