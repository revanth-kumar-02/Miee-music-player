import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/artwork_source.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/data/artwork_cache.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';

void main() {
  group('Playlist Artwork Resolution & Heritage Tests', () {
    test('ArtworkQuery.forPlaylist constructs valid playlist query', () {
      final query = ArtworkQuery.forPlaylist(
        id: 'VLPL12345',
        title: 'Dude - Side A (Original Score)',
        artist: 'Sai Abhyankkar',
        albumArtworkUrl: 'https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg',
        thumbnailUrl: 'https://i.ytimg.com/vi/playlist_thumb/hqdefault.jpg',
      );

      expect(query.isPlaylist, isTrue);
      expect(query.isYoutube, isFalse);
      expect(query.title, equals('Dude - Side A (Original Score)'));
      expect(query.album, equals('Dude - Side A (Original Score)'));
      expect(query.artist, equals('Sai Abhyankkar'));
      expect(query.albumArtworkUrl, equals('https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg'));
      expect(query.cacheKey.startsWith('playlist_'), isTrue);
      expect(query.canonicalKey.startsWith('art_canon_playlist_'), isTrue);
    });

    test('ArtworkQuery.fromMusicItem inherits album and verified album cover', () {
      const video = YouTubeVideo(
        id: 'dQw4w9WgXcQ',
        title: 'Dude - Orchestral Suite',
        channelTitle: 'Sai Abhyankkar',
        thumbnailUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '2:06',
        viewCount: '1M',
      );

      final trackQuery = ArtworkQuery.fromMusicItem(
        video,
        album: 'Dude - Side A (Original Score)',
        albumArtworkUrl: 'https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg',
        explicitUrl: 'https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg',
      );

      expect(trackQuery.id, equals('dQw4w9WgXcQ'));
      expect(trackQuery.isYoutube, isTrue);
      expect(trackQuery.album, equals('Dude - Side A (Original Score)'));
      expect(trackQuery.albumArtworkUrl, equals('https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg'));
    });

    test('ArtworkResolver resolves pre-attached verified studio album cover for playlist', () async {
      final cache = ArtworkCache();
      final resolver = ArtworkResolver(cache: cache);

      final query = ArtworkQuery.forPlaylist(
        id: 'playlist_dude_side_a',
        title: 'Dude - Side A (Original Score)',
        artist: 'Sai Abhyankkar',
        albumArtworkUrl: 'https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg',
      );

      final resolved = await resolver.resolve(query);

      expect(resolved.isNeutralFallback, isFalse);
      expect(resolved.imageUrl, equals('https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg'));
      expect(resolved.source, equals(ArtworkSource.deezer));
      expect(resolved.confidence, greaterThanOrEqualTo(0.80));

      // Check that it cached canonically
      final cached = cache.get(query.canonicalKey);
      expect(cached, isNotNull);
      expect(cached!.imageUrl, equals('https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg'));
    });

    test('Track inherits canonical album artwork without redundant network fetch', () async {
      final cache = ArtworkCache();
      final resolver = ArtworkResolver(cache: cache);

      const verifiedCover = 'https://e-cdns-images.dzcdn.net/images/cover/dude_side_a.jpg';

      const video = YouTubeVideo(
        id: 'xyz123abcde',
        title: 'Ex flashback',
        channelTitle: 'Sai Abhyankkar',
        thumbnailUrl: 'https://i.ytimg.com/vi/xyz123abcde/hqdefault.jpg',
        duration: '1:08',
        viewCount: '500K',
      );

      final trackQuery = ArtworkQuery.fromMusicItem(
        video,
        album: 'Dude - Side A (Original Score)',
        albumArtworkUrl: verifiedCover,
      );

      final trackResolved = await resolver.resolve(trackQuery);

      expect(trackResolved.isNeutralFallback, isFalse);
      expect(trackResolved.imageUrl, equals(verifiedCover));
      expect(trackResolved.confidence, greaterThanOrEqualTo(0.80));
    });
  });
}
