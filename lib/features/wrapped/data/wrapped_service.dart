import 'package:hive/hive.dart';
import '../../../core/storage/adapters/playback_history_entry.dart';
import '../../../core/storage/hive_boxes.dart';
import '../domain/wrapped_models.dart';

class WrappedService {
  /// Computes the complete Wrapped statistical breakdown from stored playback entries.
  static WrappedSummary computeSummary({
    List<PlaybackHistoryEntry>? customEntries,
    bool forceSample = false,
    String timeframe = 'year', // 'year', 'month', 'all'
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

    // 1. Filter entries according to timeframe
    final filtered = rawList.where((e) {
      if (timeframe == 'month') {
        return e.startTime.isAfter(now.subtract(const Duration(days: 30)));
      } else if (timeframe == 'year') {
        return e.startTime.year == now.year;
      }
      return true;
    }).toList();

    final hasSufficient = filtered.length >= 3;

    // 2. Return curated sample data if user doesn't have enough history or explicitly requests sample
    if (forceSample || !hasSufficient) {
      return _generateSampleWrapped(
        hasSufficient: hasSufficient,
        timeframe: timeframe,
        year: now.year,
      );
    }

    // 3. Aggregate real listening metrics
    int totalSec = 0;
    final Map<String, _TrackAgg> trackAggMap = {};
    final Map<String, _ArtistAgg> artistAggMap = {};
    final List<int> hourBuckets = List.filled(24, 0);
    final List<int> dayBuckets = List.filled(7, 0);
    final Map<String, int> dailyTrackCount = {};

    for (final entry in filtered) {
      final track = entry.track;
      final durSec = _parseDurationSec(track.duration);
      final entryListenedSec = (durSec * (entry.completionPercent > 0 ? entry.completionPercent : 1.0)).round();
      totalSec += entryListenedSec > 0 ? entryListenedSec : 180;

      // Track Aggregation
      final trackKey = track.id.isNotEmpty ? track.id : track.title;
      final existingTrack = trackAggMap[trackKey];
      if (existingTrack == null) {
        trackAggMap[trackKey] = _TrackAgg(
          trackId: track.id,
          title: track.title,
          artist: track.artist,
          imageUrl: track.imageUrl.isNotEmpty ? track.imageUrl : null,
          playCount: 1,
          totalSec: entryListenedSec,
        );
      } else {
        existingTrack.playCount++;
        existingTrack.totalSec += entryListenedSec;
      }

      // Artist Aggregation
      final artistName = track.artist.trim().isNotEmpty ? track.artist.trim() : 'Unknown Artist';
      final existingArtist = artistAggMap[artistName];
      if (existingArtist == null) {
        artistAggMap[artistName] = _ArtistAgg(
          name: artistName,
          playCount: 1,
          totalSec: entryListenedSec,
          imageUrl: track.imageUrl.isNotEmpty ? track.imageUrl : null,
        );
      } else {
        existingArtist.playCount++;
        existingArtist.totalSec += entryListenedSec;
      }

      // Time Distribution
      final hour = entry.startTime.hour;
      hourBuckets[hour]++;

      // DateTime weekday: 1 = Monday, 7 = Sunday
      final weekdayIndex = (entry.startTime.weekday - 1).clamp(0, 6);
      dayBuckets[weekdayIndex]++;

      // Single Day Spike
      final dateKey = '${entry.startTime.year}-${entry.startTime.month}-${entry.startTime.day}';
      dailyTrackCount[dateKey] = (dailyTrackCount[dateKey] ?? 0) + 1;
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
      );
    }).toList();

    // Rank Top Artists (sorted by play count, then total duration)
    final sortedArtists = artistAggMap.values.toList()
      ..sort((a, b) {
        final cmp = b.playCount.compareTo(a.playCount);
        if (cmp != 0) return cmp;
        return b.totalSec.compareTo(a.totalSec);
      });

    final topArtists = sortedArtists.take(5).toList().asMap().entries.map((entry) {
      final rank = entry.key + 1;
      final item = entry.value;
      return WrappedArtistItem(
        rank: rank,
        name: item.name,
        playCount: item.playCount,
        totalMinutes: (item.totalSec / 60).round(),
        imageUrl: item.imageUrl,
      );
    }).toList();

    // Peak Hour
    int maxHourIndex = 20; // default 8pm
    int maxHourCount = -1;
    for (int h = 0; h < 24; h++) {
      if (hourBuckets[h] > maxHourCount) {
        maxHourCount = hourBuckets[h];
        maxHourIndex = h;
      }
    }

    // Peak Day of Week
    final dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    int maxDayIndex = 4; // default Friday
    int maxDayCount = -1;
    for (int d = 0; d < 7; d++) {
      if (dayBuckets[d] > maxDayCount) {
        maxDayCount = dayBuckets[d];
        maxDayIndex = d;
      }
    }

    // Top Day Peak
    DateTime? topDayDate;
    int topDayCount = 0;
    dailyTrackCount.forEach((dateStr, count) {
      if (count > topDayCount) {
        topDayCount = count;
        final parts = dateStr.split('-');
        if (parts.length == 3) {
          topDayDate = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
        }
      }
    });

