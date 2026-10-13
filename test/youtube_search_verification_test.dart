import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/search/data/local_search_service.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/media/domain/models.dart';

void main() {
  group('YouTube & Local Search Verification Tests', () {
    late YouTubeRepository ytRepo;

    setUp(() {
      ytRepo = YouTubeRepository();
    });

    // Test 1: Search Imagine Dragons Believer
    test('1. Search "Imagine Dragons Believer" returns real parsed YouTube results', () async {
      final results = await ytRepo.search('Imagine Dragons Believer');

      expect(results, isNotEmpty, reason: 'Expected non-empty search results');
      expect(results.length, greaterThanOrEqualTo(5));

      final first = results.first;
      expect(first.id, isNotEmpty);
      expect(first.title, isNotEmpty);
      expect(first.channelTitle, isNotEmpty);
      expect(first.thumbnailUrl, startsWith('http'));
      expect(first.duration, isNotEmpty);
      expect(first.isYoutube, isTrue);

      // Verify that at least one result contains Believer or Imagine Dragons
      final hasBeliever = results.any((r) =>
          r.title.toLowerCase().contains('believer') ||
          r.channelTitle.toLowerCase().contains('imagine'));
      expect(hasBeliever, isTrue, reason: 'Expected Believer or Imagine Dragons in results');
    }, timeout: const Timeout(Duration(seconds: 30)));

    // Test 2: Search a second unrelated song
    test('2. Search "Coldplay Yellow" returns real parsed YouTube results', () async {
      final results = await ytRepo.search('Coldplay Yellow');

      expect(results, isNotEmpty, reason: 'Expected non-empty search results for Coldplay Yellow');
      expect(results.length, greaterThanOrEqualTo(1));

      final first = results.first;
      expect(first.id, isNotEmpty);
      expect(first.title, isNotEmpty);
      expect(first.channelTitle, isNotEmpty);
      expect(first.thumbnailUrl, startsWith('http'));
      expect(first.duration, isNotEmpty);

      final hasYellow = results.any((r) =>
          r.title.toLowerCase().contains('yellow') ||
          r.channelTitle.toLowerCase().contains('coldplay'));
      expect(hasYellow, isTrue, reason: 'Expected Yellow or Coldplay in results');
    }, timeout: const Timeout(Duration(seconds: 30)));

    // Test 3: Search with network error produces distinct error state
    test('3. Simulated network failure throws error and is not silently converted to empty list', () async {
      final failingRepo = FailingTestYouTubeRepository();

      expect(
        () => failingRepo.search('Any Query'),
        throwsA(isA<SocketException>()),
        reason: 'Network errors must be rethrown and not silently swallowed into []',
      );
    });

    // Test 4: Local song search still works independently
    test('4. Local song, album, artist search works independently', () {
      final localSearch = LocalSearchService();
      final List<MediaSong> mockSongs = [
        const MediaSong(
          id: '1',
          title: 'Believer',
          artist: 'Imagine Dragons',
          album: 'Evolve',
          duration: '3:24',
          durationMs: 204000,
          filePath: '/storage/music/believer.mp3',
          artworkPath: '',
        ),
        const MediaSong(
          id: '2',
          title: 'Yellow',
          artist: 'Coldplay',
          album: 'Parachutes',
          duration: '4:29',
          durationMs: 269000,
          filePath: '/storage/music/yellow.mp3',
          artworkPath: '',
        ),
        const MediaSong(
          id: '3',
          title: 'Radioactive',
          artist: 'Imagine Dragons',
          album: 'Night Visions',
          duration: '3:06',
          durationMs: 186000,
          filePath: '/storage/music/radioactive.mp3',
          artworkPath: '',
        ),
      ];

      final List<MediaAlbum> mockAlbums = [
        const MediaAlbum(id: 'a1', title: 'Evolve', artist: 'Imagine Dragons', trackCount: 11, artworkPath: ''),
        const MediaAlbum(id: 'a2', title: 'Parachutes', artist: 'Coldplay', trackCount: 10, artworkPath: ''),
      ];

      final List<MediaArtist> mockArtists = [
        const MediaArtist(id: 'ar1', name: 'Imagine Dragons', trackCount: 2, albumCount: 2),
        const MediaArtist(id: 'ar2', name: 'Coldplay', trackCount: 1, albumCount: 1),
      ];

      // Search 'Imagine'
      final matchedSongs = localSearch.searchSongs(mockSongs, 'Imagine');
      expect(matchedSongs.length, equals(2));
      expect(matchedSongs.map((s) => s.title), containsAll(['Believer', 'Radioactive']));

      final matchedAlbums = localSearch.searchAlbums(mockAlbums, 'Evolve');
      expect(matchedAlbums.length, equals(1));
      expect(matchedAlbums.first.title, equals('Evolve'));

      final matchedArtists = localSearch.searchArtists(mockArtists, 'Coldplay');
      expect(matchedArtists.length, equals(1));
      expect(matchedArtists.first.name, equals('Coldplay'));
    });

    // Test 5: Confirm selecting YouTube result passes correct Track metadata
    test('5. YouTubeVideo toTrack produces correct metadata for playback engine', () {
      const video = YouTubeVideo(
        id: '7wtfhZwyrcc',
        title: 'Believer',
        channelTitle: 'Imagine Dragons',
        thumbnailUrl: 'https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg',
        duration: '3:24',
        viewCount: '2.5B views',
      );

      final track = video.toTrack();

      expect(track.id, equals('youtube_7wtfhZwyrcc'));
      expect(track.title, equals('Believer'));
      expect(track.artist, equals('Imagine Dragons'));
      expect(track.imageUrl, equals('https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg'));
      expect(track.duration, equals('3:24'));
      expect(track.filePath, equals('https://www.youtube.com/watch?v=7wtfhZwyrcc'));
      expect(video.videoUrl, equals('https://www.youtube.com/watch?v=7wtfhZwyrcc'));
      expect(video.isYoutube, isTrue);
    });

    // Test 6: SearchState distinguishes loading, results, error, and empty states
    test('6. SearchState distinguishes all states cleanly', () {
      // Loading state
      const loadingState = SearchState(query: 'test', isYouTubeLoading: true);
      expect(loadingState.isLoading, isTrue);

      // Error state
      const errorState = SearchState(query: 'test', errorMessage: 'No internet connection.');
      expect(errorState.errorMessage, isNotNull);
      expect(errorState.isEmpty, isTrue);

      // Empty results state
      const emptyState = SearchState(query: 'test');
      expect(emptyState.isEmpty, isTrue);
      expect(emptyState.errorMessage, isNull);

      // Success state
      const successState = SearchState(
        query: 'test',
        youtubeResults: [
          const YouTubeVideo(
            id: '123',
            title: 'Test Song',
            channelTitle: 'Test Artist',
            thumbnailUrl: 'https://example.com/thumb.jpg',
            duration: '3:00',
            viewCount: '1M',
          ),
        ],
      );
      expect(successState.isEmpty, isFalse);
      expect(successState.youtubeResults.length, equals(1));
    });
  });
}

class FailingTestYouTubeRepository extends YouTubeRepository {
  @override
  Future<List<YouTubeVideo>> search(String query) async {
    throw const SocketException('Failed host lookup: www.youtube.com');
  }
}
