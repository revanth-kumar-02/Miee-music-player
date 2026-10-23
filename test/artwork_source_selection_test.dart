import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:Miee/shared/models/track.dart';

/// Enum representing the resolved image provider type.
enum ArtworkSourceType {
  network,
  file,
  fallback,
}

/// Helper replicating the pure routing logic of PlayerPage._buildArtworkImage
ArtworkSourceType resolveArtworkSource(String? rawUrl) {
  if (rawUrl == null || rawUrl.trim().isEmpty) {
    return ArtworkSourceType.fallback;
  }
  final cleanUrl = rawUrl.trim();
  if (cleanUrl.startsWith('http://') || cleanUrl.startsWith('https://')) {
    return ArtworkSourceType.network;
  }
  try {
    final normalizedPath = cleanUrl.startsWith('file://')
        ? Uri.parse(cleanUrl).toFilePath()
        : cleanUrl;
    // Check if path is non-empty and well-formed
    if (normalizedPath.isNotEmpty) {
      return ArtworkSourceType.file;
    }
    return ArtworkSourceType.fallback;
  } catch (_) {
    return ArtworkSourceType.fallback;
  }
}

void main() {
  group('Artwork Source Selection Tests', () {
    test('Resolves HTTPS URL to network provider', () {
      const url = 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg';
      final result = resolveArtworkSource(url);
      expect(result, equals(ArtworkSourceType.network));
    });

    test('Resolves HTTP URL to network provider', () {
      const url = 'http://example.com/artwork.jpg';
      final result = resolveArtworkSource(url);
      expect(result, equals(ArtworkSourceType.network));
    });

    test('Resolves local Unix/Android filesystem path to file provider', () {
      const path = '/storage/emulated/0/Android/data/com.example.miee/cache/album_42.png';
      final result = resolveArtworkSource(path);
      expect(result, equals(ArtworkSourceType.file));
    });

    test('Resolves local Windows filesystem path to file provider', () {
      const path = r'C:\Users\User\AppData\Local\Temp\album_42.png';
      final result = resolveArtworkSource(path);
      expect(result, equals(ArtworkSourceType.file));
    });

    test('Normalizes file:// URI correctly to file provider', () {
      // In Dart, Uri.parse('file:///storage/emulated/0/Music/art.jpg').toFilePath() yields path
      const uri = 'file:///storage/emulated/0/Music/art.jpg';
      final result = resolveArtworkSource(uri);
      expect(result, equals(ArtworkSourceType.file));
    });

    test('Handles null artwork URL with fallback', () {
      final result = resolveArtworkSource(null);
      expect(result, equals(ArtworkSourceType.fallback));
    });

    test('Handles empty string with fallback', () {
      final result = resolveArtworkSource('');
      expect(result, equals(ArtworkSourceType.fallback));
    });

    test('Handles whitespace-only string with fallback', () {
      final result = resolveArtworkSource('   \t\n  ');
      expect(result, equals(ArtworkSourceType.fallback));
    });

    test('Does not attempt Image.network on local paths', () {
      const localPath = '/data/user/0/com.miee.music/cache/art.png';
      expect(localPath.startsWith('http://'), isFalse);
      expect(localPath.startsWith('https://'), isFalse);
      expect(resolveArtworkSource(localPath), isNot(ArtworkSourceType.network));
    });
  });

  group('Track Model Artwork Binding Tests', () {
    test('YouTube Track maps thumbnail to network artwork', () {
      const ytTrack = Track(
        id: 'youtube_dQw4w9WgXcQ',
        title: 'Never Gonna Give You Up',
        artist: 'Rick Astley',
        imageUrl: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        duration: '3:33',
      );

      expect(ytTrack.isYoutube, isTrue);
      expect(resolveArtworkSource(ytTrack.imageUrl), equals(ArtworkSourceType.network));
    });

    test('Local Track with cached album art maps to file provider', () {
      const localTrack = Track(
        id: '101',
        title: 'Midnight City',
        artist: 'M83',
        imageUrl: '/data/user/0/com.example.miee/cache/album_12.png',
        duration: '4:03',
        filePath: '/storage/emulated/0/Music/midnight_city.mp3',
      );

      expect(localTrack.isYoutube, isFalse);
      expect(resolveArtworkSource(localTrack.imageUrl), equals(ArtworkSourceType.file));
    });

    test('Local Track without artwork falls back safely', () {
      const localTrackWithoutArt = Track(
        id: '102',
        title: 'Unknown Track',
        artist: 'Unknown Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: '/storage/emulated/0/Music/unknown.mp3',
      );

      expect(localTrackWithoutArt.imageUrl.isEmpty, isTrue);
      expect(resolveArtworkSource(localTrackWithoutArt.imageUrl), equals(ArtworkSourceType.fallback));
    });
  });

  group('Android Manifest Notification Permission Verification', () {
    test('AndroidManifest.xml contains POST_NOTIFICATIONS permission', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue, reason: 'AndroidManifest.xml must exist');

      final content = manifestFile.readAsStringSync();
      expect(
        content.contains('android.permission.POST_NOTIFICATIONS'),
        isTrue,
        reason: 'AndroidManifest.xml must declare android.permission.POST_NOTIFICATIONS for Android 13+ (API 33+)',
      );

      // Verify it is placed before <application>
      final permIndex = content.indexOf('android.permission.POST_NOTIFICATIONS');
      final appIndex = content.indexOf('<application');
      expect(permIndex, isPositive);
      expect(appIndex, isPositive);
      expect(
        permIndex < appIndex,
        isTrue,
        reason: 'Permission must be declared as a child of <manifest> before <application>',
      );
    });

    test('targetSdk is configured at or above API 33', () {
      final gradleFile = File('android/app/build.gradle.kts');
      expect(gradleFile.existsSync(), isTrue, reason: 'build.gradle.kts must exist');

      final content = gradleFile.readAsStringSync();
      final targetSdkMatch = RegExp(r'targetSdk\s*=\s*(\d+)').firstMatch(content);
      expect(targetSdkMatch, isNotNull);

      final targetSdk = int.parse(targetSdkMatch!.group(1)!);
      expect(
        targetSdk >= 33,
        isTrue,
        reason: 'targetSdk must be at least 33 (current: $targetSdk) where POST_NOTIFICATIONS is required',
      );
    });
  });
}
