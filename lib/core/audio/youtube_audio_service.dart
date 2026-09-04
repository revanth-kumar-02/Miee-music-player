import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Service responsible for extracting direct audio stream URLs (m4a/webm)
/// from YouTube video IDs for playback via just_audio.
class YouTubeAudioService {
  static final YouTubeAudioService _instance = YouTubeAudioService._internal();
  factory YouTubeAudioService() => _instance;
  YouTubeAudioService._internal();

  final YoutubeExplode _yt = YoutubeExplode();

  /// Bounded cache of resolved audio stream URLs (videoId -> direct stream URL)
  final Map<String, String> _urlCache = {};
  static const int _maxCacheSize = 50;

  /// Resolves the highest quality audio-only stream URL for [videoIdOrUrl].
  Future<String?> getAudioStreamUrl(String videoIdOrUrl) async {
    try {
      final videoId = _extractVideoId(videoIdOrUrl);
      if (videoId == null || videoId.isEmpty) {
        debugPrint('YouTubeAudioService: Invalid video ID from "$videoIdOrUrl"');
        return null;
      }

      if (_urlCache.containsKey(videoId)) {
        debugPrint('YouTubeAudioService: Cache hit for video ID $videoId');
        return _urlCache[videoId];
      }

      debugPrint('YouTubeAudioService: Extracting stream manifest for YouTube ID: $videoId');
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final audioStreams = manifest.audioOnly;

      if (audioStreams.isNotEmpty) {
        // Select highest bitrate audio stream
        final streamInfo = audioStreams.withHighestBitrate();
        final url = streamInfo.url.toString();
        debugPrint('YouTubeAudioService: Successfully resolved stream URL for $videoId (Bitrate: ${streamInfo.bitrate})');

        if (_urlCache.length >= _maxCacheSize) {
          _urlCache.remove(_urlCache.keys.first);
        }
        _urlCache[videoId] = url;
        return url;
      } else {
        debugPrint('YouTubeAudioService: No audio-only streams found for $videoId');
      }
    } catch (e, stack) {
      debugPrint('YouTubeAudioService ERROR: Failed to resolve stream for "$videoIdOrUrl": $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
    }
    return null;
  }

  String? _extractVideoId(String input) {
    var clean = input.trim();
    if (clean.startsWith('youtube_')) {
      clean = clean.replaceFirst('youtube_', '');
    }
    if (clean.contains('watch?v=')) {
      final uri = Uri.tryParse(clean);
      if (uri != null) {
        return uri.queryParameters['v'] ?? clean;
      }
    } else if (clean.contains('youtu.be/')) {
      final uri = Uri.tryParse(clean);
      if (uri != null && uri.pathSegments.isNotEmpty) {
        return uri.pathSegments.last;
      }
    }
    return clean;
  }

  void clearCache() {
    _urlCache.clear();
  }

  void dispose() {
    _yt.close();
  }
}
