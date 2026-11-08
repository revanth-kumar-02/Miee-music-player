import 'package:flutter_test/flutter_test.dart';
import '../lib/features/search/domain/artist_classifier.dart';
import '../lib/features/search/data/artist_resolution_service.dart';
import '../lib/features/search/data/search_repository.dart';
import '../lib/features/search/domain/search_deduplicator.dart';
import '../lib/features/onboarding/data/artist_discovery_repository.dart';
import '../lib/features/onboarding/domain/artist_model.dart';
import '../lib/features/youtube/domain/youtube_model.dart';
import '../lib/shared/models/track.dart';

class MockArtistRepository implements ArtistRepository {
  int searchArtistsCallCount = 0;
  final Map<String, List<ArtistModel>> mockResponses;

  MockArtistRepository({this.mockResponses = const {}});

  @override
  Future<List<ArtistModel>> searchArtists(String query, {String? language}) async {
    searchArtistsCallCount++;
    // Simulate slight network latency
    await Future.delayed(const Duration(milliseconds: 30));
    return mockResponses[query] ?? const [];
  }

  @override
  Future<List<ArtistModel>> getPopularArtists({String? language}) async => [];

  @override
  Future<List<ArtistModel>> getRelatedArtists(String artistId) async => [];

  @override
  Future<ArtistModel?> getArtistDetails(String artistId) async => null;

  @override
  Future<List<ArtistAlbum>> getArtistAlbums(String artistId) async => [];

  @override
  Future<List<ArtistTopTrack>> getArtistTopTracks(String artistId) async => [];

  @override
  List<String> getSupportedLanguages() => ['English', 'Tamil', 'Hindi'];

