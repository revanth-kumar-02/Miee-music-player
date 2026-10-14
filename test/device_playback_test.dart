import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';

import 'dart:io';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Test just_audio playback of YouTube stream on device', () async {
    final videoId = '7wtfhZwyrcc'; // Imagine Dragons - Believer
    print('\n[DeviceTest] Resolving stream for $videoId...');
    final sw = Stopwatch()..start();
    final url = await YouTubeAudioService().getAudioStreamUrl(videoId, forceRefresh: true);
    sw.stop();
    print('[DeviceTest] Resolution took ${sw.elapsedMilliseconds}ms. URL: ${url != null ? "FOUND (${url.substring(0, 50)}...)" : "NULL"}');

    if (url == null) {
      fail('Stream URL resolution returned null');
    }

    final player = AudioPlayer();
    try {
      print('[DeviceTest] Initializing AudioPlayer with resolved stream...');
      const String kYouTubeAndroidClientVersion = '20.10.38';
      const String kYouTubeAndroidUserAgent =
          'com.google.android.youtube/$kYouTubeAndroidClientVersion (Linux; U; Android 11) gzip';

      // First try with the exact headers Miee uses in audio_handler.dart:
      print('[DeviceTest] Setting audio source with Miee headers...');
      try {
        final duration = await player.setAudioSource(
          AudioSource.uri(
            Uri.parse(url),
            headers: const {
              'User-Agent': kYouTubeAndroidUserAgent,
              'Referer': 'https://www.youtube.com/',
              'Origin': 'https://www.youtube.com',
            },
          ),
        );
        print('[DeviceTest] SUCCESS with Miee headers! Duration: $duration');
      } catch (e, st) {
        print('[DeviceTest] FAILED with Miee headers:');
        print('Exception: $e');
        print('StackTrace: $st');
      }

      // Second try: without custom headers (ExoPlayer default)
      print('\n[DeviceTest] Setting audio source WITHOUT headers...');
      try {
        final duration2 = await player.setAudioSource(
          AudioSource.uri(Uri.parse(url)),
        );
        print('[DeviceTest] SUCCESS without headers! Duration: $duration2');
      } catch (e, st) {
        print('[DeviceTest] FAILED without headers:');
        print('Exception: $e');
        print('StackTrace: $st');
      }

    } finally {
      await player.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
