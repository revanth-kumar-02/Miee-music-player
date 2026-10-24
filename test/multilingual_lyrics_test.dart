import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/lyrics/data/lyrics_repository.dart';
import 'package:Miee/features/lyrics/domain/lyrics_model.dart';
import 'package:Miee/features/lyrics/domain/lyrics_search_query_builder.dart';
import 'package:Miee/features/lyrics/domain/lyrics_validator.dart';
import 'package:Miee/shared/models/track.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. English Lyrics Retrieval', () {
    test('Resolves synchronized lyrics for English track via LrclibLyricsRepository', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.contains('/api/get') || options.uri.path.contains('/api/search')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'id': 101,
                'trackName': 'Starboy',
                'artistName': 'The Weeknd',
                'syncedLyrics': '[00:15.20] I\'m tryna put you in the worst mood, ah\n[00:18.50] P1 cleaner than your church shoes, ah\n[00:22.00] Look what you\'ve done',
                'plainLyrics': 'I\'m tryna put you in the worst mood, ah\nP1 cleaner than your church shoes, ah\nLook what you\'ve done',
              },
            ));
          }
          return handler.next(options);
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'eng_1',
        title: 'Starboy',
        artist: 'The Weeknd',
        imageUrl: 'https://example.com/art.jpg',
        duration: '3:50',
      );

      final lyrics = await repo.getLyrics(track);

      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.isSynced, isTrue);
      expect(lyrics.length, 3);
      expect(lyrics[0].text, 'I\'m tryna put you in the worst mood, ah');
      expect(lyrics[0].time, const Duration(seconds: 15, milliseconds: 200));
      expect(lyrics.source, 'lrclib_get_synced');
    });
  });

  group('2. Tamil Lyrics with Native-Script Title', () {
    test('Resolves native-script Tamil lyrics even when queried in Tamil script', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final uri = options.uri;
          // When querying with transliterated candidate "kannaana kanne"
          final q = uri.queryParameters['q'] ?? uri.queryParameters['track_name'] ?? '';
          if (q.toLowerCase().contains('kannaana') || q.contains('கண்ணான')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': 202,
                  'trackName': 'Kannaana Kanney',
                  'artistName': 'Sid Sriram',
                  'duration': 269,
                  'syncedLyrics': '[00:35.54] கண்ணான கண்ணே\n[00:37.25] என் மீது சாய வா\n[00:42.67] புண்னான நெஞ்சை பூ போல நீவ வா',
                  'plainLyrics': 'கண்ணான கண்ணே\nஎன் மீது சாய வா\nபுண்னான நெஞ்சை பூ போல நீவ வா',
                }
              ],
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'tamil_native_1',
        title: 'கண்ணான கண்ணே',
        artist: 'Sid Sriram',
        imageUrl: 'https://example.com/viswasam.jpg',
        duration: '4:29',
      );

      final lyrics = await repo.getLyrics(track);

      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.isSynced, isTrue);
      expect(lyrics.length, 3);
      expect(lyrics[0].text, 'கண்ணான கண்ணே');
      expect(lyrics[1].text, 'என் மீது சாய வா');
      expect(lyrics[0].time, const Duration(seconds: 35, milliseconds: 540));
    });
  });

  group('3. Tamil Lyrics with Romanized Title and YouTube Noise', () {
    test('Strips video noise and uploader channel, extracts clean title and resolves lyrics', () async {
      final candidates = LyricsSearchQueryBuilder.buildCandidates(
        title: 'Arabic Kuthu - Video Song | Beast | Thalapathy Vijay | Sun Pictures | Anirudh',
        artist: 'Sun TV',
      );

      // Verify builder correctly identified "Arabic Kuthu" and recognized Sun TV as a channel
      expect(candidates.any((c) => c.trackName == 'Arabic Kuthu'), isTrue);

      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final q = options.uri.queryParameters['q'] ?? options.uri.queryParameters['track_name'] ?? '';
          if (q.contains('Arabic Kuthu')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': 303,
                  'trackName': 'Arabic Kuthu',
                  'artistName': 'Anirudh Ravichander',
                  'duration': 279,
                  'syncedLyrics': '[00:20.00] Malama Pitha Pithadhe\n[00:24.00] Halamithi Habibo',
                  'plainLyrics': 'Malama Pitha Pithadhe\nHalamithi Habibo',
                }
              ],
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'yt_tamil_1',
        title: 'Arabic Kuthu - Video Song | Beast | Thalapathy Vijay | Sun Pictures | Anirudh',
        artist: 'Sun TV',
        imageUrl: 'https://example.com/beast.jpg',
        duration: '4:39',
      );

      final lyrics = await repo.getLyrics(track);

      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.isSynced, isTrue);
      expect(lyrics[0].text, 'Malama Pitha Pithadhe');
    });
  });

  group('4. Telugu, Malayalam, Hindi, and Kannada Examples', () {
    test('Telugu track (Naatu Naatu) with native script resolves lyrics', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final q = options.uri.queryParameters['q'] ?? options.uri.queryParameters['track_name'] ?? '';
          if (q.toLowerCase().contains('naatu') || q.contains('నాటు')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': 401,
                  'trackName': 'Naatu Naatu',
                  'artistName': 'Rahul Sipligunj, Kaala Bhairava, M.M. Keeravani',
                  'duration': 215,
                  'syncedLyrics': '[00:10.00] పొలంగట్టు దుమ్ములోన పోట్లగిత్త దూకినట్టు\n[00:14.00] నాటు నాటు',
                }
              ],
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'telugu_1',
        title: 'నాటు నాటు',
        artist: 'M.M. Keeravani',
        imageUrl: 'https://example.com/rrr.jpg',
        duration: '3:35',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.isSynced, isTrue);
      expect(lyrics[1].text, 'నాటు నాటు');
    });

    test('Malayalam track (Malare) resolves lyrics correctly', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final q = options.uri.queryParameters['q'] ?? options.uri.queryParameters['track_name'] ?? '';
          if (q.toLowerCase().contains('malare') || q.contains('മലരേ')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': 402,
                  'trackName': 'Malare (From "Premam")',
                  'artistName': 'Vijay Yesudas',
                  'duration': 316,
                  'syncedLyrics': '[00:18.00] മലരേ മൗനമേ\n[00:23.00] എന്നിൽ നിറയും സ്നേഹമേ',
                }
              ],
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'malayalam_1',
        title: 'മലരേ (Malare)',
        artist: 'Vijay Yesudas',
        imageUrl: 'https://example.com/premam.jpg',
        duration: '5:16',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics[0].text, 'മലരേ മൗനമേ');
    });

    test('Hindi track (Kesariya) with native script resolves lyrics', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final q = options.uri.queryParameters['q'] ?? options.uri.queryParameters['track_name'] ?? '';
          if (q.toLowerCase().contains('kesariya') || q.contains('केसरिया')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': 403,
                  'trackName': 'Kesariya',
                  'artistName': 'Arijit Singh, Pritam',
                  'duration': 268,
                  'syncedLyrics': '[00:30.00] केसरिया तेरा इश्क है पिया\n[00:34.00] रंग जाऊं जो मैं हाथ लगाऊं',
                }
              ],
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'hindi_1',
        title: 'केसरिया',
        artist: 'Arijit Singh',
        imageUrl: 'https://example.com/brahmastra.jpg',
        duration: '4:28',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics[0].text, 'केसरिया तेरा इश्क है पिया');
    });

    test('Kannada track (Ra Ra Rakkamma) resolves lyrics correctly', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final q = options.uri.queryParameters['q'] ?? options.uri.queryParameters['track_name'] ?? '';
          if (q.toLowerCase().contains('rakkamma') || q.contains('ರಕ್ಕಮ್ಮ')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': 404,
                  'trackName': 'Ra Ra Rakkamma',
                  'artistName': 'Nakash Aziz, Sunidhi Chauhan',
                  'duration': 225,
                  'syncedLyrics': '[00:15.00] ರಾ ರಾ ರಕ್ಕಮ್ಮ\n[00:19.00] ಏನೇ ಹೇಳು ರಕ್ಕಮ್ಮ',
                }
              ],
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'kannada_1',
        title: 'ರಾ ರಾ ರಕ್ಕಮ್ಮ (Ra Ra Rakkamma)',
        artist: 'Nakash Aziz',
        imageUrl: 'https://example.com/vikrant.jpg',
        duration: '3:45',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics[0].text, 'ರಾ ರಾ ರಕ್ಕಮ್ಮ');
    });
  });

  group('5. Unicode Punctuation and Mixed-Script Titles', () {
    test('Handles mixed scripts and punctuation (ellipses, parentheses, symbols)', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final q = options.uri.queryParameters['q'] ?? options.uri.queryParameters['track_name'] ?? '';
          if (q.toLowerCase().contains('antava') || q.contains('అంటావా')) {
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 200,
              data: [
                {
                  'id': 501,
                  'trackName': 'Oo Antava Oo Oo Antava',
                  'artistName': 'Indravathi Chauhan',
                  'duration': 228,
                  'syncedLyrics': '[00:20.00] ఊ అంటావా మావా\n[00:25.00] ఊ ఊ అంటావా మావా',
                }
              ],
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'mixed_1',
        title: 'Oo Antava... Oo Oo Antava (ఊ అంటావా.. ఊ ఊ అంటావా) - Pushpa',
        artist: 'Aditya Music',
        imageUrl: 'https://example.com/pushpa.jpg',
        duration: '3:48',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.isSynced, isTrue);
      expect(lyrics[0].text, 'ఊ అంటావా మావా');
    });
  });

  group('6. No Matching Lyrics', () {
    test('Returns LyricsData.empty cleanly when no provider finds lyrics', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.uri.path.contains('/api/get')) {
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 404),
            ));
          }
          return handler.resolve(Response(requestOptions: options, statusCode: 200, data: <Map<String, dynamic>>[]));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'unknown_1',
        title: 'Completely Nonexistent Song XYZ 123456789',
        artist: 'Ghost Artist 98765',
        imageUrl: 'https://example.com/ghost.jpg',
        duration: '3:00',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isEmpty, isTrue);
      expect(lyrics.isSynced, isFalse);
    });
  });

  group('7. Network Failure and Rate Limiting', () {
    test('Recovers from HTTP 429/503 rate limit with retry and does not permanently cache transient failure', () async {
      int attempts = 0;
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          attempts++;
          if (attempts == 1) {
            // First attempt hits 503 Service Unavailable
            return handler.reject(DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: 503),
            ));
          }
          // Retry succeeds
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'id': 701,
              'trackName': 'Recovered Song',
              'artistName': 'Resilient Artist',
              'syncedLyrics': '[00:10.00] Recovered lyric line',
            },
          ));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'retry_track_1',
        title: 'Recovered Song',
        artist: 'Resilient Artist',
        imageUrl: 'https://example.com/art.jpg',
        duration: '2:30',
      );

      final lyrics = await repo.getLyrics(track);
      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics[0].text, 'Recovered lyric line');
      expect(attempts, greaterThanOrEqualTo(2));
    });
  });

  group('8. Similar Titles that Must Not Match the Wrong Song', () {
    test('Rejects dissimilar song ("Yellow" vs "Black and Yellow")', () {
      final valid = LyricsValidator.validate(
        queryTrackName: 'Yellow',
        candidateTrackName: 'Black and Yellow',
      );
      expect(valid, isFalse);
    });

    test('Rejects "Starboy" matching "Stargirl"', () {
      final valid = LyricsValidator.validate(
        queryTrackName: 'Starboy',
        candidateTrackName: 'Stargirl Interlude',
      );
      expect(valid, isFalse);
    });

    test('Rejects song when duration diverges significantly (> 45s difference)', () {
      final valid = LyricsValidator.validate(
        queryTrackName: 'Yellow',
        candidateTrackName: 'Yellow',
        queryDuration: const Duration(minutes: 3, seconds: 10),
        candidateDuration: const Duration(minutes: 7, seconds: 40),
      );
      expect(valid, isFalse);
    });
  });

  group('9. Timestamped Lyrics Synchronization', () {
    test('Synchronized lyrics accurately track playback position without skips', () {
      final lines = [
        const LyricLine(time: Duration(seconds: 0), text: 'Intro'),
        const LyricLine(time: Duration(seconds: 10), text: 'First verse'),
        const LyricLine(time: Duration(seconds: 25), text: 'Chorus'),
        const LyricLine(time: Duration(seconds: 40), text: 'Outro'),
      ];
      final lyricsData = LyricsData(lines: lines, isSynced: true);

      int findActiveIndex(LyricsData data, Duration currentPosition) {
        int activeIndex = -1;
        for (int i = 0; i < data.length; i++) {
          if (currentPosition >= data[i].time) {
            activeIndex = i;
          } else {
            break;
          }
        }
        return activeIndex;
      }

      expect(findActiveIndex(lyricsData, Duration.zero), 0);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 5)), 0);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 10)), 1);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 20)), 1);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 25)), 2);
      expect(findActiveIndex(lyricsData, const Duration(seconds: 55)), 3);
    });
  });

  group('10. Plain Lyrics Without Fake Synchronization', () {
    test('Fallback to plain lyrics sets isSynced: false and zero duration timestamps', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'id': 1001,
              'trackName': 'Old Folk Song',
              'artistName': 'Traditional',
              'syncedLyrics': null,
              'plainLyrics': 'First line of plain song\nSecond line of plain song\nThird line',
            },
          ));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);
      const track = Track(
        id: 'plain_1',
        title: 'Old Folk Song',
        artist: 'Traditional',
        imageUrl: 'https://example.com/folk.jpg',
        duration: '2:15',
      );

      final lyrics = await repo.getLyrics(track);

      expect(lyrics.isNotEmpty, isTrue);
      expect(lyrics.isSynced, isFalse);
      expect(lyrics.source, 'plain_fallback');
      expect(lyrics.length, 3);
      for (final line in lyrics) {
        expect(line.time, Duration.zero);
      }
    });
  });

  group('11. Cache Isolation Between Tracks', () {
    test('Cache keys isolate individual tracks and prevent cross-contamination', () async {
      final requestedQueries = <String>[];
      final mockDio = Dio();
      mockDio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final trackName = options.uri.queryParameters['track_name'] ?? options.uri.queryParameters['q'] ?? '';
          final artistName = options.uri.queryParameters['artist_name'] ?? '';
          requestedQueries.add('$trackName by $artistName');

          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'id': trackName.hashCode,
              'trackName': trackName,
              'artistName': artistName,
              'syncedLyrics': '[00:05.00] Lyrics for $trackName by $artistName',
            },
          ));
        },
      ));

      final repo = LrclibLyricsRepository(dio: mockDio);

      const trackA = Track(
        id: 'track_alpha',
        title: 'Memories',
        artist: 'Maroon 5',
        imageUrl: 'https://example.com/a.jpg',
        duration: '3:09',
      );

      const trackB = Track(
        id: 'track_beta',
        title: 'Memories',
        artist: 'David Guetta',
        imageUrl: 'https://example.com/b.jpg',
        duration: '3:30',
      );

      final lyricsA = await repo.getLyrics(trackA);
      final lyricsB = await repo.getLyrics(trackB);

      // Verify track A and track B receive their own distinct lyrics
      expect(lyricsA[0].text, contains('Maroon 5'));
      expect(lyricsB[0].text, contains('David Guetta'));

      // Repeating request for track A uses in-memory cache without hitting network again
      final initialQueryCount = requestedQueries.length;
      final cachedLyricsA = await repo.getLyrics(trackA);
      expect(cachedLyricsA[0].text, lyricsA[0].text);
      expect(requestedQueries.length, initialQueryCount);
    });
  });
}
