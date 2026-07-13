import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/hive_boxes.dart';
import '../domain/media_repository.dart';
import '../domain/models.dart';

/// Concrete implementation of [MediaRepository] utilizing `on_audio_query`.
class MediaRepositoryImpl implements MediaRepository {
  final OnAudioQuery _audioQuery = OnAudioQuery();

  // In-memory cache lists to satisfy "Load once. Refresh only when requested."
  List<MediaSong>? _cachedSongs;
  List<MediaAlbum>? _cachedAlbums;
  List<MediaArtist>? _cachedArtists;
  List<MediaGenre>? _cachedGenres;
  List<MediaPlaylist>? _cachedPlaylists;
  List<MediaFolder>? _cachedFolders;

  // Cache mapping unique album IDs to local artwork file paths
  final Map<int, String> _albumArtCache = {};

  /// Helper to check if a String represents an unknown/empty artist.
  bool _isUnknownArtist(String? name) {
    if (name == null) return true;
    final clean = name.trim().toLowerCase();
    return clean.isEmpty ||
        clean == 'unknown' ||
        clean == '<unknown>' ||
        clean == 'unknown artist';
  }

  @override
  Future<bool> checkAndRequestPermissions() async {
    if (!Platform.isAndroid) return true;
    
    if (await Permission.audio.request().isGranted) {
      return true;
    }
    if (await Permission.storage.request().isGranted) {
      return true;
    }
    
    final hasPermission = await _audioQuery.permissionsStatus();
    if (!hasPermission) {
      return await _audioQuery.permissionsRequest();
    }
    return true;
  }

  /// Helper to fetch and write album artwork to a temporary local file, returning the path.
  Future<String> _getAlbumArtworkPath(int? albumId) async {
    if (albumId == null) return '';
    if (_albumArtCache.containsKey(albumId)) {
      return _albumArtCache[albumId]!;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/album_$albumId.png');

      if (await file.exists()) {
        _albumArtCache[albumId] = file.path;
        return file.path;
      }

      final bytes = await _audioQuery.queryArtwork(
        albumId,
        ArtworkType.ALBUM,
        format: ArtworkFormat.PNG,
        size: 800,
      );

      if (bytes != null && bytes.isNotEmpty) {
        await file.writeAsBytes(bytes);
        _albumArtCache[albumId] = file.path;
        return file.path;
      }
    } catch (_) {
      // Gracefully catch background IO errors
    }

    return '';
  }

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '0:00';
    final dur = Duration(milliseconds: ms);
    final minutes = dur.inMinutes;
    final seconds = dur.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _fixCachePath(String cachedPath, String currentTempDirPath) {
    if (cachedPath.isEmpty) return '';
    if (cachedPath.startsWith('http')) return cachedPath;
    final fileName = cachedPath.split(Platform.isWindows ? '\\' : '/').last;
    return '$currentTempDirPath/$fileName';
  }

  Future<void> _queryAndSaveArtwork(int id, ArtworkType type, String targetPath) async {
    try {
      final bytes = await _audioQuery.queryArtwork(
        id,
        type,
        format: ArtworkFormat.PNG,
        size: 800,
      );
      if (bytes != null && bytes.isNotEmpty) {
        final file = File(targetPath);
        await file.writeAsBytes(bytes);
      }
    } catch (_) {}
  }

