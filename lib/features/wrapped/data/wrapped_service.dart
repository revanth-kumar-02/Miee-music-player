import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import '../../../core/storage/adapters/playback_history_entry.dart';
import '../../../core/storage/adapters/track_hive_model.dart';
import '../../../core/storage/hive_boxes.dart';
import '../../../shared/models/track.dart';
import '../domain/wrapped_models.dart';

class WrappedService {
  static const String prefAccountCreatedKey = 'account_created_at';

  /// Resolves the user's authoritative account creation date.
  /// Falls back to Profile createdDate, earliest playback history entry, or sets DateTime.now().
  static DateTime getAccountStartDate() {
    try {
      if (Hive.isBoxOpen(HiveBoxes.preferences)) {
        final box = Hive.box<dynamic>(HiveBoxes.preferences);
        final raw = box.get(prefAccountCreatedKey);
        if (raw != null) {
          final parsed = DateTime.tryParse(raw.toString());
          if (parsed != null) return parsed;
        }
      }
    } catch (_) {}

    try {
      if (Hive.isBoxOpen(HiveBoxes.profile)) {
        final profileBox = Hive.box<dynamic>(HiveBoxes.profile);
        final data = profileBox.get('active_profile');
        if (data is Map && data['createdDate'] != null) {
          final parsed = DateTime.tryParse(data['createdDate'].toString());
          if (parsed != null) {
            setAccountStartDate(parsed);
            return parsed;
          }
        }
      }
    } catch (_) {}

    try {
      if (Hive.isBoxOpen(HiveBoxes.playbackHistory)) {
        final historyBox = Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory);
        if (historyBox.isNotEmpty) {
          DateTime earliest = historyBox.values.first.startTime;
          for (final entry in historyBox.values) {
            if (entry.startTime.isBefore(earliest)) {
              earliest = entry.startTime;
            }
          }
          setAccountStartDate(earliest);
          return earliest;
        }
      }
    } catch (_) {}

