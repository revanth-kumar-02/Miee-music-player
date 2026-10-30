import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:Miee/features/library/data/favorites_repository.dart';
import 'package:Miee/features/library/data/most_played_repository.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/playlists/providers/smart_playlists_provider.dart';
import 'package:Miee/shared/models/track.dart';

class MockFavoritesNotifier extends FavoritesNotifier {
  MockFavoritesNotifier(List<Track> initial) : super(_DummyRepo()) {
    state = initial;
  }
}

class _DummyRepo implements FavoritesRepository {
  @override
  Future<void> addFavorite(Track track) async {}
  @override
  Future<void> removeFavorite(String trackId) async {}
  @override
  bool isFavorite(String trackId) => false;
  @override
  List<Track> getFavorites() => [];
  @override
  Stream<List<Track>> watchFavorites() => const Stream.empty();
  @override
  Future<void> clearAll() async {}
}

class MockMostPlayedRepo extends MostPlayedRepository {
  final Map<String, int> counts;

  MockMostPlayedRepo(Ref ref, {this.counts = const {}}) : super(ref);

  @override
  int getCount(String trackId) => counts[trackId] ?? 0;

  @override
  List<MapEntry<String, int>> getMostPlayed({int limit = 20}) {
    final list = counts.entries.toList();
    list.sort((a, b) => b.value.compareTo(a.value));
    return list.take(limit).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Smart Playlists Engine Tests', () {
    test('Generates smart playlists dynamically from favorites and library data', () {
      final container = ProviderContainer(
        overrides: [
          favoritesProvider.overrideWith((ref) => MockFavoritesNotifier([
            const Track(
              id: 'track_1',
              title: 'Chill Sunset Walk',
              artist: 'Mellow Artist',
              imageUrl: '',
              duration: '3:20',
            ),
            const Track(
              id: 'track_2',
              title: 'Heavy Beats Anthem',
              artist: 'Rock Band',
              imageUrl: '',
              duration: '4:10',
            ),
            const Track(
              id: 'track_3',
              title: 'Late Night Acoustic Melody',
              artist: 'Acoustic Guitar',
              imageUrl: '',
              duration: '2:50',
            ),
          ])),
          mostPlayedRepositoryProvider.overrideWith(
            (ref) => MockMostPlayedRepo(ref, counts: {
              'track_1': 45,
              'track_2': 10,
              'track_3': 85,
            }),
          ),
        ],
      );

      final smartPlaylists = container.read(smartPlaylistsProvider);
      expect(smartPlaylists, isNotEmpty);

      // Verify "On Repeat" is sorted by play count descending (track_3=85, track_1=45, track_2=10)
      final onRepeat = smartPlaylists.firstWhere((p) => p.id == 'smart_on_repeat');
      expect(onRepeat.tracks.first.id, 'track_3');
      expect(onRepeat.tracks[1].id, 'track_1');

      // Verify "Recently Added" contains the reversed order
      final recentlyAdded = smartPlaylists.firstWhere((p) => p.id == 'smart_recently_added');
      expect(recentlyAdded.tracks.first.id, 'track_3');

      // Verify "Late Night Chill" filters acoustic/chill keywords accurately
      final chillPlaylist = smartPlaylists.firstWhere((p) => p.id == 'smart_late_night_chill');
      expect(chillPlaylist.tracks.length, 2);
      expect(chillPlaylist.tracks.any((t) => t.id == 'track_1'), isTrue);
      expect(chillPlaylist.tracks.any((t) => t.id == 'track_3'), isTrue);
      expect(chillPlaylist.tracks.any((t) => t.id == 'track_2'), isFalse);

      container.dispose();
    });
  });
}
