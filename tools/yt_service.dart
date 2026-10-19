import 'dart:convert';
import 'dart:io';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const String kYouTubeVisionOsUserAgent =
    'com.google.ios.youtube/1.02 (RealityDevice17,1; U; visionOS 2_3)';

const YoutubeApiClient kVisionOsClient = YoutubeApiClient({
  'context': {
    'client': {
      'clientName': 'VISIONOS',
      'clientVersion': '1.02',
      'userAgent': kYouTubeVisionOsUserAgent,
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

class CachedStream {
  final String url;
  final int durationSeconds;
  final DateTime expiresAt;
  const CachedStream({
    required this.url,
    required this.durationSeconds,
    required this.expiresAt,
  });
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

void main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 8089 : 8089;
  final yt = YoutubeExplode();
  final Map<String, CachedStream> streamCache = {};
  final Map<String, List<Map<String, dynamic>>> searchCache = {};

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('[YTService] Started on http://127.0.0.1:$port');

  ProcessSignal.sigint.watch().listen((_) async {
    print('[YTService] Shutting down...');
    await server.close(force: true);
    yt.close();
    exit(0);
  });

  await for (HttpRequest request in server) {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', '*');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      continue;
    }

    final path = request.uri.path;
    try {
      if (path == '/api/yt/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 'ok'}));
      } else if (path == '/api/yt/search' || path == '/api/search') {
        final q = (request.uri.queryParameters['q'] ??
                request.uri.queryParameters['term'] ??
                '')
            .trim();
        final limitStr = request.uri.queryParameters['limit'] ?? '25';
        final limit = int.tryParse(limitStr) ?? 25;

        if (q.isEmpty) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'results': <Map<String, dynamic>>[]}));
          await request.response.close();
          continue;
        }

        final cacheKey = q.toLowerCase();
        if (searchCache.containsKey(cacheKey)) {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'results': searchCache[cacheKey]}));
          await request.response.close();
          continue;
        }

        final results = await yt.search.search(q);
        final list = <Map<String, dynamic>>[];
        for (final video in results.take(limit)) {
          final totalSec = video.duration?.inSeconds ?? 0;
          final mins = totalSec ~/ 60;
          final secs = totalSec % 60;
          final durStr = '$mins:${secs.toString().padLeft(2, '0')}';
          list.add({
            'id': video.id.value,
            'title': video.title,
            'artist': video.author,
            'duration': durStr,
            'durationSeconds': totalSec,
            'thumbnailUrl': video.thumbnails.highResUrl.isNotEmpty
                ? video.thumbnails.highResUrl
                : 'https://img.youtube.com/vi/${video.id.value}/hqdefault.jpg',
          });
        }

        if (searchCache.length >= 100) {
          searchCache.remove(searchCache.keys.first);
        }
        searchCache[cacheKey] = list;

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'results': list}));
      } else if (path == '/api/yt/resolve') {
        var id = (request.uri.queryParameters['id'] ?? '').trim();
        if (id.startsWith('youtube_')) id = id.replaceFirst('youtube_', '');
        if (id.contains('watch?v=')) {
          id = Uri.tryParse(id)?.queryParameters['v'] ?? id;
        }

        if (id.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write(jsonEncode({'error': 'Missing id parameter'}));
          await request.response.close();
          continue;
        }

        // Cache hit check
        if (streamCache.containsKey(id)) {
          final cached = streamCache[id]!;
          if (!cached.isExpired) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'streamUrl': cached.url,
              'durationSeconds': cached.durationSeconds,
              'cached': true,
            }));
            await request.response.close();
            continue;
          } else {
            streamCache.remove(id);
          }
        }

        String? streamUrl;
        int durSeconds = 0;

        // Attempt 1: VISIONOS client
        try {
          final manifest = await yt.videos.streamsClient.getManifest(
            id,
            ytClients: [kVisionOsClient],
          ).timeout(const Duration(seconds: 8));
          final audioStreams = manifest.audioOnly;
          if (audioStreams.isNotEmpty) {
            final aac = audioStreams.where((s) =>
                s.container.name.toLowerCase() == 'm4a' ||
                s.container.name.toLowerCase() == 'mp4' ||
                s.audioCodec.toLowerCase().contains('mp4a') ||
                s.audioCodec.toLowerCase().contains('aac'));
            final selected = aac.isNotEmpty
                ? aac.withHighestBitrate()
                : audioStreams.withHighestBitrate();
            streamUrl = selected.url.toString();
          }
        } catch (e) {
          print('[YTService] VISIONOS resolution failed for $id: $e');
        }

        // Attempt 2: androidSdkless fallback
        if (streamUrl == null) {
          try {
            final manifest = await yt.videos.streamsClient.getManifest(
              id,
              ytClients: [kAndroidSdklessClient],
            ).timeout(const Duration(seconds: 6));
            final audioStreams = manifest.audioOnly;
            if (audioStreams.isNotEmpty) {
              final selected = audioStreams.withHighestBitrate();
              streamUrl = selected.url.toString();
            }
          } catch (e) {
            print('[YTService] androidSdkless resolution failed for $id: $e');
          }
        }

        // Attempt 3: default client fallback
        if (streamUrl == null) {
          try {
            final manifest = await yt.videos.streamsClient.getManifest(id)
                .timeout(const Duration(seconds: 6));
            final audioStreams = manifest.audioOnly;
            if (audioStreams.isNotEmpty) {
              final selected = audioStreams.withHighestBitrate();
              streamUrl = selected.url.toString();
            }
          } catch (e) {
            print('[YTService] default resolution failed for $id: $e');
          }
        }

        if (streamUrl != null && streamUrl.isNotEmpty) {
          DateTime expiresAt = DateTime.now().add(const Duration(hours: 1));
          try {
            final uri = Uri.parse(streamUrl);
            final exp = uri.queryParameters['expire'];
            if (exp != null) {
              final secs = int.tryParse(exp);
              if (secs != null) {
                final urlExp = DateTime.fromMillisecondsSinceEpoch(secs * 1000)
                    .subtract(const Duration(minutes: 3));
                if (urlExp.isBefore(expiresAt)) expiresAt = urlExp;
              }
            }
            final durParam = uri.queryParameters['dur'];
            if (durParam != null) {
              final d = double.tryParse(durParam);
              if (d != null) durSeconds = d.round();
            }
          } catch (_) {}

          if (streamCache.length >= 100) {
            streamCache.remove(streamCache.keys.first);
          }
          streamCache[id] = CachedStream(
            url: streamUrl,
            durationSeconds: durSeconds,
            expiresAt: expiresAt,
          );

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'streamUrl': streamUrl,
            'durationSeconds': durSeconds,
          }));
        } else {
          request.response.statusCode = HttpStatus.notFound;
          request.response.write(
            jsonEncode({'error': 'Unable to resolve full audio stream for $id'}),
          );
        }
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'error': e.toString()}));
    }
    await request.response.close();
  }
}
