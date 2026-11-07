import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:Miee/core/storage/adapters/playback_history_entry.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/features/history/data/supabase_listening_history_repository.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/recommendations/data/taste_profile_repository.dart';
import 'package:Miee/features/recommendations/domain/affinity_calculator.dart';
import 'package:Miee/features/recommendations/domain/artist_normalizer.dart';
import 'package:Miee/features/recommendations/domain/user_taste_profile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  final now = DateTime(2026, 11, 7, 12, 0, 0);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_taste_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(PlaybackHistoryEntryAdapter().typeId)) {
      Hive.registerAdapter(PlaybackHistoryEntryAdapter());
    }
    if (!Hive.isBoxOpen(HiveBoxes.profile)) {
      await Hive.openBox<dynamic>(HiveBoxes.profile);
    }
    if (!Hive.isBoxOpen(HiveBoxes.playbackHistory)) {
      await Hive.openBox<PlaybackHistoryEntry>(HiveBoxes.playbackHistory);
    }
  });

  tearDown(() async {
    await Hive.close();
    await Hive.deleteFromDisk();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('ArtistNormalizer', () {
    test('normalizes - Topic suffix correctly', () {
      expect(
        ArtistNormalizer.normalize('Anirudh Ravichander - Topic'),
        equals('Anirudh Ravichander'),
      );
      expect(
        ArtistNormalizer.normalize('A.R. Rahman - Topic'),
        equals('A.R. Rahman'),
      );
    });

    test('normalizes VEVO suffixes and CamelCase VEVO channel names', () {
      expect(
        ArtistNormalizer.normalize('TaylorSwiftVEVO'),
        equals('Taylor Swift'),
      );
      expect(
        ArtistNormalizer.normalize('ArianaGrandeVevo'),
        equals('Ariana Grande'),
      );
      expect(
        ArtistNormalizer.normalize('TheWeeknd VEVO'),
        equals('The Weeknd'),
      );
    });

    test('normalizes Official / Music / Records channel suffixes', () {
      expect(
        ArtistNormalizer.normalize('Sony Music'),
        equals('Sony'),
      );
      expect(
        ArtistNormalizer.normalize('Coldplay Official'),
        equals('Coldplay'),
      );
      expect(
        ArtistNormalizer.normalize('T-Series Official Channel'),
        equals('T-Series'),
      );
    });

    test('handles whitespace and trailing punctuation cleanly', () {
      expect(
        ArtistNormalizer.normalize('  Ed Sheeran -  '),
        equals('Ed Sheeran'),
      );
      expect(
        ArtistNormalizer.normalize('Kendrick   Lamar'),
        equals('Kendrick Lamar'),
      );
    });

    test('areEquivalent identifies matching artists regardless of case and noise', () {
      expect(
        ArtistNormalizer.areEquivalent(
          'Anirudh Ravichander - Topic',
          'anirudh ravichander',
        ),
        isTrue,
      );
      expect(
        ArtistNormalizer.areEquivalent('TaylorSwiftVEVO', 'taylor swift'),
        isTrue,
      );
      expect(
        ArtistNormalizer.areEquivalent('A.R. Rahman', 'Harris Jayaraj'),
        isFalse,
      );
    });
  });

  group('AffinityCalculator - Mathematical Correctness & Time Decay', () {
    const calculator = AffinityCalculator(halfLifeDays: 14.0, sigmoidScale: 0.5);

    test('1. Empty history returns zero raw affinity and neutral 0.50 normalized', () {
      final raw = calculator.calculateRawAffinity([], referenceTime: now);
      final norm = calculator.normalize(raw);
      expect(raw, equals(0.0));
      expect(norm, equals(0.50));
    });

    test('2. Completed play yields positive weight (+1.0) and increases normalized affinity above 0.50', () {
      final event = ListeningEvent(
        id: 'evt_1',
        trackId: 't1',
        title: 'Song 1',
        artist: 'Artist A',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180, // 90% -> completedPlay (+1.0)
        completionRatio: 0.90,
      );

      final raw = calculator.calculateRawAffinity([event], referenceTime: now);
      final norm = calculator.normalize(raw);

      expect(event.eventType, equals(ListeningEventType.completedPlay));
      expect(event.weight, equals(1.0));
      expect(raw, equals(1.0));
      expect(norm, greaterThan(0.50));
      expect(norm, equals(0.6225)); // 1 / (1 + e^-0.5) = ~0.6225
    });

    test('3. Partial play yields intermediate weight (+0.5)', () {
      final event = ListeningEvent(
        id: 'evt_2',
        trackId: 't2',
        title: 'Song 2',
        artist: 'Artist B',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 100, // 50% -> partialPlay (+0.5)
        completionRatio: 0.50,
      );

      final raw = calculator.calculateRawAffinity([event], referenceTime: now);
      final norm = calculator.normalize(raw);

      expect(event.eventType, equals(ListeningEventType.partialPlay));
      expect(event.weight, equals(0.5));
      expect(raw, equals(0.5));
      expect(norm, greaterThan(0.50));
      expect(norm, lessThan(0.6225));
    });

    test('4. Skip yields negative weight (-0.8) and decreases normalized affinity below 0.50', () {
      final event = ListeningEvent(
        id: 'evt_3',
        trackId: 't3',
        title: 'Song 3',
        artist: 'Artist C',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 10, // 10s < 20s and 5% < 20% -> skip (-0.8)
        completionRatio: 0.05,
      );

      final raw = calculator.calculateRawAffinity([event], referenceTime: now);
      final norm = calculator.normalize(raw);

      expect(event.eventType, equals(ListeningEventType.skip));
      expect(event.weight, equals(-0.8));
      expect(raw, equals(-0.8));
      expect(norm, lessThan(0.50));
      expect(norm, equals(0.4013)); // 1 / (1 + e^0.4) = ~0.4013
    });

    test('5. 14-day half-life decays event weight by exactly ~50%', () {
      final fourteenDaysAgo = now.subtract(const Duration(days: 14));
      final decay = calculator.decayFactor(14.0);

      // e^(-ln(2) * 14 / 14) = e^(-ln(2)) = 1/2 = 0.50
      expect((decay - 0.50).abs(), lessThan(0.0001));

      final event = ListeningEvent(
        id: 'evt_4',
        trackId: 't4',
        title: 'Song 4',
        artist: 'Artist D',
        source: 'youtube',
        timestamp: fourteenDaysAgo,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );

      final raw = calculator.calculateRawAffinity([event], referenceTime: now);
      expect((raw - 0.50).abs(), lessThan(0.001));
    });

    test('6. Older events contribute strictly less than recent events', () {
      final recentEvent = ListeningEvent(
        id: 'evt_recent',
        trackId: 't1',
        title: 'Recent',
        artist: 'Artist E',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 2)),
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );

      final oldEvent = ListeningEvent(
        id: 'evt_old',
        trackId: 't2',
        title: 'Old',
        artist: 'Artist E',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 28)), // 2 half-lives -> 0.25
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );

      final rawRecent = calculator.calculateRawAffinity([recentEvent], referenceTime: now);
      final rawOld = calculator.calculateRawAffinity([oldEvent], referenceTime: now);

      expect(rawRecent, greaterThan(rawOld));
      expect((rawOld - 0.25).abs(), lessThan(0.01));
    });

    test('7. Multiple plays for the same artist accumulate monotonically', () {
      final event1 = ListeningEvent(
        id: 'evt_acc_1',
        trackId: 't1',
        title: 'Song 1',
        artist: 'Artist F',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );
      final event2 = ListeningEvent(
        id: 'evt_acc_2',
        trackId: 't2',
        title: 'Song 2',
        artist: 'Artist F',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );

      final raw1 = calculator.calculateRawAffinity([event1], referenceTime: now);
      final raw2 = calculator.calculateRawAffinity([event1, event2], referenceTime: now);

      expect(raw2, equals(raw1 + 1.0));
      expect(calculator.normalize(raw2), greaterThan(calculator.normalize(raw1)));
    });

    test('8. Skips safely subtract from affinity and can produce net-negative raw score', () {
      final play = ListeningEvent(
        id: 'evt_p1',
        trackId: 't1',
        title: 'Song 1',
        artist: 'Artist G',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180, // +1.0
        completionRatio: 0.90,
      );
      final skip1 = ListeningEvent(
        id: 'evt_s1',
        trackId: 't2',
        title: 'Song 2',
        artist: 'Artist G',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 5, // -0.8
        completionRatio: 0.025,
      );
      final skip2 = ListeningEvent(
        id: 'evt_s2',
        trackId: 't3',
        title: 'Song 3',
        artist: 'Artist G',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 5, // -0.8
        completionRatio: 0.025,
      );

      final raw = calculator.calculateRawAffinity([play, skip1, skip2], referenceTime: now);
      expect(raw, equals(1.0 - 0.8 - 0.8)); // -0.6
      expect(calculator.normalize(raw), lessThan(0.50));
    });

    test('9. Invalid or future timestamps are clamped safely to avoid score explosion', () {
      final futureEvent = ListeningEvent(
        id: 'evt_future',
        trackId: 't_future',
        title: 'Future',
        artist: 'Artist H',
        source: 'youtube',
        timestamp: now.add(const Duration(days: 365)), // 1 year in future
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );

      final raw = calculator.calculateRawAffinity([futureEvent], referenceTime: now);
      // Clamped decay factor = 1.0, not exponential explosion
      expect(raw, equals(1.0));
      expect(calculator.normalize(raw), equals(0.6225));
    });

    test('10. Normalized affinities are strictly bounded in [0.0, 1.0]', () {
      // Extreme positive (100 plays)
      final massivePositive = calculator.normalize(100.0);
      expect(massivePositive, lessThanOrEqualTo(1.0));
      expect(massivePositive, greaterThan(0.99));

      // Extreme negative (100 skips)
      final massiveNegative = calculator.normalize(-100.0);
      expect(massiveNegative, greaterThanOrEqualTo(0.0));
      expect(massiveNegative, lessThan(0.01));

      // NaN and Infinity safety
      expect(calculator.normalize(double.nan), equals(0.50));
      expect(calculator.normalize(double.infinity), equals(1.0));
      expect(calculator.normalize(double.negativeInfinity), equals(0.0));
    });

    test('11. Deduplication by event ID prevents duplicate processing', () {
      final event1 = ListeningEvent(
        id: 'dup_id_1',
        trackId: 't1',
        title: 'Song 1',
        artist: 'Artist I',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );
      final duplicate = ListeningEvent(
        id: 'dup_id_1',
        trackId: 't1',
        title: 'Song 1',
        artist: 'Artist I',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );

      final profile = calculator.computeTasteProfile(
        'user_1',
        [event1, duplicate],
        referenceTime: now,
      );

      expect(profile.eventsProcessedCount, equals(1));
      expect(profile.getArtistAffinity('Artist I'), equals(0.6225));
    });

    test('12. Independent artist calculations do not leak into one another', () {
      final eventA = ListeningEvent(
        id: 'evt_a',
        trackId: 't1',
        title: 'Song A',
        artist: 'Artist Alpha',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180, // completed (+1.0)
        completionRatio: 0.90,
      );
      final eventB = ListeningEvent(
        id: 'evt_b',
        trackId: 't2',
        title: 'Song B',
        artist: 'Artist Beta',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 5, // skip (-0.8)
        completionRatio: 0.025,
      );

      final profile = calculator.computeTasteProfile(
        'user_1',
        [eventA, eventB],
        referenceTime: now,
      );

      expect(profile.getArtistAffinity('Artist Alpha'), greaterThan(0.50));
      expect(profile.getArtistAffinity('Artist Beta'), lessThan(0.50));
      expect(profile.getArtistAffinity('Artist Gamma'), equals(0.50)); // unseen default
    });
  });

  group('UserTasteProfile & TasteProfileRepository', () {
    test('1. New user has empty profile with neutral defaults', () {
      final profile = UserTasteProfile.empty('user_new');
      expect(profile.userId, equals('user_new'));
      expect(profile.artistAffinities, isEmpty);
      expect(profile.languageAffinities, isEmpty);
      expect(profile.eventsProcessedCount, equals(0));
      expect(profile.getArtistAffinity('Unknown Artist'), equals(0.50));
      expect(profile.getLanguageAffinity('Tamil'), equals(0.50));
    });

    test('2. Profile correctly normalizes artist variations into unified affinity', () {
      const calculator = AffinityCalculator();
      final event1 = ListeningEvent(
        id: 'evt_norm_1',
        trackId: 't1',
        title: 'Song 1',
        artist: 'Anirudh Ravichander - Topic',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );
      final event2 = ListeningEvent(
        id: 'evt_norm_2',
        trackId: 't2',
        title: 'Song 2',
        artist: 'anirudh ravichander',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );

      final profile = calculator.computeTasteProfile(
        'user_1',
        [event1, event2],
        referenceTime: now,
      );

      expect(profile.artistAffinities.length, equals(1));
      expect(profile.artistAffinities.containsKey('anirudh ravichander'), isTrue);
      expect(profile.getArtistAffinity('Anirudh Ravichander'), greaterThan(0.6225));
    });

    test('3. Language affinities aggregate independently', () {
      const calculator = AffinityCalculator();
      final event1 = ListeningEvent(
        id: 'evt_lang_1',
        trackId: 't1',
        title: 'Song 1',
        artist: 'Artist 1',
        language: 'Tamil',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 180,
        completionRatio: 0.90,
      );
      final event2 = ListeningEvent(
        id: 'evt_lang_2',
        trackId: 't2',
        title: 'Song 2',
        artist: 'Artist 2',
        language: 'Hindi',
        source: 'youtube',
        timestamp: now,
        durationSec: 200,
        listenedSec: 5, // skip
        completionRatio: 0.025,
      );

      final profile = calculator.computeTasteProfile(
        'user_1',
        [event1, event2],
        referenceTime: now,
      );

      expect(profile.getLanguageAffinity('Tamil'), greaterThan(0.50));
      expect(profile.getLanguageAffinity('Hindi'), lessThan(0.50));
      expect(profile.getLanguageAffinity('English'), equals(0.50));
    });

    test('4. Serialization and deserialization preserves all values', () {
      final profile = UserTasteProfile(
        userId: 'user_42',
        artistAffinities: const {'coldplay': 0.75, 'radiohead': 0.82},
        languageAffinities: const {'english': 0.80},
        lastUpdated: now,
        eventsProcessedCount: 25,
        version: 1,
      );

      final map = profile.toMap();
      final restored = UserTasteProfile.fromMap(map);

      expect(restored.userId, equals(profile.userId));
      expect(restored.artistAffinities, equals(profile.artistAffinities));
      expect(restored.languageAffinities, equals(profile.languageAffinities));
      expect(restored.eventsProcessedCount, equals(profile.eventsProcessedCount));
      expect(restored.lastUpdated.millisecondsSinceEpoch,
          equals(profile.lastUpdated.millisecondsSinceEpoch));
    });

    test('5. TasteProfileRepository caches and isolates accounts strictly', () async {
      final mockHistoryRepo = SupabaseListeningHistoryRepository();
      final repo = TasteProfileRepository(
        historyRepo: mockHistoryRepo,
        cacheTtl: const Duration(hours: 1),
      );

      // Save a profile for User A directly in Hive
      final profileA = UserTasteProfile(
        userId: 'user_a',
        artistAffinities: const {'artist a': 0.90},
        languageAffinities: const {'tamil': 0.85},
        lastUpdated: DateTime.now(),
        eventsProcessedCount: 10,
      );
      final box = Hive.box<dynamic>(HiveBoxes.profile);
      await box.put('taste_profile_user_a', profileA.toMap());

      // Read back User A's profile via repo
      final loadedA = await repo.getProfile('user_a');
      expect(loadedA.userId, equals('user_a'));
      expect(loadedA.getArtistAffinity('artist a'), equals(0.90));

      // Attempt reading User B's profile - User B must NOT see User A's data
      final loadedB = await repo.getProfile('user_b');
      expect(loadedB.userId, equals('user_b'));
      expect(loadedB.getArtistAffinity('artist a'), equals(0.50)); // Neutral default
      expect(loadedB.artistAffinities, isEmpty);

      // Clear User A's profile
      await repo.clearProfile('user_a');
      expect(box.containsKey('taste_profile_user_a'), isFalse);
    });

    test('6. Ranked and disliked helper methods operate accurately', () {
      final profile = UserTasteProfile(
        userId: 'u1',
        artistAffinities: const {
          'loved': 0.85,
          'liked': 0.65,
          'disliked': 0.35,
          'hated': 0.20,
        },
        languageAffinities: const {},
        lastUpdated: now,
        eventsProcessedCount: 20,
      );

      expect(profile.topArtists(limit: 2), equals(['loved', 'liked']));
      expect(profile.dislikedArtists(threshold: 0.40), containsAll(['disliked', 'hated']));
    });
  });
}
