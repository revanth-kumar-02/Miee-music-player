abstract class YouTubeFailure implements Exception {
  final String message;
  const YouTubeFailure(this.message);

  @override
  String toString() => message;
}

class YouTubeSearchFailure extends YouTubeFailure {
  const YouTubeSearchFailure([super.message = 'Failed to search YouTube.']);
}

class YouTubePlaybackFailure extends YouTubeFailure {
  const YouTubePlaybackFailure([super.message = 'Failed to play YouTube video.']);
}

class VideoUnavailableFailure extends YouTubeFailure {
  const VideoUnavailableFailure([super.message = 'This video is unavailable or restricted.']);
}

class NetworkPlaybackFailure extends YouTubeFailure {
  const NetworkPlaybackFailure([super.message = 'Network error. Please check your internet connection.']);
}

class YouTubeApiQuotaFailure extends YouTubeFailure {
  const YouTubeApiQuotaFailure([super.message = 'YouTube API quota limit reached.']);
}

class YouTubeApiConfigFailure extends YouTubeFailure {
  const YouTubeApiConfigFailure([super.message = 'YouTube API key is not configured correctly.']);
}
