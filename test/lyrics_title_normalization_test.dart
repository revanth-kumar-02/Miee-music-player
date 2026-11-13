import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/lyrics/data/lyrics_repository.dart';
import 'package:Miee/features/lyrics/domain/lyrics_search_query_builder.dart';
import 'package:Miee/features/lyrics/domain/lyrics_title_normalizer.dart';
import 'package:Miee/features/lyrics/domain/lyrics_validator.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Title Normalization Unit Tests', () {
    test('1. Normalizes "Kadhal En Kadhal - 8K" to "Kadhal En Kadhal"', () {
      final normalized = LyricsTitleNormalizer.normalize('Kadhal En Kadhal - 8K');
      expect(normalized, 'Kadhal En Kadhal');
    });

    test('2. Normalizes "Song Name 4K" to "Song Name"', () {
      final normalized = LyricsTitleNormalizer.normalize('Song Name 4K');
      expect(normalized, 'Song Name');
    });

    test('3. Normalizes "Song Name HD" to "Song Name"', () {
      final normalized = LyricsTitleNormalizer.normalize('Song Name HD');
      expect(normalized, 'Song Name');
    });

    test('4. Normalizes "Song Name (Official Video)" to "Song Name"', () {
      final normalized = LyricsTitleNormalizer.normalize('Song Name (Official Video)');
      expect(normalized, 'Song Name');
    });

    test('5. Normalizes "Song Name [Remastered]" to "Song Name"', () {
      final normalized = LyricsTitleNormalizer.normalize('Song Name [Remastered]');
      expect(normalized, 'Song Name');
    });

    test('6. Normalizes "Song Name Lyrical Video" to "Song Name"', () {
      final normalized = LyricsTitleNormalizer.normalize('Song Name Lyrical Video');
      expect(normalized, 'Song Name');
    });

    test('7. Preserves meaningful numbers in genuine song titles', () {
      expect(LyricsTitleNormalizer.normalize('7 Years'), '7 Years');
      expect(LyricsTitleNormalizer.normalize('21 Guns'), '21 Guns');
      expect(LyricsTitleNormalizer.normalize('1999'), '1999');
      expect(LyricsTitleNormalizer.normalize('Song 2'), 'Song 2');
      expect(LyricsTitleNormalizer.normalize('3'), '3');
    });
  });

  group('Lyrics Candidate Generation & Multi-Stage Query Tests', () {
    test('Generates multi-stage candidates for "Kadhal En Kadhal - 8K" by Dhanush', () {
      final candidates = LyricsSearchQueryBuilder.buildCandidates(
        title: 'Kadhal En Kadhal - 8K',
        artist: 'Dhanush',
        album: 'Mayakkam Enna',
      );

      expect(candidates.isNotEmpty, isTrue);
      // Stage 1: Exact original
      expect(candidates[0].trackName, 'Kadhal En Kadhal - 8K');
      expect(candidates[0].artistName, 'Dhanush');

      // Stage 2: Normalized
      expect(candidates[1].trackName, 'Kadhal En Kadhal');
      expect(candidates[1].artistName, 'Dhanush');

      // Stage 3: Normalized + Album
      expect(candidates[2].trackName, 'Kadhal En Kadhal');
      expect(candidates[2].albumName, 'Mayakkam Enna');
      expect(candidates[2].artistName, 'Dhanush');
    });

    test('Handles missing artist metadata gracefully without crashing or invalid queries', () {
      final candidates = LyricsSearchQueryBuilder.buildCandidates(
        title: 'Kadhal En Kadhal - 8K',
        artist: '',
      );

      expect(candidates.isNotEmpty, isTrue);
      expect(candidates.any((c) => c.trackName == 'Kadhal En Kadhal'), isTrue);
    });

    test('Filters record label / uploader channel artist names', () {
      final candidates = LyricsSearchQueryBuilder.buildCandidates(
        title: 'Arabic Kuthu - Video Song',
        artist: 'Sun TV',
      );

      expect(candidates.isNotEmpty, isTrue);
      // When artist is a known channel like Sun TV, cleanArtist should be empty
      expect(candidates.every((c) => c.artistName.isEmpty), isTrue);
      expect(candidates.any((c) => c.trackName == 'Arabic Kuthu'), isTrue);
    });
  });

  group('Lyrics Validator Tests', () {
    test('Validates normalized candidate matching against original query title', () {
      final isValid = LyricsValidator.validate(
        queryTrackName: 'Kadhal En Kadhal',
        candidateTrackName: 'Kadhal En Kadhal',
      );
      expect(isValid, isTrue);
    });

    test('Rejects candidate when artists or song identities are different', () {
      final isValid = LyricsValidator.validate(
        queryTrackName: 'Yellow',
        candidateTrackName: 'Black and Yellow',
      );
      expect(isValid, isFalse);
    });
  });

  group('End-to-End Lyrics Repository Retrieval Tests', () {
    test('1. Resolves Kadhal En Kadhal - 8K by Dhanush via normalized fallback', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final uri = options.uri;
          final trackName = uri.queryParameters['track_name'] ?? uri.queryParameters['q'] ?? '';
          final artistName = uri.queryParameters['artist_name'] ?? '';

          // Exact unnormalized query fails (just like real LRCLIB)
          if (trackName.contains('8K')) {
            if (uri.path.contains('/api/get')) {
              return handler.reject(DioException(
                requestOptions: options,
                response: Response(requestOptions: options, statusCode: 404),
              ));
            } else {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: <dynamic>[],
              ));
            }
          }

          // Normalized title "Kadhal En Kadhal" succeeds!
          if (trackName.toLowerCase() == 'kadhal en kadhal' &&
              artistName.toLowerCase() == 'dhanush') {
            if (uri.path.contains('/api/get')) {
              return handler.resolve(Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'id': 16241359,
                  'trackName': 'Kadhal En Kadhal',
                  'artistName': 'Dhanush',
                  'albumName': 'Mayakkam Enna',
                  'duration': 367,
                  'plainLyrics': 'காதல் என் காதல் அது கண்ணீருல\nபோச்சு அது போச்சு அட தண்ணீருல',
                },
              ));
            }
          }

          return handler.next(options);
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'youtube_kadhal_8k',
        title: 'Kadhal En Kadhal - 8K',
        artist: 'Dhanush',
        albumName: 'Mayakkam Enna',
        duration: '6:07',
        imageUrl: '',
      );

      final lyrics = await repo.getLyrics(track);

      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.lines.any((l) => l.text.contains('காதல் என் காதல்')), isTrue);
      expect(lyrics.source, 'plain_fallback');
    });

    test('2. Supports local audio tracks with MediaSong album and title tags', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final trackName = options.uri.queryParameters['track_name'] ?? '';
          if (trackName == 'Vathi Coming') {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'id': 991,
                'trackName': 'Vathi Coming',
                'artistName': 'Anirudh Ravichander',
                'syncedLyrics': '[00:10.00] Vathi Coming\n[00:15.00] Otha Sollu',
              },
            ));
          }
          return handler.next(options);
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const mediaSong = MediaSong(
        id: 'local_1',
        title: 'Vathi Coming (Official Video HD)',
        artist: 'Anirudh Ravichander',
        album: 'Master',
        duration: '3:50',
        durationMs: 230000,
        filePath: '',
        artworkPath: '',
      );

      final lyrics = await repo.getLyrics(mediaSong);
      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.isSynced, isTrue);
      expect(lyrics.source, 'lrclib_get_synced');
    });

    test('3. Negative caching prevents repeated immediate network requests for unmatched tracks', () async {
      int requestCount = 0;
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          requestCount++;
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: <dynamic>[],
          ));
        },
      ));

      final repo = LrclibLyricsRepository(
        dio: mockDio,
        negativeCacheTtl: const Duration(minutes: 5),
      );
      const track = Track(
        id: 'unmatched_song_1',
        title: 'NonExistentSong12345',
        artist: 'UnknownArtist999',
        duration: '3:00',
        imageUrl: '',
      );

      final firstLyrics = await repo.getLyrics(track);
      expect(firstLyrics.isEmpty, isTrue);
      final requestsAfterFirst = requestCount;
      expect(requestsAfterFirst, greaterThan(0));

      // Second immediate lookup should return cached empty result without firing new requests
      final secondLyrics = await repo.getLyrics(track);
      expect(secondLyrics.isEmpty, isTrue);
      expect(requestCount, equals(requestsAfterFirst));
    });

    test('4. Timeout and rate limit (429/503) retry behavior', () async {
      int attempts = 0;
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          attempts++;
          if (attempts == 1) {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 429),
            ));
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'id': 555,
              'trackName': 'RetrySong',
              'artistName': 'Artist',
              'plainLyrics': 'Success after retry',
            },
          ));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'retry_song',
        title: 'RetrySong',
        artist: 'Artist',
        duration: '3:00',
        imageUrl: '',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isNotEmpty, isTrue);
      expect(attempts, greaterThanOrEqualTo(2));
    });
  });
}
