import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Test VISIONOS stream with default ExoPlayer headers', () async {
    final videoId = 'o0LydWpBQts';
    final yt = YoutubeExplode();

    const String kVisionOsUserAgent =
        'com.google.ios.youtube/1.02 (RealityDevice17,1; U; visionOS 2_3)';
    const YoutubeApiClient kVisionOsClient = YoutubeApiClient({
      'context': {
        'client': {
          'clientName': 'VISIONOS',
          'clientVersion': '1.02',
          'userAgent': kVisionOsUserAgent,
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
          'osName': 'visionOS',
          'osVersion': '2.3.21O5565d',
          'deviceMake': 'Apple',
          'deviceModel': 'RealityDevice17,1',
        },
      },
    }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

    final manifest = await yt.videos.streamsClient.getManifest(
      videoId,
      ytClients: [kVisionOsClient],
    );

    final stream = manifest.audioOnly.withHighestBitrate();

    print('Testing 2MB download with ExoPlayer default UA...');
    final client = HttpClient();
    final req = await client.getUrl(stream.url);
    req.headers.set('User-Agent', 'ExoPlayerLib/2.18.7 (Linux; Android 14) AndroidXMedia3/1.4.1');
    req.headers.set('Range', 'bytes=0-2097152');
    final resp = await req.close();
    print('Status: ${resp.statusCode} ${resp.reasonPhrase}');
    final bytes = await resp.fold<List<int>>([], (p, e) => p..addAll(e));
    print('Downloaded ${bytes.length} bytes with ExoPlayer UA!');

    print('Testing 2MB download with NO headers...');
    final client2 = HttpClient();
    final req2 = await client2.getUrl(stream.url);
    req2.headers.set('Range', 'bytes=0-2097152');
    final resp2 = await req2.close();
    print('Status: ${resp2.statusCode} ${resp2.reasonPhrase}');
    final bytes2 = await resp2.fold<List<int>>([], (p, e) => p..addAll(e));
    print('Downloaded ${bytes2.length} bytes with NO custom headers!');

    client.close();
    client2.close();
    yt.close();
  });
}
