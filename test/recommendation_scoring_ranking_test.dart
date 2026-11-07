import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/recommendations/domain/candidate_ranker.dart';
import 'package:Miee/features/recommendations/domain/recommendation_scorer.dart';
import 'package:Miee/features/recommendations/domain/user_taste_profile.dart';

void main() {
  final now = DateTime(2026, 11, 7, 14, 0, 0);

  group('RecommendationScorer - Language Scoring', () {
    const scorer = RecommendationScorer();
    final emptyProfile = UserTasteProfile.empty('user_1');

    test('Primary language preference awards +60', () {
      final track = Track(
        id: 't_tamil',
        title: 'Naa Ready (From Leo) [Tamil]',
        artist: 'Anirudh Ravichander',
        duration: '3:30',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: ['Tamil', 'Telugu'],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      expect(score.languageScore, equals(60.0));
    });

    test('Secondary language preference awards +40', () {
      final track = Track(
        id: 't_telugu',
        title: 'Butta Bomma (Telugu)',
        artist: 'Thaman S',
        duration: '3:15',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: ['Tamil', 'Telugu'],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      expect(score.languageScore, equals(40.0));
    });

    test('Language mismatch penalizes with -30', () {
      final track = Track(
        id: 't_hindi',
        title: 'Tum Hi Ho [Hindi Song]',
        artist: 'Arijit Singh',
        duration: '4:20',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: ['Tamil', 'Telugu'],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      expect(score.languageScore, equals(-30.0));
    });

    test('Unknown language awards neutral 0', () {
      final track = Track(
        id: 't_unknown',
        title: 'Dreaming in Echoes',
        artist: 'Random Indie Acoustic Band',
        duration: '2:45',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: ['Tamil'],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      expect(score.languageScore, equals(0.0));
    });
  });

  group('RecommendationScorer - Artist Affinity Scoring', () {
    const scorer = RecommendationScorer();

    test('High positive affinity (0.90) awards +64', () {
      final profile = UserTasteProfile(
        userId: 'u1',
        artistAffinities: {'coldplay': 0.90},
        languageAffinities: {},
        lastUpdated: now,
        eventsProcessedCount: 10,
      );
      final track = Track(
        id: 't1',
        title: 'Yellow',
        artist: 'Coldplay',
        duration: '4:29',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: profile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      // (0.90 - 0.50) * 160 = +64.0
      expect(score.artistScore, equals(64.0));
    });

    test('Liked artist affinity (0.75) awards +40', () {
      final profile = UserTasteProfile(
        userId: 'u1',
        artistAffinities: {'anirudh': 0.75},
        languageAffinities: {},
        lastUpdated: now,
        eventsProcessedCount: 10,
      );
      final track = Track(
        id: 't2',
        title: 'Hukum',
        artist: 'Anirudh',
        duration: '3:20',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: profile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      // (0.75 - 0.50) * 160 = +40.0
      expect(score.artistScore, equals(40.0));
    });

    test('Neutral baseline / unseen artist (0.50) awards neutral 0', () {
      final emptyProfile = UserTasteProfile.empty('u1');
      final track = Track(
        id: 't3',
        title: 'Unknown Melody',
        artist: 'Unseen Band',
        duration: '3:00',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      // (0.50 - 0.50) * 160 = 0.0
      expect(score.artistScore, equals(0.0));
    });

    test('Negative affinity / disliked artist (0.25) penalizes with -40', () {
      final profile = UserTasteProfile(
        userId: 'u1',
        artistAffinities: {'bad singer': 0.25},
        languageAffinities: {},
        lastUpdated: now,
        eventsProcessedCount: 10,
      );
      final track = Track(
        id: 't4',
        title: 'Annoying Track',
        artist: 'Bad Singer',
        duration: '2:15',
        imageUrl: '',
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: profile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        now: now,
      );

      // (0.25 - 0.50) * 160 = -40.0
      expect(score.artistScore, equals(-40.0));
    });
  });

  group('RecommendationScorer - Chart Popularity Scoring', () {
    const scorer = RecommendationScorer();
    final emptyProfile = UserTasteProfile.empty('u1');

    test('Chart Rank 1 receives maximum +30', () {
      final track = Track(id: 't_top', title: 'Song 1', artist: 'Artist 1', duration: '3:00', imageUrl: '');
      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {'t_top': 1},
        recentHistory: [],
        now: now,
      );
      expect(score.chartScore, equals(30.0));
    });

    test('Chart Rank 50 receives minimum +5', () {
      final track = Track(id: 't_tail', title: 'Song 50', artist: 'Artist 50', duration: '3:00', imageUrl: '');
      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {'t_tail': 50},
        recentHistory: [],
        now: now,
      );
      expect(score.chartScore, equals(5.0));
    });

    test('Chart ranks between 1 and 50 interpolate deterministically', () {
      final track = Track(id: 't_mid', title: 'Song Mid', artist: 'Artist Mid', duration: '3:00', imageUrl: '');
      // Rank 25.5 midpoint -> ~17.5
      // Rank 26: 30 - (25 / 49) * 25 = 30 - 12.7551 = 17.24
      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {'t_mid': 26},
        recentHistory: [],
        now: now,
      );
      expect(score.chartScore, equals(17.24));
    });

    test('Unranked track receives 0 chart score', () {
      final track = Track(id: 't_none', title: 'Non Chart', artist: 'Non Chart', duration: '3:00', imageUrl: '');
      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {'other': 1},
        recentHistory: [],
        now: now,
      );
      expect(score.chartScore, equals(0.0));
    });
  });

  group('RecommendationScorer - Track Fatigue Penalty', () {
    const scorer = RecommendationScorer();
    final emptyProfile = UserTasteProfile.empty('u1');
    final track = Track(id: 't_fatigue', title: 'Repeat Track', artist: 'Singer A', duration: '3:00', imageUrl: '');

    test('Played within 24 hours receives -100 penalty', () {
      final event = ListeningEvent(
        id: 'e1',
        trackId: 't_fatigue',
        title: 'Repeat Track',
        artist: 'Singer A',
        source: 'youtube',
        timestamp: now.subtract(const Duration(hours: 4)),
        durationSec: 180,
        listenedSec: 180,
        completionRatio: 1.0,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [event],
        now: now,
      );

      expect(score.fatiguePenalty, equals(100.0));
    });

    test('Played within 7 days receives -50 penalty', () {
      final event = ListeningEvent(
        id: 'e2',
        trackId: 't_fatigue',
        title: 'Repeat Track',
        artist: 'Singer A',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 4)),
        durationSec: 180,
        listenedSec: 180,
        completionRatio: 1.0,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [event],
        now: now,
      );

      expect(score.fatiguePenalty, equals(50.0));
    });

    test('Played older than 7 days receives 0 penalty', () {
      final event = ListeningEvent(
        id: 'e3',
        trackId: 't_fatigue',
        title: 'Repeat Track',
        artist: 'Singer A',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 9)),
        durationSec: 180,
        listenedSec: 180,
        completionRatio: 1.0,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [event],
        now: now,
      );

      expect(score.fatiguePenalty, equals(0.0));
    });

    test('Duplicate history records do not double-penalize', () {
      final e1 = ListeningEvent(
        id: 'e1',
        trackId: 't_fatigue',
        title: 'Repeat Track',
        artist: 'Singer A',
        source: 'youtube',
        timestamp: now.subtract(const Duration(hours: 2)),
        durationSec: 180,
        listenedSec: 180,
        completionRatio: 1.0,
      );
      final e2 = ListeningEvent(
        id: 'e2',
        trackId: 't_fatigue',
        title: 'Repeat Track',
        artist: 'Singer A',
        source: 'youtube',
        timestamp: now.subtract(const Duration(hours: 6)),
        durationSec: 180,
        listenedSec: 180,
        completionRatio: 1.0,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [e1, e2],
        now: now,
      );

      expect(score.fatiguePenalty, equals(100.0));
    });
  });

  group('RecommendationScorer - Skip Penalty', () {
    const scorer = RecommendationScorer();
    final emptyProfile = UserTasteProfile.empty('u1');
    final track = Track(id: 't_skip', title: 'Skipped Song', artist: 'Artist S', duration: '3:00', imageUrl: '');

    test('Single recent skip does NOT trigger -80 skip penalty', () {
      final skip1 = ListeningEvent(
        id: 's1',
        trackId: 't_skip',
        title: 'Skipped Song',
        artist: 'Artist S',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 2)),
        durationSec: 180,
        listenedSec: 5,
        completionRatio: 0.02,
        eventType: ListeningEventType.skip,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [skip1],
        now: now,
      );

      expect(score.skipPenalty, equals(0.0));
    });

    test('Two recent skips within 14 days trigger -80 skip penalty', () {
      final skip1 = ListeningEvent(
        id: 's1',
        trackId: 't_skip',
        title: 'Skipped Song',
        artist: 'Artist S',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 3)),
        durationSec: 180,
        listenedSec: 5,
        completionRatio: 0.02,
        eventType: ListeningEventType.skip,
      );
      final skip2 = ListeningEvent(
        id: 's2',
        trackId: 't_skip',
        title: 'Skipped Song',
        artist: 'Artist S',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 1)),
        durationSec: 180,
        listenedSec: 8,
        completionRatio: 0.04,
        eventType: ListeningEventType.skip,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [skip1, skip2],
        now: now,
      );

      expect(score.skipPenalty, equals(80.0));
    });

    test('Old skips outside 14-day window are excluded', () {
      final skip1 = ListeningEvent(
        id: 's1',
        trackId: 't_skip',
        title: 'Skipped Song',
        artist: 'Artist S',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 16)), // > 14 days ago
        durationSec: 180,
        listenedSec: 5,
        completionRatio: 0.02,
        eventType: ListeningEventType.skip,
      );
      final skip2 = ListeningEvent(
        id: 's2',
        trackId: 't_skip',
        title: 'Skipped Song',
        artist: 'Artist S',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 20)),
        durationSec: 180,
        listenedSec: 5,
        completionRatio: 0.02,
        eventType: ListeningEventType.skip,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [skip1, skip2],
        now: now,
      );

      expect(score.skipPenalty, equals(0.0));
    });

    test('Duplicate skip event IDs are de-duplicated and do not falsely trigger -80', () {
      final skipDup = ListeningEvent(
        id: 'same_event_id',
        trackId: 't_skip',
        title: 'Skipped Song',
        artist: 'Artist S',
        source: 'youtube',
        timestamp: now.subtract(const Duration(days: 1)),
        durationSec: 180,
        listenedSec: 5,
        completionRatio: 0.02,
        eventType: ListeningEventType.skip,
      );

      final score = scorer.scoreCandidate(
        track: track,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [skipDup, skipDup],
        now: now,
      );

      expect(score.skipPenalty, equals(0.0));
    });
  });

  group('RecommendationDiversityFilter & CandidateRanker', () {
    const ranker = CandidateRanker();

    test('Enforces maximum 2 tracks per normalized artist', () {
      final profile = UserTasteProfile(
        userId: 'u1',
        artistAffinities: const {'anirudh': 0.85},
        languageAffinities: const {},
        lastUpdated: now,
        eventsProcessedCount: 10,
      );

      final candidates = [
        Track(id: 't1', title: 'Song 1', artist: 'Anirudh', duration: '3:00', imageUrl: ''),
        Track(id: 't2', title: 'Song 2', artist: 'Anirudh', duration: '3:00', imageUrl: ''),
        Track(id: 't3', title: 'Song 3', artist: 'Anirudh - Topic', duration: '3:00', imageUrl: ''),
        Track(id: 't4', title: 'Song 4', artist: 'A.R. Rahman', duration: '3:00', imageUrl: ''),
        Track(id: 't5', title: 'Song 5', artist: 'Harris Jayaraj', duration: '3:00', imageUrl: ''),
      ];

      final ranked = ranker.rankCandidates(
        candidates: candidates,
        tasteProfile: profile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        limit: 4,
      );

      final anirudhCount = ranked.where((t) => t.artist.toLowerCase().contains('anirudh')).length;
      expect(anirudhCount, lessThanOrEqualTo(2));
      expect(ranked.length, equals(4));
    });

    test('Suppresses duplicate tracks from the same film soundtrack', () {
      final emptyProfile = UserTasteProfile.empty('u1');

      final candidates = [
        Track(id: 't1', title: 'Badass (From Leo)', artist: 'Anirudh', duration: '3:00', imageUrl: ''),
        Track(id: 't2', title: 'Ordinary Person (From Leo)', artist: 'Anirudh', duration: '3:00', imageUrl: ''),
        Track(id: 't3', title: 'Matta (From The GOAT)', artist: 'Yuvan', duration: '3:00', imageUrl: ''),
      ];

      final ranked = ranker.rankCandidates(
        candidates: candidates,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        limit: 2,
      );

      // Only one song from "Leo" should be present in top ranked
      final leoCount = ranked.where((t) => t.title.toLowerCase().contains('leo')).length;
      expect(leoCount, equals(1));
    });

    test('Preserves familiar and discovery mix (70/30 target)', () {
      final profile = UserTasteProfile(
        userId: 'u1',
        artistAffinities: const {
          'familiar artist a': 0.85,
          'familiar artist b': 0.80,
          'familiar artist c': 0.75,
        },
        languageAffinities: const {},
        lastUpdated: now,
        eventsProcessedCount: 20,
      );

      final candidates = [
        Track(id: 'f1', title: 'Fam 1', artist: 'Familiar Artist A', duration: '3:00', imageUrl: ''),
        Track(id: 'f2', title: 'Fam 2', artist: 'Familiar Artist B', duration: '3:00', imageUrl: ''),
        Track(id: 'f3', title: 'Fam 3', artist: 'Familiar Artist C', duration: '3:00', imageUrl: ''),
        Track(id: 'd1', title: 'Disc 1', artist: 'New Indie Artist 1', duration: '3:00', imageUrl: ''),
        Track(id: 'd2', title: 'Disc 2', artist: 'New Indie Artist 2', duration: '3:00', imageUrl: ''),
      ];

      final ranked = ranker.rankCandidates(
        candidates: candidates,
        tasteProfile: profile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        limit: 4,
      );

      expect(ranked.length, equals(4));
      // At least 1 discovery track must be included even when familiar tracks are present
      final discoveryItems = ranked.where((t) => t.artist.startsWith('New Indie')).toList();
      expect(discoveryItems.isNotEmpty, isTrue);
    });

    test('Gracefully falls back when insufficient candidates exist without crash', () {
      final emptyProfile = UserTasteProfile.empty('u1');
      final candidates = [
        Track(id: 't1', title: 'Solo Track', artist: 'Solo Singer', duration: '3:00', imageUrl: ''),
      ];

      final ranked = ranker.rankCandidates(
        candidates: candidates,
        tasteProfile: emptyProfile,
        preferredLanguages: [],
        chartRanks: {},
        recentHistory: [],
        limit: 10,
      );

      expect(ranked.length, equals(1));
      expect(ranked.first.id, equals('t1'));
    });

    test('REC-01 Regression: Discover candidates are not self-excluded by prior shelf exclusion sets', () {
      final emptyProfile = UserTasteProfile.empty('u1');
      const priorShelfTrackIds = {'prior_1', 'prior_2'};
      const priorShelfTrackKeys = {'old song|artist a', 'legacy tune|artist b'};

      const candidates = [
        Track(id: 'cand_1', title: 'Fresh Song 1', artist: 'Artist X', duration: '3:00', imageUrl: ''),
        Track(id: 'cand_2', title: 'Fresh Song 2', artist: 'Artist Y', duration: '3:00', imageUrl: ''),
        Track(id: 'prior_1', title: 'Old Song', artist: 'Artist A', duration: '3:00', imageUrl: ''),
      ];

      final ranked = ranker.rankCandidates(
        candidates: candidates,
        tasteProfile: emptyProfile,
        preferredLanguages: const [],
        chartRanks: const {},
        recentHistory: const [],
        limit: 5,
        excludedTrackIds: priorShelfTrackIds,
        excludedRecordingKeys: priorShelfTrackKeys,
      );

      // cand_1 and cand_2 must be preserved and ranked; prior_1 must be excluded
      expect(ranked.length, equals(2));
      expect(ranked.map((t) => t.id).toSet(), equals({'cand_1', 'cand_2'}));
    });

    test('Strict Diversity Backfill: Strictly enforces maxTracksPerArtist as hard limit (no +1 leak)', () {
      final emptyProfile = UserTasteProfile.empty('u1');
      // 5 songs by Monopolizing Singer, 1 song by Indie Singer
      const candidates = [
        Track(id: 'm1', title: 'Track 1', artist: 'Monopolizing Singer', duration: '3:00', imageUrl: ''),
        Track(id: 'm2', title: 'Track 2', artist: 'Monopolizing Singer', duration: '3:00', imageUrl: ''),
        Track(id: 'm3', title: 'Track 3', artist: 'Monopolizing Singer', duration: '3:00', imageUrl: ''),
        Track(id: 'm4', title: 'Track 4', artist: 'Monopolizing Singer', duration: '3:00', imageUrl: ''),
        Track(id: 'm5', title: 'Track 5', artist: 'Monopolizing Singer', duration: '3:00', imageUrl: ''),
        Track(id: 'i1', title: 'Track 6', artist: 'Indie Singer', duration: '3:00', imageUrl: ''),
      ];

      final ranked = ranker.rankCandidates(
        candidates: candidates,
        tasteProfile: emptyProfile,
        preferredLanguages: const [],
        chartRanks: const {},
        recentHistory: const [],
        limit: 5, // Request 5 tracks
      );

      // Max 2 from Monopolizing Singer + 1 from Indie Singer = 3 total.
      // Must NOT leak 3 tracks from Monopolizing Singer (maxTracksPerArtist + 1)
      final monoCount = ranked.where((t) => t.artist == 'Monopolizing Singer').length;
      expect(monoCount, equals(2));
      expect(ranked.length, equals(3));
    });

    test('Strict Diversity Backfill: Soundtrack cap is strictly respected during backfill', () {
      final emptyProfile = UserTasteProfile.empty('u1');
      // Multiple songs from same soundtrack by different singers
      const candidates = [
        Track(id: 's1', title: 'Song One (From Pushpa)', artist: 'Singer A', duration: '3:00', imageUrl: ''),
        Track(id: 's2', title: 'Song Two (From Pushpa)', artist: 'Singer B', duration: '3:00', imageUrl: ''),
        Track(id: 's3', title: 'Song Three (From Pushpa)', artist: 'Singer C', duration: '3:00', imageUrl: ''),
        Track(id: 'o1', title: 'Other Movie Song (From RRR)', artist: 'Singer D', duration: '3:00', imageUrl: ''),
      ];

      final ranked = ranker.rankCandidates(
        candidates: candidates,
        tasteProfile: emptyProfile,
        preferredLanguages: const [],
        chartRanks: const {},
        recentHistory: const [],
        limit: 4,
      );

      final pushpaCount = ranked.where((t) => t.title.toLowerCase().contains('pushpa')).length;
      expect(pushpaCount, equals(1));
    });
  });
}
