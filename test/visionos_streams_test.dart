import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Inspect VISIONOS stream formats and containers', () async {
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

    print('\nAll audio-only streams on VISIONOS:');
    for (final s in manifest.audioOnly) {
      print('itag: ${s.tag}, container: ${s.container.name}, codec: ${s.audioCodec}, bitrate: ${s.bitrate}, size: ${s.size}');
    }

    // Now test downloading 2MB of the highest bitrate stream
    final stream = manifest.audioOnly.withHighestBitrate();
    print('\nTesting 2MB download of highest stream (itag ${stream.tag}):');
    final client = HttpClient();
    final req = await client.getUrl(stream.url);
    req.headers.set('User-Agent', kVisionOsUserAgent);
    req.headers.set('Range', 'bytes=0-2097152'); // 2MB
    final resp = await req.close();
    print('Status: ${resp.statusCode} ${resp.reasonPhrase}, length: ${resp.headers.contentLength}');
    final bytes = await resp.fold<List<int>>([], (p, e) => p..addAll(e));
    print('Successfully downloaded ${bytes.length} bytes!');

    client.close();
    yt.close();
  });
}
