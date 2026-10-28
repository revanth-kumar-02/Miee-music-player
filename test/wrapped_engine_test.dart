import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/core/storage/adapters/playback_history_entry.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/wrapped/data/wrapped_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Miee Wrapped Engine 10-Slide Production Tests', () {
    test('Slide 1 & 2: Insufficient history safely delivers 10-slide sample preview', () {
      final summary = WrappedService.computeSummary(
        customEntries: [],
        timeframe: 'year',
      );

      expect(summary.isSampleData, isTrue);
      expect(summary.hasSufficientHistory, isFalse);

      // Slide 1 & 3: Totals
      expect(summary.totalHours, equals(128.0));
      expect(summary.totalTracks, equals(1240));
      expect(summary.totalArtists, equals(312));
      expect(summary.totalAlbums, equals(86));
      expect(summary.longestStreakDays, equals(12));
      expect(summary.totalLanguages, equals(5));

      // Slide 4: Top 5 Songs
      expect(summary.topTracks.length, equals(5));
      expect(summary.topTracks.first.title, equals('Kaadhal Rojave'));
      expect(summary.topTracks.first.playCount, equals(412));
      expect(summary.topTracks.first.musicItem, isNotNull);

      // Slide 5: Top Artist
      expect(summary.topArtist?.name, equals('A.R. Rahman'));
      expect(summary.topArtist?.playCount, equals(412));
      expect(summary.topArtist?.songsCount, equals(86));
      expect(summary.topArtist?.totalHours, equals(28.0));

      // Slide 6: Favourite Album
      expect(summary.topAlbum?.title, equals('Bombay'));
      expect(summary.topAlbum?.playCount, equals(128));

      // Slide 7: Music Timeline (4 milestones)
      expect(summary.timelineMilestones.length, equals(4));
      expect(summary.timelineMilestones[0].monthLabel, equals('Jan'));
      expect(summary.timelineMilestones[1].monthLabel, equals('Apr'));

      // Slide 8: Languages
      expect(summary.languages.length, equals(6));
      expect(summary.languages.first.name, equals('Tamil'));
      expect(summary.languages.first.percentage, equals(62));

      // Slide 9: Listening Contexts
      expect(summary.listeningContexts.length, equals(5));
      expect(summary.listeningContexts.first.label, equals('At Home'));
      expect(summary.listeningContexts.first.percentage, equals(44));
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

      // 4 plays at 19:00 (7 PM = Evening / At Home)
      final eveningTime = DateTime(now.year, 7, 15, 19, 0);

      final entries = [
        PlaybackHistoryEntry(track: eveningTrack, startTime: eveningTime, completionPercent: 1.0),
        PlaybackHistoryEntry(track: eveningTrack, startTime: eveningTime, completionPercent: 1.0),
        PlaybackHistoryEntry(track: eveningTrack, startTime: eveningTime, completionPercent: 1.0),
        PlaybackHistoryEntry(track: eveningTrack, startTime: eveningTime, completionPercent: 1.0),
      ];

      final summary = WrappedService.computeSummary(
        customEntries: entries,
        timeframe: 'year',
      );

      // Check context
      final atHome = summary.listeningContexts.firstWhere((c) => c.label == 'At Home');
      expect(atHome.percentage, greaterThanOrEqualTo(50));

      // Check timeline July (Month 7)
      final julMilestone = summary.timelineMilestones.firstWhere((m) => m.monthLabel == 'Jul');
      expect(julMilestone.title, equals('Sunset Beat'));
    });
  });
}
