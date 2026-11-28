import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/playback_state.dart';
import 'package:Miee/core/audio/player_controller.dart';
import 'package:Miee/core/audio/providers.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/core/network/network_request_coordinator.dart';
import 'package:Miee/core/storage/adapters/queue_snapshot.dart';
import 'package:Miee/features/artwork/data/artwork_resolver_impl.dart';
import 'package:Miee/features/artwork/domain/artwork_query.dart';
import 'package:Miee/features/artwork/domain/resolved_artwork.dart';
import 'package:Miee/features/artwork/presentation/artwork_providers.dart';
import 'package:Miee/features/history/domain/listening_event.dart';
import 'package:Miee/features/history/domain/listening_history_repository.dart';
import 'package:Miee/features/history/providers/history_providers.dart';
import 'package:Miee/features/library/data/favorites_repository.dart';
import 'package:Miee/features/library/data/preferences_repository.dart';
import 'package:Miee/features/library/data/queue_state_repository.dart';
import 'package:Miee/features/library/data/recently_played_repository.dart';
import 'package:Miee/features/library/providers/library_providers.dart';
import 'package:Miee/features/media/domain/models.dart';
import 'package:Miee/features/media/providers/media_providers.dart';
import 'package:Miee/features/player/presentation/player_page.dart';
import 'package:Miee/features/rooms/providers/room_providers.dart';
import 'package:Miee/features/search/data/playback_source_resolver.dart';
import 'package:Miee/features/youtube/data/youtube_repository.dart';
import 'package:Miee/features/youtube/domain/youtube_model.dart';
import 'package:Miee/features/youtube/providers/youtube_providers.dart';
import 'package:Miee/shared/models/music_item.dart';
import 'package:Miee/shared/models/track.dart';
import 'package:Miee/shared/widgets/desktop_waveform_scrubber.dart';
import 'package:Miee/shared/widgets/waveform_widget.dart';

class _StubYouTubeRepository extends YouTubeRepository {
  final Map<String, List<YouTubeVideo>> responses;
  final Map<String, Completer<void>> gates;

  _StubYouTubeRepository({
    this.responses = const {},
    this.gates = const {},
  });

  @override
  Future<List<YouTubeVideo>> search(
    String query, {
    int page = 1,
    bool forceFresh = false,
    NetworkPriority priority = NetworkPriority.userSearch,
  }) async {
    if (gates.containsKey(query)) {
      await gates[query]!.future;
    }
    if (responses.containsKey(query)) {
      return responses[query]!;
    }
    final qLower = query.toLowerCase();
    for (final e in responses.entries) {
      if (e.key.toLowerCase() == qLower) return e.value;
    }
    for (final e in responses.entries) {
      if (qLower.contains(e.key.toLowerCase())) return e.value;
    }
    return const [];
  }
}

class _FakeAudioPlayer extends AudioPlayer {
  bool _playing = false;
  ProcessingState _procState = ProcessingState.idle;
  Duration _position = Duration.zero;
  Duration _buffered = Duration.zero;
  Duration? _duration;
  double _volume = 1.0;

  Duration nextSetDuration = const Duration(minutes: 4);
  Duration positionAfterSet = Duration.zero;
  Duration? emitDurationDuringSet;
  Completer<void>? setSourceGate;
  final List<Duration?> initialPositions = [];

  final _stateCtrl = StreamController<PlayerState>.broadcast();
  final _posCtrl = StreamController<Duration>.broadcast();
  final _bufCtrl = StreamController<Duration>.broadcast();
  final _durCtrl = StreamController<Duration?>.broadcast();
  final _eventCtrl = StreamController<PlaybackEvent>.broadcast();
  final _errCtrl = StreamController<PlayerException>.broadcast();

  _FakeAudioPlayer() : super(handleInterruptions: false);

  @override
  bool get playing => _playing;
  @override
  ProcessingState get processingState => _procState;
  @override
  Duration get position => _position;
  @override
  Duration get bufferedPosition => _buffered;
  @override
  Duration? get duration => _duration;
  @override
  double get volume => _volume;

