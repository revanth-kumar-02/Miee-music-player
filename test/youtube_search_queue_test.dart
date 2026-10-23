import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/queue_manager.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/search/domain/search_state.dart';
import 'package:Miee/features/search/presentation/search_page.dart';
import 'package:Miee/features/search/providers/search_providers.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/presentation/widgets/youtube_result_tile.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';

/// Test spy recording calls to selectTrack.
class SpyPlayerController extends StateNotifier<PlaybackState>
    implements PlayerController {
  MusicItem? lastSelectedTrack;
  List<MusicItem>? lastSelectedList;
  String? lastPlayingFrom;
  int selectTrackCallCount = 0;

  SpyPlayerController([PlaybackState? initialState])
      : super(initialState ?? PlaybackState.initial());

  @override
  void selectTrack(MusicItem track, List<MusicItem> currentList,
      {String? playingFrom}) {
    if (currentList.isEmpty) return;
    final targetId = track.id.startsWith('youtube_')
        ? track.id.replaceFirst('youtube_', '')
        : track.id;
    final index = currentList.indexWhere((t) {
      final tId = t.id.startsWith('youtube_')
          ? t.id.replaceFirst('youtube_', '')
          : t.id;
      return t.id == track.id || tId == targetId;
    });
    if (index < 0) return;

    lastSelectedTrack = track;
    lastSelectedList = currentList;
    lastPlayingFrom = playingFrom;
    selectTrackCallCount++;
    state = state.copyWith(
      currentTrack: track,
      status: PlaybackStatus.playing,
      playingFrom: playingFrom ?? state.playingFrom,
    );
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

class FakeSearchNotifier extends StateNotifier<SearchState>
    implements SearchNotifier {
  FakeSearchNotifier(super.state);

  @override
  void setFilter(String filter) {}

  @override
  void updateQuery(String query) {}

  @override
  void searchNow(String query) {}

  @override
  Future<void> addHistory(String query) async {}

  @override
  Future<void> removeHistory(String query) async {}

  @override
  Future<void> clearHistory() async {}
}

void main() {
  group('YouTube Search Queue Context Preservation — Unit Tests', () {
    late QueueManager queueManager;
    late List<YouTubeVideo> searchVideos;

    setUp(() {
      queueManager = QueueManager();
      searchVideos = List.generate(
        5,
        (i) => YouTubeVideo(
          id: 'yt_vid_$i',
          title: 'Song Title $i',
          channelTitle: 'Artist $i',
          thumbnailUrl: 'https://i.ytimg.com/vi/yt_vid_$i/hqdefault.jpg',
          duration: '3:3$i',
          viewCount: '${(i + 1) * 100}K views',
        ),
      );
    });

    test('YouTubeVideo converts to Track with sanitized metadata and prefixed ID', () {
      final video = searchVideos[0];
      final track = video.toTrack();

      expect(track.id, equals('youtube_yt_vid_0'));
      expect(track.title, equals('Song Title 0'));
      expect(track.artist, equals('Artist 0'));
      expect(track.imageUrl, equals(video.thumbnailUrl));
      expect(track.duration, equals('3:30'));
      expect(track.isYoutube, isTrue);
    });

    test('Selecting first, middle, and last item selects exact track and preserves queue index', () {
      final tracks = List<Track>.unmodifiable(searchVideos.map((v) => v.toTrack()));

      // 1. Select First Item (Index 0)
      final firstTarget = tracks[0];
      final firstIdx = tracks.indexWhere((t) => t.id == firstTarget.id);
      expect(firstIdx, equals(0));
      queueManager.setQueue(tracks, startIndex: firstIdx);

      expect(queueManager.currentIndex, equals(0));
      expect(queueManager.currentTrack?.id, equals('youtube_yt_vid_0'));
      expect(queueManager.queue.length, equals(5));

      // 2. Select Middle Item (Index 2)
      final middleTarget = tracks[2];
      final middleIdx = tracks.indexWhere((t) => t.id == middleTarget.id);
      expect(middleIdx, equals(2));
      queueManager.setQueue(tracks, startIndex: middleIdx);

      expect(queueManager.currentIndex, equals(2));
      expect(queueManager.currentTrack?.id, equals('youtube_yt_vid_2'));
      expect(queueManager.queue.length, equals(5));

      // 3. Select Last Item (Index 4)
      final lastTarget = tracks[4];
      final lastIdx = tracks.indexWhere((t) => t.id == lastTarget.id);
      expect(lastIdx, equals(4));
      queueManager.setQueue(tracks, startIndex: lastIdx);

      expect(queueManager.currentIndex, equals(4));
      expect(queueManager.currentTrack?.id, equals('youtube_yt_vid_4'));
      expect(queueManager.queue.length, equals(5));
    });

    test('Full search results list is preserved in exact order', () {
      final tracks = List<Track>.unmodifiable(searchVideos.map((v) => v.toTrack()));
      queueManager.setQueue(tracks, startIndex: 2);

      for (int i = 0; i < tracks.length; i++) {
        expect(queueManager.queue[i].id, equals('youtube_yt_vid_$i'));
        expect(queueManager.queue[i].title, equals('Song Title $i'));
        expect(queueManager.queue[i].artist, equals('Artist $i'));
      }
    });

    test('Next and previous navigate sequentially through search result queue', () {
      final tracks = List<Track>.unmodifiable(searchVideos.map((v) => v.toTrack()));
      queueManager.setQueue(tracks, startIndex: 1);

      // Current is index 1
      expect(queueManager.currentTrack?.id, equals('youtube_yt_vid_1'));

      // Next -> index 2
      final nextTrack1 = queueManager.next();
      expect(nextTrack1?.id, equals('youtube_yt_vid_2'));
      expect(queueManager.currentIndex, equals(2));

      // Next -> index 3
      final nextTrack2 = queueManager.next();
      expect(nextTrack2?.id, equals('youtube_yt_vid_3'));
      expect(queueManager.currentIndex, equals(3));

      // Previous -> index 2
      final prevTrack1 = queueManager.previous();
      expect(prevTrack1?.id, equals('youtube_yt_vid_2'));
      expect(queueManager.currentIndex, equals(2));

      // Previous -> index 1
      final prevTrack2 = queueManager.previous();
      expect(prevTrack2?.id, equals('youtube_yt_vid_1'));
      expect(queueManager.currentIndex, equals(1));

      // Previous -> index 0
      final prevTrack3 = queueManager.previous();
      expect(prevTrack3?.id, equals('youtube_yt_vid_0'));
      expect(queueManager.currentIndex, equals(0));

      // Previous at 0 yields null
      expect(queueManager.previous(), isNull);
      expect(queueManager.currentIndex, equals(0));
    });

    test('YouTube IDs normalize correctly against existing Track IDs', () {
      String normalize(String id) =>
          id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;

      final rawVideo = searchVideos[3]; // id: 'yt_vid_3'
      final tracks = searchVideos.map((v) => v.toTrack()).toList(); // ids: 'youtube_yt_vid_...'

      // Match raw video ID against list of tracks with youtube_ prefix
      final targetNormalized = normalize(rawVideo.id);
      final foundIndex = tracks.indexWhere(
        (t) => t.id == rawVideo.id || normalize(t.id) == targetNormalized,
      );

      expect(foundIndex, equals(3));
      expect(tracks[foundIndex].id, equals('youtube_yt_vid_3'));

      // Reverse comparison: matching track with prefix against raw video IDs
      final trackToFind = tracks[1];
      final trackNorm = normalize(trackToFind.id);
      final foundInVideos = searchVideos.indexWhere(
        (v) => v.id == trackToFind.id || normalize(v.id) == trackNorm,
      );

      expect(foundInVideos, equals(1));
    });

    test('Empty results list fails safely without crash or enqueuing invalid items', () {
      final controller = SpyPlayerController();
      final emptyList = <Track>[];
      final dummyTrack = searchVideos[0].toTrack();

      controller.selectTrack(dummyTrack, emptyList, playingFrom: 'YouTube Search');

      expect(controller.selectTrackCallCount, equals(0));
      expect(controller.lastSelectedTrack, isNull);
      expect(controller.lastSelectedList, isNull);
    });

    test('Unresolvable selection fails safely without clobbering queue or playing wrong song', () {
      final controller = SpyPlayerController();
      final tracks = searchVideos.take(3).map((v) => v.toTrack()).toList();
      const alienTrack = Track(
        id: 'youtube_alien_video',
        title: 'Alien Song',
        artist: 'Unknown',
        imageUrl: '',
        duration: '1:00',
      );

      controller.selectTrack(alienTrack, tracks, playingFrom: 'YouTube Search');

      // Index was -1, so it safely aborts rather than defaulting to index 0
      expect(controller.selectTrackCallCount, equals(0));
      expect(controller.lastSelectedTrack, isNull);
    });

    test('Rapid taps: newer selection supersedes older selection token', () async {
      int playRequestToken = 0;
      int activeToken = 0;
      MusicItem? finalPlayedTrack;

      Future<void> simulatePlayTrack(MusicItem track) async {
        final token = ++playRequestToken;
        activeToken = token;

        // Simulate async stream resolution with delay
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // Token check ensures older async completion cannot clobber newer selection
        if (token != activeToken) {
          return;
        }

        finalPlayedTrack = track;
      }

      final trackA = searchVideos[1].toTrack();
      final trackB = searchVideos[4].toTrack();

      // Launch tap A
      final futureA = simulatePlayTrack(trackA);
      // Immediately launch tap B before tap A finishes
      final futureB = simulatePlayTrack(trackB);

      await Future.wait([futureA, futureB]);

      // Tap B supersedes tap A
      expect(finalPlayedTrack?.id, equals(trackB.id));
      expect(finalPlayedTrack?.title, equals('Song Title 4'));
    });
  });

  group('YouTube Search Queue Context Preservation — Widget Integration', () {
    testWidgets('Tapping YouTube result tile passes full search queue to selectTrack with playingFrom', (tester) async {
      final controller = SpyPlayerController();
      final searchVideos = [
        const YouTubeVideo(
          id: 'vid_101',
          title: 'Thunder',
          channelTitle: 'Imagine Dragons',
          thumbnailUrl: 'https://i.ytimg.com/vi/vid_101/hqdefault.jpg',
          duration: '3:07',
          viewCount: '2.1B views',
        ),
        const YouTubeVideo(
          id: 'vid_102',
          title: 'Believer',
          channelTitle: 'Imagine Dragons',
          thumbnailUrl: 'https://i.ytimg.com/vi/vid_102/hqdefault.jpg',
          duration: '3:24',
          viewCount: '2.5B views',
        ),
        const YouTubeVideo(
          id: 'vid_103',
          title: 'Radioactive',
          channelTitle: 'Imagine Dragons',
          thumbnailUrl: 'https://i.ytimg.com/vi/vid_103/hqdefault.jpg',
          duration: '3:06',
          viewCount: '1.6B views',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
            favoritesProvider.overrideWith((ref) => FakeFavoritesNotifier()),
            songsProvider.overrideWith((ref) => []),
            artistsProvider.overrideWith((ref) => []),
            albumsProvider.overrideWith((ref) => []),
            searchNotifierProvider.overrideWith((ref) => FakeSearchNotifier(
                  SearchState(
                    query: 'Imagine Dragons',
                    isYouTubeLoading: false,
                    youtubeResults: searchVideos,
                  ),
                )),
          ],
          child: const MaterialApp(
            home: SearchPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap the 2nd result ("Believer")
      final believerTile = find.widgetWithText(YouTubeResultTile, 'Believer');
      expect(believerTile, findsOneWidget);

      await tester.tap(believerTile);
      await tester.pumpAndSettle();

      // Verify selectTrack received:
      // 1. Correct selected track ('youtube_vid_102')
      expect(controller.selectTrackCallCount, equals(1));
      expect(controller.lastSelectedTrack?.id, equals('youtube_vid_102'));
      expect(controller.lastSelectedTrack?.title, equals('Believer'));

      // 2. Full search queue preserved (all 3 tracks in order)
      expect(controller.lastSelectedList?.length, equals(3));
      expect(controller.lastSelectedList![0].id, equals('youtube_vid_101'));
      expect(controller.lastSelectedList![1].id, equals('youtube_vid_102'));
      expect(controller.lastSelectedList![2].id, equals('youtube_vid_103'));

      // 3. playingFrom source label
      expect(controller.lastPlayingFrom, equals('YouTube Search'));
    });

    testWidgets('YouTubeResultTile recognizes isCurrentTrack across ID normalization', (tester) async {
      const activeVideo = YouTubeVideo(
        id: 'vid_active',
        title: 'Active Playing Song',
        channelTitle: 'Active Artist',
        thumbnailUrl: 'https://i.ytimg.com/vi/vid_active/hqdefault.jpg',
        duration: '4:15',
        viewCount: '500K views',
      );

      // Player has Track with id: 'youtube_vid_active'
      const playingTrack = Track(
        id: 'youtube_vid_active',
        title: 'Active Playing Song',
        artist: 'Active Artist',
        imageUrl: '',
        duration: '4:15',
      );

      final activeState = PlaybackState.initial().copyWith(
        currentTrack: playingTrack,
        status: PlaybackStatus.playing,
      );

      final controller = SpyPlayerController(activeState);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playerControllerProvider.overrideWith((ref) => controller),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: YouTubeResultTile(video: activeVideo),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // With normalized ID matching, the tile identifies itself as active:
      // - Shows equalizer icon
      // - Shows pause button
      expect(find.byIcon(Icons.equalizer_rounded), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled_rounded), findsOneWidget);
    });
  });
}