  @override
  void clearCache() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PHASE 1: Artist Classification & Filtering Suite', () {
    test('1. Legitimate "West Coast" artists and bands are ACCEPTED', () {
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('Westcoast'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Massive', fanCount: 190), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Wolves', fanCount: 114), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast All Stars', fanCount: 48), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Crew', fanCount: 41), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Revival', fanCount: 20), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Jazz Ensemble', fanCount: 12), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Weekend', fanCount: 6), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Sound', fanCount: 3), isTrue);
    });

    test('2. Unrelated educational, sports, commercial, radio, and hobby entities are REJECTED', () {
      // Educational institution from user screenshot
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Baptist College'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Harvard University Alumni'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Springfield High School'), isFalse);

      // Sports club from user screenshot
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Eagles Football Club'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Chelsea FC'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Real Madrid Sports Club'), isFalse);

      // Commercial / vocational from user screenshot
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Dealing School'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Apex Realty Consulting LLC'), isFalse);

      // Radio & broadcast from user screenshot
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Hip Hop Radio'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Sunset FM 24/7 Livestream'), isFalse);

      // Hobby / gaming alliance from user screenshot
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast Gunpla Alliance'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Global Esports Gaming Clan'), isFalse);

      // Vibe aggregator from user screenshot
      expect(ArtistClassifier.isLegitimateMusicArtist('West Coast G-Funk Vibes'), isFalse);
      expect(ArtistClassifier.isLegitimateMusicArtist('Midnight Chill Vibes'), isFalse);
    });

    test('3. Ensembles and choirs associated with academies are safely rescued', () {
      expect(ArtistClassifier.isLegitimateMusicArtist('Berklee College of Music Choir'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('Oxford University Orchestra'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('London Symphony Orchestra'), isTrue);
    });

    test('4. Popular mainstream artists across languages are safely PRESERVED', () {
      expect(ArtistClassifier.isLegitimateMusicArtist('Anirudh Ravichander'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('A. R. Rahman'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('Lana Del Rey'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('Imagine Dragons'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('Kendrick Lamar'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('Taylor Swift'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('BTS'), isTrue);
      expect(ArtistClassifier.isLegitimateMusicArtist('Coldplay'), isTrue);
    });
  });

  group('PHASE 2: Artist Resolution & Network Optimization Suite', () {
    test('1. Resolving curated artist completes with ZERO network requests', () async {
      final mockRepo = MockArtistRepository();
      final service = ArtistResolutionService();

      const track = Track(
        id: 'track-1',
        title: 'Hukum',
        artist: 'Anirudh Ravichander',
        imageUrl: 'https://example.com/hukum.jpg',
        duration: '3:20',
      );

      final artist = await service.resolveTrackArtist(track, artistRepo: mockRepo);

      expect(mockRepo.searchArtistsCallCount, equals(0));
      expect(artist.name, equals('Anirudh Ravichander'));
      expect(artist.id.isNotEmpty, isTrue);
    });

    test('2. Multiple simultaneous track resolutions for same artist deduplicate to 1 network request', () async {
      final mockRepo = MockArtistRepository(
        mockResponses: {
          'Kavinsky': [
            const ArtistModel(
              id: 'deezer-999',
              name: 'Kavinsky',
              imageUrl: 'https://example.com/kavinsky.jpg',
              fanCount: 150000,
            ),
          ],
        },
      );
      final service = ArtistResolutionService();

      const tracks = [
        Track(id: 't-1', title: 'Nightcall', artist: 'Kavinsky', imageUrl: '', duration: '4:10'),
        Track(id: 't-2', title: 'Pacific Coast Highway', artist: 'Kavinsky', imageUrl: '', duration: '3:50'),
        Track(id: 't-3', title: 'Roadgame', artist: 'Kavinsky', imageUrl: '', duration: '4:00'),
        Track(id: 't-4', title: 'Protovision', artist: 'Kavinsky', imageUrl: '', duration: '3:30'),
      ];

      // Fire 4 simultaneous resolution calls (simulates scroll / multiple song cards)
      final results = await Future.wait(
        tracks.map((t) => service.resolveTrackArtist(t, artistRepo: mockRepo)),
      );

      expect(mockRepo.searchArtistsCallCount, equals(1));
      for (final a in results) {
        expect(a.id, equals('deezer-999'));
        expect(a.name, equals('Kavinsky'));
      }

      // Subsequent call reuses memory cache with zero network calls
      final cachedResult = await service.resolveTrackArtist(tracks.first, artistRepo: mockRepo);
      expect(mockRepo.searchArtistsCallCount, equals(1));
      expect(cachedResult.id, equals('deezer-999'));
    });

    test('3. Unrelated fuzzy match from online search is REJECTED and does not create false link', () async {
      final mockRepo = MockArtistRepository(
        mockResponses: {
          'Random Unknown Vocalist': [
            // Repository returns unrelated artist with a vaguely similar token
            const ArtistModel(
              id: 'deezer-fake-123',
              name: 'Completely Different Artist',
              imageUrl: 'https://example.com/fake.jpg',
              fanCount: 500,
            ),
          ],
        },
      );
      final service = ArtistResolutionService();

      const track = Track(
        id: 't-unknown',
        title: 'Independent Track',
        artist: 'Random Unknown Vocalist',
        imageUrl: '',
        duration: '2:50',
      );

      final result = await service.resolveTrackArtist(track, artistRepo: mockRepo);

      // Result displays the real credited name, but ID is empty so no fake profile link is invented
      expect(result.name, equals('Random Unknown Vocalist'));
      expect(result.id, isEmpty);
    });

    test('4. Stable artistId on Track is preserved and prioritized', () async {
      final mockRepo = MockArtistRepository();
      final service = ArtistResolutionService();

      const track = Track(
        id: 't-curated',
        title: 'Song With ID',
        artist: 'AR Rahman',
        imageUrl: '',
        duration: '4:00',
        artistId: '491', // Curated ID for A.R. Rahman
      );

      final result = await service.resolveTrackArtist(track, artistRepo: mockRepo);

      expect(mockRepo.searchArtistsCallCount, equals(0));
      expect(result.id, equals('491'));
      expect(result.name, equals('A. R. Rahman'));
    });
  });

  group('PHASE 3: Search Deduplication & Entity Filtering Suite', () {
    test('1. Deduplication removes identical video IDs with or without prefix', () {
      const v1 = YouTubeVideo(
        id: 'abc12345678',
        title: 'West Coast',
        channelTitle: 'Lana Del Rey',
        thumbnailUrl: 'https://example.com/thumb1.jpg',
        duration: '4:17',
        viewCount: '100M views',
      );

      const v2 = YouTubeVideo(
        id: 'youtube_abc12345678',
        title: 'West Coast (Audio)',
        channelTitle: 'LanaDelReyVEVO',
        thumbnailUrl: 'https://example.com/thumb2.jpg',
        duration: '4:17',
        viewCount: '50M views',
      );

      const v3 = YouTubeVideo(
        id: 'def87654321',
        title: 'West Coast - Radio Edit',
        channelTitle: 'Lana Del Rey',
        thumbnailUrl: 'https://example.com/thumb3.jpg',
        duration: '3:50',
        viewCount: '10M views',
      );

      final deduped = SearchDeduplicator.deduplicateAndRank([v1, v2, v3], query: 'West Coast');

      // The duplicate video ID is filtered; genuine distinct edit (Radio Edit) is preserved
      final ids = deduped.map((v) => v.id.replaceFirst('youtube_', '')).toList();
      expect(ids.where((id) => id == 'abc12345678').length, equals(1));
    });

    test('2. SearchRepository.mergeAndDeduplicateArtists excludes non-music entities', () {
      final curatedAndDeezer = [
        const ArtistModel(id: 'd1', name: 'West Coast', imageUrl: '', fanCount: 2000),
        const ArtistModel(id: 'd2', name: 'West Coast Baptist College', imageUrl: '', fanCount: 460),
        const ArtistModel(id: 'd3', name: 'West Coast Wolves', imageUrl: '', fanCount: 114),
      ];

      final youtubeArtists = [
        const ArtistModel(id: 'yt1', name: 'West Coast Eagles Football Club', imageUrl: ''),
        const ArtistModel(id: 'yt2', name: 'West Coast Dealing School', imageUrl: ''),
        const ArtistModel(id: 'yt3', name: 'West Coast Jazz Ensemble', imageUrl: ''),
      ];

      final merged = SearchRepository.mergeAndDeduplicateArtists(
        curatedAndDeezer: curatedAndDeezer,
        youtubeArtists: youtubeArtists,
        query: 'West Coast',
      );

      final names = merged.map((a) => a.name).toList();

      // Legitimate musical artists and bands ARE kept
      expect(names.contains('West Coast'), isTrue);
      expect(names.contains('West Coast Wolves'), isTrue);
      expect(names.contains('West Coast Jazz Ensemble'), isTrue);

      // Unrelated entities ARE strictly excluded
      expect(names.contains('West Coast Baptist College'), isFalse);
      expect(names.contains('West Coast Eagles Football Club'), isFalse);
      expect(names.contains('West Coast Dealing School'), isFalse);
    });
  });
}
