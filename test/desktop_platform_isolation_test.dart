import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/features/media/domain/library_filter_policy.dart';
import 'package:Miee/features/media/data/desktop_media_repository.dart';
import 'package:Miee/features/media/data/web_media_repository.dart';
import 'package:Miee/features/media/providers/media_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_isolation_test_');
    Hive.init(tempDir.path);
    await Hive.openBox(HiveBoxes.preferences);
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Phase D2 — Platform Abstraction & Core Isolation Tests', () {
    test('1. WebMediaRepository provides clean no-op responses without platform channels', () async {
      final repo = WebMediaRepository();
      expect(await repo.checkAndRequestPermissions(), isTrue);
      expect(await repo.getSongs(), isEmpty);
      expect(await repo.getAlbums(), isEmpty);
      expect(await repo.getArtists(), isEmpty);
      expect(await repo.getFolders(), isEmpty);
      expect(await repo.getFolderPreferences(), isA<LibraryFolderPreferences>());
    });

    test('2. DesktopMediaRepository checks permissions and manages folder preferences in Hive', () async {
      final repo = DesktopMediaRepository();
      expect(await repo.checkAndRequestPermissions(), isTrue);

      final initialPrefs = await repo.getFolderPreferences();
      expect(initialPrefs, isA<LibraryFolderPreferences>());

      final customPrefs = initialPrefs.copyWith(
        includedFolders: {tempDir.path},
        excludeTempAndCache: false,
      );
      await repo.saveFolderPreferences(customPrefs);

      final retrievedPrefs = await repo.getFolderPreferences();
      final normalized = LibraryFolderPreferences.normalizeFolderPath(tempDir.path);
      expect(retrievedPrefs.includedFolders.contains(normalized), isTrue);
    });

    test('3. DesktopMediaRepository scans directory and builds MediaSong models', () async {
      final repo = DesktopMediaRepository();

      // Create dummy audio files in tempDir
      final songFile = File('${tempDir.path}/Sai Abhyankkar - Veezha Veera.mp3');
      await songFile.writeAsBytes(List.filled(1024, 0));

      final customPrefs = LibraryFolderPreferences(
        includedFolders: {tempDir.path},
        excludeTempAndCache: false,
      );
      await repo.saveFolderPreferences(customPrefs);

      final songs = await repo.getSongs(forceRefresh: true);
      expect(songs.isNotEmpty, isTrue);

      final normalizedFilePath = songFile.path.toLowerCase().replaceAll('\\', '/');
      final matched = songs.firstWhere(
        (s) => s.filePath.toLowerCase().replaceAll('\\', '/') == normalizedFilePath,
      );
      expect(matched.artist, equals('Sai Abhyankkar'));
      expect(matched.title, equals('Veezha Veera'));
      expect(matched.id.startsWith('desktop_'), isTrue);

      // Verify aggregated albums and artists
      final albums = await repo.getAlbums();
      expect(albums.isNotEmpty, isTrue);

      final artists = await repo.getArtists();
      expect(artists.any((a) => a.name == 'Sai Abhyankkar'), isTrue);
    });

    test('4. mediaRepositoryProvider resolves to DesktopMediaRepository on desktop host', () {
      final container = ProviderContainer();
      final repo = container.read(mediaRepositoryProvider);

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        expect(repo, isA<DesktopMediaRepository>());
      }
      container.dispose();
    });
  });
}
