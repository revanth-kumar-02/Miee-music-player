import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';

/// Strongly-typed domain model representing a YouTube search result.
class YouTubeVideo implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  final String channelTitle;
  final String thumbnailUrl;
  @override
  final String duration; // e.g. "3:45"
  final String viewCount; // e.g. "124K views" or "1.2M views"

  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.duration,
    required this.viewCount,
  });

  /// The standard watch page URL for this video.
  String get videoUrl => 'https://www.youtube.com/watch?v=$id';

  /// The watch page URL optimized for YouTube Music.
  String get musicUrl => 'https://music.youtube.com/watch?v=$id';

  @override
  String get artist => channelTitle;

  @override
  String get imageUrl => thumbnailUrl;

  @override
  String get filePath => videoUrl;

  @override
  bool get isYoutube => true;

  /// Converts this YouTube result into a standard [Track] model so it can be
  /// played or queued by Miee's playback engine.
  Track toTrack() {
    return Track(
      id: 'youtube_$id',
      title: title,
      artist: channelTitle,
      imageUrl: thumbnailUrl,
      duration: duration,
      filePath: videoUrl, // Playback engine will recognize this is a YouTube stream URL
      isFavorited: false,
    );
  }
}

