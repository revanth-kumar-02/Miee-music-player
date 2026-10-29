import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/storage/adapters/playback_history_entry.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/wrapped/data/wrapped_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Wrapped Engine Production Real-Data Tests', () {
    test('Empty history produces honest empty state without fabricating fake data', () {
      final summary = WrappedService.computeSummary(
        customEntries: [],
        timeframe: 'year',
      );

      expect(summary.isSampleData, isFalse);
      expect(summary.hasSufficientHistory, isFalse);
      expect(summary.totalHours, equals(0.0));
      expect(summary.totalTracks, equals(0));
      expect(summary.totalArtists, equals(0));
      expect(summary.totalAlbums, equals(0));
      expect(summary.longestStreakDays, equals(0));
      expect(summary.totalLanguages, equals(0));

      // Slides 4-7: No fabricated items
      expect(summary.topTracks, isEmpty);
      expect(summary.topArtist, isNull);
      expect(summary.topAlbum, isNull);
      expect(summary.timelineMilestones, isEmpty);
      expect(summary.languages, isEmpty);

      // Slide 2: Honest newcomer archetype
      expect(summary.archetype.id, equals('newcomer'));
    });

    test('Demo mode with forceSample=true provides sample preview', () {
      final summary = WrappedService.computeSummary(
        customEntries: [],
        forceSample: true,
        timeframe: 'year',
      );

      expect(summary.isSampleData, isTrue);
      expect(summary.topTracks.length, equals(5));
      expect(summary.topArtist?.name, equals('A.R. Rahman'));
    });

    test('Partial history (1-2 tracks) returns exact tracks without inventing fake entries', () {
      final now = DateTime.now();
      final track = TrackHiveModel(
        id: 'single_1',
        title: 'Only Song',
        artist: 'Solo Artist',
        imageUrl: 'https://example.com/art.jpg',
        duration: '03:30',
        filePath: 'music/SingleAlbum/01.mp3',
      );

      final entries = [
        PlaybackHistoryEntry(
          track: track,
          startTime: DateTime(now.year, now.month, 10, 14, 0),
          completionPercent: 1.0,
        ),
      ];

      final summary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'year',
      );

      expect(summary.isSampleData, isFalse);
      expect(summary.hasSufficientHistory, isFalse); // < 3 tracks
      expect(summary.totalTracks, equals(1));
      expect(summary.totalArtists, equals(1));
      expect(summary.topTracks.length, equals(1)); // Exactly 1 track, not 5
      expect(summary.topTracks.first.title, equals('Only Song'));
      expect(summary.topArtist?.name, equals('Solo Artist'));
      expect(summary.topAlbum?.title, equals('SingleAlbum'));
      expect(summary.timelineMilestones.length, equals(1)); // Exactly 1 active month
      expect(summary.archetype.id, equals('newcomer'));
    });

    test('Slide 3-6: Real playback entries accurately compute real metrics without double counting', () {
      final now = DateTime.now();

      final track1 = TrackHiveModel(
        id: 't1',
        title: 'Kaadhal Rojave',
        artist: 'A.R. Rahman',
        imageUrl: 'https://example.com/art1.jpg',
        duration: '04:12', // 252s
        filePath: 'music/Roja/01.mp3',
      );

      final track2 = TrackHiveModel(
        id: 't2',
        title: 'Vaseegara',
        artist: 'Bombay Jayashri',
        imageUrl: 'https://example.com/art2.jpg',
        duration: '05:00', // 300s
        filePath: 'music/Minnale/02.mp3',
      );

      // Play sessions across 3 consecutive days at 23:00 (11 PM)
      final day1 = DateTime(now.year, 10, 20, 23, 10);
      final day2 = DateTime(now.year, 10, 21, 23, 20);
      final day3 = DateTime(now.year, 10, 22, 23, 30);

      final entries = [
        PlaybackHistoryEntry(track: track1, startTime: day1, completionPercent: 1.0),
        PlaybackHistoryEntry(track: track1, startTime: day2, completionPercent: 1.0),
        PlaybackHistoryEntry(track: track1, startTime: day3, completionPercent: 1.0),
        PlaybackHistoryEntry(track: track2, startTime: day1, completionPercent: 1.0),
        PlaybackHistoryEntry(track: track2, startTime: day2, completionPercent: 1.0),
      ];

      final summary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'year',
      );

      expect(summary.isSampleData, isFalse);
      expect(summary.hasSufficientHistory, isTrue);

      // Top Track: Kaadhal Rojave (3 plays)
      expect(summary.topTrack?.title, equals('Kaadhal Rojave'));
      expect(summary.topTrack?.playCount, equals(3));
      expect(summary.topTrack?.musicItem?.id, equals('t1'));

      // Top Artist: A.R. Rahman (3 plays)
      expect(summary.topArtist?.name, equals('A.R. Rahman'));
      expect(summary.topArtist?.playCount, equals(3));

      // Streak: 3 consecutive days
      expect(summary.longestStreakDays, equals(3));

      // Late night plays at 23:00 -> The Midnight Listener archetype
      expect(summary.archetype.id, equals('midnight'));
      expect(summary.archetype.title, equals('The Midnight Listener'));
    });

    test('Slide 7 & 9: Timeline and Context breakdown reflect actual hours and month distributions', () {
      final now = DateTime.now();

      final eveningTrack = TrackHiveModel(
        id: 't_evening',
        title: 'Sunset Beat',
        artist: 'Indie Artist',
        imageUrl: '',
        duration: '03:00',
      );

      // 4 distinct sessions in July at 19:00 (7 PM = Evening / At Home)
      final d1 = DateTime(now.year, 7, 10, 19, 0);
      final d2 = DateTime(now.year, 7, 11, 19, 0);
      final d3 = DateTime(now.year, 7, 12, 19, 0);
      final d4 = DateTime(now.year, 7, 13, 19, 0);

      final entries = [
        PlaybackHistoryEntry(track: eveningTrack, startTime: d1, completionPercent: 1.0),
        PlaybackHistoryEntry(track: eveningTrack, startTime: d2, completionPercent: 1.0),
        PlaybackHistoryEntry(track: eveningTrack, startTime: d3, completionPercent: 1.0),
        PlaybackHistoryEntry(track: eveningTrack, startTime: d4, completionPercent: 1.0),
      ];

      final summary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'year',
      );

      // Only July was active, so exactly 1 milestone is produced
      expect(summary.timelineMilestones.length, equals(1));
      expect(summary.timelineMilestones.first.monthLabel, equals('Jul'));
      expect(summary.timelineMilestones.first.title, equals('Sunset Beat'));

      // Evening context should be 100% of plays
      final atHome = summary.listeningContexts.firstWhere((c) => c.label == 'At Home');
      expect(atHome.percentage, equals(100));
    });

    test('Monthly vs Annual date boundaries correctly exclude out-of-range entries', () {
      final now = DateTime.now();

      final oldTrack = TrackHiveModel(
        id: 'old_1',
        title: 'Old Song',
        artist: 'Old Artist',
        imageUrl: '',
        duration: '03:00',
      );

      final recentTrack = TrackHiveModel(
        id: 'recent_1',
        title: 'Recent Song',
        artist: 'Recent Artist',
        imageUrl: '',
        duration: '03:00',
      );

      final entries = [
        // 60 days ago (outside past 30 days)
        PlaybackHistoryEntry(
          track: oldTrack,
          startTime: now.subtract(const Duration(days: 60)),
          completionPercent: 1.0,
        ),
        // 5 days ago (inside past 30 days)
        PlaybackHistoryEntry(
          track: recentTrack,
          startTime: now.subtract(const Duration(days: 5)),
          completionPercent: 1.0,
        ),
      ];

      // Month query should only have recentTrack
      final monthSummary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'month',
      );
      expect(monthSummary.totalTracks, equals(1));
      expect(monthSummary.topTracks.first.title, equals('Recent Song'));

      // All-time query should have both tracks
      final allSummary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'all',
      );
      expect(allSummary.totalTracks, equals(2));
    });

    test('Language detection accurately classifies scripts and tags and sums to 100%', () {
      final now = DateTime.now();

      final tamilTrack = TrackHiveModel(
        id: 'l1',
        title: 'காதல் ரோஜாவே',
        artist: 'A.R. Rahman',
        imageUrl: '',
        duration: '04:00',
      );

      final englishTrack = TrackHiveModel(
        id: 'l2',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        imageUrl: '',
        duration: '03:20',
      );

      final entries = [
        PlaybackHistoryEntry(track: tamilTrack, startTime: now, completionPercent: 1.0),
        PlaybackHistoryEntry(track: englishTrack, startTime: now, completionPercent: 1.0),
      ];

      final langs = WrappedService.detectLanguagesFromHistory(entries);
      expect(langs.length, equals(2));
      expect(langs.map((l) => l.name), containsAll(['Tamil', 'English']));

      final totalPct = langs.fold<int>(0, (sum, l) => sum + l.percentage);
      expect(totalPct, equals(100));
    });
  });
}
