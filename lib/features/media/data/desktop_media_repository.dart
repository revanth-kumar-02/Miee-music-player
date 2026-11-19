import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/hive_boxes.dart';
import '../domain/library_filter_policy.dart';
import '../domain/media_repository.dart';
import '../domain/models.dart';

/// Concrete implementation of [MediaRepository] for Desktop operating systems
/// (Windows, macOS, Linux) utilizing direct file-system traversal.
class DesktopMediaRepository implements MediaRepository {
  static const String _kFolderPrefsKey = 'library_folder_preferences';
  static const String _kScannedDesktopSongsKey = 'scanned_desktop_songs';

  final AudioLibraryFilter _filter = const AudioLibraryFilter();

  List<MediaSong>? _cachedSongs;
  List<MediaAlbum>? _cachedAlbums;
  List<MediaArtist>? _cachedArtists;
  List<MediaGenre>? _cachedGenres;
  List<MediaPlaylist>? _cachedPlaylists;
  List<MediaFolder>? _cachedFolders;

  static const Set<String> _audioExtensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.wav',
    '.ogg',
    '.opus',
    '.aac',
    '.wma',
  };

  @override
  Future<bool> checkAndRequestPermissions() async {
    // Desktop systems have standard OS-level user directory permissions.
    return true;
  }

  @override
  Future<LibraryFolderPreferences> getFolderPreferences() async {
    try {
      final box = Hive.box(HiveBoxes.preferences);
      final raw = box.get(_kFolderPrefsKey);
      if (raw is Map) {
        return LibraryFolderPreferences.fromJson(raw);
      }
    } catch (_) {}
    return const LibraryFolderPreferences();
  }

  @override
  Future<void> saveFolderPreferences(LibraryFolderPreferences preferences) async {
    final box = Hive.box(HiveBoxes.preferences);
    await box.put(_kFolderPrefsKey, preferences.toJson());
    _invalidateCache();
  }

  void _invalidateCache() {
    _cachedSongs = null;
    _cachedAlbums = null;
    _cachedArtists = null;
    _cachedGenres = null;
    _cachedPlaylists = null;
    _cachedFolders = null;
  }

  /// Discovers standard default music directories on the desktop host.
  Future<List<String>> _getDefaultMusicDirectories() async {
    final List<String> paths = [];
    try {
      // 1. Check path_provider getApplicationDocumentsDirectory
      final docDir = await getApplicationDocumentsDirectory();
      final userDir = docDir.parent;
      final defaultMusic = Directory(p.join(userDir.path, 'Music'));
      if (await defaultMusic.exists()) {
        paths.add(defaultMusic.path);
      }
    } catch (_) {}

    // 2. Check standard environment variables on Windows / Linux / macOS
    if (Platform.isWindows) {
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final winMusic = Directory(p.join(userProfile, 'Music'));
        if (winMusic.existsSync() && !paths.contains(winMusic.path)) {
          paths.add(winMusic.path);
        }
      }
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final unixMusic = Directory(p.join(home, 'Music'));
        if (unixMusic.existsSync() && !paths.contains(unixMusic.path)) {
          paths.add(unixMusic.path);
        }
      }
    }

    return paths;
  }

  @override
  Future<List<MediaSong>> getSongs({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedSongs != null) {
      return _cachedSongs!;
    }

    final prefs = await getFolderPreferences();
    final box = Hive.box(HiveBoxes.preferences);

    // Check disk cache first unless forceRefresh is true
    if (!forceRefresh) {
      final cachedRaw = box.get(_kScannedDesktopSongsKey);
      if (cachedRaw is List && cachedRaw.isNotEmpty) {
        final List<MediaSong> loaded = [];
        for (final item in cachedRaw) {
          if (item is Map) {
            try {
              final song = MediaSong.fromJson(Map<String, dynamic>.from(item));
              if (File(song.filePath).existsSync()) {
                loaded.add(song);
              }
            } catch (_) {}
          }
        }
        if (loaded.isNotEmpty) {
          _cachedSongs = loaded;
          return loaded;
        }
      }
    }

    // Determine target directories to scan
    final Set<String> targetDirs = Set<String>.from(prefs.includedFolders);
    if (targetDirs.isEmpty) {
      final defaults = await _getDefaultMusicDirectories();
      targetDirs.addAll(defaults);
    }

    final List<MediaSong> discovered = [];
    final Set<String> seenPaths = {};

    for (final dirPath in targetDirs) {
      final dir = Directory(dirPath);
      if (!await dir.exists()) continue;

      try {
        final entities = dir.listSync(recursive: true, followLinks: false);
        for (final entity in entities) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (!_audioExtensions.contains(ext)) continue;
          if (!seenPaths.add(entity.path)) continue;

          final song = _parseSongFromFile(entity, prefs);
          if (song != null) {
            discovered.add(song);
          }
        }
      } catch (e) {
        debugPrint('[DesktopMediaRepository] Scan error in $dirPath: $e');
      }
    }

    // Persist scanned songs to Hive
    try {
      final serialized = discovered.map((s) => s.toJson()).toList();
      await box.put(_kScannedDesktopSongsKey, serialized);
    } catch (_) {}

    _cachedSongs = discovered;
    return discovered;
  }

  MediaSong? _parseSongFromFile(File file, LibraryFolderPreferences prefs) {
    final filePath = file.path;
    final fileName = p.basenameWithoutExtension(filePath);

    // Intelligent title and artist extraction from filename
    String title = fileName;
    String artist = 'Unknown Artist';
    String album = p.basename(file.parent.path);

    if (fileName.contains(' - ')) {
      final parts = fileName.split(' - ');
      if (parts.length >= 2) {
        artist = parts[0].trim();
        title = parts.sublist(1).join(' - ').trim();
      }
    }

    // Apply directory / path exclusion policies
    if (!_filter.shouldIncludeAudio(
      filePath: filePath,
      durationMs: 180000, // Estimated duration default for file listing
      artist: artist == 'Unknown Artist' ? null : artist,
      preferences: prefs,
    )) {
      return null;
    }

    // Generate deterministic ID from canonical file path
    final pathHash = sha256.convert(utf8.encode(filePath)).toString().substring(0, 16);
    final id = 'desktop_$pathHash';

    // Check for companion album cover in the same directory (cover.jpg, folder.jpg)
    String artworkPath = '';
    final parent = file.parent;
    for (final candidate in ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png', 'album.jpg']) {
      final artFile = File(p.join(parent.path, candidate));
      if (artFile.existsSync()) {
        artworkPath = artFile.path;
        break;
      }
    }

    return MediaSong(
      id: id,
      title: title.isEmpty ? fileName : title,
      artist: artist,
      album: album.isEmpty ? 'Local Audio' : album,
      duration: '3:30', // Default estimated formatted duration
      durationMs: 210000,
      filePath: filePath,
      artworkPath: artworkPath,
    );
  }

  @override
  Future<List<MediaAlbum>> getAlbums({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedAlbums != null) return _cachedAlbums!;
    final songs = await getSongs(forceRefresh: forceRefresh);

    final Map<String, List<MediaSong>> grouped = {};
    for (final song in songs) {
      grouped.putIfAbsent(song.album, () => []).add(song);
    }

    final List<MediaAlbum> albums = [];
    grouped.forEach((albumName, albumSongs) {
      final first = albumSongs.first;
      final albumId = sha256.convert(utf8.encode(albumName)).toString().substring(0, 12);
      albums.add(
        MediaAlbum(
          id: albumId,
          title: albumName,
          artist: first.artist,
          trackCount: albumSongs.length,
          artworkPath: first.artworkPath,
        ),
      );
    });

    _cachedAlbums = albums;
    return albums;
  }

  @override
  Future<List<MediaArtist>> getArtists({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedArtists != null) return _cachedArtists!;
    final songs = await getSongs(forceRefresh: forceRefresh);

    final Map<String, List<MediaSong>> grouped = {};
    for (final song in songs) {
      grouped.putIfAbsent(song.artist, () => []).add(song);
    }

    final List<MediaArtist> artists = [];
    grouped.forEach((artistName, artistSongs) {
      final distinctAlbums = artistSongs.map((s) => s.album).toSet().length;
      final artistId = sha256.convert(utf8.encode(artistName)).toString().substring(0, 12);
      artists.add(
        MediaArtist(
          id: artistId,
          name: artistName,
          trackCount: artistSongs.length,
          albumCount: distinctAlbums,
          artworkPath: artistSongs.first.artworkPath,
        ),
      );
    });

    _cachedArtists = artists;
    return artists;
  }

  @override
  Future<List<MediaGenre>> getGenres({bool forceRefresh = false}) async {
    return const [];
  }

  @override
  Future<List<MediaPlaylist>> getPlaylists({bool forceRefresh = false}) async {
    return const [];
  }

  @override
  Future<List<MediaFolder>> getFolders({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedFolders != null) return _cachedFolders!;
    final songs = await getSongs(forceRefresh: forceRefresh);

    final Map<String, List<MediaSong>> grouped = {};
    for (final song in songs) {
      final parentDir = p.dirname(song.filePath);
      grouped.putIfAbsent(parentDir, () => []).add(song);
    }

    final List<MediaFolder> folders = [];
    grouped.forEach((folderPath, folderSongs) {
      folders.add(
        MediaFolder(
          name: p.basename(folderPath),
          path: folderPath,
          trackCount: folderSongs.length,
        ),
      );
    });

    _cachedFolders = folders;
    return folders;
  }
}
