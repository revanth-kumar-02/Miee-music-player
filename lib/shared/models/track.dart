import 'music_item.dart';

/// Model representing a music track.
class Track implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String imageUrl;
  @override
  final String duration;
  
  final String? localFilePath;
  final double progress;
  final bool isPlaying;
  final bool isFavorited;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.duration,
    String? filePath,
    this.progress = 0.0,
    this.isPlaying = false,
    this.isFavorited = false,
  }) : localFilePath = filePath;

  @override
  String get filePath => localFilePath ?? '';

  @override
  bool get isYoutube => id.startsWith('youtube_') || (localFilePath?.contains('youtube.com') ?? false);
}

