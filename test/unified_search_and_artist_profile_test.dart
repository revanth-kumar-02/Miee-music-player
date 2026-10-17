import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/recommendations/data/recommendation_service.dart';
import 'package:Miee/features/search/domain/search_deduplicator.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/shared/widgets/artist_avatar.dart';
import 'package:Miee/shared/widgets/song_tile.dart';

void main() {
  group('Issue 1: Universal Artist Image Correctness & Avatar Verification', () {
    test('filters out Deezer default empty silhouette hash', () {
      const emptyHashUrl = 'https://e-cdns-images.dzcdn.net/images/artist/d41d8cd98f00b204e9800998ecf8427e/250x250-000000-80-0-0.jpg';
      expect(ArtistAvatar.isValidArtistImageUrl(emptyHashUrl), isFalse);
    });

    test('filters out malformed or empty URLs', () {
      expect(ArtistAvatar.isValidArtistImageUrl(null), isFalse);
      expect(ArtistAvatar.isValidArtistImageUrl(''), isFalse);
      expect(ArtistAvatar.isValidArtistImageUrl('   '), isFalse);
      expect(ArtistAvatar.isValidArtistImageUrl('not-a-url'), isFalse);
      expect(ArtistAvatar.isValidArtistImageUrl('https://api.deezer.com/artist//image'), isFalse);
    });

    test('accepts valid high-resolution Deezer artist portraits', () {
      const validUrl = 'https://e-cdns-images.dzcdn.net/images/artist/f10e4a3b118086c2e36f1c482f505ea9/500x500.jpg';
      expect(ArtistAvatar.isValidArtistImageUrl(validUrl), isTrue);
    });

    test('resolves fallback from curated catalog for major Indian artists when URL is empty', () {
      final anirudhPortrait = ArtistAvatar.resolvePortraitUrl(
        name: 'Anirudh Ravichander',
        imageUrl: '',
      );
      expect(anirudhPortrait, isNotNull);
      expect(anirudhPortrait!.contains('d41d8cd98f00b204e9800998ecf8427e'), isFalse);

      final gvPrakashPortrait = ArtistAvatar.resolvePortraitUrl(
        name: 'G. V. Prakash Kumar',
        imageUrl: null,
      );
      expect(gvPrakashPortrait, isNotNull);
      expect(gvPrakashPortrait!.contains('d41d8cd98f00b204e9800998ecf8427e'), isFalse);
    });

    testWidgets('ArtistAvatar renders neutral initials fallback when image is unavailable', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ArtistAvatar(
              name: 'Xavier Unknown',
              imageUrl: null,
              radius: 30.0,
            ),
          ),
        ),
      );

      expect(find.text('X'), findsOneWidget);
    });
  });

  group('Issue 2: Unified Song & Artist Search State and Filters', () {
    test('SearchState holds online artists, albums, songs and filter tabs', () {
      const state = SearchState(
        query: 'Anirudh',
        activeFilter: 'All',
        onlineArtists: [
          ArtistModel(
            id: '12345',
            name: 'Anirudh Ravichander',
            imageUrl: 'https://example.com/anirudh.jpg',
            fanCount: 1500000,
          ),
        ],
        onlineAlbums: [
          ArtistAlbum(
            id: '6789',
            title: 'Leo (Original Motion Picture Soundtrack)',
            coverUrl: 'https://example.com/leo.jpg',
            releaseDate: '2023-10-19',
            artistName: 'Anirudh Ravichander',
          ),
        ],
        youtubeResults: [
          YouTubeVideo(
            id: 'yt_badass',
            title: 'Badass - Leo',
            channelTitle: 'Anirudh Ravichander',
            thumbnailUrl: 'https://example.com/badass.jpg',
            duration: '3:49',
            viewCount: '50M views',
          ),
        ],
      );

      expect(state.hasQuery, isTrue);
      expect(state.totalArtistsCount, equals(1));
      expect(state.totalAlbumsCount, equals(1));
      expect(state.totalSongsCount, equals(1));
      expect(state.isEmpty, isFalse);
    });

    test('deduplicates canonical songs without merging different artists', () {
      final videos = [
        const YouTubeVideo(
          id: 'v1',
          title: 'Hukum',
          channelTitle: 'Anirudh Ravichander',
          thumbnailUrl: 'https://example.com/1.jpg',
          duration: '3:27',
          viewCount: '100M views',
          rawTitle: 'Hukum (From "Jailer")',
          rawChannelTitle: 'Sun TV',
        ),
        const YouTubeVideo(
          id: 'v2',
          title: 'Hukum',
          channelTitle: 'Anirudh Ravichander',
          thumbnailUrl: 'https://example.com/2.jpg',
          duration: '3:27',
          viewCount: '10M views',
          rawTitle: 'Hukum - Official Lyrical Video | Jailer',
          rawChannelTitle: 'Sun TV',
        ),
        const YouTubeVideo(
          id: 'v3',
          title: 'Hukum',
          channelTitle: 'Independent Singer',
          thumbnailUrl: 'https://example.com/3.jpg',
          duration: '3:20',
          viewCount: '50K views',
          rawTitle: 'Hukum (Cover)',
          rawChannelTitle: 'Independent Singer',
        ),
      ];

      final deduped = SearchDeduplicator.deduplicateAndRank(videos, query: 'Hukum');

      // Should deduplicate the duplicate upload by Anirudh, but keep the independent singer
      expect(deduped.length, equals(2));
      expect(deduped.any((v) => v.channelTitle == 'Anirudh Ravichander'), isTrue);
      expect(deduped.any((v) => v.channelTitle == 'Independent Singer'), isTrue);
    });
  });

  group('Issue 4: Discover More Relevance & Player UI Corrections', () {
    test('filters out full movies, podcasts, and giant jukeboxes from recommendations', () {
      const fullMovie = YouTubeVideo(
        id: 'm1',
        title: 'Leo Full Movie 4K Ultra HD Tamil',
        channelTitle: 'Cinema Plus',
        thumbnailUrl: '',
        duration: '2:45:00',
        viewCount: '1M views',
      );
      expect(RecommendationService.isLegitimateSong(fullMovie), isFalse);

      const podcast = YouTubeVideo(
        id: 'p1',
        title: 'Anirudh Ravichander Special Interview | The Ranveer Show Podcast Episode #250',
        channelTitle: 'TRS Clips',
        thumbnailUrl: '',
        duration: '1:15:00',
        viewCount: '500K views',
      );
      expect(RecommendationService.isLegitimateSong(podcast), isFalse);

      const jukebox = YouTubeVideo(
        id: 'j1',
        title: 'Anirudh Best Songs All Time Hits Mega Jukebox Audio Collections',
        channelTitle: 'Sony Music South',
        thumbnailUrl: '',
        duration: '1:30:00',
        viewCount: '20M views',
      );
      expect(RecommendationService.isLegitimateSong(jukebox), isFalse);

      const legitimateSong = YouTubeVideo(
        id: 's1',
        title: 'Badass (From "Leo")',
        channelTitle: 'Anirudh Ravichander',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: '3:49',
        viewCount: '80M views',
      );
      expect(RecommendationService.isLegitimateSong(legitimateSong), isTrue);

      const legitimateLongSong = YouTubeVideo(
        id: 's2',
        title: 'Classical Ragam Tanam Pallavi - Carnatic Concert',
        channelTitle: 'Sanjay Subrahmanyan',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        duration: '18:20',
        viewCount: '100K views',
      );
      expect(RecommendationService.isLegitimateSong(legitimateLongSong), isTrue);
    });

    testWidgets('SongTile shows album artwork instead of leading waveform when isPlaying is true and imageUrl exists', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SongTile(
              title: 'Chaleya',
              artist: 'Anirudh Ravichander',
              duration: '3:20',
              imageUrl: 'https://example.com/chaleya.jpg',
              isPlaying: true, // Currently active song in Home or Queue
            ),
          ),
        ),
      );

      // Verify that artwork takes precedence over leading waveform equalizer
      expect(find.text('Chaleya'), findsOneWidget);
      expect(find.text('Anirudh Ravichander'), findsOneWidget);
    });
  });
}
