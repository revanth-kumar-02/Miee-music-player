import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/settings/domain/settings_model.dart';
import 'package:Miee/features/settings/presentation/settings_controller.dart';
import 'package:Miee/features/settings/presentation/settings_page.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/profile/presentation/profile_controller.dart';
import 'package:Miee/features/profile/domain/profile_model.dart';
import 'package:Miee/features/auth/providers/auth_providers.dart';
import 'package:Miee/shared/models/track.dart';

/// Test Spy for MediaLibraryService tracking scanDevice calls and controlling async lifecycle.
class FakeMediaLibraryService extends StateNotifier<MediaLibraryState>
    implements MediaLibraryService {
  int scanDeviceCallCount = 0;
  bool? lastForceRefresh;
  Completer<void>? scanCompleter;
  bool permissionDenied = false;
  bool shouldThrow = false;
  bool shouldSetError = false;
  String? errorMessage;
  List<MediaSong> resultSongs = const [];

  FakeMediaLibraryService([MediaLibraryState? initial])
      : super(initial ?? MediaLibraryState.initial());

  @override
  Future<void> scanDevice({bool forceRefresh = false}) async {
    scanDeviceCallCount++;
    lastForceRefresh = forceRefresh;
    state = state.copyWith(isLoading: true, errorMessage: null);

    if (scanCompleter != null) {
      await scanCompleter!.future;
    }

    if (shouldThrow) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'An error occurred during scan: I/O failure',
      );
      throw Exception('I/O failure');
    }

    if (permissionDenied) {
      state = state.copyWith(
        isLoading: false,
        hasPermission: false,
        errorMessage: 'Storage permission was denied.',
      );
      return;
    }

    if (shouldSetError) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: errorMessage ?? 'Catalog indexing failed',
      );
      return;
    }

    state = state.copyWith(
      isLoading: false,
      hasPermission: true,
      songs: resultSongs,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake SettingsController to track lastScanTime updates and avoid Hive persistence in tests.
class FakeSettingsController extends StateNotifier<SettingsModel>
    implements SettingsController {
  int updateLastScanTimeCallCount = 0;
  String? lastScanTimeRecorded;

  FakeSettingsController([SettingsModel? initial])
      : super(initial ?? const SettingsModel());

  @override
  Future<void> updateLastScanTime(String? time) async {
    updateLastScanTimeCallCount++;
    lastScanTimeRecorded = time;
    state = state.copyWith(lastScanTime: time);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFavoritesNotifier extends StateNotifier<List<Track>>
    implements FavoritesNotifier {
  FakeFavoritesNotifier() : super([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSearchHistoryNotifier extends StateNotifier<List<String>>
    implements SearchHistoryNotifier {
  FakeSearchHistoryNotifier() : super([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProfileNotifier extends StateNotifier<ProfileModel>
    implements ProfileNotifier {
  FakeProfileNotifier() : super(ProfileModel.initial());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Settings Refresh Metadata — Unit & Logic Tests', () {
    test('Successful scan invokes scanDevice(forceRefresh: true) and updates state', () async {
      final fakeService = FakeMediaLibraryService();
      fakeService.resultSongs = [
        const MediaSong(
          id: '1',
          title: 'Song 1',
          artist: 'Artist 1',
          album: 'Album 1',
          duration: '3:30',
          filePath: '/storage/music/song1.mp3',
        ),
        const MediaSong(
          id: '2',
          title: 'Song 2',
          artist: 'Artist 2',
          album: 'Album 2',
          duration: '4:10',
          filePath: '/storage/music/song2.mp3',
        ),
      ];

      expect(fakeService.state.isLoading, isFalse);
      expect(fakeService.scanDeviceCallCount, equals(0));

      await fakeService.scanDevice(forceRefresh: true);

      expect(fakeService.scanDeviceCallCount, equals(1));
      expect(fakeService.lastForceRefresh, isTrue);
      expect(fakeService.state.isLoading, isFalse);
      expect(fakeService.state.hasPermission, isTrue);
      expect(fakeService.state.errorMessage, isNull);
      expect(fakeService.state.songs.length, equals(2));
      expect(fakeService.state.songs[0].title, equals('Song 1'));
    });

    test('Scan failure produces error state and resets loading to false', () async {
      final fakeService = FakeMediaLibraryService();
      fakeService.shouldSetError = true;
      fakeService.errorMessage = 'Corrupted media store database';

      await fakeService.scanDevice(forceRefresh: true);

      expect(fakeService.scanDeviceCallCount, equals(1));
      expect(fakeService.state.isLoading, isFalse);
      expect(fakeService.state.errorMessage, equals('Corrupted media store database'));
      expect(fakeService.state.songs, isEmpty);
    });

    test('Permission denial sets hasPermission to false and provides truthful error', () async {
      final fakeService = FakeMediaLibraryService();
      fakeService.permissionDenied = true;

      await fakeService.scanDevice(forceRefresh: true);

      expect(fakeService.scanDeviceCallCount, equals(1));
      expect(fakeService.state.isLoading, isFalse);
      expect(fakeService.state.hasPermission, isFalse);
      expect(fakeService.state.errorMessage, equals('Storage permission was denied.'));
    });

    test('Loading state accurately reflects active scan progress', () async {
      final completer = Completer<void>();
      final fakeService = FakeMediaLibraryService();
      fakeService.scanCompleter = completer;

      final future = fakeService.scanDevice(forceRefresh: true);

      // In flight
      expect(fakeService.state.isLoading, isTrue);

      // Complete
      completer.complete();
      await future;

      expect(fakeService.state.isLoading, isFalse);
    });
  });

  group('Settings Refresh Metadata — Widget Integration Tests', () {
    late FakeMediaLibraryService fakeMediaService;
    late FakeSettingsController fakeSettingsController;

    setUp(() {
      fakeMediaService = FakeMediaLibraryService();
      fakeSettingsController = FakeSettingsController();
    });

    List<Override> createOverrides() {
      return [
        mediaLibraryServiceProvider.overrideWith((ref) => fakeMediaService),
        settingsControllerProvider.overrideWith((ref) => fakeSettingsController),
        favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
        searchHistoryProvider.overrideWith((ref) => FakeSearchHistoryNotifier()),
        profileProvider.overrideWith((ref) => FakeProfileNotifier()),
        currentUserProfileProvider.overrideWith((ref) => null),
        currentAuthUserProvider.overrideWith((ref) => null),
      ];
    }

    Widget createTestWidget({Widget? child}) {
      return ProviderScope(
        overrides: createOverrides(),
        child: MaterialApp(
          home: child ?? const SettingsPage(),
        ),
      );
    }

    testWidgets('Renders Refresh Metadata tile with chevron when idle', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      expect(find.text('Refresh Metadata'), findsOneWidget);
      expect(find.text('Reload tags and local file information'), findsOneWidget);
      expect(find.byIcon(Icons.refresh_outlined), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Tapping Refresh Metadata invokes scanDevice(forceRefresh: true)', (tester) async {
      fakeMediaService.resultSongs = [
        const MediaSong(
          id: '1',
          title: 'Track A',
          artist: 'Artist A',
          album: 'Album A',
          duration: '3:00',
          filePath: '/storage/trackA.mp3',
        ),
      ];

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      final tileFinder = find.widgetWithText(ListTile, 'Refresh Metadata');
      expect(tileFinder, findsOneWidget);

      await tester.tap(tileFinder);
      await tester.pump();

      expect(fakeMediaService.scanDeviceCallCount, equals(1));
      expect(fakeMediaService.lastForceRefresh, isTrue);

      await tester.pumpAndSettle();

      // Verified success SnackBar appears with correct song count
      expect(find.text('Metadata tags refreshed successfully (1 songs).'), findsOneWidget);
      // Verified lastScanTime was updated in settings
      expect(fakeSettingsController.updateLastScanTimeCallCount, equals(1));
    });

    testWidgets('Shows loading feedback while scan is active and disables repeated taps', (tester) async {
      final completer = Completer<void>();
      fakeMediaService.scanCompleter = completer;

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      final tileFinder = find.widgetWithText(ListTile, 'Refresh Metadata');
      await tester.tap(tileFinder);
      await tester.pump();

      // 1. Initial transient feedback
      expect(find.text('Refreshing metadata...'), findsOneWidget);
      // 2. Trailing shows CircularProgressIndicator instead of chevron
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(fakeMediaService.scanDeviceCallCount, equals(1));

      // 3. Repeated tap while scanning is active
      await tester.tap(tileFinder);
      await tester.pump();

      // Scan count remains 1 (prevented duplicate launch)
      expect(fakeMediaService.scanDeviceCallCount, equals(1));

      // 4. Resolve scan
      completer.complete();
      await tester.pumpAndSettle();

      // Circular indicator removed, returned to idle
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Metadata tags refreshed successfully'), findsOneWidget);
    });

    testWidgets('Scan failure produces error SnackBar and resets loading state', (tester) async {
      fakeMediaService.shouldSetError = true;
      fakeMediaService.errorMessage = 'Media metadata parser crashed';

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      final tileFinder = find.widgetWithText(ListTile, 'Refresh Metadata');
      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      expect(fakeMediaService.scanDeviceCallCount, equals(1));
      expect(find.text('Media metadata parser crashed'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Permission denial displays truthful error SnackBar', (tester) async {
      fakeMediaService.permissionDenied = true;

      await tester.pumpWidget(createTestWidget());
      await tester.pump();

      final tileFinder = find.widgetWithText(ListTile, 'Refresh Metadata');
      await tester.tap(tileFinder);
      await tester.pumpAndSettle();

      expect(fakeMediaService.scanDeviceCallCount, equals(1));
      expect(find.text('Storage permission was denied.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('Navigating away while scan is active does not cause unsafe widget updates', (tester) async {
      final completer = Completer<void>();
      fakeMediaService.scanCompleter = completer;

      await tester.pumpWidget(
        ProviderScope(
          overrides: createOverrides(),
          child: MaterialApp(
            home: Navigator(
              pages: const [
                MaterialPage(child: Scaffold(body: Text('Root Screen'))),
                MaterialPage(child: SettingsPage()),
              ],
              onPopPage: (route, result) => route.didPop(result),
            ),
          ),
        ),
      );
      await tester.pump();

      final tileFinder = find.widgetWithText(ListTile, 'Refresh Metadata');
      expect(tileFinder, findsOneWidget);

      // Start scan
      await tester.tap(tileFinder);
      await tester.pump();

      expect(fakeMediaService.scanDeviceCallCount, equals(1));

      // Pop SettingsPage while scan is still in flight
      final navigatorState = tester.state<NavigatorState>(find.byType(Navigator));
      navigatorState.pop();
      await tester.pump();

      // Complete async scan while SettingsPage is unmounted
      completer.complete();
      await tester.pumpAndSettle();

      // No assertion failure or exception thrown
      expect(find.text('Root Screen'), findsOneWidget);
    });
  });
}
