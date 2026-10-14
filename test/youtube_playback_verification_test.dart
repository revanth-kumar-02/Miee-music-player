import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/features/media/domain/models.dart';

void main() {
  group('YouTube Playback & Stream Resolution Runtime Verification', () {
    late YouTubeAudioService audioService;

    setUp(() {
      audioService = YouTubeAudioService();
      audioService.clearCache();
    });

    tearDown(() {
      audioService.dispose();
    });

    test('1. Stream resolution succeeds for Believer (o0LydWpBQts) via VISIONOS', () async {
      final videoId = 'o0LydWpBQts';
      final sw = Stopwatch()..start();
      final url = await audioService.getAudioStreamUrl(videoId, forceRefresh: true);
      sw.stop();

      expect(url, isNotNull, reason: 'Stream URL must not be null');
      expect(url, isNotEmpty);
      expect(url, startsWith('https://'));
      expect(url, contains('googlevideo.com'));
      print('Resolved $videoId in ${sw.elapsedMilliseconds}ms');

      // Verify range beyond 1MB allowance (bypassing the 403 cold-start cap)
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url!));
      req.headers.set('User-Agent', kYouTubeVisionOsUserAgent);
      req.headers.set('Range', 'bytes=1500000-2548576'); // 1MB chunk past 1.5MB
      final resp = await req.close();

      expect(resp.statusCode, equals(206), reason: 'Expected HTTP 206 Partial Content past 1MB, not HTTP 403');
      final bytes = await resp.fold<List<int>>([], (p, e) => p..addAll(e));
      expect(bytes.length, equals(1048577), reason: 'Must successfully receive full audio chunk past 1MB');
      client.close();
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('2. Stream resolution succeeds for Lana Del Rey (o_1aF54DO60)', () async {
      final videoId = 'o_1aF54DO60';
      final sw = Stopwatch()..start();
      final url = await audioService.getAudioStreamUrl(videoId, forceRefresh: true);
      sw.stop();

      expect(url, isNotNull);
      expect(url, isNotEmpty);
      expect(url, startsWith('https://'));
      print('Resolved $videoId in ${sw.elapsedMilliseconds}ms');

      // Verify stream bytes past 1MB
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(url!));
      req.headers.set('User-Agent', kYouTubeVisionOsUserAgent);
      req.headers.set('Range', 'bytes=1200000-1202048');
      final resp = await req.close();

      expect(resp.statusCode, equals(206));
      client.close();
    }, timeout: const Timeout(Duration(seconds: 45)));

    test('3. Stream URL validity and cache helpers behave correctly', () {
      expect(audioService.isUrlValid(''), isFalse);
      expect(audioService.isUrlValid('not-a-url'), isFalse);
      
      const futureExpiryUrl = 'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000'; // Year 2050
      expect(audioService.isUrlValid(futureExpiryUrl), isTrue);

      const expiredUrl = 'https://rr1---sn-test.googlevideo.com/videoplayback?expire=1000000000'; // Year 2001
      expect(audioService.isUrlValid(expiredUrl), isFalse);
    });

    test('4. Local track playback source remains independent', () {
      const localTrack = MediaSong(
        id: 'local_1',
        title: 'Local Test Track',
        artist: 'Local Artist',
        album: 'Local Album',
        duration: '3:00',
        durationMs: 180000,
        filePath: '/storage/emulated/0/Music/test.mp3',
        artworkPath: '/storage/emulated/0/Music/test.jpg',
      );

      expect(localTrack.isYoutube, isFalse);
      expect(localTrack.filePath.startsWith('http'), isFalse);
    });
  });
}
