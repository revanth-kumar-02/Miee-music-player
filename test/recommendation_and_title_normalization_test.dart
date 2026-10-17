import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/history/data/listening_history_repository.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/profile/domain/user_profile.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_metadata_cleaner.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';

import 'package:Miee/shared/models/music_item.dart';

class MockYouTubeRepository implements YouTubeRepository {
  final Map<String, List<YouTubeVideo>> queryResponses;

  MockYouTubeRepository(this.queryResponses);

  @override
  Future<List<YouTubeVideo>> search(String query) async {
    for (final entry in queryResponses.entries) {
      if (query.toLowerCase().contains(entry.key.toLowerCase())) {
        return entry.value;
      }
    }
    return [];
  }

  @override
  void clearCache() {}

  @override
  Future<List<String>> getSuggestions(String query) async => [];
}

class MockArtistRepository implements ArtistRepository {
  final List<ArtistModel> related;

  MockArtistRepository({this.related = const []});

  @override
  Future<List<ArtistModel>> getPopularArtists({String? language}) async => [];

  @override
  Future<List<ArtistModel>> searchArtists(String query, {String? language}) async => [];

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async => related;

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async => [];

  @override
  Future<ArtistModel?> getArtistDetails(String artistId) async => null;

  @override
  Future<List<ArtistTopTrack>> getArtistTopTracks(String artistId) async => [];

  @override
  List<String> getSupportedLanguages() => ['Tamil', 'Hindi', 'Telugu', 'English'];
}

class MockHistoryRepository implements ListeningHistoryRepository {
  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {}

  @override
  Future<List<ListeningEvent>> getRecentHistory({required String? uid, int limit = 30}) async => [];

  @override
  Future<void> clearHistory(String? uid) async {}
}

