import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Test various clients past 1MB allowance', () async {
    final videoId = 'o0LydWpBQts'; // Or Lana Del Rey track
    final yt = YoutubeExplode();

    // 1. VISIONOS client definition (from InterTune / yt-dlp)
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

    // 2. TVHTML5 client definition
    const YoutubeApiClient kTvHtml5Client = YoutubeApiClient({
      'context': {
        'client': {
          'clientName': 'TVHTML5',
          'clientVersion': '7.20250312.16.00',
          'hl': 'en',
          'timeZone': 'UTC',
          'utcOffsetMinutes': 0,
        },
      },
    }, 'https://www.youtube.com/youtubei/v1/player?prettyPrint=false');

    // Test VISIONOS
    print('\n================== Testing VISIONOS ==================');
    try {
      final manifest = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [kVisionOsClient],
      );
      print('VISIONOS audio streams: ${manifest.audioOnly.length}');
      if (manifest.audioOnly.isNotEmpty) {
        final stream = manifest.audioOnly.withHighestBitrate();
        print('Stream container: ${stream.container.name}, codec: ${stream.audioCodec}, bitrate: ${stream.bitrate}, size: ${stream.size}');
        print('URL host: ${stream.url.host}');
        await testByteRanges(stream.url);
      }
    } catch (e, st) {
      print('VISIONOS failed: $e\n$st');
    }

    // Test TVHTML5
    print('\n================== Testing TVHTML5 ==================');
    try {
      final manifest = await yt.videos.streamsClient.getManifest(
        videoId,
        ytClients: [kTvHtml5Client],
      );
      print('TVHTML5 audio streams: ${manifest.audioOnly.length}');
      if (manifest.audioOnly.isNotEmpty) {
        final stream = manifest.audioOnly.withHighestBitrate();
        print('Stream container: ${stream.container.name}, codec: ${stream.audioCodec}, bitrate: ${stream.bitrate}, size: ${stream.size}');
        await testByteRanges(stream.url);
      }
    } catch (e, st) {
      print('TVHTML5 failed: $e\n$st');
    }

    // Test default yt.videos.streamsClient.getManifest (which uses youtube_explode's default chain)
    print('\n================== Testing default getManifest ==================');
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      print('Default audio streams: ${manifest.audioOnly.length}');
      if (manifest.audioOnly.isNotEmpty) {
        final stream = manifest.audioOnly.withHighestBitrate();
        print('Stream container: ${stream.container.name}, codec: ${stream.audioCodec}, bitrate: ${stream.bitrate}, size: ${stream.size}');
        await testByteRanges(stream.url);
      }
    } catch (e, st) {
      print('Default getManifest failed: $e\n$st');
    }

    yt.close();
  });
}

Future<void> testByteRanges(Uri uri) async {
  print('  Testing byte 0-1KB...');
  await checkRange(uri, 'bytes=0-1024');
  print('  Testing byte 1.5MB-1.501MB...');
  await checkRange(uri, 'bytes=1500000-1501024');
  print('  Testing byte 2.5MB-2.501MB...');
  await checkRange(uri, 'bytes=2500000-2501024');
  print('  Testing full read 1.5MB to 2.5MB (1MB chunk)...');
  await checkRange(uri, 'bytes=1500000-2548576');
}

Future<void> checkRange(Uri uri, String range) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    req.headers.set('Range', range);
    final resp = await req.close();
    print('    $range -> HTTP ${resp.statusCode} ${resp.reasonPhrase} (${resp.headers.contentLength} bytes, content-type: ${resp.headers.contentType})');
    final bytes = await resp.fold<List<int>>([], (p, e) => p..addAll(e));
    if (resp.statusCode >= 400) {
      print('    FAIL body: ${String.fromCharCodes(bytes)}');
    } else {
      print('    SUCCESS received ${bytes.length} bytes');
    }
  } finally {
    client.close();
  }
}
