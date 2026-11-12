import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/preloading/next_track_preloader.dart';
import 'package:Miee/core/audio/preloading/preload_cache_manager.dart';
import 'package:Miee/core/audio/preloading/preload_models.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/shared/models/music_item.dart';

class _LoopTestTrack implements MusicItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String artist;
  @override
  final String imageUrl;
  @override
  final String duration;
  @override
  final String filePath;
  @override
  final bool isYoutube;

  const _LoopTestTrack({
    required this.id,
    required this.title,
    required this.filePath,
    this.isYoutube = false,
  })  : artist = 'Test Artist',
        imageUrl = '',
        duration = '03:00';
}

class _LoopFakeAudioPlayer extends AudioPlayer {
  bool _isPlaying = false;
  ProcessingState _procState = ProcessingState.idle;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  Duration _pos = Duration.zero;
  double _volume = 1.0;

  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  final List<Duration?> seekCalls = [];
  final List<AudioSource> loadedSources = [];
  final List<Duration?> loadedInitialPositions = [];
  Completer<void>? gateNextSetSource;

  final StreamController<PlayerState> _stateCtrl =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _posCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durCtrl =
      StreamController<Duration?>.broadcast();
  final StreamController<PlaybackEvent> _eventCtrl =
      StreamController<PlaybackEvent>.broadcast();
  final StreamController<PlayerException> _errCtrl =
      StreamController<PlayerException>.broadcast();

  _LoopFakeAudioPlayer() : super(handleInterruptions: false);

  @override
  bool get playing => _isPlaying;
  @override
  ProcessingState get processingState => _procState;
  @override
  LoopMode get loopMode => _loopMode;
  @override
  bool get shuffleModeEnabled => _shuffleEnabled;
  @override
  Duration get position => _pos;
  @override
  Duration get bufferedPosition => _pos;
  @override
  Duration? get duration => const Duration(minutes: 3);
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
  Stream<Duration> get bufferedPositionStream => _posCtrl.stream;

  void simulateProgress(Duration position) {
    _pos = position;
    _posCtrl.add(position);
  }

  void emitCompleted({bool playing = true}) {
    _pos = const Duration(minutes: 3);
    _posCtrl.add(_pos);
    _isPlaying = playing;
    _procState = ProcessingState.completed;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  void emitError(int code, String message) {
    _errCtrl.add(PlayerException(code, message, 0));
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    Duration? initialPosition,
    int? initialIndex,
  }) async {
    if (gateNextSetSource != null) {
      await gateNextSetSource!.future;
      gateNextSetSource = null;
    }
    loadedSources.add(source);
    loadedInitialPositions.add(initialPosition);
    _pos = initialPosition ?? Duration.zero;
    _posCtrl.add(_pos);
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
    return const Duration(minutes: 3);
  }

  @override
  Future<Duration?> setUrl(
    String url, {
    Map<String, String>? headers,
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    return setAudioSource(
      AudioSource.uri(Uri.parse(url), headers: headers, tag: tag),
      initialPosition: initialPosition,
      preload: preload,
    );
  }

  @override
  Future<void> play() async {
    playCalls++;
    _isPlaying = true;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _isPlaying = false;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _isPlaying = false;
    _procState = ProcessingState.idle;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    seekCalls.add(position);
    _pos = position ?? Duration.zero;
    _posCtrl.add(_pos);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    _loopMode = mode;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
  }

  @override
  Future<void> dispose() async {
    await _stateCtrl.close();
    await _posCtrl.close();
    await _durCtrl.close();
    await _eventCtrl.close();
    await _errCtrl.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_loop_reg_');
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MieeAudioHandler createHandler(
    _LoopFakeAudioPlayer player, {
    Future<ResolvedYouTubeStream?> Function(
      String videoId, {
      bool forceRefresh,
      String? title,
      String? artist,
    })? resolveYouTubeStream,
  }) {
    final cacheManager = PreloadCacheManager(
      cacheDirectoryProvider: () async => tempDir,
    );
    final preloader = NextTrackPreloader(
      cacheManager: cacheManager,
      connectivityProvider: () async => [ConnectivityResult.wifi],
      freeDiskBytesProvider: () async => 500 * 1024 * 1024,
      resolveYouTubeStream: resolveYouTubeStream,
    );
    return MieeAudioHandler(player: player, preloader: preloader);
  }

  group('Playback Loop Regression Tests', () {
    test('1. Two-track local queue advances A -> B at 0:00 and stops after B',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'Track A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'Track B', filePath: '/music/b.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();
      player.simulateProgress(const Duration(minutes: 2, seconds: 59));

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'B');
      expect(handler.loadedAudioTrackId, 'B');
      expect(player.position, Duration.zero);
      expect(player.loadedSources.length, 2);
      expect(player.loadedInitialPositions.last, isNull);
      expect(player.playing, isTrue);

      // Complete B with LoopMode.off -> stops cleanly without restarting A or B.
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(player.stopCalls, greaterThanOrEqualTo(1));
      expect(player.playing, isFalse);
      expect(handler.loadedAudioTrackId, isNull);

      await handler.disposeHandler();
    });

    test('2. Four-track local queue advances A -> B -> C -> D sequentially',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _LoopTestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
        _LoopTestTrack(id: 'D', title: 'D', filePath: '/music/d.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      for (final expected in ['B', 'C', 'D']) {
        player.simulateProgress(const Duration(minutes: 3));
        player.emitCompleted(playing: true);
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(handler.mediaItem.value?.id, expected);
        expect(handler.loadedAudioTrackId, expected);
        expect(player.position, Duration.zero);
      }

      expect(player.loadedSources.length, 4);
      await handler.disposeHandler();
    });

    test('3. YouTube queue advances ytA -> ytB using preloaded streamReady entry',
        () async {
      final player = _LoopFakeAudioPlayer();
      var resolveCalls = 0;
      final handler = createHandler(
        player,
        resolveYouTubeStream: (
          videoId, {
          bool forceRefresh = false,
          String? title,
          String? artist,
        }) async {
          resolveCalls++;
          return ResolvedYouTubeStream(
            url: 'https://rr1---sn-test.googlevideo.com/videoplayback?id=$videoId&expire=2524608000',
            userAgent: 'TestAgent/1.0',
            clientName: 'ANDROID',
          );
        },
      );

      const queue = [
        _LoopTestTrack(
          id: 'youtube_vidA0000001',
          title: 'YT A',
          filePath: 'https://rr1---sn-test.googlevideo.com/videoplayback?id=vidA0000001&expire=2524608000',
          isYoutube: true,
        ),
        _LoopTestTrack(
          id: 'youtube_vidB0000002',
          title: 'YT B',
          filePath: '',
          isYoutube: true,
        ),
        _LoopTestTrack(
          id: 'youtube_vidC0000003',
          title: 'YT C',
          filePath: '',
          isYoutube: true,
        ),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();
      await Future<void>.delayed(const Duration(milliseconds: 80));

      // Preloader resolved vidB and vidC while A played.
      expect(resolveCalls, greaterThanOrEqualTo(1));
      final preloadedB = handler.preloader.cacheManager.getEntry('vidB0000002');
      expect(preloadedB?.state, PreloadState.streamReady);

      // A completes -> advances to B without restarting A.
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'youtube_vidB0000002');
      expect(handler.loadedAudioTrackId, 'youtube_vidB0000002');
      expect(player.position, Duration.zero);

      await handler.disposeHandler();
    });

    test('4. RepeatMode.all wraps multi-track queue A -> B -> A at 0:00',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
      ];

      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'B');