  @override
  Stream<PlayerState> get playerStateStream => _stateCtrl.stream;
  @override
  Stream<Duration> get positionStream => _posCtrl.stream;
  @override
  Stream<Duration?> get durationStream => _durCtrl.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => _eventCtrl.stream;
  @override
  Stream<PlayerException> get errorStream => _errCtrl.stream;
  @override
  Stream<Duration> get bufferedPositionStream => _bufCtrl.stream;

  void emitPosition(Duration p) {
    _position = p;
    _posCtrl.add(p);
  }

  void emitBuffered(Duration b) {
    _buffered = b;
    _bufCtrl.add(b);
  }

  void emitDuration(Duration? d) {
    _duration = d;
    _durCtrl.add(d);
  }

  void emitState(bool playing, ProcessingState proc) {
    _playing = playing;
    _procState = proc;
    _stateCtrl.add(PlayerState(playing, proc));
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    initialPositions.add(initialPosition);
    if (setSourceGate != null) {
      await setSourceGate!.future;
      setSourceGate = null;
    }
    _procState = ProcessingState.loading;
    _stateCtrl.add(PlayerState(_playing, ProcessingState.loading));
    if (emitDurationDuringSet != null) {
      _duration = emitDurationDuringSet;
      _durCtrl.add(_duration);
      emitDurationDuringSet = null;
    } else {
      _duration = nextSetDuration;
      _durCtrl.add(_duration);
    }
    _position = initialPosition ?? positionAfterSet;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(_playing, ProcessingState.ready));
    return _duration;
  }

  @override
  Future<void> play() async {
    _playing = true;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(true, _procState));
  }

  @override
  Future<void> pause() async {
    _playing = false;
    _stateCtrl.add(PlayerState(false, _procState));
  }

  @override
  Future<void> stop() async {
    _playing = false;
    _procState = ProcessingState.idle;
    _stateCtrl.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      _position = position;
      _posCtrl.add(position);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {}

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}

  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await _posCtrl.close();
    await _bufCtrl.close();
    await _durCtrl.close();
    await _eventCtrl.close();
    await _errCtrl.close();
  }
}

class _FakeQueueStateRepo implements QueueStateRepository {
  @override
  List<MusicItem>? loadQueueTracks() => null;
  @override
  QueueSnapshot? loadSnapshot() => null;
  @override
  Future<void> saveSnapshot({
    required List<MusicItem> queue,
    required int currentIndex,
    required int positionMs,
    required bool isShuffleEnabled,
    required String repeatMode,
  }) async {}
  @override
  Future<void> clear() async {}
}

