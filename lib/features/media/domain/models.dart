import '../../../shared/models/music_item.dart';

/// Strongly typed application domain model for a local song/track discovered on the device.
class MediaSong implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  final String album;
  @override
  final String duration; // e.g. "3:42"
  final int durationMs;
  @override
  final String filePath;
  final String artworkPath; // Local temporary file path for artwork bytes

  const MediaSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.durationMs,
    required this.filePath,
    required this.artworkPath,
  });

  @override
  String get imageUrl => artworkPath;

  @override
  bool get isYoutube => false;
}


/// Strongly typed application domain model for an album.
class MediaAlbum {
  final String id;
  final String title;
  final String artist;
  final int trackCount;
  final String artworkPath;

  const MediaAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.trackCount,
    required this.artworkPath,
  });
}

/// Strongly typed application domain model for an artist.
class MediaArtist {
  final String id;
  final String name;
  final int trackCount;
  final int albumCount;

  const MediaArtist({
    required this.id,
    required this.name,
    required this.trackCount,
    required this.albumCount,
  });
}

/// Strongly typed application domain model for a genre.
class MediaGenre {
  final String id;
  final String name;
  final int trackCount;

  const MediaGenre({
    required this.id,
    required this.name,
    required this.trackCount,
  });
}

/// Strongly typed application domain model for a playlist.
class MediaPlaylist {
  final String id;
  final String name;
  final int trackCount;

  const MediaPlaylist({
    required this.id,
    required this.name,
    required this.trackCount,
  });
}

/// Strongly typed application domain model for a directory folder containing music.
class MediaFolder {
  final String name;
  final String path;
  final int trackCount;

  const MediaFolder({
    required this.name,
    required this.path,
    required this.trackCount,
  });
}