  @override
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_cachedSongs != null) {
        return _cachedSongs!;
      }

      final box = Hive.box(HiveBoxes.preferences);
      final cachedData = box.get('scanned_songs');
      if (cachedData is List) {
        final tempDir = await getTemporaryDirectory();
        final List<MediaSong> cachedSongs = [];
        for (final item in cachedData) {
          if (item is Map) {
            final castedMap = Map<String, dynamic>.from(item);
            final song = MediaSong.fromJson(castedMap);
            
            // Check and exclude unknown/empty/whitespace-only artists
            if (_isUnknownArtist(song.artist)) {
              continue;
            }

            final fixedArtworkPath = _fixCachePath(song.artworkPath, tempDir.path);
            
            if (fixedArtworkPath.isNotEmpty) {
              final file = File(fixedArtworkPath);
              if (!await file.exists()) {
                final baseName = fixedArtworkPath.split(Platform.isWindows ? '\\' : '/').last;
                final idStr = baseName.replaceAll('album_', '').replaceAll('.png', '');
                final albumId = int.tryParse(idStr);
                if (albumId != null) {
                  await _queryAndSaveArtwork(albumId, ArtworkType.ALBUM, fixedArtworkPath);
                } else {
                  final songId = int.tryParse(song.id);
                  if (songId != null) {
                    await _queryAndSaveArtwork(songId, ArtworkType.AUDIO, fixedArtworkPath);
                  }
                }
              }
            }

            cachedSongs.add(MediaSong(
              id: song.id,
              title: song.title,
              artist: song.artist,
              album: song.album,
              duration: song.duration,
              durationMs: song.durationMs,
              filePath: song.filePath,
              artworkPath: fixedArtworkPath,
            ));
          }
        }
        if (cachedSongs.isNotEmpty) {
          _cachedSongs = cachedSongs;
          return cachedSongs;
        }
      }
    }

    final hasPerm = await checkAndRequestPermissions();
    if (!hasPerm) return [];

    final rawSongs = await _audioQuery.querySongs(
      sortType: SongSortType.TITLE,
      orderType: OrderType.ASC_OR_SMALLER,
      uriType: UriType.EXTERNAL,
      ignoreCase: true,
    );

    final List<MediaSong> songs = [];
    final Set<String> seenPaths = {};

    for (final song in rawSongs) {
      // Exclude notification/alarm sounds, and enforce the 30-second limit
      if (song.isNotification == true || song.isAlarm == true) continue;
      if (song.duration != null && song.duration! < 30000) continue;

      final path = song.data;
      if (path == null || path.isEmpty) continue;
      if (!seenPaths.add(path)) continue; // skip duplicates

      // Validate and exclude unknown artists globally
      if (_isUnknownArtist(song.artist)) continue;

      final title = song.title.isEmpty ? 'Unknown Title' : song.title;
      final artistName = song.artist!;
      final albumName = (song.album == null || song.album == '<unknown>' || song.album!.trim().isEmpty) ? 'Unknown Album' : song.album!;

      final artPath = await _getAlbumArtworkPath(song.albumId);
      songs.add(
        MediaSong(
          id: song.id.toString(),
          title: title,
          artist: artistName,
          album: albumName,
          duration: _formatDuration(song.duration),
          durationMs: song.duration ?? 0,
          filePath: path,
          artworkPath: artPath,
        ),
      );
    }

    _cachedSongs = songs;

    final box = Hive.box(HiveBoxes.preferences);
    final songMaps = songs.map((s) => s.toJson()).toList();
    await box.put('scanned_songs', songMaps);

    return songs;
  }

  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedAlbums != null) {
      return _cachedAlbums!;
    }

    final hasPerm = await checkAndRequestPermissions();
    if (!hasPerm) return [];

    final rawAlbums = await _audioQuery.queryAlbums(
      sortType: AlbumSortType.ALBUM,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );

    final songsList = _cachedSongs ?? await getSongs();
    final List<MediaAlbum> albums = [];

    for (final album in rawAlbums) {
      // Exclude albums whose artist is unknown
      if (_isUnknownArtist(album.artist)) continue;

      final albumTitle = (album.album.isEmpty || album.album == '<unknown>') ? 'Unknown Album' : album.album;
      final artistName = album.artist!;

      // Calculate track count dynamically based only on active, non-filtered songs
      final albumSongsCount = songsList.where((s) => s.album.trim().toLowerCase() == albumTitle.trim().toLowerCase()).length;
      if (albumSongsCount == 0) continue; // If no playable songs in album, exclude it!

      final artPath = await _getAlbumArtworkPath(album.id);
      albums.add(
        MediaAlbum(
          id: album.id.toString(),
          title: albumTitle,
          artist: artistName,
          trackCount: albumSongsCount,
          artworkPath: artPath,
        ),
      );
    }

    _cachedAlbums = albums;
    return albums;
  }

  Future<String?> _resolveArtistArtwork(String name, List<MediaSong> songsList, Box prefBox) async {
    final cacheKey = 'artist_art_$name';
    final cached = prefBox.get(cacheKey) as String?;
    if (cached != null && cached.isNotEmpty) {
      if (cached.startsWith('http') || await File(cached).exists()) {
        return cached;
      }
    }

    // 1. Find local song artwork
    final artistSongs = songsList.where((s) => s.artist.trim().toLowerCase() == name.trim().toLowerCase() && s.artworkPath.isNotEmpty);
    if (artistSongs.isNotEmpty) {
      final localArt = artistSongs.first.artworkPath;
      await prefBox.put(cacheKey, localArt);
      return localArt;
    }

    // 2. Fetch from internet (Deezer API)
    try {
      final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 3)));
      final response = await dio.get('https://api.deezer.com/search/artist', queryParameters: {'q': name});
      if (response.statusCode == 200 && response.data is Map) {
        final data = response.data;
        final list = data['data'];
        if (list is List && list.isNotEmpty) {
          final first = list.first;
          final pictureUrl = first['picture_medium'] as String?;
          if (pictureUrl != null && pictureUrl.isNotEmpty) {
            final tempDir = await getTemporaryDirectory();
            final sanitized = name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
            final file = File('${tempDir.path}/artist_$sanitized.png');
            
            await dio.download(pictureUrl, file.path);
            await prefBox.put(cacheKey, file.path);
            return file.path;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching internet artwork for artist $name: $e');
    }

    return null;
  }

  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedArtists != null) {
      return _cachedArtists!;
    }

    final hasPerm = await checkAndRequestPermissions();
    if (!hasPerm) return [];

    final rawArtists = await _audioQuery.queryArtists(
      sortType: ArtistSortType.ARTIST,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );

    final songsList = _cachedSongs ?? await getSongs();
    final prefBox = Hive.box(HiveBoxes.preferences);

    // Validate and exclude unknown artists
    final filteredRawArtists = rawArtists.where((artist) {
      return !_isUnknownArtist(artist.artist);
    }).toList();

    final List<MediaArtist?> artistsRaw = await Future.wait(
      filteredRawArtists.map((artist) async {
        final name = artist.artist;
        final artistSongs = songsList.where((s) => s.artist.trim().toLowerCase() == name.trim().toLowerCase()).toList();
        final artistSongsCount = artistSongs.length;
        if (artistSongsCount == 0) return null; // If no active songs, exclude it!

        final artistAlbumsCount = artistSongs.map((s) => s.album.trim().toLowerCase()).toSet().length;

        final artPath = await _resolveArtistArtwork(name, songsList, prefBox);
        return MediaArtist(
          id: artist.id.toString(),
          name: name,
          trackCount: artistSongsCount,
          albumCount: artistAlbumsCount,
          artworkPath: artPath,
        );
      }),
    );

    final artists = artistsRaw.whereType<MediaArtist>().toList();
    _cachedArtists = artists;
    return artists;
  }

  @override
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedGenres != null) {
      return _cachedGenres!;
    }

    final hasPerm = await checkAndRequestPermissions();
    if (!hasPerm) return [];

    final rawGenres = await _audioQuery.queryGenres(
      sortType: GenreSortType.GENRE,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );

    final songsList = _cachedSongs ?? await getSongs();

    final List<MediaGenre> genres = [];
    for (final genre in rawGenres) {
      final name = genre.genre;
      if (name.isEmpty || name == '<unknown>' || name == 'Unknown' || name.trim().isEmpty) {
        continue;
      }
      
      // Calculate active track count from our filtered songs.
      final genreRawSongs = await _audioQuery.queryAudiosFrom(
        AudiosFromType.GENRE_ID,
        genre.id,
      );
      
      final activeCount = genreRawSongs.where((rawSong) {
        return songsList.any((s) => s.id == rawSong.id.toString());
      }).length;

      if (activeCount > 0) {
        genres.add(
          MediaGenre(
            id: genre.id.toString(),
            name: name,
            trackCount: activeCount,
          ),
        );
      }
    }

    _cachedGenres = genres;
    return genres;
  }

  @override
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedPlaylists != null) {
      return _cachedPlaylists!;
    }

    final hasPerm = await checkAndRequestPermissions();
    if (!hasPerm) return [];

    final rawPlaylists = await _audioQuery.queryPlaylists(
      sortType: PlaylistSortType.PLAYLIST,
      orderType: OrderType.ASC_OR_SMALLER,
      ignoreCase: true,
    );

    final playlists = rawPlaylists
        .map(
          (pl) => MediaPlaylist(
            id: pl.id.toString(),
            name: pl.playlist,
            trackCount: pl.numOfSongs,
          ),
        )
        .toList();

    _cachedPlaylists = playlists;
    return playlists;
  }

  @override
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedFolders != null) {
      return _cachedFolders!;
    }

    final songs = await getSongs(forceRefresh: forceRefresh);
    final Map<String, int> folderCounts = {};
    final Map<String, String> folderPaths = {};

    for (final song in songs) {
      if (song.filePath.isEmpty) continue;
      final file = File(song.filePath);
      final parentDir = file.parent;
      final parentPath = parentDir.path;

      folderCounts[parentPath] = (folderCounts[parentPath] ?? 0) + 1;
      folderPaths[parentPath] = parentDir.uri.pathSegments.isNotEmpty
          ? parentDir.uri.pathSegments[parentDir.uri.pathSegments.length - 2]
          : parentDir.path;
    }

    final List<MediaFolder> folders = [];
    folderCounts.forEach((path, count) {
      var name = path.split(Platform.isWindows ? '\\' : '/').last;
      if (name.isEmpty) {
        name = 'Device Music';
      }
      folders.add(
        MediaFolder(
          name: name,
          path: path,
          trackCount: count,
        ),
      );
    });

    _cachedFolders = folders;
    return folders;
  }
}
