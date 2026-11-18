import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:Miee/core/storage/adapters/playlist_hive_model.dart';
import 'package:Miee/core/storage/adapters/track_hive_model.dart';
import 'package:Miee/features/playlists/domain/playlist_model.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_collab_test_');
    Hive.init(tempDir.path);
    if (!Hive.isAdapterRegistered(1)) {
      Hive.registerAdapter(TrackHiveModelAdapter());
    }
    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(PlaylistHiveModelAdapter());
    }
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PlaylistModel Domain & Role-Based Permissions', () {
    test('Default permissions for owner', () {
      final playlist = PlaylistModel(
        id: 'pl_1',
        name: 'My Vibes',
        tracks: const [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        type: PlaylistType.private,
        ownerId: 'user_123',
        role: PlaylistRole.owner,
      );

      expect(playlist.isOwner, isTrue);
      expect(playlist.canEdit, isTrue);
      expect(playlist.isCollaborative, isFalse);
    });

    test('Editor permissions on collaborative playlist', () {
      final playlist = PlaylistModel(
        id: 'pl_2',
        name: 'Party Collab',
        tracks: const [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        type: PlaylistType.collaborative,
        ownerId: 'user_other',
        role: PlaylistRole.editor,
      );

      expect(playlist.isOwner, isFalse);
      expect(playlist.canEdit, isTrue);
      expect(playlist.isCollaborative, isTrue);
    });

    test('Viewer permissions on shared playlist', () {
      final playlist = PlaylistModel(
        id: 'pl_3',
        name: 'Shared Vibes',
        tracks: const [],
        createdAt: DateTime.now(),
        lastModified: DateTime.now(),
        type: PlaylistType.shared,
        ownerId: 'user_other',
        role: PlaylistRole.viewer,
      );

      expect(playlist.isOwner, isFalse);
      expect(playlist.canEdit, isFalse);
      expect(playlist.isCollaborative, isFalse);
    });

    test('PlaylistType and PlaylistRole string parsing', () {
      expect(PlaylistType.fromString('collaborative'), equals(PlaylistType.collaborative));
      expect(PlaylistType.fromString('shared'), equals(PlaylistType.shared));
      expect(PlaylistType.fromString('private'), equals(PlaylistType.private));
      expect(PlaylistType.fromString('unknown'), equals(PlaylistType.private));
      expect(PlaylistType.fromString(null), equals(PlaylistType.private));

      expect(PlaylistRole.fromString('owner'), equals(PlaylistRole.owner));
      expect(PlaylistRole.fromString('editor'), equals(PlaylistRole.editor));
      expect(PlaylistRole.fromString('viewer'), equals(PlaylistRole.viewer));
      expect(PlaylistRole.fromString(null), equals(PlaylistRole.owner));
    });
  });

  group('PlaylistHiveModel & Adapter Backward Compatibility', () {
    test('Reads and writes full 11-field collaborative model', () async {
      final box = await Hive.openBox<PlaylistHiveModel>('test_collab_box');
      final now = DateTime.now();

      final model = PlaylistHiveModel(
        id: 'box_pl_1',
        name: 'Weekend Jams',
        tracks: [
          TrackHiveModel(
            id: 't_1',
            title: 'Track One',
            artist: 'Artist One',
            imageUrl: 'https://example.com/art.jpg',
            duration: '3:30',
          ),
        ],
        createdAt: now,
        lastModified: now,
        type: 'collaborative',
        ownerId: 'user_abc',
        role: 'editor',
        description: 'Collaborative playlist for the weekend',
        version: 2,
      );

      await box.put('box_pl_1', model);
      final retrieved = box.get('box_pl_1')!;

      expect(retrieved.id, equals('box_pl_1'));
      expect(retrieved.name, equals('Weekend Jams'));
      expect(retrieved.type, equals('collaborative'));
      expect(retrieved.ownerId, equals('user_abc'));
      expect(retrieved.role, equals('editor'));
      expect(retrieved.description, equals('Collaborative playlist for the weekend'));
      expect(retrieved.version, equals(2));
      expect(retrieved.tracks.length, equals(1));
      expect(retrieved.tracks.first.title, equals('Track One'));

      await box.close();
    });
  });

  group('Guest Playlist Migration Logic', () {
    test('Identifies and assigns guest playlists to newly signed-in user', () async {
      final box = await Hive.openBox<PlaylistHiveModel>('test_migration_box');
      final now = DateTime.now();

      // Playlist 1: created as guest (no ownerId)
      final guest1 = PlaylistHiveModel(
        id: 'guest_pl_1',
        name: 'Offline Jams',
        tracks: [],
        createdAt: now,
        lastModified: now,
        ownerId: null,
      );

      // Playlist 2: created with offline mock user ID
      final guest2 = PlaylistHiveModel(
        id: 'guest_pl_2',
        name: 'Road Trip',
        tracks: [],
        createdAt: now,
        lastModified: now,
        ownerId: 'offline_guest_user',
      );

      // Playlist 3: already owned by existing user
      final existingUserPl = PlaylistHiveModel(
        id: 'user_pl_3',
        name: 'Cloud Jams',
        tracks: [],
        createdAt: now,
        lastModified: now,
        ownerId: 'already_existing_user',
      );

      await box.put('guest_pl_1', guest1);
      await box.put('guest_pl_2', guest2);
      await box.put('user_pl_3', existingUserPl);

      // Simulate migration logic
      const newUserId = 'authenticated_user_999';
      final guestPlaylists = box.values.where((p) {
        return p.ownerId == null ||
            p.ownerId!.isEmpty ||
            p.ownerId == 'offline_guest_user';
      }).toList();

      expect(guestPlaylists.length, equals(2));

      for (final p in guestPlaylists) {
        p.ownerId = newUserId;
        p.role = 'owner';
        await p.save();
      }

      // Assertions
      expect(box.get('guest_pl_1')!.ownerId, equals(newUserId));
      expect(box.get('guest_pl_2')!.ownerId, equals(newUserId));
      expect(box.get('user_pl_3')!.ownerId, equals('already_existing_user'));

      await box.close();
    });
  });
}
