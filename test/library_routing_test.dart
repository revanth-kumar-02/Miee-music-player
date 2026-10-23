import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/features/media/domain/models.dart';

/// Helper simulating the navigation resolution logic from PlaylistsPage._buildStructuredTable
class NavigationTarget {
  final String route;
  final Object? extra;

  const NavigationTarget(this.route, {this.extra});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationTarget &&
          runtimeType == other.runtimeType &&
          route == other.route &&
          extra == other.extra;

  @override
  int get hashCode => route.hashCode ^ extra.hashCode;

  @override
  String toString() => 'NavigationTarget(route: $route, extra: $extra)';
}

NavigationTarget? resolveLibraryTableRowNavigation(dynamic item) {
  if (item is MediaArtist) {
    if (item.id.trim().isNotEmpty) {
      return NavigationTarget(
        '/artist/${Uri.encodeComponent(item.id.trim())}',
        extra: item,
      );
    }
  } else if (item is MediaAlbum) {
    if (item.id.trim().isNotEmpty) {
      return NavigationTarget(
        '/album/${Uri.encodeComponent(item.id.trim())}',
      );
    }
  }
  return null;
}

void main() {
  group('Library Table Navigation Tests', () {
    test('MediaArtist row resolves to /artist/:id with extra', () {
      const artist = MediaArtist(
        id: '101',
        name: 'The Weeknd',
        trackCount: 15,
        albumCount: 3,
        artworkPath: '/cache/art_101.png',
      );

      final target = resolveLibraryTableRowNavigation(artist);
      expect(target, isNotNull);
      expect(target!.route, equals('/artist/101'));
      expect(target.extra, equals(artist));
      expect(target.route, isNot(equals('/search')), reason: 'Must not redirect to search');
    });

    test('MediaAlbum row resolves to /album/:id without redirecting to search', () {
      const album = MediaAlbum(
        id: '202',
        title: 'After Hours',
        artist: 'The Weeknd',
        trackCount: 14,
        artworkPath: '/cache/album_202.png',
      );

      final target = resolveLibraryTableRowNavigation(album);
      expect(target, isNotNull);
      expect(target!.route, equals('/album/202'));
      expect(target.route, isNot(equals('/search')), reason: 'Must not redirect to search');
    });

    test('Special characters in IDs are safely percent-encoded for GoRouter', () {
      const artistSpecial = MediaArtist(
        id: 'artist/special #1',
        name: 'AC/DC',
        trackCount: 10,
        albumCount: 2,
      );

      final target = resolveLibraryTableRowNavigation(artistSpecial);
      expect(target, isNotNull);
      expect(target!.route, equals('/artist/artist%2Fspecial%20%231'));

      // Verify that Uri.decodeComponent properly recovers the original ID
      final extractedId = target.route.replaceFirst('/artist/', '');
      expect(Uri.decodeComponent(extractedId), equals('artist/special #1'));
    });

    test('Empty or whitespace-only IDs do not produce broken route transitions', () {
      const emptyArtist = MediaArtist(
        id: '   ',
        name: 'Ghost Artist',
        trackCount: 0,
        albumCount: 0,
      );

      const emptyAlbum = MediaAlbum(
        id: '',
        title: 'Empty Album',
        artist: 'Unknown',
        trackCount: 0,
        artworkPath: '',
      );

      expect(resolveLibraryTableRowNavigation(emptyArtist), isNull);
      expect(resolveLibraryTableRowNavigation(emptyAlbum), isNull);
    });

    test('GoRouter parameter extraction pattern verification', () {
      // Simulating GoRouter path parameter extraction for /artist/:id and /album/:id
      final artistRegex = RegExp(r'^/artist/(.+)$');
      final albumRegex = RegExp(r'^/album/(.+)$');

      final artistRoute = '/artist/42';
      final albumRoute = '/album/99';

      final artistMatch = artistRegex.firstMatch(artistRoute);
      final albumMatch = albumRegex.firstMatch(albumRoute);

      expect(artistMatch, isNotNull);
      expect(artistMatch!.group(1), equals('42'));

      expect(albumMatch, isNotNull);
      expect(albumMatch!.group(1), equals('99'));
    });
  });
}
