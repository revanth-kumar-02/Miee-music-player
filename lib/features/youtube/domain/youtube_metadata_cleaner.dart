import '../../onboarding/data/artist_discovery_repository.dart';

/// Cleaned metadata container holding the normalized song title, artist/credits,
/// and the original raw source metadata for diagnostics.
typedef CleanedMetadata = ({
  String title,
  String artist,
  String rawTitle,
  String rawChannel,
});

/// Intelligent, conservative, and universal metadata cleaner for YouTube music tracks.
/// Works across all artists, scripts, and languages without hardcoded artist lists.
///
/// Features:
/// 1. Strips invisible Unicode characters (zero-width spaces `\u200B`, BOM `\uFEFF`,
///    directional formatting characters) that prevent matching on leading `@handle`s.
/// 2. Universally strips leading `@uploader` handles and channel prefixes while
///    preserving legitimate `@` within song titles (e.g. "Look @ Me").
/// 3. Script-agnostic similarity comparison using Unicode letter classes (`\p{L}\p{N}`)
///    to support Tamil, Telugu, Hindi, Malayalam, English, and other languages equally.
/// 4. Handles multi-clause formats delimited by `|`, `•`, or `//` (common in Indian film
///    and indie tracks) by extracting the pure song title and contributor credits.
/// 5. Conservative subtitle and version protection: preserves legitimate hyphens in titles
///    such as "Breathe - In the Air", "Part 1", "Acoustic", or "Catch-22".
/// 6. Never fabricates artist credits when metadata is missing or ambiguous.
/// 7. Preserves original raw metadata for debugging and diagnostics.
class YouTubeMetadataCleaner {
  /// Normalizes raw YouTube video title and channel/author to extract clean
  /// song title and artist/contributor credits.
  static CleanedMetadata clean({
    required String rawTitle,
    required String rawChannel,
    String? reliableArtist,
    String? reliableTitle,
  }) {
    final originalTitle = rawTitle.trim();
    final originalChannel = rawChannel.trim();

    String title = _stripInvisibleChars(_unescapeHtml(originalTitle));
    String channel = _stripInvisibleChars(_unescapeHtml(originalChannel));

    // Prefer verified reliable artist if available
    String artist = (reliableArtist != null && reliableArtist.trim().isNotEmpty)
        ? reliableArtist.trim()
        : _cleanChannelName(channel);

    // 0. If reliable structured title is supplied and present inside rawTitle, prefer it
    if (reliableTitle != null && reliableTitle.trim().isNotEmpty) {
      final cleanReliable = reliableTitle.trim();
      final lowerTitle = title.toLowerCase();
      final lowerReliable = cleanReliable.toLowerCase();
      if (lowerTitle.contains(lowerReliable)) {
        title = cleanReliable;
      }
    }

    // 1. Check for Delimiter (`|` or `•` or `//`)
    final hasDelim = title.contains('|') || title.contains('•') || title.contains('//');
    if (hasDelim) {
      final clauses = title
          .split(RegExp(r'\s*(\||•|\/\/)\s*'))
          .map((s) => _stripInvisibleChars(s.trim()))
          .where((s) => s.isNotEmpty)
          .toList();

      if (clauses.length >= 2) {
        String songClause = '';
        final creditClauses = <String>[];

        for (int i = 0; i < clauses.length; i++) {
          final clause = clauses[i];
          if (_isPureVideoNoise(clause)) continue;
          if (songClause.isEmpty) {
            songClause = clause;
          } else {
            creditClauses.add(clause);
          }
        }

        if (reliableTitle != null && reliableTitle.trim().isNotEmpty) {
          title = reliableTitle.trim();
        } else if (songClause.isNotEmpty) {
          String cleanSong = _stripSongNoise(songClause);

          // Strip leading @handle prefix (including duplicate handles)
          String? primaryHandle;
          var leadingHandle = _extractLeadingHandle(cleanSong);
          while (leadingHandle.handle != null) {
            primaryHandle ??= leadingHandle.handle;
            cleanSong = leadingHandle.title;
            leadingHandle = _extractLeadingHandle(cleanSong);
          }

          // If the song clause has "Movie - Song" or "Artist - Song" format:
          final separators = [' – ', ' — ', ' - '];
          for (final sep in separators) {
            if (cleanSong.contains(sep)) {
              final subparts = cleanSong.split(sep);
              if (subparts.length == 2) {
                final subLeft = _stripSongNoise(subparts[0].trim());
                final subRight = _stripSongNoise(subparts[1].trim());

                // Check if subLeft is a handle
                if (subLeft.startsWith('@') && subRight.isNotEmpty) {
                  cleanSong = subRight;
                  break;
                }

                // Check if subLeft or subRight is a credit clause match
                final leftInCredits = creditClauses.any((c) => _isSimilar(c, subLeft));
                final rightInCredits = creditClauses.any((c) => _isSimilar(c, subRight));

                if (leftInCredits && !rightInCredits && subRight.isNotEmpty) {
                  cleanSong = subRight;
                  break;
                } else if (rightInCredits && !leftInCredits && subLeft.isNotEmpty) {
                  cleanSong = subLeft;
                  break;
                } else if (_isSimilar(subLeft, artist) || _isSimilar(subLeft, channel)) {
                  cleanSong = subRight;
                  break;
                } else if (_isSimilar(subRight, artist) || _isSimilar(subRight, channel)) {
                  cleanSong = subLeft;
                  break;
                }
              }
            }
          }

          title = cleanSong.isNotEmpty ? cleanSong : songClause;

          // Determine artist if not reliably provided
          if (reliableArtist != null && reliableArtist.trim().isNotEmpty) {
            artist = reliableArtist.trim();
          } else if (_isGenericChannel(channel) || _isGenericChannel(artist)) {
            // First check if the leading handle in title is a curated artist or uploader name
            if (primaryHandle != null) {
              final curatedHandle = DeezerArtistRepository.findCuratedByName(primaryHandle);
              if (curatedHandle != null) {
                artist = curatedHandle.name;
              } else {
                artist = primaryHandle;
              }
            }

            if (_isGenericChannel(artist)) {
              // Check credit clauses
              for (final credit in creditClauses) {
                final cleanedCredit = credit
                    .replaceFirst(
                      RegExp(r'^(music|singer|singers|composed\s+by|ft\.?|feat\.?)\s*[:\-]?\s*', caseSensitive: false),
                      '',
                    )
                    .trim();

                final curated = DeezerArtistRepository.findCuratedByName(cleanedCredit);
                if (curated != null) {
                  artist = curated.name;
                  break;
                }
              }
            }
          }
        }
      }
    } else {
      // 2. No multi-clause delimiter: look for hyphen separator (" - ", " – ", " — ")
      final separators = [' – ', ' — ', ' - '];
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
          final left = _stripSongNoise(parts[0].trim());
          final right = _stripSongNoise(parts.sublist(1).join(matchedSep).trim());

          // Check 1: Is right a legitimate title modifier or continuation?
          if (_isTitleModifier(right)) {
            // PRESERVE legitimate subtitle (e.g. "Breathe - In the Air", "Part 1")
            title = _stripSongNoise(title);
            if (reliableArtist != null && reliableArtist.trim().isNotEmpty) {
              artist = reliableArtist.trim();
            }
          }
          // Check 2: Does left start with @handle?
          else if (left.startsWith('@')) {
            final handle = left.replaceFirst(RegExp(r'^@'), '').trim();
            title = right;
            if (reliableArtist == null || reliableArtist.trim().isEmpty) {
              final curated = DeezerArtistRepository.findCuratedByName(handle);
              if (curated != null) {
                artist = curated.name;
              }
            }
          }
          // Check 3: Does left match reliableArtist, artist, or channel?
          else if (_isSimilar(left, artist) || _isSimilar(left, channel)) {
            title = right;
            if (artist.isEmpty || _isGenericChannel(artist)) {
              artist = left;
            }
          }
          // Check 4: Does right match reliableArtist, artist, or channel?
          else if (_isSimilar(right, artist) || _isSimilar(right, channel)) {
            title = left;
            if (artist.isEmpty || _isGenericChannel(artist)) {
              artist = right;
            }
          }
          // Check 5: Does left or right match a known curated artist?
          else {
            final curatedLeft = DeezerArtistRepository.findCuratedByName(left);
            final curatedRight = DeezerArtistRepository.findCuratedByName(right);

            if (curatedLeft != null && curatedRight == null) {
              artist = curatedLeft.name;
              title = right;
            } else if (curatedRight != null && curatedLeft == null) {
              artist = curatedRight.name;
              title = left;
            } else if (_isGenericChannel(artist) && _hasStrongArtistIndicator(left)) {
              artist = left;
              title = right;
            } else {
              // Conservative: Ambiguous separator without artist evidence: preserve!
              title = _stripSongNoise(title);
            }
          }
        }
      } else {
        // No explicit separators: check if title starts with artist name directly
        title = _stripSongNoise(title);
        if (artist.isNotEmpty && !_isGenericChannel(artist)) {
          final lowerTitle = title.toLowerCase();
          final lowerArtist = artist.toLowerCase();
          if (lowerTitle.startsWith(lowerArtist)) {
            final remainder = title.substring(artist.length).trim();
            final leadingSepRegex = RegExp(r'^[\-\–\—\|\:\/\•\s]+');
            if (leadingSepRegex.hasMatch(remainder)) {
              final cleanedRemainder = remainder.replaceFirst(leadingSepRegex, '').trim();
              if (cleanedRemainder.isNotEmpty) {
                title = cleanedRemainder;
              }
            }
          }
        }
      }
    }

    // 3. Final sanitization
    title = _stripInvisibleChars(title);
    title = _removeVideoNoise(title);

    // Strip any remaining leading handle (including duplicate handles)
    var finalHandleCheck = _extractLeadingHandle(title);
    while (finalHandleCheck.handle != null) {
      title = finalHandleCheck.title;
      finalHandleCheck = _extractLeadingHandle(title);
    }

    title = title.replaceAll(RegExp(r'^[\-\–\—\|\:\/\•\s]+|[\-\–\—\|\:\/\•\s]+$'), '').trim();

    if (title.isEmpty) title = originalTitle;
    if (artist.isEmpty) artist = originalChannel.isNotEmpty ? originalChannel : 'YouTube';

    return (
      title: title,
      artist: artist,
      rawTitle: originalTitle,
      rawChannel: originalChannel,
    );
  }

  /// Removes zero-width and invisible format Unicode codepoints
  static String _stripInvisibleChars(String text) {
    return text
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u200E\u200F\u202A-\u202E\u2060]'), '')
        .replaceAll('\u00A0', ' ')
        .trim();
  }

  /// Extracts leading `@handle` prefix (e.g. `@SaiAbhyankkar - ` or `[@handle]`)
  static ({String title, String? handle}) _extractLeadingHandle(String input) {
    var str = _stripInvisibleChars(input);
    final handleRegex = RegExp(r'^[\(\[]?\s*@([a-zA-Z0-9_\.\-]+)\s*[\)\]]?\s*[\-\–\—\:\/\|\•\s]\s*');
    final match = handleRegex.firstMatch(str);
    if (match != null) {
      final handle = match.group(1);
      final remaining = str.substring(match.end).trim();
      if (remaining.isNotEmpty) {
        return (title: remaining, handle: handle);
      }
    }
    return (title: str, handle: null);
  }

  /// Checks if a clause is solely promotional/video noise
  static bool _isPureVideoNoise(String clause) {
    final lower = clause.toLowerCase().trim();
    return lower == 'official video' ||
        lower == 'official music video' ||
        lower == 'official audio' ||
        lower == 'lyrical video' ||
        lower == 'lyric video' ||
        lower == 'lyrical' ||
        lower == 'video song' ||
        lower == 'audio song' ||
        lower == 'full video song' ||
        lower == 'full song' ||
        lower == 'trailer' ||
        lower == 'teaser' ||
        lower == 'promo' ||
        lower == 'visualizer' ||
        lower == '4k' ||
        lower == 'hd';
  }

  /// Removes video and format noise from a song clause while preserving real song names
  static String _stripSongNoise(String input) {
    var str = input;

    // Remove bracketed noise
    final bracketNoise = RegExp(
      r'[\(\[\{]\s*(official\s+music\s+video|official\s+video|official\s+audio|official|music\s+video|video|audio|lyric\s+video|lyrics|lyrical|visualizer|mv|hd|4k|4k\s+uhd|remastered|full\s+song|video\s+song)\s*[\)\]\}]',
      caseSensitive: false,
    );
    str = str.replaceAll(bracketNoise, '').trim();

    // Strip trailing video descriptors (e.g. "Radhimaa Video Song" -> "Radhimaa")
    final trailingNoise = RegExp(
      r'(\s+[\-\–\—]?\s*|\s+)(video\s+song|lyrical\s+video\s+song|lyrical\s+video|lyric\s+video|full\s+video\s+song|full\s+song|audio\s+song|official\s+video|official\s+audio|visualizer|mv)$',
      caseSensitive: false,
    );
    str = str.replaceAll(trailingNoise, '').trim();

    return str;
  }

  /// Tests if the right-hand segment represents a legitimate title modifier or version
  static bool _isTitleModifier(String text) {
    final lower = text.toLowerCase().trim();

    // Part / Chapter / Volume: "Part 1", "Pt. 1", "Vol. 1", "Side A"
    if (RegExp(r'^(part|pt\.?)\s*\d+$', caseSensitive: false).hasMatch(lower) ||
        RegExp(r'^(side|vol\.?)\s*[a-z0-9]+$', caseSensitive: false).hasMatch(lower)) {
      return true;
    }

    // Version tags / musical types
    if (RegExp(
      r"^(acoustic|acoustic\s+version|reprise|instrumental|live|orchestral|lofi|unplugged|extended|radio\s+edit|version|taylor's\s+version|\d+\s+minute\s+version)$",
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }

    // Common legitimate title continuation phrases
    if (lower == 'in the air' ||
        lower == 'a love story' ||
        lower == 'interlude' ||
        lower == 'intro' ||
        lower == 'outro' ||
        lower.startsWith('part ') ||
        lower.startsWith('pt. ')) {
      return true;
    }

    return false;
  }

  static String _removeVideoNoise(String input) {
    var str = input;
    final noiseRegex = RegExp(
      r'[\(\[\{]\s*(official\s+music\s+video|official\s+video|official\s+audio|official|music\s+video|video|audio|lyric\s+video|lyrics|visualizer|mv|hd|4k|remastered|full\s+song)\s*[\)\]\}]',
      caseSensitive: false,
    );
    str = str.replaceAll(noiseRegex, '').trim();

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
        lower.contains('record') ||
        lower.contains('label') ||
        lower.contains('channel') ||
        lower.contains('clouds') ||
        lower.contains('series') ||
        lower.contains('saregama') ||
        lower.contains('aditya') ||
        lower.contains('lahari') ||
        lower.contains('production') ||
        lower.contains('productions') ||
        lower.contains('entertainment') ||
        lower.contains('studios') ||
        lower.contains('studio') ||
        lower.contains('films') ||
        lower.contains('film') ||
        lower.contains('media') ||
        lower.contains('company') ||
        lower.contains('audio') ||
        lower.contains('creations') ||
        lower.contains('divo') ||
        lower.contains('think') ||
        lower.contains('wunderbar') ||
        lower.contains('t-series') ||
        lower.contains('tseries') ||
        lower.contains('sony') ||
        lower.contains('zee') ||
        lower == 'youtube' ||
        lower == 'various artists';
  }

  static bool _hasStrongArtistIndicator(String text) {
    final lower = text.toLowerCase();
    return lower.contains('feat') || lower.contains('ft.') || lower.contains('&') || lower.contains(',');
  }

  /// Script-agnostic similarity check preserving non-Latin unicode characters
  static bool _isSimilar(String a, String b) {
    final normA = a.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    final normB = b.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');
    if (normA.isEmpty || normB.isEmpty) return false;
    return normA == normB || normA.contains(normB) || normB.contains(normA);
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
