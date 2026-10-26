import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:Miee/core/audio/playback_state.dart' as pb;
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/features/rooms/presentation/create_room_page.dart';
import 'package:Miee/features/search/data/local_search_service.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/domain/youtube_metadata_cleaner.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/main_app_shell.dart';
import 'package:Miee/shared/widgets/mini_player.dart';
import 'package:Miee/shared/widgets/bottom_navigation.dart';

class FakePlayerController extends StateNotifier<pb.PlaybackState>
    implements PlayerController {
  FakePlayerController(super.state);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Issue 1: MainAppShell Route Overlay Fixes', () {
    testWidgets('MiniPlayer and BottomNavigation are completely hidden on /rooms/active', (tester) async {
      const activeTrack = Track(
        id: 'track_1',
        title: 'Radhima Original',
        artist: 'Original Artist',
        imageUrl: 'https://example.com/cover.jpg',
        duration: '3:45',
      );

      final router = GoRouter(
        initialLocation: '/rooms/active',
        routes: [
          ShellRoute(
            builder: (context, state, child) => MainAppShell(child: child),
            routes: [
              GoRoute(
                path: '/rooms/active',
                builder: (context, state) => const Scaffold(
                  body: Center(child: Text('Active Room Content')),
                ),
              ),
              GoRoute(
                path: '/home',
                builder: (context, state) => const Scaffold(
                  body: Center(child: Text('Home Content')),
                ),
              ),
            ],
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith(
              (ref) => FakePlayerController(
                pb.PlaybackState.initial().copyWith(
                  currentTrack: activeTrack,
                  status: pb.PlaybackStatus.playing,
                ),
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // On /rooms/active, neither MiniPlayer nor BottomNavigation must be shown
      expect(find.text('Active Room Content'), findsOneWidget);
      expect(find.byType(MiniPlayer), findsNothing);
      expect(find.byType(BottomNavigation), findsNothing);
    });

    testWidgets('MiniPlayer is hidden on /rooms, /rooms/create, /rooms/join', (tester) async {
      const activeTrack = Track(
        id: 'track_1',
        title: 'Song',
        artist: 'Artist',
        imageUrl: 'https://example.com/cover.jpg',
        duration: '3:00',
      );

      for (final path in ['/rooms', '/rooms/create', '/rooms/join']) {
        final router = GoRouter(
          initialLocation: path,
          routes: [
            ShellRoute(
              builder: (context, state, child) => MainAppShell(child: child),
              routes: [
                GoRoute(
                  path: path,
                  builder: (context, state) => Scaffold(
                    body: Center(child: Text('Page $path')),
                  ),
                ),
              ],
            ),
          ],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playerControllerProvider.overrideWith(
                (ref) => FakePlayerController(
                  pb.PlaybackState.initial().copyWith(
                    currentTrack: activeTrack,
                    status: pb.PlaybackStatus.playing,
                  ),
                ),
              ),
            ],
            child: MaterialApp.router(
              routerConfig: router,
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.byType(MiniPlayer), findsNothing, reason: 'MiniPlayer must be hidden on $path');
      }
    });
  });

  group('Issue 3: Local Search Fuzzy Matching Strictness', () {
    final localService = LocalSearchService();

    test('Searching "radhima" does NOT match "alaaka loova"', () {
      final songs = [
        const MediaSong(
          id: '1',
          title: 'Alaaka Loova',
          artist: 'Sai Abhyankkar',
          album: 'Single',
          duration: '3:20',
          durationMs: 200000,
          filePath: '/path/alaaka.mp3',
          artworkPath: '',
        ),
        const MediaSong(
          id: '2',
          title: 'Radhima',
          artist: 'Original Artist',
          album: 'Soundtrack',
          duration: '3:45',
          durationMs: 225000,
          filePath: '/path/radhima.mp3',
          artworkPath: '',
        ),
      ];

      final results = localService.searchSongs(songs, 'radhima');

      expect(results.length, equals(1));
      expect(results.first.title, equals('Radhima'));
      expect(results.any((s) => s.title == 'Alaaka Loova'), isFalse);
    });

    test('Searching "radhima" does not match random songs with scattered character overlap', () {
      final songs = [
        const MediaSong(
          id: '10',
          title: 'Random Track with Letters R A D H I M A',
          artist: 'Another Artist',
          album: 'Album',
          duration: '3:00',
          durationMs: 180000,
          filePath: '/path/song.mp3',
          artworkPath: '',
        ),
      ];

      final results = localService.searchSongs(songs, 'radhima');
      expect(results, isEmpty);
    });
  });

  group('Issue 4: Search Deduplication & Derivative Edit Filtering', () {
    test('Detects and filters out mashups (e.g. "radhima x spiderman")', () {
      const mashup = YouTubeVideo(
        id: 'mashup_1',
        title: 'Radhima x Spiderman Theme (Mashup)',
        channelTitle: 'FanEdits',
        thumbnailUrl: 'https://example.com/mashup.jpg',
        duration: '2:45',
        viewCount: '50K views',
        rawTitle: 'Radhima x Spiderman | Tamil Mashup 2024',
      );

      final intent = QueryIntent.fromQuery('radhima');
      final editType = SearchDeduplicator.detectEditType(mashup, intent);
      expect(editType, equals(EditType.mashupRemake));
    });

    test('Detects and filters out slowed + reverse', () {
      const slowedReverse = YouTubeVideo(
        id: 'slowed_rev_1',
        title: 'Radhima (Slowed + Reverse)',
        channelTitle: 'VibeStation',
        thumbnailUrl: 'https://example.com/slowed.jpg',
        duration: '4:15',
        viewCount: '20K views',
        rawTitle: 'Radhima - Slowed + Reverb + Reverse Audio',
      );

      final intent = QueryIntent.fromQuery('radhima');
      final editType = SearchDeduplicator.detectEditType(slowedReverse, intent);
      expect(editType, equals(EditType.slowedReverb));
    });

    test('Detects and filters out bass audio / bass boosted', () {
      const bassVideo = YouTubeVideo(
        id: 'bass_1',
        title: 'Radhima Bass Audio Boosted',
        channelTitle: 'BassHub',
        thumbnailUrl: 'https://example.com/bass.jpg',
        duration: '3:45',
        viewCount: '80K views',
        rawTitle: 'Radhima [Bass Boosted Audio] High Quality',
      );

      final intent = QueryIntent.fromQuery('radhima');
      final editType = SearchDeduplicator.detectEditType(bassVideo, intent);
      expect(editType, equals(EditType.audioModified));
    });

    test('Detects standalone edits and trending clickbait', () {
      const trendingEdit = YouTubeVideo(
        id: 'trend_1',
        title: 'New Trending Radhima Song Edit',
        channelTitle: 'Tamil Status',
        thumbnailUrl: 'https://example.com/trend.jpg',
        duration: '1:00',
        viewCount: '15K views',
        rawTitle: 'New Trending Radhima Song Edit | Full Screen Status',
      );

      final intent = QueryIntent.fromQuery('radhima');
      final editType = SearchDeduplicator.detectEditType(trendingEdit, intent);
      expect(editType != EditType.none, isTrue);
    });

    test('deduplicateAndRank returns only authentic original release for "radhima"', () {
      final candidates = [
        const YouTubeVideo(
          id: 'radhima_original',
          title: 'Radhima',
          channelTitle: 'Sony Music South',
          thumbnailUrl: 'https://example.com/orig.jpg',
          duration: '3:45',
          viewCount: '10M views',
          rawViewCount: 10000000,
          rawTitle: 'Radhima - Official Audio | Original Artist',
          rawChannelTitle: 'SonyMusicSouthVEVO',
        ),
        const YouTubeVideo(
          id: 'radhima_mashup',
          title: 'Radhima x Spiderman',
          channelTitle: 'Editor Boy',
          thumbnailUrl: 'https://example.com/mashup.jpg',
          duration: '2:30',
          viewCount: '45K views',
          rawViewCount: 45000,
          rawTitle: 'Radhima x Spiderman Theme Mashup',
        ),
        const YouTubeVideo(
          id: 'radhima_slowed_rev',
          title: 'Radhima (Slowed + Reverse)',
          channelTitle: 'Lofi Chills',
          thumbnailUrl: 'https://example.com/slowed.jpg',
          duration: '4:20',
          viewCount: '30K views',
          rawViewCount: 30000,
          rawTitle: 'Radhima Slowed + Reverse',
        ),
        const YouTubeVideo(
          id: 'radhima_bass',
          title: 'Radhima Bass Audio',
          channelTitle: 'Bass King',
          thumbnailUrl: 'https://example.com/bass.jpg',
          duration: '3:45',
          viewCount: '60K views',
          rawViewCount: 60000,
          rawTitle: 'Radhima Bass Audio Boosted',
        ),
        const YouTubeVideo(
          id: 'radhima_trend',
          title: 'New Trending Radhima',
          channelTitle: 'Tamil Editz',
          thumbnailUrl: 'https://example.com/trend.jpg',
          duration: '0:55',
          viewCount: '12K views',
          rawViewCount: 12000,
          rawTitle: 'New Trending Radhima | WhatsApp Status Edit',
        ),
        const YouTubeVideo(
          id: 'radhima_spiderman_cross',
          title: 'Radhima × Spider-Man',
          channelTitle: 'Red Lion',
          thumbnailUrl: 'https://example.com/spiderman.jpg',
          duration: '2:40',
          viewCount: '25K views',
          rawViewCount: 25000,
          rawTitle: 'Radhima × Spider-Man ❤️ ft. Red Lion Mashup',
        ),
        const YouTubeVideo(
          id: 'radhima_spaced_slowed',
          title: 'radhima ( s l o w e d + r e v e ...',
          channelTitle: 'lilvibe -',
          thumbnailUrl: 'https://example.com/spaced.jpg',
          duration: '4:30',
          viewCount: '18K views',
          rawViewCount: 18000,
          rawTitle: 'radhima ( s l o w e d + r e v e r b )',
        ),
        const YouTubeVideo(
          id: 'radhima_ringtone_epic',
          title: 'Radhimaa (Thalapathy Vijay ...',
          channelTitle: 'Ringtones Epic',
          thumbnailUrl: 'https://example.com/ringtone.jpg',
          duration: '0:35',
          viewCount: '8K views',
          rawViewCount: 8000,
          rawTitle: 'Radhimaa (Thalapathy Vijay BGM Ringtone)',
          rawChannelTitle: 'Ringtones Epic',
        ),
        const YouTubeVideo(
          id: 'radhima_promo',
          title: 'Radhimaa (Promo)',
          channelTitle: 'Think Music India',
          thumbnailUrl: 'https://example.com/promo.jpg',
          duration: '1:26',
          viewCount: '2.9M views',
          rawViewCount: 2981215,
          rawTitle: '@SaiAbhyankkar - Radhimaa (Promo) | Bhagyashri Borse | Think Indie',
        ),
        const YouTubeVideo(
          id: 'radhima_spotify_ad',
          title: 'Be a Thangamaana Paiyan',
          channelTitle: 'Spotify India',
          thumbnailUrl: 'https://example.com/spotify.jpg',
          duration: '1:04',
          viewCount: '8.5M views',
          rawViewCount: 8572861,
          rawTitle: 'Be a Thangamaana Paiyan | Radhimaa | Spotify India',
        ),
        const YouTubeVideo(
          id: 'radhima_doc',
          title: 'Radhimaa (Documentary)',
          channelTitle: 'Think Music India',
          thumbnailUrl: 'https://example.com/doc.jpg',
          duration: '8:12',
          viewCount: '450K views',
          rawViewCount: 450000,
          rawTitle: 'SaiAbhyankkar - Radhimaa (Documentary) | Bhagyshri Borse | Think Indie',
        ),
        const YouTubeVideo(
          id: 'radhima_500_days',
          title: 'Radhima ft 500 days of summer',
          channelTitle: 'Aurinity',
          thumbnailUrl: 'https://example.com/500days.jpg',
          duration: '1:53',
          viewCount: '89K views',
          rawViewCount: 89000,
          rawTitle: 'Radhima ft 500 days of summer (Movie Edit)',
        ),
        const YouTubeVideo(
          id: 'radhima_multimix',
          title: 'Ava Enna Enna Thedi Vantha Radhimaa Multimix',
          channelTitle: 'Shayanthan Music',
          thumbnailUrl: 'https://example.com/multimix.jpg',
          duration: '1:18',
          viewCount: '590K views',
          rawViewCount: 590000,
          rawTitle: 'Ava Enna Enna Thedi Vantha Radhimaa Multimix',
        ),
        const YouTubeVideo(
          id: 'radhima_boosted',
          title: 'Radhimaa Lyrica song',
          channelTitle: 'The Antony',
          thumbnailUrl: 'https://example.com/boosted.jpg',
          duration: '4:20',
          viewCount: '276K views',
          rawViewCount: 276000,
          rawTitle: 'Radhimaa Lyrica song | Audio release Boosted #youtube #music',
        ),
      ];

      const config = SearchRankingConfig(filterDerivativeEdits: true);
      final results = SearchDeduplicator.deduplicateAndRank(
        candidates,
        query: 'radhima',
        config: config,
      );

      // Must only contain the official original release
      expect(results.length, equals(1));
      expect(results.first.id, equals('radhima_original'));
    });

    test('YouTubeMetadataCleaner correctly extracts artist from leading @handle', () {
      final cleaned = YouTubeMetadataCleaner.clean(
        rawTitle: '@SaiAbhyankkar - Radhimaa (Music Video) | Bhagyashri Borse | Vivek | Thejo Bharathwaj | Think Indie',
        rawChannel: 'Think Music India',
      );

      expect(cleaned.title, equals('Radhimaa'));
      expect(cleaned.artist, equals('Sai Abhyankkar'));
    });
  });

  group('Issue 5: Room Creation Queue Option', () {
    testWidgets('CreateRoomPage includes "Start with Empty Queue" toggle', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: CreateRoomPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('ROOM QUEUE OPTION'), findsOneWidget);
      expect(find.text('Start with Empty Queue'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsOneWidget);

      // Verify toggle is on by default
      final switchTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(switchTile.value, isTrue);

      // Verify tapping changes the value
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      final updatedTile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(updatedTile.value, isFalse);
    });
  });
}
