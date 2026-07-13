/// Model representing a single line of lyrics with its timestamp.
class LyricLine {
  final Duration time;
  final String text;

  LyricLine({
    required this.time,
    required this.text,
  });
}

/// Parser for standard `.lrc` formatted lyrics files.
class LyricParser {
  /// Parses standard LRC formatted [lrcText] string.
  ///
  /// Supports multi-timestamp lines, e.g. `[00:12.30][00:15.50] Hello world!`
  static List<LyricLine> parse(String lrcText) {
    final lines = lrcText.split('\n');
    final List<LyricLine> lyrics = [];
    final regExp = RegExp(r'\[(\d+):(\d+)(?:\.(\d+))?\]');

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      // Extract all timestamps in this line
      final matches = regExp.allMatches(line);
      if (matches.isEmpty) continue;

      // Get the lyric text (which is after the last timestamp match)
      final lastMatch = matches.last;
      final text = line.substring(lastMatch.end).trim();

      for (var match in matches) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final millisecondsStr = match.group(3) ?? '00';
        
        // Handle 2-digit vs 3-digit milliseconds (e.g. .25 -> 250ms, .025 -> 25ms)
        final milliseconds = int.parse(millisecondsStr.padRight(3, '0').substring(0, 3));
        
        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: milliseconds,
        );
        lyrics.add(LyricLine(time: duration, text: text));
      }
    }

    // Sort lyrics by timestamp ascending
    lyrics.sort((a, b) => a.time.compareTo(b.time));
    return lyrics;
  }
}
