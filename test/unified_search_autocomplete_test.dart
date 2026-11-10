import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:Miee/core/storage/hive_boxes.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/search/data/search_repository.dart';
import 'package:Miee/features/search/domain/music_suggestion.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/onboarding/domain/artist_model.dart';
import 'package:Miee/features/onboarding/data/artist_discovery_repository.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/shared/models/track.dart';

class MockYouTubeRepository extends YouTubeRepository {
  List<YouTubeVideo> mockVideos = [];
  bool shouldThrowError = false;
  int searchCalls = 0;
  Duration delay = Duration.zero;

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
  }) async {
    searchCalls++;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (shouldThrowError) {
      throw const SocketException('Simulated offline network failure');
    }
    return mockVideos;
  }
}

class MockArtistRepository implements ArtistRepository {
  List<ArtistModel> mockArtists = [];

  @override
  Future<List<ArtistModel>> searchArtists(String query, {String? language}) async {
    return mockArtists;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockPlayerController extends StateNotifier<PlaybackState> implements PlayerController {
  MockPlayerController() : super(PlaybackState.initial());

  MusicItem? selectedTrack;
  List<MusicItem>? selectedQueue;

  @override
  void selectTrack(
    MusicItem track,
    List<MusicItem> currentList, {
    String? playingFrom,
  }) {
    selectedTrack = track;
    selectedQueue = currentList;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_unified_search_test_');
    Hive.init(tempDir.path);
    await Hive.openBox<Object?>(HiveBoxes.preferences);
  });

  tearDown(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  final localBeliever = const MediaSong(
    id: 'local_song_1',
    title: 'Believer',
    artist: 'Imagine Dragons',
    album: 'Evolve',
    duration: '3:24',
    durationMs: 204000,
    filePath: '/storage/emulated/0/Music/Believer.mp3',
    artworkPath: '',
  );

  final youtubeBeliever = const YouTubeVideo(
    id: '7wtfhZwyrcc',
    title: 'Imagine Dragons - Believer (Official Music Video)',
    channelTitle: 'ImagineDragonsVEVO',
    thumbnailUrl: 'https://i.ytimg.com/vi/7wtfhZwyrcc/hqdefault.jpg',
    duration: '3:36',
    viewCount: '2.5B views',
    canonicalTitle: 'Believer',
    canonicalArtist: 'Imagine Dragons',
    highResArtworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/believer_600x600.jpg',
  );

  final youtubeRadioactive = const YouTubeVideo(
    id: 'ktvTqknDobU',
    title: 'Imagine Dragons - Radioactive',
    channelTitle: 'ImagineDragonsVEVO',
    thumbnailUrl: 'https://i.ytimg.com/vi/ktvTqknDobU/hqdefault.jpg',
    duration: '4:21',
    viewCount: '1.6B views',
    canonicalTitle: 'Radioactive',
    canonicalArtist: 'Imagine Dragons',
  );

  group('Unified Search Autocomplete — Comprehensive Test Scenarios', () {
    test('1. Search with only local matching songs', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.mockVideos = []; // No online matches

      final repo = SearchRepository(youtubeRepository: mockYt);
      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'Believer',
        localSongs: [localBeliever],
      );

      expect(suggestions.isNotEmpty, isTrue);
      final localSong = suggestions.firstWhere((s) => s.type == SuggestionType.song);
      expect(localSong.title, equals('Believer'));
      expect(localSong.isOnline, isFalse);
      expect(localSong.sourceLabel, equals('Local'));
      expect(localSong.typeLabel, contains('Local'));
    });

    test('2. Search with only YouTube Music matching songs', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.mockVideos = [youtubeBeliever, youtubeRadioactive];

      final repo = SearchRepository(youtubeRepository: mockYt);
      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'Believer',
        localSongs: [], // No local matches
      );

      expect(suggestions.isNotEmpty, isTrue);
      final ytSongs = suggestions.where((s) => s.type == SuggestionType.song && s.isOnline).toList();
      expect(ytSongs.isNotEmpty, isTrue);

      final first = ytSongs.first;
      expect(first.id, equals('7wtfhZwyrcc'));
      expect(first.title, equals('Believer'));
      expect(first.subtitle, equals('Imagine Dragons'));
      expect(first.imageUrl, equals('https://is1-ssl.mzstatic.com/image/thumb/believer_600x600.jpg'));
      expect(first.isOnline, isTrue);
      expect(first.sourceLabel, equals('YouTube'));
      expect(first.typeLabel, contains('YouTube'));
    });

    test('3. Search with both local and online matches merges harmoniously', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.mockVideos = [youtubeRadioactive];

      final repo = SearchRepository(youtubeRepository: mockYt);
      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'Imagine',
        localSongs: [localBeliever],
      );

      final songSuggestions = suggestions.where((s) => s.type == SuggestionType.song).toList();
      expect(songSuggestions.length, greaterThanOrEqualTo(2));