    final now = DateTime.now();
    setAccountStartDate(now);
    return now;
  }

  /// Sets and persists the user's account start date.
  static void setAccountStartDate(DateTime date) {
    try {
      if (Hive.isBoxOpen(HiveBoxes.preferences)) {
        Hive.box<dynamic>(HiveBoxes.preferences).put(prefAccountCreatedKey, date.toIso8601String());
      }
    } catch (_) {}
  }

  /// Computes the complete 10-slide Wrapped statistical breakdown from stored playback entries.
  static WrappedSummary computeSummary({
    List<PlaybackHistoryEntry>? customEntries,
    bool forceSample = false,
    String timeframe = 'year', // 'year', 'month', 'anniversary', 'all'
    int? targetYear,
    DateTime? startDate,
    DateTime? endDate,
    int anniversaryYear = 1,
  }) {
    List<PlaybackHistoryEntry> rawList;
    if (customEntries != null) {
      rawList = customEntries;
    } else {
      try {
        if (Hive.isBoxOpen(HiveBoxes.playbackHistory)) {
          rawList = Hive.box<PlaybackHistoryEntry>(HiveBoxes.playbackHistory).values.toList();
        } else {
          rawList = [];
        }
      } catch (_) {
        rawList = [];
      }
    }

    final now = DateTime.now();
    final year = targetYear ?? now.year;

    // 1. Explicit demo/test sample request
    if (forceSample) {
      return _generateSampleWrapped(
        hasSufficient: true,
        timeframe: timeframe,
        year: year,
        anniversaryYear: anniversaryYear,
      );
    }

    // 2. Filter entries according to timeframe with strict boundaries
    final filtered = rawList.where((e) {
      if (e.startTime.isAfter(now.add(const Duration(minutes: 5)))) {
        // Discard future glitch timestamps
        return false;
      }
      if (startDate != null && e.startTime.isBefore(startDate)) {
        return false;
      }
      if (endDate != null && e.startTime.isAfter(endDate)) {
        return false;
      }
      if (startDate == null && endDate == null) {
        if (timeframe == 'month') {
          return e.startTime.isAfter(now.subtract(const Duration(days: 30)));
        } else if (timeframe == 'year') {
          return e.startTime.year == year;
        }
      }
      return true;
    }).toList();

    // 3. If history is empty, return an honest empty state without fabricated data
    if (filtered.isEmpty) {
      return _buildEmptySummary(
        year: year,
        timeframe: timeframe,
        anniversaryYear: anniversaryYear,
      );
    }

    // 4. Sort entries chronologically to detect distinct listening sessions accurately
    filtered.sort((a, b) => a.startTime.compareTo(b.startTime));

    int totalSec = 0;
    final Map<String, _TrackAgg> trackAggMap = {};
    final Map<String, _ArtistAgg> artistAggMap = {};
    final Map<String, _AlbumAgg> albumAggMap = {};
    final List<int> hourBuckets = List.filled(24, 0);
    final List<int> dayBuckets = List.filled(7, 0);
    final Set<String> distinctDays = {};
    final Map<String, int> dailyTrackCount = {};
    final Map<int, List<PlaybackHistoryEntry>> monthBuckets = {};

    // Track session continuity per track to avoid inflating play count on periodic flushes
    final Map<String, DateTime> lastSessionPerTrack = {};

    for (final entry in filtered) {
      final track = entry.track;
      final durSec = _parseDurationSec(track.duration);
      final entryListenedSec = (durSec * (entry.completionPercent > 0 ? entry.completionPercent : 1.0)).round();
      final effectiveSec = entryListenedSec > 0 ? entryListenedSec : 180;
      totalSec += effectiveSec;

      final trackKey = track.id.isNotEmpty ? track.id : track.title;
      final prevTime = lastSessionPerTrack[trackKey];
      final isNewSession = prevTime == null ||
          entry.startTime.difference(prevTime).inSeconds > (durSec > 0 ? durSec + 30 : 210);

      lastSessionPerTrack[trackKey] = entry.startTime;

      // Track Aggregation
      final existingTrack = trackAggMap[trackKey];
      if (existingTrack == null) {
        trackAggMap[trackKey] = _TrackAgg(
          trackId: track.id,
          title: track.title,
          artist: track.artist,
          imageUrl: track.imageUrl.isNotEmpty ? track.imageUrl : null,
          playCount: 1,
          totalSec: effectiveSec,
        );
      } else {
        if (isNewSession) {
          existingTrack.playCount++;
        }
        existingTrack.totalSec += effectiveSec;
        if (existingTrack.imageUrl == null && track.imageUrl.isNotEmpty) {
          existingTrack.imageUrl = track.imageUrl;
        }
      }

      // Artist Aggregation
      final artistName = track.artist.trim().isNotEmpty ? track.artist.trim() : 'Unknown Artist';
      final existingArtist = artistAggMap[artistName];
      if (existingArtist == null) {
        artistAggMap[artistName] = _ArtistAgg(
          name: artistName,
          playCount: 1,
          totalSec: effectiveSec,
          imageUrl: track.imageUrl.isNotEmpty ? track.imageUrl : null,
        );
      } else {
        if (isNewSession) {
          existingArtist.playCount++;
        }
        existingArtist.totalSec += effectiveSec;
        if (existingArtist.imageUrl == null && track.imageUrl.isNotEmpty) {
          existingArtist.imageUrl = track.imageUrl;
        }
      }

      // Album Aggregation: only if genuine album folder name or tag exists
      String? albumName;
      if (track.filePath != null && track.filePath!.isNotEmpty) {
        final normalized = track.filePath!.replaceAll('\\', '/');
        final segments = normalized.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.length >= 2) {
          final candidate = segments[segments.length - 2];
          final lower = candidate.toLowerCase();
          if (!lower.contains('download') &&
              !lower.contains('music') &&
              !lower.contains('storage') &&
              !lower.contains('emulated') &&
              !lower.contains('0') &&
              candidate.length >= 2) {
            albumName = candidate;
          }
        }
      }

      if (albumName != null && albumName.isNotEmpty) {
        final existingAlbum = albumAggMap[albumName];
        if (existingAlbum == null) {
          albumAggMap[albumName] = _AlbumAgg(
            title: albumName,
            artist: artistName,
            playCount: 1,
            totalSec: effectiveSec,
            artworkUrl: track.imageUrl.isNotEmpty ? track.imageUrl : null,
          );
        } else {
          if (isNewSession) {
            existingAlbum.playCount++;
          }
          existingAlbum.totalSec += effectiveSec;
          if (existingAlbum.artworkUrl == null && track.imageUrl.isNotEmpty) {
            existingAlbum.artworkUrl = track.imageUrl;
          }
        }
      }

      // Time Distribution
      final hour = entry.startTime.hour;
      hourBuckets[hour]++;

      final weekdayIndex = (entry.startTime.weekday - 1).clamp(0, 6);
      dayBuckets[weekdayIndex]++;

      // Distinct Days & Streak
      final dateKey = '${entry.startTime.year}-${entry.startTime.month.toString().padLeft(2, '0')}-${entry.startTime.day.toString().padLeft(2, '0')}';
      distinctDays.add(dateKey);
      dailyTrackCount[dateKey] = (dailyTrackCount[dateKey] ?? 0) + 1;

      // Month buckets for Timeline (Slide 7)
      final month = entry.startTime.month;
      monthBuckets.putIfAbsent(month, () => []).add(entry);
    }

    // Rank Top Tracks (sorted by play count, then total duration)
    final sortedTracks = trackAggMap.values.toList()
      ..sort((a, b) {
        final cmp = b.playCount.compareTo(a.playCount);
        if (cmp != 0) return cmp;
        return b.totalSec.compareTo(a.totalSec);
      });

    final topTracks = sortedTracks.take(5).toList().asMap().entries.map((entry) {
      final rank = entry.key + 1;
      final item = entry.value;
      return WrappedTrackItem(
        rank: rank,
        trackId: item.trackId,
        title: item.title,
        artist: item.artist,
        imageUrl: item.imageUrl,
        playCount: item.playCount,
        totalMinutes: (item.totalSec / 60).round(),
        musicItem: Track(
          id: item.trackId,
          title: item.title,
          artist: item.artist,
          imageUrl: item.imageUrl ?? '',
          duration: '${(item.totalSec / item.playCount / 60).floor()}:${((item.totalSec / item.playCount) % 60).round().toString().padLeft(2, '0')}',
        ),
      );
    }).toList();

    // Rank Top Artists
    final sortedArtists = artistAggMap.values.toList()
      ..sort((a, b) {
        final cmp = b.playCount.compareTo(a.playCount);
        if (cmp != 0) return cmp;
        return b.totalSec.compareTo(a.totalSec);
      });

    WrappedArtistItem? topArtist;
    if (sortedArtists.isNotEmpty) {
      final first = sortedArtists.first;
      final songsCount = trackAggMap.values.where((t) => t.artist == first.name).length;
      topArtist = WrappedArtistItem(
        rank: 1,
        name: first.name,
        playCount: first.playCount,
        songsCount: songsCount > 0 ? songsCount : 1,
        totalHours: double.parse((first.totalSec / 3600.0).toStringAsFixed(1)),
        imageUrl: first.imageUrl,
        quote: '“ Their music was your constant companion this year. ”',
      );
    }

    // Rank Top Album
    final sortedAlbums = albumAggMap.values.toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));

    WrappedAlbumItem? topAlbum;
    if (sortedAlbums.isNotEmpty) {
      final alb = sortedAlbums.first;
      topAlbum = WrappedAlbumItem(
        title: alb.title,
        artist: alb.artist,
        playCount: alb.playCount,
        totalHours: double.parse((alb.totalSec / 3600.0).toStringAsFixed(1)),
        artworkUrl: alb.artworkUrl,
        quote: '“ Some albums don\'t just play, they stay with you. ”',
      );
    }

    // Longest Streak Calculation
    final sortedDays = distinctDays.toList()..sort();
    int longestStreak = distinctDays.isNotEmpty ? 1 : 0;
    int currentStreak = distinctDays.isNotEmpty ? 1 : 0;
    for (int i = 1; i < sortedDays.length; i++) {
      final prev = DateTime.parse(sortedDays[i - 1]);
      final curr = DateTime.parse(sortedDays[i]);
      if (curr.difference(prev).inDays == 1) {
        currentStreak++;
        if (currentStreak > longestStreak) longestStreak = currentStreak;
      } else if (curr.difference(prev).inDays > 1) {
        currentStreak = 1;
      }
    }

    // Peak Hour
    int maxHourIndex = 0;
    int maxHourCount = -1;
    for (int h = 0; h < 24; h++) {
      if (hourBuckets[h] > maxHourCount) {
        maxHourCount = hourBuckets[h];
        maxHourIndex = h;
      }
    }

    // Peak Day of Week
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    int maxDayIndex = 0;
    int maxDayCount = -1;
    for (int d = 0; d < 7; d++) {
      if (dayBuckets[d] > maxDayCount) {
        maxDayCount = dayBuckets[d];
        maxDayIndex = d;
      }
    }

    // Top Single-Day Spike
    DateTime? topDayDate;
    int topDayCount = 0;
    dailyTrackCount.forEach((dateStr, count) {
      if (count > topDayCount) {
        topDayCount = count;
        topDayDate = DateTime.tryParse(dateStr);
      }
    });

    // Determine Archetype
    final totalPlays = filtered.length;
    final nocturnalPlays = hourBuckets[22] + hourBuckets[23] + hourBuckets[0] + hourBuckets[1] + hourBuckets[2] + hourBuckets[3] + hourBuckets[4];
    final morningPlays = hourBuckets[5] + hourBuckets[6] + hourBuckets[7] + hourBuckets[8] + hourBuckets[9] + hourBuckets[10];
    final topArtistPlays = sortedArtists.isNotEmpty ? sortedArtists.first.playCount : 0;
    final uniqueArtistsCount = artistAggMap.length;

    ListeningArchetype archetype;
    if (totalPlays < 3) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'newcomer');
    } else if (nocturnalPlays / totalPlays >= 0.35) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'midnight');
    } else if (morningPlays / totalPlays >= 0.35) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'curator');
    } else if (topArtistPlays / totalPlays >= 0.40) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'repeat');
    } else if (uniqueArtistsCount / totalPlays >= 0.65) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'explorer');
    } else {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'loyalist');
    }

    // Music Timeline (Slide 7): derived only from actual listening months
    final timelineMilestones = _buildTimelineMilestones(monthBuckets);

    // Languages (Slide 8): real detection from tracks
    final languages = detectLanguagesFromHistory(filtered);

    // Listening Contexts (Slide 9: Time distribution patterns)
    final listeningContexts = _buildListeningContexts(hourBuckets, totalPlays);

    final totalMin = (totalSec / 60).round();
    final totalHours = double.parse((totalMin / 60.0).toStringAsFixed(1));

    String timeframeLabel;
    if (startDate != null && endDate != null) {
      timeframeLabel = 'Year $anniversaryYear Milestone';
    } else if (timeframe == 'month') {
      timeframeLabel = 'Past 30 Days';
    } else if (timeframe == 'all') {
      timeframeLabel = 'All-Time';
    } else {
      timeframeLabel = '$year';
    }

    return WrappedSummary(
      year: year,
      timeframeLabel: timeframeLabel,
      totalMinutes: totalMin > 0 ? totalMin : 1,
      totalHours: totalHours,
      totalTracks: trackAggMap.length,
      totalArtists: artistAggMap.length,
      totalAlbums: albumAggMap.length,
      longestStreakDays: longestStreak,
      totalLanguages: languages.length,
      topTracks: topTracks,
      topArtist: topArtist,
      topAlbum: topAlbum,
      timelineMilestones: timelineMilestones,
      languages: languages,
      listeningContexts: listeningContexts,
      archetype: archetype,
      peakHour: maxHourIndex,
      peakHourLabel: _formatHour(maxHourIndex),
      peakDayName: dayNames[maxDayIndex],
      topDay: topDayDate,
      topDayTrackCount: topDayCount,
      isSampleData: false,
      hasSufficientHistory: filtered.length >= 3,
      anniversaryYear: anniversaryYear,
    );
  }

  static WrappedSummary _buildEmptySummary({
    required int year,
    required String timeframe,
    int anniversaryYear = 1,
  }) {
    final timeframeLabel = timeframe == 'month'
        ? 'Past 30 Days'
        : (timeframe == 'all' ? 'All-Time' : (timeframe == 'anniversary' ? 'Year $anniversaryYear Milestone' : '$year'));

    final newcomerArchetype = ListeningArchetype.allArchetypes.firstWhere(
      (a) => a.id == 'newcomer',
      orElse: () => ListeningArchetype.allArchetypes.first,
    );

    return WrappedSummary(
      year: year,
      timeframeLabel: timeframeLabel,
      totalMinutes: 0,
      totalHours: 0.0,
      totalTracks: 0,
      totalArtists: 0,
      totalAlbums: 0,
      longestStreakDays: 0,
      totalLanguages: 0,
      topTracks: const [],
      topArtist: null,
      topAlbum: null,
      timelineMilestones: const [],
      languages: const [],
      listeningContexts: _buildListeningContexts(List.filled(24, 0), 0),
      archetype: newcomerArchetype,
      peakHour: 0,
      peakHourLabel: '12 AM',
      peakDayName: 'None',
      topDay: null,
      topDayTrackCount: 0,
      isSampleData: false,
      hasSufficientHistory: false,
      anniversaryYear: anniversaryYear,
    );
  }

  static List<WrappedTimelineMilestone> _buildTimelineMilestones(
    Map<int, List<PlaybackHistoryEntry>> monthBuckets,
  ) {
    const monthNames = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final List<WrappedTimelineMilestone> milestones = [];

    final activeMonths = monthBuckets.keys.toList()..sort();
    for (final monthNum in activeMonths) {
      final entries = monthBuckets[monthNum]!;
      if (entries.isEmpty) continue;

      // Find top track in this month
      final Map<String, int> monthTrackPlays = {};
      final Map<String, TrackHiveModel> monthTrackModels = {};

      for (final e in entries) {
        final key = e.track.id.isNotEmpty ? e.track.id : e.track.title;
        monthTrackPlays[key] = (monthTrackPlays[key] ?? 0) + 1;
        monthTrackModels[key] = e.track;
      }

      final sortedMonthTracks = monthTrackPlays.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (sortedMonthTracks.isEmpty) continue;

      final topEntry = sortedMonthTracks.first;
      final topTrack = monthTrackModels[topEntry.key]!;
      final playCount = topEntry.value;
      final monthLabel = monthNames[monthNum];

      milestones.add(
        WrappedTimelineMilestone(
          monthLabel: monthLabel,
          title: topTrack.title,
          description: 'Top track in $monthLabel with $playCount ${playCount == 1 ? "play" : "plays"}.',
          imageUrl: topTrack.imageUrl.isNotEmpty ? topTrack.imageUrl : null,
        ),
      );
    }

    return milestones;
  }

  static List<WrappedLanguageItem> detectLanguagesFromHistory(List<PlaybackHistoryEntry> entries) {
    if (entries.isEmpty) return const [];

    final Map<String, int> langCounts = {};

    for (final entry in entries) {
      final title = entry.track.title.toLowerCase();
      final artist = entry.track.artist.toLowerCase();
      final combined = '$title $artist';

      String detected;

      // 1. Script checks
      if (RegExp(r'[\u0B80-\u0BFF]').hasMatch(combined)) {
        detected = 'Tamil';
      } else if (RegExp(r'[\u0C00-\u0C7F]').hasMatch(combined)) {
        detected = 'Telugu';
      } else if (RegExp(r'[\u0900-\u097F]').hasMatch(combined)) {
        detected = 'Hindi';
      } else if (RegExp(r'[\u0D00-\u0D7F]').hasMatch(combined)) {
        detected = 'Malayalam';
      } else if (RegExp(r'[\u0C80-\u0CFF]').hasMatch(combined)) {
        detected = 'Kannada';
      } else if (RegExp(r'[\u0A00-\u0A7F]').hasMatch(combined)) {
        detected = 'Punjabi';
      } else if (RegExp(r'[\uAC00-\uD7AF\u1100-\u11FF]').hasMatch(combined)) {
        detected = 'Korean';
      } else if (RegExp(r'[\u3040-\u30FF\u4E00-\u9FAF]').hasMatch(combined)) {
        detected = 'Japanese';
      }
      // 2. Keyword checks in title / artist
      else if (RegExp(r'\b(tamil|tamizh)\b').hasMatch(combined)) {
        detected = 'Tamil';
      } else if (RegExp(r'\b(telugu)\b').hasMatch(combined)) {
        detected = 'Telugu';
      } else if (RegExp(r'\b(hindi|bollywood)\b').hasMatch(combined)) {
        detected = 'Hindi';
      } else if (RegExp(r'\b(malayalam)\b').hasMatch(combined)) {
        detected = 'Malayalam';
      } else if (RegExp(r'\b(kannada)\b').hasMatch(combined)) {
        detected = 'Kannada';
      } else if (RegExp(r'\b(punjabi)\b').hasMatch(combined)) {
        detected = 'Punjabi';
      } else if (RegExp(r'\b(spanish|español|latino)\b').hasMatch(combined)) {
        detected = 'Spanish';
      } else if (RegExp(r'\b(k-pop|kpop|bts|blackpink|twice|newjeans)\b').hasMatch(combined)) {
        detected = 'Korean';
      }
      // 3. Known artist mappings
      else if (_isTamilArtist(artist)) {
        detected = 'Tamil';
      } else if (_isTeluguArtist(artist)) {
        detected = 'Telugu';
      } else if (_isHindiArtist(artist)) {
        detected = 'Hindi';
      } else if (_isMalayalamArtist(artist)) {
        detected = 'Malayalam';
      } else if (_isEnglishArtist(artist)) {
        detected = 'English';
      } else {
        detected = 'Other';
      }

      langCounts[detected] = (langCounts[detected] ?? 0) + 1;
    }

    final total = entries.length;
    final sortedLangs = langCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final Map<String, Color> langColors = {
      'Tamil': const Color(0xFF7D9D8B),
      'English': const Color(0xFFC87D6B),
      'Hindi': const Color(0xFFE9C9B7),
      'Telugu': const Color(0xFFA3C4BC),
      'Malayalam': const Color(0xFFD78D9B),
      'Kannada': const Color(0xFF8B4F48),
      'Punjabi': const Color(0xFFD97706),
      'Korean': const Color(0xFF9D8189),
      'Japanese': const Color(0xFF5A4A50),
      'Spanish': const Color(0xFFD4A373),
      'Other': const Color(0xFFB0A8A0),
    };

    int sumPercent = 0;
    final List<WrappedLanguageItem> items = [];

    for (int i = 0; i < sortedLangs.length; i++) {
      final entry = sortedLangs[i];
      int pct = ((entry.value / total) * 100).round();
      if (pct == 0 && entry.value > 0) pct = 1;
      sumPercent += pct;
      items.add(
        WrappedLanguageItem(
          name: entry.key,
          percentage: pct,
          color: langColors[entry.key] ?? const Color(0xFFB0A8A0),
        ),
      );
    }

    // Ensure sum equals 100%
    if (items.isNotEmpty && sumPercent != 100) {
      final diff = 100 - sumPercent;
      final first = items.first;
      items[0] = WrappedLanguageItem(
        name: first.name,
        percentage: (first.percentage + diff).clamp(1, 100),
        color: first.color,
      );
    }

    return items;
  }

  static bool _isTamilArtist(String a) {
    const artists = [
      'a.r. rahman', 'ar rahman', 'ilaiyaraaja', 'ilayaraja', 'anirudh', 'anirudh ravichander',
      'yuvan', 'yuvan shankar raja', 'harris jayaraj', 'sid sriram', 'd. imman', 'imman',
      'santhosh narayanan', 'vijay antony', 'g.v. prakash', 'gv prakash', 'vidyasagar',
      'deva', 'hiphop tamizha', 'sean roldan', 'pradeep kumar', 'dhibu ninan thomas',
      'sam c.s.', 'sam cs', 's. p. balasubrahmanyam', 'spb', 'hariharan', 'unni menon'
    ];
    return artists.any((art) => a.contains(art));
  }

  static bool _isTeluguArtist(String a) {
    const artists = [
      'devi sri prasad', 'dsp', 'thaman', 's. thaman', 'm.m. keeravaani', 'keeravani',
      'mickey j. meyer', 'mani sharma', 'chaitan bharadwaj', 'radhan', 'anup rubens',
      'ghibran', 'ram miriyala', 'anurag kulkarni'
    ];
    return artists.any((art) => a.contains(art));
  }

  static bool _isHindiArtist(String a) {
    const artists = [
      'arijit singh', 'shreya ghoshal', 'pritam', 'neha kakkar', 'badshah', 'sonu nigam',
      'vishal-shekhar', 'vishal shekhar', 'sachin-jigar', 'sachin jigar', 'amit trivedi',
      'atif aslam', 'kk', 'mohit chauhan', 'armaan malik', 'jubin nautiyal', 'alka yagnik',
      'kumar sanu', 'udit narayan', 'sunidhi chauhan', 'mithoon', 'yo yo honey singh'
    ];
    return artists.any((art) => a.contains(art));
  }

  static bool _isMalayalamArtist(String a) {
    const artists = [
      'sushin shyam', 'shaan rahman', 'gopi sundar', 'bijibal', 'deepak dev',
      'jakes bejoy', 'heshem abdul wahab', 'k.j. yesudas', 'yesudas', 'k.s. chithra'
    ];
    return artists.any((art) => a.contains(art));
  }

  static bool _isEnglishArtist(String a) {
    const artists = [
      'taylor swift', 'ed sheeran', 'the weeknd', 'drake', 'billie eilish', 'adele',
      'coldplay', 'bruno mars', 'dua lipa', 'post malone', 'justin bieber', 'rihanna',
      'eminem', 'beyonce', 'katy perry', 'maroon 5', 'imagine dragons', 'ariana grande',
      'shawn mendes', 'charlie puth', 'olivia rodrigo', 'harry styles', 'kendrick lamar'
    ];
    return artists.any((art) => a.contains(art));
  }

  static List<WrappedContextItem> _buildListeningContexts(List<int> hourBuckets, int totalPlays) {
    if (totalPlays <= 0) {
      return const [
        WrappedContextItem(
          label: 'At Home',
          subLabel: 'Evening & Unwind (6 PM - 10 PM)',
          percentage: 0,
          icon: Icons.chair_rounded,
        ),
        WrappedContextItem(
          label: 'While Studying',
          subLabel: 'Focus & Productivity (12 PM - 6 PM)',
          percentage: 0,
          icon: Icons.laptop_mac_rounded,
        ),
        WrappedContextItem(
          label: 'During Travel',
          subLabel: 'Morning Commute (6 AM - 12 PM)',
          percentage: 0,
          icon: Icons.headphones_rounded,
        ),
        WrappedContextItem(
          label: 'Late Night',
          subLabel: 'Midnight Sanctuary (11 PM - 5 AM)',
          percentage: 0,
          icon: Icons.nightlight_round,
        ),
        WrappedContextItem(
          label: 'Work / Others',
          subLabel: 'Ambient Moments',
          percentage: 0,
          icon: Icons.coffee_rounded,
        ),
      ];
    }

    // Evening: 18-22
    int evening = 0;
    for (int h = 18; h <= 22; h++) {
      evening += hourBuckets[h];
    }
    // Afternoon: 12-17
    int afternoon = 0;
    for (int h = 12; h <= 17; h++) {
      afternoon += hourBuckets[h];
    }
    // Morning: 06-11
    int morning = 0;
    for (int h = 6; h <= 11; h++) {
      morning += hourBuckets[h];
    }
    // Late Night: 23-05
    int lateNight = (hourBuckets[23] + hourBuckets[0] + hourBuckets[1] +
        hourBuckets[2] + hourBuckets[3] + hourBuckets[4] + hourBuckets[5]);

    int pEvening = ((evening / totalPlays) * 100).round();
    int pAfternoon = ((afternoon / totalPlays) * 100).round();
    int pMorning = ((morning / totalPlays) * 100).round();
    int pLateNight = ((lateNight / totalPlays) * 100).round();
    int pOther = (100 - (pEvening + pAfternoon + pMorning + pLateNight)).clamp(0, 100);

    return [
      WrappedContextItem(
        label: 'At Home',
        subLabel: 'Evening & Unwind (6 PM - 10 PM)',
        percentage: pEvening,
        icon: Icons.chair_rounded,
      ),
      WrappedContextItem(
        label: 'While Studying',
        subLabel: 'Focus & Productivity (12 PM - 6 PM)',
        percentage: pAfternoon,
        icon: Icons.laptop_mac_rounded,
      ),
      WrappedContextItem(
        label: 'During Travel',
        subLabel: 'Morning Commute (6 AM - 12 PM)',
        percentage: pMorning,
        icon: Icons.headphones_rounded,
      ),
      WrappedContextItem(
        label: 'Late Night',
        subLabel: 'Midnight Sanctuary (11 PM - 5 AM)',
        percentage: pLateNight,
        icon: Icons.nightlight_round,
      ),
      WrappedContextItem(
        label: 'Work / Others',
        subLabel: 'Ambient Moments',
        percentage: pOther,
        icon: Icons.coffee_rounded,
      ),
    ];
  }

  static String _formatHour(int h) {
    final nextH = (h + 1) % 24;
    final startStr = _format12Hour(h);
    final endStr = _format12Hour(nextH);
    return '$startStr – $endStr';
  }

  static String _format12Hour(int h) {
    if (h == 0) return '12 AM';
    if (h == 12) return '12 PM';
    if (h > 12) return '${h - 12} PM';
    return '$h AM';
  }

  static int _parseDurationSec(String dur) {
    if (dur.isEmpty) return 180;
    final parts = dur.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return m * 60 + s;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return h * 3600 + m * 60 + s;
    }
    return 180;
  }

  static WrappedSummary _generateSampleWrapped({
    required bool hasSufficient,
    required String timeframe,
    required int year,
    int anniversaryYear = 1,
  }) {
    String timeframeLabel = timeframe == 'month'
        ? 'Past 30 Days'
        : (timeframe == 'all' ? 'All-Time' : (timeframe == 'anniversary' ? 'Year $anniversaryYear Milestone' : '$year'));

    final sampleTracks = [
      const WrappedTrackItem(
        rank: 1,
        trackId: 'sample_1',
        title: 'Kaadhal Rojave',
        artist: 'A.R. Rahman',
        imageUrl: 'https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=300',
        playCount: 412,
        totalMinutes: 1373,
        isFavorited: true,
        musicItem: Track(
          id: 'sample_1',
          title: 'Kaadhal Rojave',
          artist: 'A.R. Rahman',
          imageUrl: 'https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=300',
          duration: '04:12',
        ),
      ),
      const WrappedTrackItem(
        rank: 2,
        trackId: 'sample_2',
        title: 'Vaseegara',
        artist: 'Bombay',
        imageUrl: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=300',
        playCount: 368,
        totalMinutes: 1226,
        isFavorited: false,
        musicItem: Track(
          id: 'sample_2',
          title: 'Vaseegara',
          artist: 'Bombay',
          imageUrl: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=300',
          duration: '05:02',
        ),
      ),
      const WrappedTrackItem(
        rank: 3,
        trackId: 'sample_3',
        title: 'Ilaya Nila',
        artist: 'A.R. Rahman',
        imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300',
        playCount: 301,
        totalMinutes: 1003,
        isFavorited: false,
        musicItem: Track(
          id: 'sample_3',
          title: 'Ilaya Nila',
          artist: 'A.R. Rahman',
          imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300',
          duration: '04:35',
        ),
      ),
      const WrappedTrackItem(
        rank: 4,
        trackId: 'sample_4',
        title: 'Munbe Vaa',
        artist: 'Sillunu Oru Kaadhal',
        imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
        playCount: 289,
        totalMinutes: 963,
        isFavorited: false,
        musicItem: Track(
          id: 'sample_4',
          title: 'Munbe Vaa',
          artist: 'Sillunu Oru Kaadhal',
          imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
          duration: '05:58',
        ),
      ),
      const WrappedTrackItem(
        rank: 5,
        trackId: 'sample_5',
        title: 'The Life of Ram',
        artist: '96',
        imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
        playCount: 274,
        totalMinutes: 913,
        isFavorited: false,
        musicItem: Track(
          id: 'sample_5',
          title: 'The Life of Ram',
          artist: '96',
          imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
          duration: '05:46',
        ),
      ),
    ];

    const sampleArtist = WrappedArtistItem(
      rank: 1,
      name: 'A.R. Rahman',
      playCount: 412,
      songsCount: 86,
      totalHours: 28.0,
      imageUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
      quote: '“ His music was your constant companion this year. ”',
    );

    const sampleAlbum = WrappedAlbumItem(
      title: 'Bombay',
      artist: 'A.R. Rahman',
      playCount: 128,
      totalHours: 9.4,
      artworkUrl: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=400',
      quote: '“ Some albums don\'t just play, they stay with you. ”',
    );

    const sampleTimeline = [
      WrappedTimelineMilestone(
        monthLabel: 'Jan',
        title: 'Tamil Melodies',
        description: 'Started the year with timeless classics.',
        imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=200',
      ),
      WrappedTimelineMilestone(
        monthLabel: 'Apr',
        title: 'Indie Discoveries',
        description: 'You explored new artists and sounds.',
        imageUrl: 'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=200',
      ),
      WrappedTimelineMilestone(
        monthLabel: 'Jul',
        title: 'Repeat Favourites',
        description: 'These songs never left your queue.',
        imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=200',
      ),
      WrappedTimelineMilestone(
        monthLabel: 'Oct',
        title: 'Feel Good Vibes',
        description: 'A mix of love, travel, and happiness.',
        imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=200',
      ),
    ];

    const sampleLanguages = [
      WrappedLanguageItem(name: 'Tamil', percentage: 62, color: Color(0xFF7D9D8B)),
      WrappedLanguageItem(name: 'English', percentage: 18, color: Color(0xFFC87D6B)),
      WrappedLanguageItem(name: 'Hindi', percentage: 8, color: Color(0xFFE9C9B7)),
      WrappedLanguageItem(name: 'Telugu', percentage: 7, color: Color(0xFFA3C4BC)),
      WrappedLanguageItem(name: 'Malayalam', percentage: 4, color: Color(0xFFD78D9B)),
      WrappedLanguageItem(name: 'Others', percentage: 1, color: Color(0xFFB0A8A0)),
    ];

    const sampleContexts = [
      WrappedContextItem(
        label: 'At Home',
        subLabel: 'Evening Relax',
        percentage: 44,
        icon: Icons.chair_rounded,
      ),
      WrappedContextItem(
        label: 'While Studying',
        subLabel: 'Focus Sessions',
        percentage: 22,
        icon: Icons.laptop_mac_rounded,
      ),
      WrappedContextItem(
        label: 'During Travel',
        subLabel: 'Daily Commute',
        percentage: 18,
        icon: Icons.headphones_rounded,
      ),
      WrappedContextItem(
        label: 'Late Night',
        subLabel: 'Midnight Peace',
        percentage: 12,
        icon: Icons.nightlight_round,
      ),
      WrappedContextItem(
        label: 'Work / Others',
        subLabel: 'Background Tunes',
        percentage: 4,
        icon: Icons.coffee_rounded,
      ),
    ];

    return WrappedSummary(
      year: year,
      timeframeLabel: timeframeLabel,
      totalMinutes: 7680,
      totalHours: 128.0,
      totalTracks: 1240,
      totalArtists: 312,
      totalAlbums: 86,
      longestStreakDays: 12,
      totalLanguages: 5,
      topTracks: sampleTracks,
      topArtist: sampleArtist,
      topAlbum: sampleAlbum,
      timelineMilestones: sampleTimeline,
      languages: sampleLanguages,
      listeningContexts: sampleContexts,
      archetype: ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'midnight'),
      peakHour: 23,
      peakHourLabel: '11:00 PM – 12:00 AM',
      peakDayName: 'Friday',
      topDay: DateTime(year, 10, 24),
      topDayTrackCount: 47,
      isSampleData: true,
      hasSufficientHistory: hasSufficient,
      anniversaryYear: anniversaryYear,
    );
  }
}

class _TrackAgg {
  final String trackId;
  final String title;
  final String artist;
  String? imageUrl;
  int playCount;
  int totalSec;

  _TrackAgg({
    required this.trackId,
    required this.title,
    required this.artist,
    this.imageUrl,
    required this.playCount,
    required this.totalSec,
  });
}

class _ArtistAgg {
  final String name;
  int playCount;
  int totalSec;
  String? imageUrl;

  _ArtistAgg({
    required this.name,
    required this.playCount,
    required this.totalSec,
    this.imageUrl,
  });
}

class _AlbumAgg {
  final String title;
  final String artist;
  int playCount;
  int totalSec;
  String? artworkUrl;

  _AlbumAgg({
    required this.title,
    required this.artist,
    required this.playCount,
    required this.totalSec,
    this.artworkUrl,
  });
}
