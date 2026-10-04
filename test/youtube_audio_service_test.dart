import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';

void main() {
  test('YouTubeAudioService resolves 5 songs and caches URLs', () async {
    final service = YouTubeAudioService();

    final testSongs = [
      ('Birds of a Feather', 'V9PVRfjEBTI'),
      ('Never Gonna Give You Up', 'dQw4w9WgXcQ'),
      ('Cruel Summer', 'ic8j13piAhQ'),
      ('Shape of You', 'JGwWNGJdvx8'),
      ('Despacito', 'kJQP7kiw5Fk'),
    ];

    for (final song in testSongs) {
      final name = song.$1;
      final videoId = song.$2;

      final sw = Stopwatch()..start();
      final url = await service.getAudioStreamUrl(videoId);
      sw.stop();

      expect(url, isNotNull, reason: 'Failed to resolve $name ($videoId)');
      expect(url!.startsWith('http'), isTrue);

      // Verify in-memory cache hit
      final cacheSw = Stopwatch()..start();
      final cachedUrl = await service.getAudioStreamUrl(videoId);
      cacheSw.stop();

      expect(cachedUrl, equals(url));
      expect(cacheSw.elapsedMilliseconds, lessThan(50),
          reason: 'Cache hit should be instantaneous');
    }

    service.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