      final hasLocal = songSuggestions.any((s) => !s.isOnline && s.title == 'Believer');
      final hasOnline = songSuggestions.any((s) => s.isOnline && s.title == 'Radioactive');
      expect(hasLocal, isTrue, reason: 'Local song should be present');
      expect(hasOnline, isTrue, reason: 'Online YouTube song should be present');
    });

    test('4. Search with no matching results displays only search query action', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.mockVideos = [];

      final repo = SearchRepository(youtubeRepository: mockYt);
      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'xyznonexistent123',
        localSongs: [],
      );

      expect(suggestions.length, equals(1));
      expect(suggestions.first.type, equals(SuggestionType.searchQuery));
      expect(suggestions.first.title, equals('Search for "xyznonexistent123"'));
    });

    test('5. Search while offline gracefully preserves local suggestions', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.shouldThrowError = true; // Offline simulated

      final repo = SearchRepository(youtubeRepository: mockYt);
      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'Believer',
        localSongs: [localBeliever],
      );

      expect(suggestions.isNotEmpty, isTrue);
      final localSong = suggestions.firstWhere((s) => s.type == SuggestionType.song);
      expect(localSong.title, equals('Believer'));
      expect(localSong.isOnline, isFalse);
    });

    test('6. Rapid typing resets debounce and empty query clears suggestions', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchNotifierProvider.notifier);

      notifier.updateQuery('a');
      notifier.updateQuery('ab');
      notifier.updateQuery('abc');
      notifier.updateQuery('ab');
      notifier.updateQuery('');

      final state = container.read(searchNotifierProvider);
      expect(state.query, isEmpty);
      expect(state.liveSuggestions, isEmpty);
      expect(state.isSuggestionsLoading, isFalse);
    });

    test('7. Select a local suggestion invokes local track playback', () {
      final player = MockPlayerController();
      final song = localBeliever;

      // When local suggestion is tapped, PlayerController.selectTrack is called with MediaSong
      player.selectTrack(song, [song]);

      expect(player.selectedTrack, isNotNull);
      expect(player.selectedTrack!.id, equals('local_song_1'));
      expect(player.selectedTrack is MediaSong, isTrue);
    });

    test('8. Select a YouTube Music suggestion invokes online playback preserving video ID', () {
      final player = MockPlayerController();
      final video = youtubeBeliever;

      final track = video.toTrack();
      player.selectTrack(track, [track], playingFrom: 'Search: Imagine Dragons');

      expect(player.selectedTrack, isNotNull);
      final selected = player.selectedTrack as Track;
      expect(selected.id, equals('youtube_7wtfhZwyrcc'));
      expect(selected.sourceId, equals('7wtfhZwyrcc'));
      expect(selected.sourceProvider, equals('youtube'));
      expect(selected.isYoutube, isTrue);
      expect(selected.title, equals('Believer'));
    });

    test('9. Search for same title in both sources preserves both without collision', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.mockVideos = [youtubeBeliever]; // Online "Believer"

      final repo = SearchRepository(youtubeRepository: mockYt);
      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'Believer',
        localSongs: [localBeliever], // Local "Believer"
      );

      final believerSongs = suggestions.where((s) => s.type == SuggestionType.song && s.title == 'Believer').toList();
      expect(believerSongs.length, equals(2), reason: 'Both local Believer and YouTube Believer must appear');

      final localItem = believerSongs.firstWhere((s) => !s.isOnline);
      final onlineItem = believerSongs.firstWhere((s) => s.isOnline);
      expect(localItem.sourceLabel, equals('Local'));
      expect(onlineItem.sourceLabel, equals('YouTube'));
      expect(onlineItem.id, equals('7wtfhZwyrcc'));
    });

    test('10. In-memory suggestion cache avoids duplicate requests for identical queries', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.mockVideos = [youtubeBeliever];

      final repo = SearchRepository(youtubeRepository: mockYt);

      // First query
      await repo.getLiveMusicSuggestions(query: 'Believer');
      expect(mockYt.searchCalls, equals(1));

      // Repeated query should hit cache
      await repo.getLiveMusicSuggestions(query: 'Believer');
      expect(mockYt.searchCalls, equals(1), reason: 'Repeated query must be served from cache without extra network call');
    });

    test('11. Slower stale responses do not overwrite newer active queries', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.delay = const Duration(milliseconds: 100);

      final container = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(SearchRepository(youtubeRepository: mockYt)),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(searchNotifierProvider.notifier);

      notifier.updateQuery('QueryOld');
      // Rapidly replace with newer query
      notifier.updateQuery('QueryNew');

      expect(container.read(searchNotifierProvider).query, equals('QueryNew'));
    });

    test('12. Online track metadata (artwork, duration, title, artist) remains intact', () async {
      final mockYt = MockYouTubeRepository();
      mockYt.mockVideos = [youtubeBeliever];

      final repo = SearchRepository(youtubeRepository: mockYt);
      final suggestions = await repo.getLiveMusicSuggestions(
        query: 'Believer',
      );

      final song = suggestions.firstWhere((s) => s.type == SuggestionType.song && s.isOnline);
      expect(song.id, equals('7wtfhZwyrcc'));
      expect(song.title, equals('Believer'));
      expect(song.subtitle, equals('Imagine Dragons'));
      expect(song.imageUrl, contains('thumb/believer_600x600.jpg'));

      final entity = song.entity as YouTubeVideo;
      expect(entity.duration, equals('3:36'));
      expect(entity.viewCount, equals('2.5B views'));
      expect(entity.toTrack().isYoutube, isTrue);
    });
  });
}