    // Determine Archetype
    final totalPlays = filtered.length;
    final nocturnalPlays = hourBuckets[22] + hourBuckets[23] + hourBuckets[0] + hourBuckets[1] + hourBuckets[2] + hourBuckets[3] + hourBuckets[4];
    final morningPlays = hourBuckets[5] + hourBuckets[6] + hourBuckets[7] + hourBuckets[8] + hourBuckets[9] + hourBuckets[10];
    final topArtistPlays = sortedArtists.isNotEmpty ? sortedArtists.first.playCount : 0;
    final uniqueArtistsCount = artistAggMap.length;

    ListeningArchetype archetype;
    if (nocturnalPlays / totalPlays >= 0.35) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'nocturnal');
    } else if (morningPlays / totalPlays >= 0.35) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'sunrise');
    } else if (topArtistPlays / totalPlays >= 0.40) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'devotee');
    } else if (uniqueArtistsCount / totalPlays >= 0.70 && totalPlays >= 8) {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'explorer');
    } else {
      archetype = ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'connoisseur');
    }

    final totalMin = (totalSec / 60).round();
    final totalHours = double.parse((totalMin / 60.0).toStringAsFixed(1));

    String timeframeLabel;
    if (timeframe == 'month') {
      timeframeLabel = 'Past 30 Days';
    } else if (timeframe == 'all') {
      timeframeLabel = 'All-Time';
    } else {
      timeframeLabel = '${now.year}';
    }

    return WrappedSummary(
      year: now.year,
      timeframeLabel: timeframeLabel,
      totalMinutes: totalMin > 0 ? totalMin : 1,
      totalHours: totalHours,
      totalTracks: trackAggMap.length,
      totalArtists: artistAggMap.length,
      topTracks: topTracks,
      topArtists: topArtists,
      archetype: archetype,
      peakHour: maxHourIndex,
      peakHourLabel: _formatHour(maxHourIndex),
      peakDayName: dayNames[maxDayIndex],
      topDay: topDayDate,
      topDayTrackCount: topDayCount,
      isSampleData: false,
      hasSufficientHistory: true,
    );
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
  }) {
    String timeframeLabel = timeframe == 'month' ? 'Past 30 Days' : (timeframe == 'all' ? 'All-Time' : '$year');

    final sampleTracks = [
      const WrappedTrackItem(
        rank: 1,
        trackId: 'sample_1',
        title: 'Starboy',
        artist: 'The Weeknd, Daft Punk',
        imageUrl: 'https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=300',
        playCount: 42,
        totalMinutes: 147,
      ),
      const WrappedTrackItem(
        rank: 2,
        trackId: 'sample_2',
        title: 'Midnight City',
        artist: 'M83',
        imageUrl: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=300',
        playCount: 36,
        totalMinutes: 126,
      ),
      const WrappedTrackItem(
        rank: 3,
        trackId: 'sample_3',
        title: 'After Hours',
        artist: 'The Weeknd',
        imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300',
        playCount: 29,
        totalMinutes: 110,
      ),
      const WrappedTrackItem(
        rank: 4,
        trackId: 'sample_4',
        title: 'Get Lucky',
        artist: 'Daft Punk, Pharrell Williams',
        imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
        playCount: 24,
        totalMinutes: 96,
      ),
      const WrappedTrackItem(
        rank: 5,
        trackId: 'sample_5',
        title: 'Instant Crush',
        artist: 'Daft Punk, Julian Casablancas',
        imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
        playCount: 19,
        totalMinutes: 82,
      ),
    ];

    final sampleArtists = [
      const WrappedArtistItem(
        rank: 1,
        name: 'The Weeknd',
        playCount: 84,
        totalMinutes: 310,
        imageUrl: 'https://images.unsplash.com/photo-1614613535308-eb5fbd3d2c17?w=300',
      ),
      const WrappedArtistItem(
        rank: 2,
        name: 'Daft Punk',
        playCount: 65,
        totalMinutes: 240,
        imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=300',
      ),
      const WrappedArtistItem(
        rank: 3,
        name: 'M83',
        playCount: 41,
        totalMinutes: 155,
        imageUrl: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?w=300',
      ),
      const WrappedArtistItem(
        rank: 4,
        name: 'Tame Impala',
        playCount: 32,
        totalMinutes: 120,
        imageUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=300',
      ),
      const WrappedArtistItem(
        rank: 5,
        name: 'Flume',
        playCount: 22,
        totalMinutes: 88,
        imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=300',
      ),
    ];

    return WrappedSummary(
      year: year,
      timeframeLabel: timeframeLabel,
      totalMinutes: 3420,
      totalHours: 57.0,
      totalTracks: 184,
      totalArtists: 62,
      topTracks: sampleTracks,
      topArtists: sampleArtists,
      archetype: ListeningArchetype.allArchetypes.firstWhere((a) => a.id == 'nocturnal'),
      peakHour: 23,
      peakHourLabel: '11:00 PM – 12:00 AM',
      peakDayName: 'Friday',
      topDay: DateTime(year, 10, 24),
      topDayTrackCount: 47,
      isSampleData: true,
      hasSufficientHistory: hasSufficient,
    );
  }
}

class _TrackAgg {
  final String trackId;
  final String title;
  final String artist;
  final String? imageUrl;
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
  final String? imageUrl;

  _ArtistAgg({
    required this.name,
    required this.playCount,
    required this.totalSec,
    this.imageUrl,
  });
}
