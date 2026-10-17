import '../../../shared/models/track.dart';
import '../../../shared/models/music_item.dart';
import 'youtube_metadata_cleaner.dart';

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
  final String? rawTitle;
  final String? rawChannelTitle;
  final String? audioStreamUrl;

  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.duration,
    required this.viewCount,
    this.rawTitle,
    this.rawChannelTitle,
    this.audioStreamUrl,
  });

  YouTubeVideo copyWith({
    String? id,
    String? title,
    String? channelTitle,
    String? thumbnailUrl,
    String? duration,
    String? viewCount,
    String? rawTitle,
    String? rawChannelTitle,
    String? audioStreamUrl,
  }) {
    return YouTubeVideo(
      id: id ?? this.id,
      title: title ?? this.title,
      channelTitle: channelTitle ?? this.channelTitle,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      viewCount: viewCount ?? this.viewCount,
      rawTitle: rawTitle ?? this.rawTitle,
      rawChannelTitle: rawChannelTitle ?? this.rawChannelTitle,
      audioStreamUrl: audioStreamUrl ?? this.audioStreamUrl,
    );
  }

  /// The standard watch page URL for this video.
  String get videoUrl => 'https://www.youtube.com/watch?v=$id';

  /// The watch page URL optimized for YouTube Music.
  String get musicUrl => 'https://music.youtube.com/watch?v=$id';

  @override
  String get artist => channelTitle;

  @override
  String get imageUrl => thumbnailUrl;

  @override
  String get filePath => audioStreamUrl ?? videoUrl;

  @override
  bool get isYoutube => audioStreamUrl == null || !audioStreamUrl!.startsWith('http') || audioStreamUrl!.contains('youtube.com');

  /// Converts this YouTube result into a standard [Track] model so it can be
  /// played or queued by Miee's playback engine.
  Track toTrack({String? reliableArtist, String? reliableTitle}) {
    final cleaned = YouTubeMetadataCleaner.clean(
      rawTitle: rawTitle ?? title,
      rawChannel: rawChannelTitle ?? channelTitle,
      reliableArtist: reliableArtist,
      reliableTitle: reliableTitle,
    );
    return Track(
      id: 'youtube_$id',
      title: cleaned.title,
      artist: cleaned.artist,
      imageUrl: thumbnailUrl,
      duration: duration,
      filePath: audioStreamUrl ?? videoUrl, // Playback engine will recognize direct audio stream or YouTube URL
      isFavorited: false,
      rawTitle: rawTitle ?? title,
      rawArtist: rawChannelTitle ?? channelTitle,
    );
  }
}

