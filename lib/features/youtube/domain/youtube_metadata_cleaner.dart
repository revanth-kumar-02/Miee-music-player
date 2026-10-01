/// Utility class for cleaning YouTube video titles and channel/author names.
/// Extracts clean song title and artist name without duplicating artist inside title.
class YouTubeMetadataCleaner {
  /// Cleans raw YouTube video title and channel/author to extract separate song title and artist name.
  static ({String title, String artist}) clean({
    required String rawTitle,
    required String rawChannel,
  }) {
    String title = _unescapeHtml(rawTitle.trim());
    String channel = _unescapeHtml(rawChannel.trim());

    // 1. Remove video noise from title e.g. "(Official Audio)", "[Official Music Video]"
    title = _removeVideoNoise(title);

    // 2. Clean channel name e.g. "Lana Del Rey - Topic" -> "Lana Del Rey", "LanaDelReyVEVO" -> "Lana Del Rey"
    String artist = _cleanChannelName(channel);

    // 3. Look for explicit title separators: " – ", " — ", " - ", " | ", " : "
    final separators = [' – ', ' — ', ' - ', ' | ', ' : '];
    String? matchedSep;
    for (final sep in separators) {
      if (title.contains(sep)) {
        matchedSep = sep;
        break;
      }
    }

    if (matchedSep != null) {
      final parts = title.split(matchedSep);
      if (parts.length >= 2) {
        final left = parts[0].trim();
        final right = parts.sublist(1).join(matchedSep).trim();

        // Case A: Left part matches or is similar to channel/artist name
        if (_isSimilar(left, artist) || _isSimilar(left, channel)) {
          title = right;
          if (artist.isEmpty || _isGenericChannel(artist)) {
            artist = left;
          }
        }
        // Case B: Right part matches or is similar to channel/artist name
        else if (_isSimilar(right, artist) || _isSimilar(right, channel)) {
          title = left;
          if (artist.isEmpty || _isGenericChannel(artist)) {
            artist = right;
          }
        }
        // Case C: Channel name is generic (e.g. "YouTube Music", "7clouds"), assume "Artist - Song" format
        else if (_isGenericChannel(artist) && left.isNotEmpty && right.isNotEmpty) {
          artist = left;
          title = right;
        }
        // Case D: Title starts with artist name even without exact match
        else if (_startsWithArtist(left, artist)) {
          title = right;
        }
      }
    } else {
      // If no explicit separator with spaces, check if title starts with artist name directly
      if (artist.isNotEmpty && !_isGenericChannel(artist)) {
        final lowerTitle = title.toLowerCase();
        final lowerArtist = artist.toLowerCase();
        if (lowerTitle.startsWith(lowerArtist)) {
          final remainder = title.substring(artist.length).trim();
          final leadingSepRegex = RegExp(r'^[\-\–\—\|\:\s]+');
          if (leadingSepRegex.hasMatch(remainder)) {
            final cleanedRemainder = remainder.replaceFirst(leadingSepRegex, '').trim();
            if (cleanedRemainder.isNotEmpty) {
              title = cleanedRemainder;
            }
          }
        }
      }
    }

    // Final fallback
    if (title.isEmpty) title = rawTitle;
    if (artist.isEmpty) artist = rawChannel.isNotEmpty ? rawChannel : 'YouTube';

    return (title: title, artist: artist);
  }

  static String _removeVideoNoise(String input) {
    var str = input;
    // Regex matching parentheses or brackets containing official video/audio noise
    final noiseRegex = RegExp(
      r'[\(\[\{]\s*(official\s+music\s+video|official\s+video|official\s+audio|official|music\s+video|video|audio|lyric\s+video|lyrics|visualizer|mv|hd|4k|remastered|full\s+song)\s*[\)\]\}]',
      caseSensitive: false,
    );
    str = str.replaceAll(noiseRegex, '').trim();

    // Also strip trailing noise if present without brackets
    final trailingNoiseRegex = RegExp(
      r'\s+(official\s+music\s+video|official\s+video|official\s+audio|lyric\s+video|visualizer|mv)$',
      caseSensitive: false,
    );
    str = str.replaceAll(trailingNoiseRegex, '').trim();

    return str;
  }

  static String _cleanChannelName(String channel) {
    var str = channel.trim();
    if (str.endsWith(' - Topic')) {
      str = str.substring(0, str.length - 8).trim();
    } else if (str.endsWith('Topic')) {
      str = str.substring(0, str.length - 5).trim();
    }
    if (str.endsWith('VEVO') || str.endsWith('Vevo')) {
      str = str.substring(0, str.length - 4).trim();
    }
    return str;
  }

  static bool _isGenericChannel(String channel) {
    final lower = channel.toLowerCase();
    return lower.contains('vevo') ||
        lower.contains('topic') ||
        lower.contains('music') ||
        lower.contains('records') ||
        lower.contains('label') ||
        lower.contains('channel') ||
        lower.contains('clouds') ||
        lower == 'youtube' ||
        lower == 'various artists';
  }

  static bool _isSimilar(String a, String b) {
    final normA = a.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normB = b.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (normA.isEmpty || normB.isEmpty) return false;
    return normA == normB || normA.contains(normB) || normB.contains(normA);
  }

  static bool _startsWithArtist(String left, String artist) {
    final normLeft = left.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final normArtist = artist.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normLeft.startsWith(normArtist) || normArtist.startsWith(normLeft);
  }

  static String _unescapeHtml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
