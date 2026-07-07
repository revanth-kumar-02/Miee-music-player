/// Model representing a music album or playlist.
class Album {
  final String id;
  final String title;
  final String artist;
  final String imageUrl;
  final String? subtitle;

  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.imageUrl,
    this.subtitle,
  });
}