class _FakePreferencesRepo implements PreferencesRepository {
  @override
  double getPlaybackSpeed() => 1.0;
  @override
  String getRepeatMode() => 'off';
  @override
  bool getShuffle() => false;
  @override
  String getSourceSelectionMode() => 'smart';
  @override
  bool getResumePlayback() => false;
  @override
  bool getAutoPlayNext() => false;
  @override
  bool getShuffleDefault() => false;
  @override
  String getRepeatDefault() => 'off';
  @override
  bool getCrossfadeEnabled() => false;
  @override
  bool getGaplessPlaybackEnabled() => true;
  @override
  String? getLastScanTime() => null;
  @override
  bool getMediaNotificationEnabled() => true;
  @override
  bool getBackgroundPlaybackEnabled() => true;
  @override
  bool getLockScreenControlsEnabled() => true;
  @override
  String getAudioQuality() => 'high';
  @override
  int? getSleepTimerMinutes() => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeListeningHistoryRepo implements ListeningHistoryRepository {
  @override
  Future<void> clearHistory(String? uid) async {}
  @override
  Future<List<ListeningEvent>> getRecentHistory({
    required String? uid,
    int limit = 30,
  }) async =>
      const [];
  @override
  Future<void> recordListeningEvent({
    required String? uid,
    required MusicItem track,
    required int listenedSec,
    required int durationSec,
  }) async {}
}

class _FakeRecentlyPlayedRepo implements RecentlyPlayedRepository {
  @override
  Future<void> recordPlay(Track track) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeFavoritesRepo implements FavoritesRepository {
  @override
  List<Track> getFavorites() => const [];
  @override
  bool isFavorite(String trackId) => false;
  @override
  Future<void> addFavorite(Track track) async {}
  @override
  Future<void> removeFavorite(String trackId) async {}
  @override
  Future<void> clearAll() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeArtworkResolver extends ArtworkResolver {
  @override
  Future<ResolvedArtwork> resolve(
    ArtworkQuery query, {
    bool forceRefresh = false,
  }) async =>
      ResolvedArtwork.neutralFallback();
}

void _stubAudioSessionChannel() {
  const channel = MethodChannel('com.ryanheise.android_audio_manager');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async => null);
}

ProviderContainer _createTestContainer({
  required MieeAudioHandler handler,
  required PlaybackSourceResolver resolver,
}) {
  return ProviderContainer(overrides: [
    audioHandlerProvider.overrideWithValue(handler),
    preferencesRepositoryProvider.overrideWithValue(_FakePreferencesRepo()),
    queueStateRepositoryProvider.overrideWithValue(_FakeQueueStateRepo()),
    listeningHistoryRepositoryProvider
        .overrideWithValue(_FakeListeningHistoryRepo()),
    recentlyPlayedRepositoryProvider.overrideWithValue(_FakeRecentlyPlayedRepo()),
    artworkResolverProvider.overrideWithValue(_FakeArtworkResolver()),
    songsProvider.overrideWithValue(const []),
    sourceSelectionProvider.overrideWithValue('smart'),
    youtubeRepositoryProvider.overrideWithValue(_StubYouTubeRepository()),
    playerControllerProvider.overrideWith((ref) => PlayerController(
          handler,
          ref.watch(queueManagerProvider),
          ref,
          sourceResolver: resolver,
        )),
  ]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _stubAudioSessionChannel();

  setUp(() {
    YouTubeAudioService().resetTestingHooks();
    YouTubeAudioService().clearCache();
  });

  tearDown(() {
    YouTubeAudioService().resetTestingHooks();
    YouTubeAudioService().clearCache();
  });

  group('Playback Progress & Waveform Sync Regression Suite', () {
    test('1. 6m -> 3m handler skipToNext resets position/buffer and never inherits old duration', () async {
      const vidA = 'aaaaaaaaaaa';
      const vidB = 'bbbbbbbbbbb';
      final player = _FakeAudioPlayer();
      final resolver = PlaybackSourceResolver.withRepository(_StubYouTubeRepository());
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      final container = _createTestContainer(handler: handler, resolver: resolver);
      addTearDown(container.dispose);

      YouTubeAudioService().cacheUrlForTesting(
        vidA,
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vidA&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        'mmmmmmmmmmm',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=mmmmmmmmmmm&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        vidB,
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vidB&expire=2524608000',
      );

      const longTrack = Track(
        id: 'youtube_$vidA',
        title: 'Long Song',
        artist: 'Artist A',
        imageUrl: '',
        duration: '6:00',
      );
      // Track B has placeholder 3:30 duration initially; stream resolves to 3:00.
      const shortTrack = Track(
        id: 'youtube_$vidB',
        title: 'Short Song',
        artist: 'Artist B',
        imageUrl: '',
        duration: '3:30',
      );

      final ctrl = container.read(playerControllerProvider.notifier);
      player.nextSetDuration = const Duration(minutes: 6);
      ctrl.setQueue(const [longTrack, shortTrack], startIndex: 0);
      await pumpEventQueue(times: 25);
      expect(container.read(playerControllerProvider).status,
          PlaybackStatus.playing);

      player.emitPosition(const Duration(minutes: 5, seconds: 12));
      player.emitBuffered(const Duration(minutes: 5, seconds: 40));
      await pumpEventQueue(times: 6);
      expect(container.read(playerControllerProvider).position,
          const Duration(minutes: 5, seconds: 12));
      expect(container.read(playerControllerProvider).duration,
          const Duration(minutes: 6));

      // Pause Track B load inside setAudioSource so we observe loading state directly.
      final gateB = Completer<void>();
      player.setSourceGate = gateB;
      player.nextSetDuration = const Duration(minutes: 3);

      final skipFuture = handler.skipToNext();
      for (var i = 0; i < 40 && !handler.isLoadingTrack; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await pumpEventQueue(times: 6);

      final midLoad = container.read(playerControllerProvider);
      expect(midLoad.currentTrack?.id, shortTrack.id);
      expect(midLoad.position, Duration.zero);
      expect(midLoad.bufferedPosition, Duration.zero);
      expect(midLoad.duration, Duration.zero); // Never 6:00 from Track A or 3:30 placeholder

      gateB.complete();
      await skipFuture;
      await pumpEventQueue(times: 6);

      final loaded = container.read(playerControllerProvider);
      expect(loaded.duration, const Duration(minutes: 3));
      expect(loaded.position, Duration.zero);
      expect(loaded.status, PlaybackStatus.playing);
    });

    test('2. 3m -> 6m auto-completion skip resets position & clears completed status', () async {
      const vidA = 'ccccccccccc';
      const vidB = 'ddddddddddd';
      final player = _FakeAudioPlayer();
      final resolver = PlaybackSourceResolver.withRepository(_StubYouTubeRepository());
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      final container = _createTestContainer(handler: handler, resolver: resolver);
      addTearDown(container.dispose);

      YouTubeAudioService().cacheUrlForTesting(
        vidA,
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vidA&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        'mmmmmmmmmmm',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=mmmmmmmmmmm&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        vidB,
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vidB&expire=2524608000',
      );

      const trackA = Track(
        id: 'youtube_$vidA',
        title: 'Ambikapathy - Unnaal Unnaal',
        artist: 'Dhanush',
        imageUrl: '',
        duration: '4:56',
      );
      const trackB = Track(
        id: 'youtube_$vidB',
        title: 'Chekka Chivantha Vaanam - Mazhai Kuruvi',
        artist: 'A. R. Rahman',
        imageUrl: '',
        duration: '5:47',
      );

      final ctrl = container.read(playerControllerProvider.notifier);
      player.nextSetDuration = const Duration(minutes: 4, seconds: 56);
      ctrl.setQueue(const [trackA, trackB], startIndex: 0);
      await pumpEventQueue(times: 8);

      player.emitPosition(const Duration(minutes: 4, seconds: 52));
      await pumpEventQueue(times: 4);

      final gateB = Completer<void>();
      player.setSourceGate = gateB;
      player.nextSetDuration = const Duration(minutes: 5, seconds: 47);

      // Simulate completion auto-advance at 4:52
      player.emitState(false, ProcessingState.completed);
      await pumpEventQueue(times: 6);

      final whileLoadingB = container.read(playerControllerProvider);
      expect(whileLoadingB.currentTrack?.id, trackB.id);
      expect(whileLoadingB.status, PlaybackStatus.loading);
      expect(whileLoadingB.position, Duration.zero); // Never 4:52!
      expect(whileLoadingB.duration, const Duration(minutes: 5, seconds: 47));

      gateB.complete();
      await pumpEventQueue(times: 8);
      expect(container.read(playerControllerProvider).status, PlaybackStatus.playing);
      expect(container.read(playerControllerProvider).position, Duration.zero);
    });

    test('3. Old position, buffer, duration & state events cannot overwrite new loading track (YouTube & Local)', () async {
      const vidA = 'eeeeeeeeeee';
      final resolutionGate = Completer<void>();
      final repo = _StubYouTubeRepository(
        responses: {
          'A.R. Rahman - New Song (Official Audio)': const [
            YouTubeVideo(
              id: 'fffffffffff',
              title: 'New Song',
              channelTitle: 'A.R. Rahman',
              thumbnailUrl: '',
              duration: '5:10',
              viewCount: '1M views',
            ),
          ],
        },
        gates: {'A.R. Rahman - New Song (Official Audio)': resolutionGate},
      );
      final player = _FakeAudioPlayer();
      final resolver = PlaybackSourceResolver.withRepository(repo);
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      final container = _createTestContainer(handler: handler, resolver: resolver);
      addTearDown(container.dispose);

      YouTubeAudioService().cacheUrlForTesting(
        vidA,
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vidA&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        'mmmmmmmmmmm',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=mmmmmmmmmmm&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        'fffffffffff',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=fffffffffff&expire=2524608000',
      );

      const trackA = Track(
        id: 'youtube_$vidA',
        title: 'Old Track',
        artist: 'Old Artist',
        imageUrl: '',
        duration: '4:56',
      );
      const trackB = Track(
        id: 'youtube_itunes_new',
        title: 'New Song',
        artist: 'A.R. Rahman',
        imageUrl: '',
        duration: '5:10',
        metadataProvider: 'itunes',
      );
      const localTrack = Track(
        id: 'local_99',
        title: 'Local Hit',
        artist: 'Local Artist',
        imageUrl: '',
        duration: '3:45',
        filePath: '/storage/emulated/0/Music/local_hit.mp3',
      );

      final ctrl = container.read(playerControllerProvider.notifier);
      player.nextSetDuration = const Duration(minutes: 4, seconds: 56);
      await ctrl.playTrack(trackA);
      player.emitPosition(const Duration(minutes: 4, seconds: 10));
      player.emitBuffered(const Duration(minutes: 4, seconds: 30));
      await pumpEventQueue(times: 4);

      // Start switching to YouTube track B while blocked in PlaybackSourceResolver (_handler.isLoadingTrack == false)
      final playFuture = ctrl.playTrack(trackB);
      await pumpEventQueue(times: 4);

      // Emit stale events from Track A while Track B resolves
      player.emitState(true, ProcessingState.buffering);
      player.emitPosition(const Duration(minutes: 4, seconds: 15));
      player.emitBuffered(const Duration(minutes: 4, seconds: 45));
      player.emitDuration(const Duration(minutes: 4, seconds: 56));
      await pumpEventQueue(times: 4);

      final duringResolve = container.read(playerControllerProvider);
      expect(duringResolve.status, PlaybackStatus.loading);
      expect(duringResolve.position, Duration.zero);
      expect(duringResolve.bufferedPosition, Duration.zero);
      expect(duringResolve.duration, const Duration(minutes: 5, seconds: 10));

      resolutionGate.complete();
      player.nextSetDuration = const Duration(minutes: 5, seconds: 10);
      await playFuture;

      // Switch YouTube Track B -> Local Track (loadingTrackId must protect until loaded)
      player.emitPosition(const Duration(minutes: 3, seconds: 20));
      await pumpEventQueue(times: 4);
      final localGate = Completer<void>();
      player.setSourceGate = localGate;
      player.positionAfterSet = const Duration(seconds: 1); // residual 1s must also reset to 0:00
      player.nextSetDuration = const Duration(minutes: 3, seconds: 45);

      final localFuture = ctrl.playTrack(localTrack);
      await pumpEventQueue(times: 4);
      player.emitPosition(const Duration(minutes: 3, seconds: 22));
      player.emitDuration(const Duration(minutes: 5, seconds: 10));
      await pumpEventQueue(times: 4);
      expect(container.read(playerControllerProvider).position, Duration.zero);
      expect(container.read(playerControllerProvider).duration,
          const Duration(minutes: 3, seconds: 45));

      localGate.complete();
      await localFuture;
      await pumpEventQueue(times: 4);
      expect(container.read(playerControllerProvider).position, Duration.zero);
      expect(player.position, Duration.zero);
    });

    test('4. Failed track resolution/timeout + Retry via play() starts cleanly at 0:00', () async {
      const vidA = 'ggggggggggg';
      final player = _FakeAudioPlayer();
      final resolver = PlaybackSourceResolver.withRepository(_StubYouTubeRepository());
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      final container = _createTestContainer(handler: handler, resolver: resolver);
      addTearDown(container.dispose);

      YouTubeAudioService().cacheUrlForTesting(
        vidA,
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vidA&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        'mmmmmmmmmmm',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=mmmmmmmmmmm&expire=2524608000',
      );

      const trackA = Track(
        id: 'youtube_$vidA',
        title: 'Previous Track',
        artist: 'Artist',
        imageUrl: '',
        duration: '4:56',
      );
      const trackB = Track(
        id: 'youtube_itunes_fail',
        title: 'Retry Track',
        artist: 'Artist B',
        imageUrl: '',
        duration: '5:00',
        metadataProvider: 'itunes',
      );

      final ctrl = container.read(playerControllerProvider.notifier);
      await ctrl.playTrack(trackA);
      player.emitPosition(const Duration(minutes: 4, seconds: 0));
      await pumpEventQueue(times: 4);

      // Fail switching to Track B
      await ctrl.playTrack(trackB);
      await pumpEventQueue(times: 6);
      final failed = container.read(playerControllerProvider);
      expect(failed.status, PlaybackStatus.error);
      expect(failed.position, Duration.zero);

      // Simulate retry via controller.play() after making cache entry available
      final resolver2 = PlaybackSourceResolver.withRepository(
        _StubYouTubeRepository(responses: {
          'Artist B - Retry Track (Official Audio)': const [
            YouTubeVideo(
              id: 'hhhhhhhhhhh',
              title: 'Retry Track',
              channelTitle: 'Artist B',
              thumbnailUrl: '',
              duration: '5:00',
              viewCount: '1M views',
            ),
          ],
        }),
      );
      final container2 = _createTestContainer(handler: handler, resolver: resolver2);
      addTearDown(container2.dispose);
      YouTubeAudioService().cacheUrlForTesting(
        'hhhhhhhhhhh',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=hhhhhhhhhhh&expire=2524608000',
      );
      final ctrl2 = container2.read(playerControllerProvider.notifier);
      await ctrl2.playTrack(trackA);
      player.emitPosition(const Duration(minutes: 4, seconds: 0));
      await pumpEventQueue(times: 4);
      // Force transition via handler skip to Track B where attempt 1 fails with stale state position
      await ctrl2.playTrack(const Track(
        id: 'local_missing',
        title: 'Broken Local',
        artist: 'Artist',
        imageUrl: '',
        duration: '3:00',
        filePath: '',
      ));
      await pumpEventQueue(times: 6);
      expect(container2.read(playerControllerProvider).position, Duration.zero);
      expect(container2.read(playerControllerProvider).status, PlaybackStatus.error);
      // Retry via play() must clear resumePos rather than leaking Track A's 4:00
      try {
        await ctrl2.play();
      } catch (_) {}
      await pumpEventQueue(times: 4);
      expect(player.initialPositions.last, isNull);
    });

    test('5. Rapid track switching A -> B -> C & 1-track RepeatMode.all wrap & Previous threshold', () async {
      const vidA = 'iiiiiiiiiii';
      const vidB = 'jjjjjjjjjjj';
      const vidC = 'kkkkkkkkkkk';
      final gateB = Completer<void>();
      final repo = _StubYouTubeRepository(
        responses: {
          'Artist B - Song B (Official Audio)': const [
            YouTubeVideo(
              id: vidB,
              title: 'Song B',
              channelTitle: 'Artist B',
              thumbnailUrl: '',
              duration: '3:20',
              viewCount: '1M views',
            ),
          ],
          'Artist C - Song C (Official Audio)': const [
            YouTubeVideo(
              id: vidC,
              title: 'Song C',
              channelTitle: 'Artist C',
              thumbnailUrl: '',
              duration: '5:15',
              viewCount: '2M views',
            ),
          ],
        },
        gates: {'Artist B - Song B (Official Audio)': gateB},
      );
      final player = _FakeAudioPlayer();
      final resolver = PlaybackSourceResolver.withRepository(repo);
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      final container = _createTestContainer(handler: handler, resolver: resolver);
      addTearDown(container.dispose);

      for (final id in [vidA, vidB, vidC]) {
        YouTubeAudioService().cacheUrlForTesting(
          id,
          'https://rr1---sn-test.googlevideo.com/videoplayback?id=$id&expire=2524608000',
        );
      }

      const trackA = Track(
        id: 'youtube_$vidA',
        title: 'Song A',
        artist: 'Artist A',
        imageUrl: '',
        duration: '4:00',
      );
      const trackB = Track(
        id: 'youtube_itunes_b',
        title: 'Song B',
        artist: 'Artist B',
        imageUrl: '',
        duration: '3:20',
        metadataProvider: 'itunes',
      );
      const trackC = Track(
        id: 'youtube_itunes_c',
        title: 'Song C',
        artist: 'Artist C',
        imageUrl: '',
        duration: '5:15',
        metadataProvider: 'itunes',
      );

      final ctrl = container.read(playerControllerProvider.notifier);
      await ctrl.playTrack(trackA);
      player.emitPosition(const Duration(minutes: 3, seconds: 10));
      await pumpEventQueue(times: 4);

      final fB = ctrl.playTrack(trackB);
      final fC = ctrl.playTrack(trackC);
      gateB.complete();
      player.nextSetDuration = const Duration(minutes: 5, seconds: 15);
      await Future.wait([fB, fC]);
      await pumpEventQueue(times: 6);

      final active = container.read(playerControllerProvider);
      expect(active.currentTrack?.title, 'Song C');
      expect(active.position, Duration.zero);
      expect(active.duration, const Duration(minutes: 5, seconds: 15));

      // RepeatMode.all on 1-track queue wrapping via next() must restart at 0:00
      ctrl.setQueue(const [trackA], startIndex: 0);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await pumpEventQueue(times: 10);
      expect(container.read(playerControllerProvider).status,
          PlaybackStatus.playing);
      await ctrl.toggleRepeatMode(); // off -> all
      player.emitPosition(const Duration(minutes: 3, seconds: 50));
      await pumpEventQueue(times: 4);
      await ctrl.next();
      await pumpEventQueue(times: 10);
      expect(container.read(playerControllerProvider).position, Duration.zero);
    });

    testWidgets('6. Waveform geometry is per-track & PlayerPage shows 0:00 / --:-- instead of stale progress or 3:56', (tester) async {
      final bars1 = WaveformWidget.heightsForTrack(
        'youtube_aaaaaaaaaaa',
        title: 'Ambikapathy - Unnaal Unnaal',
        artist: 'Dhanush',
      );
      final bars2 = WaveformWidget.heightsForTrack(
        'youtube_bbbbbbbbbbb',
        title: 'Chekka Chivantha Vaanam',
        artist: 'A. R. Rahman',
      );
      expect(bars1, isNot(equals(bars2)));

      final ratios1 = DiscreteWaveformScrubber.ratiosForTrack(
        'youtube_aaaaaaaaaaa',
        title: 'Ambikapathy - Unnaal Unnaal',
        artist: 'Dhanush',
      );
      final ratios2 = DiscreteWaveformScrubber.ratiosForTrack(
        'youtube_bbbbbbbbbbb',
        title: 'Chekka Chivantha Vaanam',
        artist: 'A. R. Rahman',
      );
      expect(ratios1, isNot(equals(ratios2)));

      const vidA = 'lllllllllll';
      final player = _FakeAudioPlayer();
      final resolver = PlaybackSourceResolver.withRepository(_StubYouTubeRepository());
      final handler = MieeAudioHandler(player: player, sourceResolver: resolver);
      YouTubeAudioService().cacheUrlForTesting(
        vidA,
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=$vidA&expire=2524608000',
      );
      YouTubeAudioService().cacheUrlForTesting(
        'mmmmmmmmmmm',
        'https://rr1---sn-test.googlevideo.com/videoplayback?id=mmmmmmmmmmm&expire=2524608000',
      );

      final loadingGate = Completer<void>();
      final slowRepo = _StubYouTubeRepository(
        responses: {
          'A.R. Rahman - Chekka Chivantha Vaanam (Official Audio)': const [
            YouTubeVideo(
              id: 'mmmmmmmmmmm',
              title: 'Chekka Chivantha Vaanam',
              channelTitle: 'A.R. Rahman',
              thumbnailUrl: '',
              duration: '5:47',
              viewCount: '5M views',
            ),
          ],
        },
        gates: {'A.R. Rahman - Chekka Chivantha Vaanam (Official Audio)': loadingGate},
      );
      final slowResolver = PlaybackSourceResolver.withRepository(slowRepo);

      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final container = ProviderContainer(overrides: [
        audioHandlerProvider.overrideWithValue(handler),
        preferencesRepositoryProvider.overrideWithValue(_FakePreferencesRepo()),
        queueStateRepositoryProvider.overrideWithValue(_FakeQueueStateRepo()),
        listeningHistoryRepositoryProvider
            .overrideWithValue(_FakeListeningHistoryRepo()),
        recentlyPlayedRepositoryProvider
            .overrideWithValue(_FakeRecentlyPlayedRepo()),
        artworkResolverProvider.overrideWithValue(_FakeArtworkResolver()),
        songsProvider.overrideWithValue(const <MediaSong>[]),
        artistsProvider.overrideWithValue(const <MediaArtist>[]),
        favoritesRepositoryProvider.overrideWithValue(_FakeFavoritesRepo()),
        activeRoomProvider.overrideWith((ref) => null),
        sourceSelectionProvider.overrideWithValue('preferYouTube'),
        playerControllerProvider.overrideWith((ref) => PlayerController(
              handler,
              ref.watch(queueManagerProvider),
              ref,
              sourceResolver: slowResolver,
            )),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: PlayerPage()),
        ),
      );
      await tester.pump();

      final ctrl = container.read(playerControllerProvider.notifier);
      const trackNoDur = Track(
        id: 'youtube_$vidA',
        title: 'Ambikapathy - Unnaal Unnaal',
        artist: 'Dhanush',
        imageUrl: '',
        duration: '3:30',
      );
      final sourceGateA = Completer<void>();
      player.setSourceGate = sourceGateA;
      player.nextSetDuration = const Duration(minutes: 4, seconds: 56);
      final loadingPlay = ctrl.playTrack(trackNoDur);
      await tester.pump();

      // Must show 0:00 and --:-- (never hardcoded 1:24 or 3:56)
      expect(find.text('1:24'), findsNothing);
      expect(find.text('3:56'), findsNothing);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('--:--'), findsOneWidget);

      sourceGateA.complete();
      await loadingPlay;
      await tester.pump();

      // Advance Track A to 4:00, then switch to loading Chekka Chivantha Vaanam (5:47)
      player.emitPosition(const Duration(minutes: 4));
      await tester.pump();
      expect(find.text('4:00'), findsOneWidget);

      const trackB = Track(
        id: 'youtube_itunes_ccv',
        title: 'Chekka Chivantha Vaanam',
        artist: 'A.R. Rahman',
        imageUrl: '',
        duration: '5:47',
        metadataProvider: 'itunes',
      );
      final loadingB = ctrl.playTrack(trackB);
      await tester.pump();

      expect(find.text('4:00'), findsNothing);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('5:47'), findsOneWidget);

      loadingGate.complete();
      player.nextSetDuration = const Duration(minutes: 5, seconds: 47);
      await tester.pump(const Duration(milliseconds: 120));
      await loadingB;
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