void main() {
  group('Issue 1 & 2: Discover More Candidate Filtering & Classification', () {
    test('1. Rejects a 29-minute playlist compilation', () {
      const compilation = YouTubeVideo(
        id: 'comp_29m',
        title: 'Best Tamil Songs Playlist 2024 Non Stop',
        channelTitle: 'Music Label',
        thumbnailUrl: 'https://img.youtube.com/vi/comp_29m/0.jpg',
        duration: '29:15',
        viewCount: '1M views',
      );

      expect(RecommendationService.isLegitimateSong(compilation), isFalse);
    });

    test('2. Rejects Top 10 and Top 20 collections', () {
      const top10 = YouTubeVideo(
        id: 'top10',
        title: 'Top 10 Tamil Melody Songs of Anirudh',
        channelTitle: 'Tamil Hits',
        thumbnailUrl: 'https://img.youtube.com/vi/top10/0.jpg',
        duration: '42:10',
        viewCount: '500K views',
      );

      const top20 = YouTubeVideo(
        id: 'top20',
        title: 'Top 20 Hit Songs 2023 | Latest Hits',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://img.youtube.com/vi/top20/0.jpg',
        duration: '18:30',
        viewCount: '800K views',
      );

      expect(RecommendationService.isLegitimateSong(top10), isFalse);
      expect(RecommendationService.isLegitimateSong(top20), isFalse);
    });

    test('3. Rejects Jukeboxes and continuous mixes', () {
      const jukebox = YouTubeVideo(
        id: 'juke1',
        title: 'A.R. Rahman Hits Audio Jukebox | All Time Melodies',
        channelTitle: 'Saregama Tamil',
        thumbnailUrl: 'https://img.youtube.com/vi/juke1/0.jpg',
        duration: '35:20',
        viewCount: '2M views',
      );

      const continuousMix = YouTubeVideo(
        id: 'mix1',
        title: 'Harris Jayaraj Non Stop Continuous Mix',
        channelTitle: 'Star Music',
        thumbnailUrl: 'https://img.youtube.com/vi/mix1/0.jpg',
        duration: '22:15',
        viewCount: '400K views',
      );

      expect(RecommendationService.isLegitimateSong(jukebox), isFalse);
      expect(RecommendationService.isLegitimateSong(continuousMix), isFalse);
    });

    test('4. Preserves a genuine long individual song (e.g. 14-18 minute piece or classical)', () {
      const longClassical = YouTubeVideo(
        id: 'raga1',
        title: 'Kalyani Raga Alapana - Sudha Ragunathan',
        channelTitle: 'Carnatic Music',
        thumbnailUrl: 'https://img.youtube.com/vi/raga1/0.jpg',
        duration: '16:45',
        viewCount: '150K views',
      );

      const longRockEpic = YouTubeVideo(
        id: 'epic1',
        title: 'Echoes (2023 Remaster)',
        channelTitle: 'Pink Floyd',
        thumbnailUrl: 'https://img.youtube.com/vi/epic1/0.jpg',
        duration: '14:20',
        viewCount: '3M views',
      );

      expect(RecommendationService.isLegitimateSong(longClassical), isTrue);
      expect(RecommendationService.isLegitimateSong(longRockEpic), isTrue);
    });

    test('5. Rejects podcast episodes and spoken-word videos', () {
      const podcast = YouTubeVideo(
        id: 'pod1',
        title: 'The Ranveer Show Podcast Episode #152 with Anirudh',
        channelTitle: 'BeerBiceps',
        thumbnailUrl: 'https://img.youtube.com/vi/pod1/0.jpg',
        duration: '45:10',
        viewCount: '1.2M views',
      );

      const interview = YouTubeVideo(
        id: 'inter1',
        title: 'Exclusive Interview with G.V. Prakash Kumar | Film Companion',
        channelTitle: 'Film Companion South',
        thumbnailUrl: 'https://img.youtube.com/vi/inter1/0.jpg',
        duration: '28:40',
        viewCount: '300K views',
      );

      expect(RecommendationService.isLegitimateSong(podcast), isFalse);
      expect(RecommendationService.isLegitimateSong(interview), isFalse);
    });

    test('6. Preserves an ordinary standalone song, even with ambiguous terms like "hits" or "official video"', () {
      const standardSong = YouTubeVideo(
        id: 'aalaporan',
        title: 'Aalaporaan Thamizhan | Mersal | Official Video | AR Rahman Hits',
        channelTitle: 'Sony Music South',
        thumbnailUrl: 'https://img.youtube.com/vi/aalaporan/0.jpg',
        duration: '4:35',
        viewCount: '150M views',
      );

      expect(RecommendationService.isLegitimateSong(standardSong), isTrue);
    });
  });

  group('Issue 3: Song Title Normalization & Credit Extraction', () {
    test('7. Normalizes "Radhimaa | Bhagyashri Borse | ..." with reliable metadata', () {
      final cleaned = YouTubeMetadataCleaner.clean(
        rawTitle: 'Radhimaa | Bhagyashri Borse | Dulquer Salmaan | GV Prakash Kumar | Official Video',
        rawChannel: 'Saregama South',
        reliableArtist: 'G. V. Prakash Kumar',
        reliableTitle: 'Radhimaa',
      );

      expect(cleaned.title, equals('Radhimaa'));
      expect(cleaned.artist, equals('G. V. Prakash Kumar'));
      expect(cleaned.rawTitle, equals('Radhimaa | Bhagyashri Borse | Dulquer Salmaan | GV Prakash Kumar | Official Video'));
    });

    test('8. Normalizes "Pavazha Malli | Kayadu | Shruti ..." with reliable metadata', () {
      final cleaned = YouTubeMetadataCleaner.clean(
        rawTitle: 'Pavazha Malli | Kayadu Lohar | Shruti Haasan | Santhosh Narayanan | Lyric Video',
        rawChannel: 'Think Music India',
        reliableArtist: 'Santhosh Narayanan',
      );

      expect(cleaned.title, equals('Pavazha Malli'));
      expect(cleaned.artist, equals('Santhosh Narayanan'));
    });

    test('9. Preserves titles containing legitimate separators without destructive splitting', () {
      final breatheCleaned = YouTubeMetadataCleaner.clean(
        rawTitle: 'Pink Floyd - Breathe - In the Air',
        rawChannel: 'Pink Floyd',
      );
      expect(breatheCleaned.title, equals('Breathe - In the Air'));

      final part1Cleaned = YouTubeMetadataCleaner.clean(
        rawTitle: 'Shine On You Crazy Diamond - Part 1',
        rawChannel: 'Pink Floyd',
      );
      expect(part1Cleaned.title, equals('Shine On You Crazy Diamond - Part 1'));

      final acousticCleaned = YouTubeMetadataCleaner.clean(
        rawTitle: 'Ghost - Acoustic',
        rawChannel: 'Justin Bieber',
      );
      expect(acousticCleaned.title, equals('Ghost - Acoustic'));
    });

    test('10. Handles missing or ambiguous artist metadata without fabricating artist credits', () {
      final cleaned = YouTubeMetadataCleaner.clean(
        rawTitle: 'Mysterious Melodies in the Dark',
        rawChannel: 'Chill Vibes Channel',
      );

      expect(cleaned.title, equals('Mysterious Melodies in the Dark'));
      // Does not invent a composer or performer, gracefully preserves channel
      expect(cleaned.artist, equals('Chill Vibes Channel'));
    });
  });

  group('Discover More Fallback & Multi-Tier Resolution', () {
    test('11. Discover More falls back when filtering eliminates non-songs and leaves too few results', () async {
      // Setup mock YouTube repo where the first related artist returns ONLY compilations & podcasts
      final mockYt = MockYouTubeRepository({
        'rel_bad song': [
          const YouTubeVideo(
            id: 'c1',
            title: 'Top 20 Hit Songs Compilation',
            channelTitle: 'Label',
            thumbnailUrl: '',
            duration: '29:00',
            viewCount: '100K',
          ),
          const YouTubeVideo(
            id: 'c2',
            title: 'All Songs Jukebox Non Stop',
            channelTitle: 'Label',
            thumbnailUrl: '',
            duration: '45:00',
            viewCount: '200K',
          ),
        ],
        'fav_good song': [
          const YouTubeVideo(
            id: 'good1',
            title: 'Hukum | Jailer | Official Audio',
            channelTitle: 'Sun TV',
            thumbnailUrl: '',
            duration: '3:20',
            viewCount: '50M',
          ),
          const YouTubeVideo(
            id: 'good2',
            title: 'Naa Ready | Leo | Official Audio',
            channelTitle: 'Sony Music South',
            thumbnailUrl: '',
            duration: '3:45',
            viewCount: '80M',
          ),
          const YouTubeVideo(
            id: 'good3',
            title: 'Badass | Leo | Official Audio',
            channelTitle: 'Sony Music South',
            thumbnailUrl: '',
            duration: '3:50',
            viewCount: '40M',
          ),
        ],
        'rahman song': [
          const YouTubeVideo(
            id: 'good4',
            title: 'Chaiyya Chaiyya | Dil Se | Official Audio',
            channelTitle: 'Sony Music India',
            thumbnailUrl: '',
            duration: '4:10',
            viewCount: '300M',
          ),
        ],
      });

      final mockArtistRepo = MockArtistRepository(
        related: [
          const ArtistModel(
            id: 'rel_1',
            name: 'rel_bad',
            imageUrl: 'https://example.com/rel1.jpg',
          ),
        ],
      );

      final service = RecommendationService(
        youtubeRepo: mockYt,
        artistRepo: mockArtistRepo,
        historyRepo: MockHistoryRepository(),
      );

      final profile = UserProfile(
        uid: 'test_uid',
        email: 'user@example.com',
        displayName: 'Test User',
        onboardingCompleted: true,
        selectedArtists: const [
          ArtistSummary(id: 'fav_1', name: 'fav_good', imageUrl: ''),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final sections = await service.getPersonalizedSections(profile: profile);

      // Verify that discoverMore did NOT accept the 29-minute compilation or jukebox
      final compilationIds = {'c1', 'c2'};
      for (final item in sections.discoverMore) {
        expect(compilationIds.contains(item.id.replaceFirst('youtube_', '')), isFalse);
      }

      // Verify that Discover More fell back to the next tiers and collected legitimate songs
      expect(sections.discoverMore.isNotEmpty, isTrue);
      expect(sections.discoverMore.any((item) => item.title.contains('Chaiyya') || item.title.contains('Badass')), isTrue);
    });
  });
}
