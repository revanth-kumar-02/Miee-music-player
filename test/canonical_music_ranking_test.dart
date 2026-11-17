import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/domain/canonical_music_ranker.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';

class MockPlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  MockPlayerController() : super(PlaybackState.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockFavoritesNotifier extends StateNotifier<List<Track>> implements FavoritesNotifier {
  MockFavoritesNotifier() : super([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestSearchNotifier extends StateNotifier<SearchState> implements SearchNotifier {
  TestSearchNotifier(super.state);

  @override
  void setFilter(String filter) {
    state = state.copyWith(activeFilter: filter);
  }

  @override
  void updateQuery(String query) {
    state = state.copyWith(query: query);
  }

  @override
  void searchNow(String query) {}

  @override
  Future<void> addHistory(String query) async {}

  @override
  Future<void> removeHistory(String query) async {}

  @override
  Future<void> clearHistory() async {}

  @override
  Future<void> enrichArtistsFromSongsForTesting(String query, List<YouTubeVideo> youtube) async {}
}

void main() {
  List<Override> commonOverrides(SearchState state) => [
        playerControllerProvider.overrideWith((ref) => MockPlayerController()),
        favoritesProvider.overrideWith((ref) => MockFavoritesNotifier()),
        songsProvider.overrideWith((ref) => []),
        artistsProvider.overrideWith((ref) => []),
        albumsProvider.overrideWith((ref) => []),
        searchNotifierProvider.overrideWith((ref) => TestSearchNotifier(state)),
        resolvedArtworkProvider.overrideWith((ref, query) async {
          return ResolvedArtwork(
            imageUrl: query.fallbackThumbnailUrl ?? '',
            source: ArtworkSource.neutralFallback,
            confidence: 0.5,
            resolvedAt: DateTime.now(),
          );
        }),
      ];

  group('CanonicalMusicRanker Tests', () {
    test('1. Shape of You — Ed Sheeran original recording ranks #1 above Caitlin De Ville and tribute covers', () {
      final edSheeran = YouTubeVideo(
        id: 'itunes_ed_sheeran_soy',
        title: 'Shape of You',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: 'https://is1-ssl.mzstatic.com/image/thumb/soy.jpg',
        duration: '3:53',
        viewCount: '3.5B',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Ed Sheeran',
        albumName: '÷ (Deluxe)',
        metadataProvider: 'itunes',
      );

      final caitlinDeVille = YouTubeVideo(
        id: 'mb_caitlin_soy',
        title: 'Shape of You',
        channelTitle: 'Caitlin De Ville',
        thumbnailUrl: '',
        duration: '3:55',
        viewCount: 'MusicBrainz Verified',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Caitlin De Ville',
        albumName: 'Covers Collection',
        metadataProvider: 'musicbrainz',
      );

      final sinus = YouTubeVideo(
        id: 'mb_sinus_soy',
        title: 'Shape of You',
        channelTitle: 'Sinus',
        thumbnailUrl: '',
        duration: '3:35',
        viewCount: 'MusicBrainz Verified',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Sinus',
        metadataProvider: 'musicbrainz',
      );

      final candidates = <YouTubeVideo>[caitlinDeVille, sinus, edSheeran];

      final prominentArtists = [
        const ArtistModel(
          id: 'ed_sheeran',
          name: 'Ed Sheeran',
          imageUrl: 'https://example.com/ed.jpg',
          fanCount: 20900000,
        ),
        const ArtistModel(
          id: 'caitlin_de_ville',
          name: 'Caitlin De Ville',
          imageUrl: 'https://example.com/caitlin.jpg',
          fanCount: 6000,
        ),
      ];

      final ranked = CanonicalMusicRanker.rankVideos(
        candidates,
        query: 'shape of you',
        canonicalArtist: 'Ed Sheeran',
        prominentArtists: prominentArtists,
      );

      expect(ranked.first.canonicalArtist, 'Ed Sheeran');
      expect(ranked.first.id, 'itunes_ed_sheeran_soy');

      // Caitlin De Ville's cover should be ranked last due to tribute/cover penalty
      expect(ranked.last.canonicalArtist, 'Caitlin De Ville');
    });

    test('2. Brooklyn Baby — Lana Del Rey ranks #1 above Vitamin String Quartet and Lullaby covers', () {
      final vitaminStringQuartet = YouTubeVideo(
        id: 'mb_vsq_bb',
        title: 'Brooklyn Baby',
        channelTitle: 'Vitamin String Quartet',
        thumbnailUrl: '',
        duration: '4:55',
        viewCount: 'MusicBrainz Verified',
        canonicalTitle: 'Brooklyn Baby',
        canonicalArtist: 'Vitamin String Quartet',
        albumName: 'Vitamin String Quartet Performs Lana Del Rey',
        metadataProvider: 'musicbrainz',
      );

      final twinkleTwinkle = YouTubeVideo(
        id: 'mb_tt_bb',
        title: 'Brooklyn Baby',
        channelTitle: 'Twinkle Twinkle Little Rock Star',
        thumbnailUrl: '',
        duration: '4:12',
        viewCount: 'MusicBrainz Verified',
        canonicalTitle: 'Brooklyn Baby',
        canonicalArtist: 'Twinkle Twinkle Little Rock Star',
        albumName: 'Lullaby Versions of Lana Del Rey',
        metadataProvider: 'musicbrainz',
      );

      final lanaDelRey = YouTubeVideo(
        id: 'itunes_ldr_bb',
        title: 'Brooklyn Baby',
        channelTitle: 'Lana Del Rey',
        thumbnailUrl: 'https://example.com/ldr.jpg',
        duration: '5:51',
        viewCount: 'Apple Music',
        canonicalTitle: 'Brooklyn Baby',
        canonicalArtist: 'Lana Del Rey',
        albumName: 'Ultraviolence',
        metadataProvider: 'itunes',
      );

      final candidates = <YouTubeVideo>[vitaminStringQuartet, twinkleTwinkle, lanaDelRey];

      final prominentArtists = [
        const ArtistModel(
          id: 'lana_del_rey',
          name: 'Lana Del Rey',
          imageUrl: 'https://example.com/lana.jpg',
          fanCount: 5800000,
        ),
        const ArtistModel(
          id: 'vitamin_string_quartet',
          name: 'Vitamin String Quartet',
          imageUrl: '',
          fanCount: 50000,
        ),
      ];

      final ranked = CanonicalMusicRanker.rankVideos(
        candidates,
        query: 'brooklyn baby',
        canonicalArtist: 'Lana Del Rey',
        prominentArtists: prominentArtists,
      );

      expect(ranked.first.canonicalArtist, 'Lana Del Rey');
      expect(ranked.first.albumName, 'Ultraviolence');
      expect(ranked.any((v) => v.canonicalArtist == 'Vitamin String Quartet'), isTrue);
      expect(ranked.first.canonicalArtist == 'Vitamin String Quartet', isFalse);
    });

    test('3. We On Go — BIA recording is prioritized and correctly scored', () {
      final biaSong = YouTubeVideo(
        id: 'itunes_bia_wog',
        title: 'WE ON GO',
        channelTitle: 'BIA',
        thumbnailUrl: 'https://example.com/bia.jpg',
        duration: '2:48',
        viewCount: 'Apple Music',
        canonicalTitle: 'WE ON GO',
        canonicalArtist: 'BIA',
        albumName: 'REALLY HER (INTL DELUXE)',
        metadataProvider: 'itunes',
      );

      final randomCover = YouTubeVideo(
        id: 'mb_unknown_wog',
        title: 'WE ON GO (Cover)',
        channelTitle: 'Cover Artist',
        thumbnailUrl: '',
        duration: '3:00',
        viewCount: 'MusicBrainz Verified',
        canonicalTitle: 'WE ON GO (Cover)',
        canonicalArtist: 'Cover Artist',
        metadataProvider: 'musicbrainz',
      );

      final ranked = CanonicalMusicRanker.rankVideos(
        [randomCover, biaSong],
        query: 'we on go',
        canonicalArtist: 'BIA',
        prominentArtists: [
          const ArtistModel(id: 'bia', name: 'BIA', imageUrl: '', fanCount: 7000),
          const ArtistModel(id: 'weongo', name: 'Weongo', imageUrl: '', fanCount: 5000),
        ],
      );

      expect(ranked.first.canonicalTitle, 'WE ON GO');
      expect(ranked.first.canonicalArtist, 'BIA');
    });

    test('4. Intent Preservation — Explicit requests for cover, live, or acoustic versions are honored', () {
      final soyStudio = YouTubeVideo(
        id: 'ed_soy_studio',
        title: 'Shape of You',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: '',
        duration: '3:53',
        viewCount: 'Official Audio',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Ed Sheeran',
      );

      final soyAcoustic = YouTubeVideo(
        id: 'ed_soy_acoustic',
        title: 'Shape of You (Acoustic)',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: '',
        duration: '3:45',
        viewCount: 'Official Audio',
        canonicalTitle: 'Shape of You (Acoustic)',
        canonicalArtist: 'Ed Sheeran',
      );

      final soyCaitlin = YouTubeVideo(
        id: 'caitlin_soy',
        title: 'Shape of You',
        channelTitle: 'Caitlin De Ville',
        thumbnailUrl: '',
        duration: '3:55',
        viewCount: 'YouTube',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Caitlin De Ville',
        albumName: 'Covers Collection',
      );

      // A) Query: "shape of you acoustic"
      final rankedAcoustic = CanonicalMusicRanker.rankVideos(
        [soyStudio, soyAcoustic],
        query: 'shape of you acoustic',
        canonicalArtist: 'Ed Sheeran',
      );
      expect(rankedAcoustic.first.id, 'ed_soy_acoustic');

      // B) Query: "shape of you caitlin de ville" -> explicitly named artist is NOT penalized
      final rankedCaitlin = CanonicalMusicRanker.rankVideos(
        [soyStudio, soyCaitlin],
        query: 'shape of you caitlin de ville',
      );
      expect(rankedCaitlin.first.id, 'caitlin_soy');
    });

    test('5. Deduplication preserves unique canonical recordings without duplicating identical tracks', () {
      final v1 = YouTubeVideo(
        id: 'mb_111',
        title: 'Shape of You',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: 'https://example.com/mb.jpg',
        duration: '3:53',
        viewCount: 'MusicBrainz Verified',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Ed Sheeran',
        metadataProvider: 'musicbrainz',
      );

      final v2 = YouTubeVideo(
        id: 'itunes_222',
        title: 'Shape of You',
        channelTitle: 'Ed Sheeran',
        thumbnailUrl: 'https://example.com/itunes_highres.jpg',
        duration: '3:53',
        viewCount: 'Apple Music',
        canonicalTitle: 'Shape of You',
        canonicalArtist: 'Ed Sheeran',
        metadataProvider: 'itunes',
      );

      final ranked = CanonicalMusicRanker.rankVideos(
        [v1, v2],
        query: 'shape of you',
        canonicalArtist: 'Ed Sheeran',
      );

      expect(ranked.length, 1);
      expect(ranked.first.canonicalTitle, 'Shape of You');
      expect(ranked.first.canonicalArtist, 'Ed Sheeran');
    });

    testWidgets('6. SearchPage Top Result — "we on go" selects Song "WE ON GO" by BIA, NOT artist "Weongo"', (tester) async {
      final searchState = SearchState(
        query: 'we on go',
        activeFilter: 'All',
        onlineArtists: [
          const ArtistModel(id: 'weongo', name: 'Weongo', imageUrl: '', fanCount: 5000),
          const ArtistModel(id: 'wonho', name: 'WONHO', imageUrl: '', fanCount: 22000),
          const ArtistModel(id: 'bia', name: 'Bïa', imageUrl: '', fanCount: 7000),
        ],
        youtubeResults: [
          const YouTubeVideo(
            id: 'bia_we_on_go',
            title: 'WE ON GO',
            channelTitle: 'BIA',
            thumbnailUrl: '',
            duration: '2:48',
            viewCount: 'MusicBrainz Verified',
            canonicalTitle: 'WE ON GO',
            canonicalArtist: 'BIA',
            metadataProvider: 'musicbrainz',
          ),
        ],
        isArtistsLoading: false,
        isYouTubeLoading: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides(searchState),
          child: const MaterialApp(home: SearchPage()),
        ),
      );

      await tester.pump();

      // Top result section exists
      expect(find.text('Top result'), findsOneWidget);

      // The top result card must display the song 'WE ON GO', and BIA
      expect(find.widgetWithText(GestureDetector, 'WE ON GO'), findsWidgets);
      expect(find.widgetWithText(GestureDetector, 'BIA'), findsWidgets);
    });

    testWidgets('7. SearchPage Top Result — "ed sheeran" selects Artist "Ed Sheeran" with fan count', (tester) async {
      final searchState = SearchState(
        query: 'ed sheeran',
        activeFilter: 'All',
        onlineArtists: [
          const ArtistModel(id: 'ed_sheeran', name: 'Ed Sheeran', imageUrl: '', fanCount: 20900000),
        ],
        youtubeResults: [
          const YouTubeVideo(
            id: 'soy',
            title: 'Shape of You',
            channelTitle: 'Ed Sheeran',
            thumbnailUrl: '',
            duration: '3:53',
            viewCount: 'MusicBrainz Verified',
            canonicalTitle: 'Shape of You',
            canonicalArtist: 'Ed Sheeran',
            metadataProvider: 'musicbrainz',
          ),
        ],
        isArtistsLoading: false,
        isYouTubeLoading: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: commonOverrides(searchState),
          child: const MaterialApp(home: SearchPage()),
        ),
      );

      await tester.pump();

      expect(find.text('Top result'), findsOneWidget);
      expect(find.text('Ed Sheeran'), findsWidgets);
      expect(find.text('20.9M fans'), findsWidgets);
    });
  });
}
