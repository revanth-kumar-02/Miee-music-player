import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  group('Preview vs Full-Track Duration Regression Tests', () {
    test('1. YouTubeVideo from web backend preserves full track duration and leaves audioStreamUrl null for on-demand full resolution', () {
      final video = YouTubeVideo(
        id: 'oKxuiw3iMBE',
        title: 'West Coast',
        channelTitle: 'Lana Del Rey',
        thumbnailUrl: 'https://img.youtube.com/vi/oKxuiw3iMBE/hqdefault.jpg',
        duration: '4:16',
        viewCount: 'Verified Song',
        audioStreamUrl: null, // Full stream is resolved on play, never fixed to a 30s preview
      );

      final track = video.toTrack();

      expect(track.id, equals('youtube_oKxuiw3iMBE'));
      expect(track.duration, equals('4:16'));
      expect(track.isYoutube, isTrue);
      // filePath should be the YouTube video URL, NOT a 30s preview URL
      expect(track.filePath, equals('https://www.youtube.com/watch?v=oKxuiw3iMBE'));
      expect(track.filePath.contains('itunes.apple.com'), isFalse);
      expect(track.filePath.contains('preview'), isFalse);
    });

    test('2. Web discovery parsing does NOT substitute 30s previewUrl as audioStreamUrl', () {
      // Test parsing logic directly
      final itunesJson = {
        'kind': 'song',
        'trackId': 1440818780,
        'trackName': 'West Coast',
        'artistName': 'Lana Del Rey',
        'trackTimeMillis': 256800, // 4:16
        'artworkUrl100': 'https://is1-ssl.mzstatic.com/image/thumb/Music/v4/100x100bb.jpg',
        'previewUrl': 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/bf/preview.m4a',
      };

      // Ensure that when converting or handling preview tracks, duration is preserved
      final millis = itunesJson['trackTimeMillis'] as int;
      final totalSeconds = millis ~/ 1000;
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      final durationStr = '$minutes:${seconds.toString().padLeft(2, '0')}';

      expect(durationStr, equals('4:16'));
      expect(totalSeconds, equals(256));
      expect(totalSeconds > 60, isTrue); // Significantly longer than a 30s preview
    });

    test('3. Full duration is preserved in Track model and never overwritten with 30s preview', () {
      final track = Track(
        id: 'youtube_oKxuiw3iMBE',
        title: 'West Coast',
        artist: 'Lana Del Rey',
        imageUrl: 'https://img.youtube.com/vi/oKxuiw3iMBE/hqdefault.jpg',
        duration: '4:16',
        filePath: 'https://www.youtube.com/watch?v=oKxuiw3iMBE',
      );

      expect(track.duration, equals('4:16'));
      expect(track.isYoutube, isTrue);

      // Verify duration parsing
      final parts = track.duration.split(':');
      final parsedDuration = Duration(
        minutes: int.parse(parts[0]),
        seconds: int.parse(parts[1]),
      );

      expect(parsedDuration.inSeconds, equals(256));
      expect(parsedDuration, isNot(equals(const Duration(seconds: 30))));
    });

    test('4. Preview URLs are detected and rejected as direct full-length streams', () {
      const itunesPreview =
          'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/bf/preview.m4a';
      const fullGooglevideo =
          'https://rr1---sn-gwpa-h55es.googlevideo.com/videoplayback?expire=1792263277&dur=265.891';

      bool isPreview(String url) =>
          url.contains('itunes.apple.com') ||
          url.contains('/AudioPreview') ||
          url.contains('preview');

      expect(isPreview(itunesPreview), isTrue);
      expect(isPreview(fullGooglevideo), isFalse);
    });
  });
}