      player.simulateProgress(const Duration(minutes: 3));
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, 'A');
      expect(player.position, Duration.zero);
      expect(player.playing, isTrue);

      await handler.disposeHandler();
    });

    test('5. RepeatMode.all wraps 1-track queue starting at 0:00 (not end pos)',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
      ];

      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      player.simulateProgress(const Duration(minutes: 3));
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, 'A');
      expect(player.position, Duration.zero);
      expect(player.loadedInitialPositions.last, isNull);
      expect(player.playing, isTrue);

      await handler.disposeHandler();
    });

    test('6. RepeatMode.one repeats same track at 0:00 without advancing',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
      ];

      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      player.simulateProgress(const Duration(minutes: 3));
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, 'A');
      expect(player.seekCalls, contains(Duration.zero));
      expect(player.position, Duration.zero);
      expect(player.playing, isTrue);

      await handler.disposeHandler();
    });

    test('7. Duplicate completion events advance only once (A -> B, not C)',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _LoopTestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      player.emitCompleted(playing: true);
      player.emitCompleted(playing: false);
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'B');
      expect(player.loadedSources.length, 2);

      await handler.disposeHandler();
    });

    test('8. Manual skip during completion transition supersedes cleanly',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _LoopTestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      final gate = Completer<void>();
      player.gateNextSetSource = gate;

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final manualSkip = handler.skipToNext();
      gate.complete();
      await manualSkip;

      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, 'C');
      expect(handler.loadedAudioTrackId, 'C');

      await handler.disposeHandler();
    });

    test('9. Shuffle-reordered queue advances through synced order without loop',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _LoopTestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      // Simulate shuffled order [A, C, B] synced from PlayerController.
      await handler.syncQueueOrder([queue[0], queue[2], queue[1]], 0);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'C');

      await handler.disposeHandler();
    });

    test('10. Preloader syncWindow never mutates currentIndex or restarts track',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _LoopTestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();
      player.simulateProgress(const Duration(seconds: 45));

      await handler.preloader.syncWindow(
        queue: queue,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );

      expect(handler.currentIndex, 0);
      expect(handler.loadedAudioTrackId, 'A');
      expect(player.position, const Duration(seconds: 45));
      expect(player.loadedSources.length, 1);

      await handler.disposeHandler();
    });

    test('11. Completion does not emit AudioProcessingState.completed while advancing',
        () async {
      final player = _LoopFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _LoopTestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _LoopTestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
      ];

      final emittedStates = <AudioProcessingState>[];
      final sub = handler.playbackState.listen((s) {
        emittedStates.add(s.processingState);
      });

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();
      emittedStates.clear();

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(emittedStates, isNot(contains(AudioProcessingState.completed)));
      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'B');

      await sub.cancel();
      await handler.disposeHandler();
    });
  });
}

