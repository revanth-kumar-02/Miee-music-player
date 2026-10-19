import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/music_item.dart';
import '../domain/lyrics_model.dart';

final _lyricsDio = Dio(
  BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    headers: {
      'User-Agent': 'MieeMusic/1.0.0 (https://github.com/revanth-kumar-02/Miee-music-player)',
    },
  ),
);

/// Provider that resolves synchronized lyrics for the active track.
final lyricsProvider = FutureProvider.family<List<LyricLine>, MusicItem?>((ref, track) async {
  if (track == null) return [];

  // 1. Try resolving local .lrc file
  if (!track.isYoutube && track.filePath.isNotEmpty) {
    try {
      final songFile = File(track.filePath);
      if (await songFile.exists()) {
        final baseName = songFile.path.substring(0, songFile.path.lastIndexOf('.'));
        final lrcFile = File('$baseName.lrc');
        if (await lrcFile.exists()) {
          final content = await lrcFile.readAsString();
          final list = LyricParser.parse(content);
          if (list.isNotEmpty) return list;
        }
      }
    } catch (e) {
      debugPrint('[Lyrics] Local .lrc read error: $e');
    }
  }

  // 2. Query LRCLIB public API for real synchronized lyrics
  try {
    final cleanTitle = _cleanTitle(track.title);
    final cleanArtist = _cleanArtist(track.artist);

    final response = await _lyricsDio.get(
      'https://lrclib.net/api/get',
      queryParameters: {
        'track_name': cleanTitle,
        'artist_name': cleanArtist,
      },
    );

    if (response.statusCode == 200 && response.data is Map) {
      final data = response.data as Map;
      final synced = data['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final parsed = LyricParser.parse(synced);
        if (parsed.isNotEmpty) return parsed;
      }

      final plain = data['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        return _formatPlainLyrics(plain, track.duration);
      }
    }
  } catch (e) {
    debugPrint('[Lyrics] LRCLIB get query failed: $e. Trying search fallback...');
  }

  // 3. Search fallback on LRCLIB
  try {
    final cleanTitle = _cleanTitle(track.title);
    final cleanArtist = _cleanArtist(track.artist);
    final query = cleanArtist.isNotEmpty ? '$cleanTitle $cleanArtist' : cleanTitle;

    final searchResp = await _lyricsDio.get(
      'https://lrclib.net/api/search',
      queryParameters: {'q': query},
    );

    if (searchResp.statusCode == 200 && searchResp.data is List && (searchResp.data as List).isNotEmpty) {
      final firstHit = (searchResp.data as List).first as Map;
      final synced = firstHit['syncedLyrics'] as String?;
      if (synced != null && synced.trim().isNotEmpty) {
        final parsed = LyricParser.parse(synced);
        if (parsed.isNotEmpty) return parsed;
      }

      final plain = firstHit['plainLyrics'] as String?;
      if (plain != null && plain.trim().isNotEmpty) {
        return _formatPlainLyrics(plain, track.duration);
      }
    }
  } catch (e) {
    debugPrint('[Lyrics] LRCLIB search query failed: $e');
  }

  return [];
});

/// Formats plain unsynchronized lyrics with estimated timing based on track length.
List<LyricLine> _formatPlainLyrics(String plain, String durationStr) {
  final lines = plain.split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isEmpty) return [];

  int totalSec = 180;
  final parts = durationStr.split(':');
  if (parts.length == 2) {
    final m = int.tryParse(parts[0]) ?? 3;
    final s = int.tryParse(parts[1]) ?? 0;
    totalSec = m * 60 + s;
  }

  final stepSec = (totalSec / (lines.length + 1)).clamp(3.0, 10.0);
  final List<LyricLine> result = [];
  var current = const Duration(seconds: 2);

  for (final line in lines) {
    result.add(LyricLine(time: current, text: line));
    current += Duration(milliseconds: (stepSec * 1000).toInt());
  }

  return result;
}

String _cleanTitle(String title) {
  var t = title;
  t = t.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\b(official audio|official video|lyric video|lyrics|remastered|video song|full song|audio song|hd|4k)\b', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

String _cleanArtist(String artist) {
  var a = artist;
  a = a.replaceAll(RegExp(r'\b(topic|vevo)\b', caseSensitive: false), '');
  a = a.replaceAll(RegExp(r'\s+'), ' ').trim();
  return a;
}
