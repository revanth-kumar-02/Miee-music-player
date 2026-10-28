import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/storage/adapters/playback_history_entry.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/wrapped/data/wrapped_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Wrapped Engine Tests', () {
    test('Empty / Insufficient history falls back to high-quality sample data', () {
      final summary = WrappedService.computeSummary(
        customEntries: [],
        timeframe: 'year',
      );

      expect(summary.isSampleData, isTrue);
      expect(summary.hasSufficientHistory, isFalse);
      expect(summary.totalMinutes, greaterThan(100));
      expect(summary.topTracks.length, equals(5));
      expect(summary.topArtists.length, equals(5));
      expect(summary.topTrack?.title, isNotEmpty);
      expect(summary.topArtist?.name, isNotEmpty);
      expect(summary.archetype.id, equals('nocturnal'));
    });

    test('Real playback entries correctly aggregate top tracks, artists, and durations', () {
      final now = DateTime.now();

      final trackA = TrackHiveModel(
        id: 'track_a',
        title: 'Starboy',
        artist: 'The Weeknd',
        imageUrl: '',
        duration: '03:50', // 230s
      );

      final trackB = TrackHiveModel(
        id: 'track_b',
        title: 'Instant Crush',
        artist: 'Daft Punk',
        imageUrl: '',
        duration: '05:37', // 337s
      );

      final trackC = TrackHiveModel(
        id: 'track_c',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        imageUrl: '',
        duration: '03:20', // 200s
      );

      // Create history: 3 plays of trackA, 2 plays of trackB, 1 play of trackC
      // Set all at 23:00 (11 PM) on a Friday
      // October 23, 2026 was a Friday (weekday = 5)
      final fridayNight = DateTime(now.year, 10, 23, 23, 15);

      final entries = [
        PlaybackHistoryEntry(track: trackA, startTime: fridayNight, completionPercent: 1.0),
        PlaybackHistoryEntry(track: trackA, startTime: fridayNight, completionPercent: 1.0),
        PlaybackHistoryEntry(track: trackA, startTime: fridayNight, completionPercent: 1.0),
        PlaybackHistoryEntry(track: trackB, startTime: fridayNight, completionPercent: 1.0),
        PlaybackHistoryEntry(track: trackB, startTime: fridayNight, completionPercent: 1.0),
        PlaybackHistoryEntry(track: trackC, startTime: fridayNight, completionPercent: 1.0),
      ];

      final summary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'year',
      );

      expect(summary.isSampleData, isFalse);
      expect(summary.hasSufficientHistory, isTrue);

      // Verify Top Song: Starboy (3 plays)
      expect(summary.topTrack?.title, equals('Starboy'));
      expect(summary.topTrack?.playCount, equals(3));
      expect(summary.topTrack?.rank, equals(1));

      // Verify Top Artist: The Weeknd (4 total plays: 3 from trackA + 1 from trackC)
      expect(summary.topArtist?.name, equals('The Weeknd'));
      expect(summary.topArtist?.playCount, equals(4));

      // Verify #2 Artist: Daft Punk (2 plays)
      expect(summary.topArtists[1].name, equals('Daft Punk'));
      expect(summary.topArtists[1].playCount, equals(2));

      // Peak hour: 23 (11 PM)
      expect(summary.peakHour, equals(23));
      expect(summary.peakHourLabel, contains('11 PM'));

      // Peak day: Friday
      expect(summary.peakDayName, equals('Friday'));

      // All plays at 23:00 -> Nocturnal Wanderer archetype
      expect(summary.archetype.id, equals('nocturnal'));
    });

    test('Morning listening sessions classify as The Sunrise Architect', () {
      final now = DateTime.now();

      final morningTrack = TrackHiveModel(
        id: 'track_morning',
        title: 'Morning Sun',
        artist: 'Acoustic Soul',
        imageUrl: '',
        duration: '03:00',
      );

      // Play at 07:30 AM
      final morningTime = DateTime(now.year, 8, 12, 7, 30);

      final entries = [
        PlaybackHistoryEntry(track: morningTrack, startTime: morningTime, completionPercent: 1.0),
        PlaybackHistoryEntry(track: morningTrack, startTime: morningTime, completionPercent: 1.0),
        PlaybackHistoryEntry(track: morningTrack, startTime: morningTime, completionPercent: 1.0),
        PlaybackHistoryEntry(track: morningTrack, startTime: morningTime, completionPercent: 1.0),
      ];

      final summary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'year',
      );

      expect(summary.archetype.id, equals('sunrise'));
      expect(summary.archetype.title, equals('The Sunrise Architect'));
    });

    test('Timeframe filtering excludes entries outside the selected window', () {
      final now = DateTime.now();

      final currentTrack = TrackHiveModel(
        id: 't_now',
        title: 'Recent Hit',
        artist: 'Current Artist',
        imageUrl: '',
        duration: '03:00',
      );

      final oldTrack = TrackHiveModel(
        id: 't_old',
        title: 'Old Song',
        artist: 'Vintage Artist',
        imageUrl: '',
        duration: '03:00',
      );

      final entries = [
        PlaybackHistoryEntry(track: currentTrack, startTime: now.subtract(const Duration(days: 2)), completionPercent: 1.0),
        PlaybackHistoryEntry(track: currentTrack, startTime: now.subtract(const Duration(days: 5)), completionPercent: 1.0),
        PlaybackHistoryEntry(track: currentTrack, startTime: now.subtract(const Duration(days: 8)), completionPercent: 1.0),
        PlaybackHistoryEntry(track: oldTrack, startTime: now.subtract(const Duration(days: 60)), completionPercent: 1.0),
      ];

      // With month filter: oldTrack (60 days ago) should be excluded
      final monthSummary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'month',
      );

      expect(monthSummary.topTracks.any((t) => t.title == 'Old Song'), isFalse);
      expect(monthSummary.topTrack?.title, equals('Recent Hit'));
    });
  });
}
