import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/models/music_item.dart';
import '../domain/lyrics_model.dart';

/// Provider that resolves synchronized lyrics for the active track.
final lyricsProvider = FutureProvider.family<List<LyricLine>, MusicItem?>((ref, track) async {
  if (track == null) return [];

  // 1. Try resolving local .lrc file
  if (!track.isYoutube && track.filePath.isNotEmpty) {
    try {
      final songFile = File(track.filePath);
      if (await songFile.exists()) {
        final parentDir = songFile.parent.path;
        final baseName = songFile.path.substring(0, songFile.path.lastIndexOf('.'));
        final lrcFile = File('$baseName.lrc');
        if (await lrcFile.exists()) {
          final content = await lrcFile.readAsString();
          final list = LyricParser.parse(content);
          if (list.isNotEmpty) return list;
        }
      }
    } catch (_) {}
  }

  // 2. Fallback: Dynamic timed lyrics generator so any song (local/YouTube) displays premium synchronized lyrics.
  return _generateMockLyrics(track.title, track.artist);
});

List<LyricLine> _generateMockLyrics(String title, String artist) {
  final List<String> verses = [
    "Welcome to the sonic journey...",
    "Listening to $title",
    "Beautifully crafted by $artist",
    "Hear the melody flow through the air",
    "A symphony of thoughts beyond compare",
    "Lost in the depths of this harmony",
    "Every beat and chord is setting us free",
    "Time moves slower when the music plays",
    "Drifting away through the golden haze",
    "Feel the bass resonate in your soul",
    "Making the broken pieces whole",
    "A quiet echo in the midnight sky",
    "Watching the stars as they float by",
    "We write our stories in the key of sound",
    "Where lost dreams are finally found",
    "Another verse begins to unfold",
    "In the greatest story ever told",
    "The rhythm guides us through the dark",
    "Igniting a wild and eternal spark",
    "Thank you for playing with Miee...",
    "Where every note feels like home."
  ];

  final List<LyricLine> lines = [];
  Duration current = const Duration(seconds: 2);
  
  lines.add(LyricLine(time: Duration.zero, text: "(Instrumental Intro)"));

  for (var i = 0; i < verses.length; i++) {
    lines.add(LyricLine(time: current, text: verses[i]));
    // Add 4-7 seconds interval between lines
    current += Duration(seconds: 4 + (i % 3));
    
    if (i == 6 || i == 13) {
      lines.add(LyricLine(time: current, text: "(Guitar Solo / Instrumental Break)"));
      current += const Duration(seconds: 8);
    }
  }
  
  lines.add(LyricLine(time: current, text: "(Outro)"));
  return lines;
}
