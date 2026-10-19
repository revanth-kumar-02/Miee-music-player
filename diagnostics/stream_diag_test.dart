import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Diagnose YouTube stream resolution and HTTP status', () async {
    final videoId = '7wtfhZwyrcc'; // Imagine Dragons - Believer
    print('\n=== Testing video ID: $videoId ===');

    const String kYouTubeAndroidClientVersion = '20.10.38';
    const String kYouTubeAndroidUserAgent =
        'com.google.android.youtube/$kYouTubeAndroidClientVersion (Linux; U; Android 11) gzip';

    const YoutubeApiClient kAndroidSdklessClient = YoutubeApiClient({
      'context': {
        'client': {
          'clientName': 'ANDROID',
          'clientVersion': kYouTubeAndroidClientVersion,
          'userAgent': kYouTubeAndroidUserAgent,
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
          'osName': 'Android',
          'osVersion': '11',
        },
      },
    }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

    final yt = YoutubeExplode();

    print('\n--- 1. Testing kAndroidSdklessClient ---');
    final sw1 = Stopwatch()..start();
    try {
      final manifest1 = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [kAndroidSdklessClient],
      );
      sw1.stop();
      print('Manifest fetched in ${sw1.elapsedMilliseconds}ms');
      print('Audio-only streams count: ${manifest1.audioOnly.length}');

      for (final s in manifest1.audioOnly) {
        print('\n[Stream Details]');
        print('Tag: ${s.tag}');
        print('Container: ${s.container.name}');
        print('Codec: ${s.audioCodec}');
        print('Bitrate: ${s.bitrate}');
        print('Size: ${s.size}');
        final uri = s.url;
        print('URL Scheme/Host: ${uri.scheme}://${uri.host}${uri.path}');
        print('URL Query params: ${uri.queryParameters.keys.toList()}');
        print('Expire timestamp: ${uri.queryParameters['expire']}');

        // Test HTTP GET with headers
        final httpClient = HttpClient();
        try {
          final req = await httpClient.getUrl(uri);
          req.headers.set('User-Agent', kYouTubeAndroidUserAgent);
          req.headers.set('Referer', 'https://www.youtube.com/');
          req.headers.set('Origin', 'https://www.youtube.com');
          req.headers.set('Range', 'bytes=0-1024');

          final resp = await req.close();
          print('HTTP Status: ${resp.statusCode} ${resp.reasonPhrase}');
          print('Content-Type: ${resp.headers.contentType}');
          print('Content-Length: ${resp.headers.contentLength}');

          final bytes = await resp.fold<List<int>>([], (prev, elem) => prev..addAll(elem));
          print('Received bytes count: ${bytes.length}');
          if (resp.statusCode != 200 && resp.statusCode != 206) {
            print('Non-200/206 Response Body: ${String.fromCharCodes(bytes)}');
          }
        } finally {
          httpClient.close();
        }
        break; // test highest
      }
    } catch (e, st) {
      print('kAndroidSdklessClient error: $e\n$st');
    }

    print('\n--- 2. Testing default yt.videos.streamsClient.getManifest(videoId) ---');
    final sw2 = Stopwatch()..start();
    try {
      final manifestDefault = await yt.videos.streamsClient.getManifest(videoId);
      sw2.stop();
      print('Default manifest fetched in ${sw2.elapsedMilliseconds}ms');
      print('Default audio-only streams: ${manifestDefault.audioOnly.length}');
      if (manifestDefault.audioOnly.isNotEmpty) {
        final stream = manifestDefault.audioOnly.withHighestBitrate();
        print('Default Stream: tag=${stream.tag}, container=${stream.container.name}, codec=${stream.audioCodec}, bitrate=${stream.bitrate}');
        
        final httpClient = HttpClient();
        try {
          final req = await httpClient.getUrl(stream.url);
          req.headers.set('Range', 'bytes=0-1024');
          final resp = await req.close();
          print('Default stream HTTP Status: ${resp.statusCode} ${resp.reasonPhrase}');
          print('Default stream Content-Type: ${resp.headers.contentType}');
        } finally {
          httpClient.close();
        }
      }
    } catch (e) {
      print('Default manifest error: $e');
    }

    yt.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
