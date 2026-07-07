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
  
  final String? filePath;
  final double progress;
  final bool isPlaying;
  final bool isFavorited;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.duration,
    this.filePath,
    this.progress = 0.0,
    this.isPlaying = false,
    this.isFavorited = false,
  });

  @override
  String get filePathValue => filePath ?? '';

  // For compatibility with the interface
  @override
  String get filePath => filePathValue;

  @override
  bool get isYoutube => id.startsWith('youtube_') || (filePath?.contains('youtube.com') ?? false);
}

