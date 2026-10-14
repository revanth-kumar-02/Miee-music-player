import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Find Lana Del Rey video ID and test VISIONOS', () async {
    final yt = YoutubeExplode();
    final results = await yt.search.search('Lana Del Rey');
    print('Found ${results.length} results for Lana Del Rey:');
    for (var i = 0; i < 5 && i < results.length; i++) {
      final v = results[i];
      print('${i + 1}. [${v.id.value}] "${v.title}" by ${v.author}');
    }

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

    final firstId = results.first.id.value;
    print('\nTesting stream resolution for $firstId using VISIONOS:');
    final manifest = await yt.videos.streamsClient.getManifest(firstId, ytClients: [kVisionOsClient]);
    final stream = manifest.audioOnly.withHighestBitrate();
    print('Stream itag: ${stream.tag}, container: ${stream.container.name}, size: ${stream.size}');

    yt.close();
  });
}
