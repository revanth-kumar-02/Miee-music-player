/// Model representing a music track.
class Track {
  final String id;
  final String title;
  final String artist;
  final String imageUrl;
  final String duration;
  final double progress;
  final bool isPlaying;
  final bool isFavorited;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    required this.duration,
    this.progress = 0.0,
    this.isPlaying = false,
    this.isFavorited = false,
  });
}
