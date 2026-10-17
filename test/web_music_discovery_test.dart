import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/data/web_music_discovery_source.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';

void main() {
  group('Web Music Discovery and Playable Stream Resolution', () {
    test('1. Discovers genuine individual songs for artist query', () async {
      final source = WebMusicDiscoverySource();
      final songs = await source.searchVideos('Anirudh song', limit: 5);

      expect(songs.isNotEmpty, isTrue);
      final first = songs.first;
      expect(first.title.isNotEmpty, isTrue);
      expect(first.channelTitle.isNotEmpty, isTrue);
      expect(first.duration.contains(':'), isTrue);
      expect(first.thumbnailUrl.startsWith('http'), isTrue);
      // Valid individual song check
      expect(RecommendationService.isLegitimateSong(first), isTrue);
    });

    test('2. Converts YouTubeVideo to Track preserving playable stream and original metadata', () async {
      final source = WebMusicDiscoverySource();
      final songs = await source.searchVideos('Arijit Singh song', limit: 3);

      expect(songs.isNotEmpty, isTrue);
      final song = songs.first;
      final track = song.toTrack();

      expect(track.id.startsWith('youtube_'), isTrue);
      expect(track.title, equals(song.title));
      expect(track.artist, equals(song.channelTitle));
      expect(track.imageUrl, equals(song.thumbnailUrl));
      expect(track.duration, equals(song.duration));
      expect(track.filePath.isNotEmpty, isTrue);
    });

    test('3. YouTubeRepository transparently falls back to WebMusicDiscoverySource on web', () async {
      final repo = YouTubeRepository();
      final results = await repo.search('Coldplay song');

      expect(results.isNotEmpty, isTrue);
      expect(results.any((v) => v.channelTitle.toLowerCase().contains('coldplay')), isTrue);
    });
  });
}
