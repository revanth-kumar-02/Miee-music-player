/// Strongly-typed domain model for an online YouTube Music playlist search result.
class OnlinePlaylist {
  final String id;
  final String title;
  final String author;
  final String thumbnailUrl;
  final int trackCount;

  const OnlinePlaylist({
    required this.id,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.trackCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OnlinePlaylist &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

