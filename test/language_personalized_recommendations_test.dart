import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/recommendations/data/trending_music_service.dart';
import 'package:Miee/features/recommendations/domain/music_language_service.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

class MockYouTubeRepo implements YouTubeRepository {
  final Map<String, List<YouTubeVideo>> responses;

  MockYouTubeRepo(this.responses);

  @override
  Future<List<YouTubeVideo>> search(String query, {int page = 1, bool forceFresh = false}) async {
    final lower = query.toLowerCase();
    for (final entry in responses.entries) {
      if (lower.contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return [];
  }

  @override
  Future<List<YouTubeVideo>> getArtistTracks(
    String artistName, {
    int page = 1,
    int limit = 15,
    List<String> preferredLanguages = const [],
  }) async {
    final candidateVideos = <YouTubeVideo>[];
    final topLang = preferredLanguages.isNotEmpty ? preferredLanguages.first : null;
    if (page == 1 && topLang != null && MusicLanguageService.isArtistMultilingualInLang(artistName, topLang)) {
      final langVideos = await search('$artistName $topLang songs', page: 1);
      candidateVideos.addAll(langVideos);
    }
    final mainVideos = await search('$artistName songs', page: page);
    candidateVideos.addAll(mainVideos);
    final deduplicated = SearchDeduplicator.deduplicateAndRank(
      candidateVideos,
      query: artistName,
    );
    return deduplicated.take(limit).toList();
  }

  @override
  void clearCache() {}

  @override
  Future<List<String>> getSuggestions(String query) async => [];

  @override
  Future<List<ArtistModel>> searchArtists(String query) async => const [];

  @override
  Future<List<YouTubeVideo>> getRelatedTracks(YouTubeVideo seed, {int limit = 15}) async => [];
}

class MockArtistRepo implements ArtistRepository {
  @override
  Future<List<ArtistModel>> getPopularArtists({String? language}) async => [];

  @override
  Future<List<ArtistModel>> searchArtists(String query, {String? language}) async => [];

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async => [];

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async => [];

  @override
  Future<ArtistModel?> getArtistDetails(String artistId) async => null;

  @override
  Future<List<ArtistTopTrack>> getArtistTopTracks(String artistId) async => [];

  @override
  List<String> getSupportedLanguages() => ['Tamil', 'Hindi', 'Telugu', 'English'];
}

class MockListeningHistoryRepo implements ListeningHistoryRepository {
  final Map<String, List<ListeningEvent>> userHistories = {};

  void setHistoryForUser(String uid, List<ListeningEvent> events) {
    userHistories[uid] = events;
  }

  @override
  Future<List<ListeningEvent>> getRecentHistory({required String? uid, int limit = 30}) async {
    if (uid == null) return [];
    return (userHistories[uid] ?? []).take(limit).toList();
  }

  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {
    if (uid == null) return;
    final event = ListeningEvent(
      id: 'event_${DateTime.now().millisecondsSinceEpoch}',
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      source: 'youtube',
      timestamp: DateTime.now(),
      durationSec: durationSec,
      listenedSec: listenedSec,
      completionRatio: durationSec > 0 ? (listenedSec / durationSec).clamp(0.0, 1.0) : 0.0,
    );
    userHistories.putIfAbsent(uid, () => []).insert(0, event);
  }

  @override
  Future<void> clearHistory(String? uid) async {
    if (uid != null) userHistories.remove(uid);
  }
}

class MockTrendingService extends TrendingMusicService {
  @override
  Future<TrendingResult> getTrendingAndRecentReleases({
    bool forceRefresh = false,
    String? regionCode,
  }) async {
    return TrendingResult(
      trendingTracks: const [],
      recentReleases: const [],
      fetchedAt: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Test Fixtures
  const anirudhSummary = ArtistSummary(
    id: '1516162',
    name: 'Anirudh Ravichander',
    imageUrl: 'https://example.com/anirudh.jpg',
  );

  const taylorSummary = ArtistSummary(
    id: '12246',
    name: 'Taylor Swift',
    imageUrl: 'https://example.com/taylor.jpg',
  );

  final mockVideos = <String, List<YouTubeVideo>>{
    'Anirudh Ravichander Tamil songs': [
      const YouTubeVideo(
        id: 'hukum_tam',
        title: 'Hukum [Tamil]',
        channelTitle: 'Sun TV',
        thumbnailUrl: 'https://example.com/hukum.jpg',
        duration: '3:20',
        viewCount: '50M',
      ),
      const YouTubeVideo(
        id: 'naa_ready_tam',
        title: 'Naa Ready [Tamil]',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://example.com/naa_ready.jpg',
        duration: '4:05',
        viewCount: '80M',
      ),
      const YouTubeVideo(
        id: 'badass_tam',
        title: 'Badass (Tamil)',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://example.com/badass.jpg',
        duration: '3:45',
        viewCount: '40M',
      ),
    ],
    'Anirudh Ravichander Hindi songs': [
      const YouTubeVideo(
        id: 'chaleya_hin',
        title: 'Chaleya [Hindi]',
        channelTitle: 'T-Series',
        thumbnailUrl: 'https://example.com/chaleya.jpg',
        duration: '3:20',
        viewCount: '100M',
      ),
      const YouTubeVideo(
        id: 'zinda_banda_hin',
        title: 'Zinda Banda [Hindi]',
        channelTitle: 'T-Series',
        thumbnailUrl: 'https://example.com/zinda.jpg',
        duration: '4:15',
        viewCount: '90M',
      ),
    ],
    'Anirudh Ravichander Telugu songs': [
      const YouTubeVideo(
        id: 'fear_song_tel',
        title: 'Fear Song [Telugu]',
        channelTitle: 'T-Series Telugu',
        thumbnailUrl: 'https://example.com/fear.jpg',
        duration: '3:15',
        viewCount: '30M',
      ),
      const YouTubeVideo(
        id: 'devara_tel',
        title: 'Chuttamalle [Telugu]',
        channelTitle: 'T-Series Telugu',
        thumbnailUrl: 'https://example.com/devara.jpg',
        duration: '3:40',
        viewCount: '45M',
      ),
    ],
    'Anirudh Ravichander songs': [
      const YouTubeVideo(
        id: 'fear_song_tel',
        title: 'Fear Song [Telugu]',
        channelTitle: 'T-Series Telugu',
        thumbnailUrl: 'https://example.com/fear.jpg',
        duration: '3:15',
        viewCount: '30M',
      ),
      const YouTubeVideo(
        id: 'chaleya_hin',
        title: 'Chaleya [Hindi]',
        channelTitle: 'T-Series',
        thumbnailUrl: 'https://example.com/chaleya.jpg',
        duration: '3:20',
        viewCount: '100M',
      ),
      const YouTubeVideo(
        id: 'hukum_tam',
        title: 'Hukum [Tamil]',
        channelTitle: 'Sun TV',
        thumbnailUrl: 'https://example.com/hukum.jpg',
        duration: '3:20',
        viewCount: '50M',
      ),
      const YouTubeVideo(
        id: 'naa_ready_tam',
        title: 'Naa Ready [Tamil]',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://example.com/naa_ready.jpg',
        duration: '4:05',
        viewCount: '80M',
      ),
    ],
    'Taylor Swift songs': [
      const YouTubeVideo(
        id: 'cruel_summer',
        title: 'Cruel Summer [Official Video]',
        channelTitle: 'Taylor Swift',
        thumbnailUrl: 'https://example.com/cruel.jpg',
        duration: '3:00',
        viewCount: '200M',
      ),
      const YouTubeVideo(
        id: 'anti_hero',
        title: 'Anti-Hero [Official Video]',
        channelTitle: 'Taylor Swift',
        thumbnailUrl: 'https://example.com/antihero.jpg',
        duration: '3:20',
        viewCount: '150M',
      ),
    ],
  };

  group('Miee — Language Personalized Recommendations Test Suite', () {
    late MockYouTubeRepo ytRepo;
    late MockArtistRepo artistRepo;
    late MockListeningHistoryRepo historyRepo;
    late RecommendationService recService;

    setUp(() {
      ytRepo = MockYouTubeRepo(mockVideos);
      artistRepo = MockArtistRepo();
      historyRepo = MockListeningHistoryRepo();
      recService = RecommendationService(
        youtubeRepo: ytRepo,
        artistRepo: artistRepo,
        historyRepo: historyRepo,
        trendingService: MockTrendingService(),
      );
    });

    test('1. A Tamil-preferred user with an artist who releases songs in multiple languages', () async {
      final tracks = await recService.getTracksForArtist(
        anirudhSummary,
        limit: 4,
        preferredLanguages: ['Tamil'],
      );

      expect(tracks.isNotEmpty, isTrue);
      // Top tracks must be in Tamil
      expect(tracks.first.title.toLowerCase().contains('tamil'), isTrue);
      final tamilCount = tracks.where((t) => t.title.toLowerCase().contains('tamil')).length;
      expect(tamilCount, greaterThanOrEqualTo(2));
    });

    test('2. A user whose strongest preference is Hindi', () async {
      final tracks = await recService.getTracksForArtist(
        anirudhSummary,
        limit: 4,
        preferredLanguages: ['Hindi'],
      );

      expect(tracks.isNotEmpty, isTrue);
      // Top tracks must be in Hindi
      expect(tracks.first.title.toLowerCase().contains('hindi'), isTrue);
      expect(tracks.any((t) => t.title.contains('Chaleya')), isTrue);
    });

    test('3. A multilingual user with two or more strong language preferences (Tamil + Telugu)', () async {
      // User with plays in both Tamil and Telugu
      final history = [
        ListeningEvent(
          id: '1',
          trackId: 'hukum',
          title: 'Hukum [Tamil]',
          artist: 'Anirudh',
          source: 'youtube',
          timestamp: DateTime.now(),
          durationSec: 200,
          listenedSec: 190,
          completionRatio: 0.95,
        ),
        ListeningEvent(
          id: '2',
          trackId: 'fear',
          title: 'Fear Song [Telugu]',
          artist: 'Anirudh',
          source: 'youtube',
          timestamp: DateTime.now(),
          durationSec: 200,
          listenedSec: 190,
          completionRatio: 0.95,
        ),
      ];

      final calculatedLanguages = MusicLanguageService.getPreferredLanguages(history: history);
      expect(calculatedLanguages.contains('Tamil'), isTrue);
      expect(calculatedLanguages.contains('Telugu'), isTrue);

      final tracks = await recService.getTracksForArtist(
        anirudhSummary,
        limit: 4,
        preferredLanguages: calculatedLanguages,
      );

      // Both Tamil and Telugu tracks must rank above any Hindi tracks
      final hindiIndex = tracks.indexWhere((t) => t.title.contains('[Hindi]'));
      final tamilIndex = tracks.indexWhere((t) => t.title.contains('[Tamil]'));
      final teluguIndex = tracks.indexWhere((t) => t.title.contains('[Telugu]'));

      expect(tamilIndex, lessThan(hindiIndex != -1 ? hindiIndex : 999));
      expect(teluguIndex, lessThan(hindiIndex != -1 ? hindiIndex : 999));
    });

    test('4. An artist with no matching tracks in the preferred language (Graceful Fallback)', () async {
      // User prefers Tamil, but artist is Taylor Swift (English only)
      final tracks = await recService.getTracksForArtist(
        taylorSummary,
        limit: 4,
        preferredLanguages: ['Tamil'],
      );

      // Must NOT return empty shelf or crash
      expect(tracks.isNotEmpty, isTrue);
      expect(tracks.first.artist, equals('Taylor Swift'));
      expect(tracks.first.title, contains('Cruel Summer'));
    });

    test('5. Tracks with missing language metadata', () {
      // Tracks without script or keyword tags
      final detected1 = MusicLanguageService.detectLanguage('Midnight Serenade', artist: 'Unknown Trio');
      final detected2 = MusicLanguageService.detectLanguage('Soundtrack Theme No. 4', artist: 'Anirudh Ravichander');

      // Conservative classification leaves them as 'Unknown'
      expect(detected1, equals('Unknown'));
      expect(detected2, equals('Unknown'));

      // Neutral scoring: not penalized or wrongly categorized
      const track = Track(id: '1', title: 'Instrumental Theme', artist: 'Anirudh', imageUrl: '', duration: '3:00');
      final scoreWithPrefs = MusicLanguageService.scoreTrack(track, ['Tamil'], baseRank: 100);
      expect(scoreWithPrefs, equals(100.0)); // neutral baseRank preserved
    });

    test('6. A user with no listening history (Cold Start)', () async {
      final preferredLanguages = MusicLanguageService.getPreferredLanguages(
        history: const [],
        profile: null,
      );

      // Must be empty: no hardcoded Tamil or any bias
      expect(preferredLanguages.isEmpty, isTrue);

      final tracks = await recService.getTracksForArtist(
        anirudhSummary,
        limit: 4,
        preferredLanguages: preferredLanguages,
      );

      expect(tracks.isNotEmpty, isTrue);
      // Standard search order preserved
      expect(tracks.first.title, contains('Fear Song'));
    });

    test('7. Repeated plays influencing language preference appropriately', () {
      final history = [
        // 5 repeated full plays of a Tamil track
        for (int i = 0; i < 5; i++)
          ListeningEvent(
            id: 'tam_$i',
            trackId: 'hukum',
            title: 'Hukum [Tamil]',
            artist: 'Anirudh',
            source: 'youtube',
            timestamp: DateTime.now().subtract(Duration(minutes: i * 10)),
            durationSec: 200,
            listenedSec: 200,
            completionRatio: 1.0,
          ),
        // 1 single brief play of a Hindi track (12 seconds)
        ListeningEvent(
          id: 'hin_1',
          trackId: 'chaleya',
          title: 'Chaleya [Hindi]',
          artist: 'Anirudh',
          source: 'youtube',
          timestamp: DateTime.now(),
          durationSec: 200,
          listenedSec: 12,
          completionRatio: 0.06,
        ),
      ];

      final preferred = MusicLanguageService.getPreferredLanguages(history: history);

      // Tamil must be the dominant and primary preferred language
      expect(preferred.isNotEmpty, isTrue);
      expect(preferred.first, equals('Tamil'));
      // The skipped Hindi play should not dilute or hijack the preference
      expect(preferred.contains('Hindi'), isFalse);
    });

    test('8. Unknown or ambiguous metadata does not produce false positives', () {
      // Title containing 'behind' shouldn't trigger 'hindi'
      final detected = MusicLanguageService.detectLanguage('Behind The Veil', artist: 'Rock Band');
      expect(detected, isNot(equals('Hindi')));

      // Title containing 'tam' inside 'contamination' shouldn't trigger 'tamil'
      final detectedTam = MusicLanguageService.detectLanguage('Contamination Area', artist: 'DJ Mix');
      expect(detectedTam, isNot(equals('Tamil')));
    });

    test('9. Duplicate songs appearing in recommendation results are deduplicated', () {
      const candidates = [
        Track(id: 'v1', title: 'Hukum [Tamil]', artist: 'Anirudh Ravichander', imageUrl: '', duration: '3:20'),
        Track(id: 'v2', title: 'Hukum (From "Jailer")', artist: 'Anirudh Ravichander', imageUrl: '', duration: '3:20'),
        Track(id: 'v3', title: 'Hukum - Official Audio', artist: 'Anirudh Ravichander', imageUrl: '', duration: '3:20'),
        Track(id: 'v4', title: 'Naa Ready [Tamil]', artist: 'Anirudh Ravichander', imageUrl: '', duration: '4:00'),
      ];

      final ranked = MusicLanguageService.rankAndDeduplicate(candidates, ['Tamil']);

      // "Hukum" should be deduplicated to 1 track, plus "Naa Ready"
      expect(ranked.length, equals(2));
      expect(ranked[0].title, contains('Hukum'));
      expect(ranked[1].title, contains('Naa Ready'));
    });

    test('10. Switching between user accounts without sharing preferences', () async {
      final now = DateTime.now();

      // User A (Tamil preference)
      final userA = UserProfile(
        uid: 'user_tamil_123',
        displayName: 'User Tamil',
        email: 'tamil@example.com',
        selectedArtists: [anirudhSummary],
        createdAt: now,
        updatedAt: now,
      );
      historyRepo.setHistoryForUser(userA.uid, [
        ListeningEvent(
          id: 'e1',
          trackId: 't1',
          title: 'Hukum [Tamil]',
          artist: 'Anirudh',
          source: 'youtube',
          timestamp: now,
          durationSec: 180,
          listenedSec: 180,
          completionRatio: 1.0,
        ),
      ]);

      // User B (Hindi preference)
      final userB = UserProfile(
        uid: 'user_hindi_456',
        displayName: 'User Hindi',
        email: 'hindi@example.com',
        selectedArtists: [anirudhSummary],
        createdAt: now,
        updatedAt: now,
      );
      historyRepo.setHistoryForUser(userB.uid, [
        ListeningEvent(
          id: 'e2',
          trackId: 't2',
          title: 'Chaleya [Hindi]',
          artist: 'Anirudh',
          source: 'youtube',
          timestamp: now,
          durationSec: 180,
          listenedSec: 180,
          completionRatio: 1.0,
        ),
      ]);

      // Fetch for User A
      final sectionsA = await recService.getPersonalizedSections(profile: userA);
      expect(sectionsA.fromYourArtists.isNotEmpty, isTrue);
      expect(sectionsA.fromYourArtists.first.title, contains('[Tamil]'));

      // Fetch for User B
      final sectionsB = await recService.getPersonalizedSections(profile: userB);
      expect(sectionsB.fromYourArtists.isNotEmpty, isTrue);
      expect(sectionsB.fromYourArtists.first.title, contains('[Hindi]'));

      // Ensure no state contamination: User B's recommendations did not receive User A's Tamil preference
      expect(sectionsB.fromYourArtists.first.title, isNot(contains('[Tamil]')));
    });
  });
}
