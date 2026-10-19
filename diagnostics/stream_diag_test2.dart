import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Diagnose o0LydWpBQts stream resolution and headers', () async {
    final videoId = 'o0LydWpBQts'; // The exact video ID that failed on device
    print('\n=== Diagnosing failing track video ID: $videoId ===');

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

    print('\n[1] Resolving manifest via kAndroidSdklessClient...');
    final sw = Stopwatch()..start();
    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [kAndroidSdklessClient],
    );
    sw.stop();
    print('Manifest resolved in ${sw.elapsedMilliseconds}ms. Audio streams: ${manifest.audioOnly.length}');

    final audioStreams = manifest.audioOnly;
    final aacStreams = audioStreams.where((s) =>
        s.container.name.toLowerCase() == 'm4a' ||
        s.container.name.toLowerCase() == 'mp4' ||
        s.audioCodec.toLowerCase().contains('mp4a') ||
        s.audioCodec.toLowerCase().contains('aac'));

    final selected = aacStreams.isNotEmpty
        ? aacStreams.withHighestBitrate()
        : audioStreams.withHighestBitrate();

    final url = selected.url;
    print('Selected stream tag: ${selected.tag}, container: ${selected.container.name}, codec: ${selected.audioCodec}, bitrate: ${selected.bitrate}');
    print('URL host: ${url.host}');
    print('URL params: ${url.queryParameters.keys.toList()}');

    // Test Header Combination 1: Miee current headers
    print('\n--- Test 1: Miee current headers (UA + Referer + Origin) ---');
    await testHttp(url, {
      'User-Agent': kYouTubeAndroidUserAgent,
      'Referer': 'https://www.youtube.com/',
      'Origin': 'https://www.youtube.com',
      'Range': 'bytes=0-1024',
    });

    // Test Header Combination 2: No Referer, No Origin, only User-Agent
    print('\n--- Test 2: Only User-Agent (No Referer/Origin) ---');
    await testHttp(url, {
      'User-Agent': kYouTubeAndroidUserAgent,
      'Range': 'bytes=0-1024',
    });

    // Test Header Combination 3: No custom headers at all (default)
    print('\n--- Test 3: No custom headers ---');
    await testHttp(url, {
      'Range': 'bytes=0-1024',
    });

    // Test Header Combination 4: Standard ExoPlayer User-Agent
    print('\n--- Test 4: ExoPlayer User-Agent ---');
    await testHttp(url, {
      'User-Agent': 'ExoPlayerLib/2.18.7 (Linux; Android 14) AndroidXMedia3/1.4.1',
      'Range': 'bytes=0-1024',
    });

    yt.close();
  });
}

Future<void> testHttp(Uri uri, Map<String, String> headers) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    headers.forEach((k, v) => req.headers.set(k, v));
    final resp = await req.close();
    print('HTTP ${resp.statusCode} ${resp.reasonPhrase} | Content-Type: ${resp.headers.contentType} | Content-Length: ${resp.headers.contentLength}');
    final bytes = await resp.fold<List<int>>([], (p, e) => p..addAll(e));
    print('Read ${bytes.length} bytes.');
    if (resp.statusCode >= 400) {
      print('Error body: ${String.fromCharCodes(bytes)}');
    }
  } catch (e) {
    print('Request error: $e');
  } finally {
    client.close();
  }
}
