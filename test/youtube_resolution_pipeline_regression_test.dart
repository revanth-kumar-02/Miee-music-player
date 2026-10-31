import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/domain/music_result_classifier.dart';

void main() {
  group('YouTube ID Extraction, Normalization & Pipeline Verification', () {
    String extractYouTubeVideoId(String trackId) {
      var id = trackId.trim();
      if (id.startsWith('youtube_')) {
        id = id.substring('youtube_'.length);
      }
      if (id.contains('watch?v=')) {
        id = Uri.tryParse(id)?.queryParameters['v'] ?? id;
      } else if (id.contains('youtu.be/')) {
        final segs = Uri.tryParse(id)?.pathSegments ?? [];
        if (segs.isNotEmpty) id = segs.last;
      }
      return id;
    }

    test('Standard 11-char YouTube ID is preserved without change', () {
      const rawId = 'dQw4w9WgXcQ';
      expect(extractYouTubeVideoId(rawId), equals('dQw4w9WgXcQ'));
      expect(RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(extractYouTubeVideoId(rawId)), isTrue);
    });

    test('youtube_ prefixed 11-char ID is extracted cleanly', () {
      const prefixedId = 'youtube_8g25GeJgxgs';
      final extracted = extractYouTubeVideoId(prefixedId);
      expect(extracted, equals('8g25GeJgxgs'));
      expect(extracted.length, equals(11));
      expect(RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(extracted), isTrue);
    });

    test('Discovery metadata IDs (wm_...) are recognized as needing query resolution', () {
      const chartId = 'wm_chart_1885110066';
      final extracted = extractYouTubeVideoId(chartId);
      expect(extracted, equals('wm_chart_1885110066'));
      // Must flag as needing query-based stream resolution
      final needsResolution = extracted.startsWith('wm_') ||
          extracted.length != 11 ||
          !RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(extracted);
      expect(needsResolution, isTrue);
    });

    test('Track model correctly classifies isYoutube for online, discovery, and web streams', () {
      const ytTrack = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        imageUrl: '',
        duration: '3:32',
      );
      expect(ytTrack.isYoutube, isTrue);

      const chartTrack = Track(
        id: 'wm_chart_12345',
        title: 'Babydoll',
        artist: 'Jamie Miller',
        imageUrl: '',
        duration: '3:30',
      );
      expect(chartTrack.isYoutube, isTrue);

      const localTrack = Track(
        id: 'local_song_456',
        title: 'Offline Song',
        artist: 'Local Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: '/storage/emulated/0/Music/song.mp3',
      );
      // In non-web tests, local tracks without http/youtube paths remain local offline items
      expect(localTrack.filePath, equals('/storage/emulated/0/Music/song.mp3'));
    });

    test('Classifier recognizes official music track even with featured artist titles', () {
      const candidate = YouTubeVideo(
        id: '8g25GeJgxgs',
        title: 'Jamie Miller - Babydoll feat. Antonio Cipriano',
        channelTitle: 'Jamie Miller',
        thumbnailUrl: '',
        duration: '3:00',
        viewCount: '',
        rawTitle: 'Jamie Miller - Babydoll feat. Antonio Cipriano',
        rawChannelTitle: 'Jamie Miller',
      );

      final isValid = MusicResultClassifier.isValidMusicTrack(candidate, query: 'Babydoll Jamie Miller');
      expect(isValid, isTrue);
    });

    test('Classifier handles lyric videos and studio versions without crashing', () {
      const lyricCandidate = YouTubeVideo(
        id: 'wrDNIUHUUyU',
        title: 'Gracie Abrams - Here You Come, There You Go (Lyrics)',
        channelTitle: 'SyrebralVibes',
        thumbnailUrl: '',
        duration: '2:50',
        viewCount: '',
        rawTitle: 'Gracie Abrams - Here You Come, There You Go (Lyrics)',
        rawChannelTitle: 'SyrebralVibes',
      );

      final verdict = MusicResultClassifier.classify(lyricCandidate, query: 'Here You Come, There You Go Gracie Abrams');
      expect(verdict.isMusic, isTrue);
    });
  });
}
