import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/preloading/next_track_preloader.dart';
import 'package:Miee/core/audio/preloading/preload_cache_manager.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/shared/models/music_item.dart';

class _TestTrack implements MusicItem {
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

  const _TestTrack({
    required this.id,
    required this.title,
    required this.filePath,
    this.isYoutube = false,
  })  : artist = 'Test Artist',
        imageUrl = '',
        duration = '03:00';
}

class _AdvancementFakeAudioPlayer extends AudioPlayer {
  bool _isPlaying = false;
  ProcessingState _procState = ProcessingState.idle;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  Duration _pos = Duration.zero;
  double _volume = 1.0;

  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;
  int setVolumeCalls = 0;
  final List<AudioSource> loadedSources = [];
  Completer<void>? gateNextSetSource;
  bool throwOnNextSetSource = false;

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

  _AdvancementFakeAudioPlayer() : super(handleInterruptions: false);

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

  void emitCompleted({bool playing = true}) {
    _isPlaying = playing;
    _procState = ProcessingState.completed;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
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
    if (throwOnNextSetSource) {
      throwOnNextSetSource = false;
      throw PlayerException(999, 'Simulated source failure', null);
    }
    loadedSources.add(source);
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
    _pos = position ?? Duration.zero;
    _posCtrl.add(_pos);
  }

  @override
  Future<void> setVolume(double volume) async {
    setVolumeCalls++;
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

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_auto_adv_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  MieeAudioHandler createHandler(_AdvancementFakeAudioPlayer player) {
    final preloader = NextTrackPreloader(
      cacheManager: PreloadCacheManager(
        cacheDirectoryProvider: () async => tempDir,
      ),
      resolveYouTubeStream: (id, {forceRefresh = false, title, artist}) async =>
          ResolvedYouTubeStream(
        url: 'https://rr1---sn-test.googlevideo.com/videoplayback?id=$id&expire=9999999999',
        userAgent: 'TestUA/1.0',
        clientName: 'ANDROID_VR',
      ),
      isYouTubeUrlValid: (u) => u.startsWith('http'),
      invalidateYouTubeCache: (_) {},
      logger: (_) {},
    );
    return MieeAudioHandler(player: player, preloader: preloader);
  }

  group('Automatic Queue Advancement', () {
    test('A finishes -> B starts -> C starts automatically without fadeOutAndPause',
        () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();
      final initialPauseCalls = player.pauseCalls;

      // A finishes -> B starts automatically.
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'B');
      expect(player.playing, isTrue);
      expect(player.pauseCalls, initialPauseCalls); // No unnecessary fadeOutAndPause

      // B finishes -> C starts automatically.
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, 'C');
      expect(player.playing, isTrue);

      await handler.disposeHandler();
    });

    test('Queue end with repeat disabled stops cleanly', () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.currentIndex, 0);
      expect(player.stopCalls, greaterThanOrEqualTo(1));
      expect(player.playing, isFalse);

      await handler.disposeHandler();
    });

    test('Repeat-all at final queue entry wraps around to index 0', () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 1);
      await handler.setRepeatMode(AudioServiceRepeatMode.all);
      await handler.play();

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, 'A');
      expect(player.playing, isTrue);

      await handler.disposeHandler();
    });

    test('Repeat-one does not advance queue on completion', () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.setRepeatMode(AudioServiceRepeatMode.one);
      await handler.play();

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.currentIndex, 0);
      expect(handler.mediaItem.value?.id, 'A');

      await handler.disposeHandler();
    });

    test('Shuffle progression advances along synced shuffled queue order',
        () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const original = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];
      final shuffled = [original[0], original[2], original[1]];

      await handler.loadQueue(original, startIndex: 0);
      await handler.syncQueueOrder(shuffled, 0);
      await handler.setShuffleMode(AudioServiceShuffleMode.all);
      await handler.play();

      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'C');

      await handler.disposeHandler();
    });

    test('YouTube A -> Local B and Local A -> YouTube B advance automatically',
        () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(
          id: 'youtube_dQw4w9WgXcQ',
          title: 'YT A',
          filePath: 'https://rr1---sn-test.googlevideo.com/videoplayback?id=1&expire=9999999999',
          isYoutube: true,
        ),
        _TestTrack(id: 'local_B', title: 'Local B', filePath: '/music/b.mp3'),
        _TestTrack(
          id: 'youtube_o0LydWpBQts',
          title: 'YT C',
          filePath: 'https://rr1---sn-test.googlevideo.com/videoplayback?id=2&expire=9999999999',
          isYoutube: true,
        ),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      // YouTube A -> Local B
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'local_B');
      expect(player.playing, isTrue);

      // Local B -> YouTube C
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, 'youtube_o0LydWpBQts');
      expect(player.playing, isTrue);

      await handler.disposeHandler();
    });

    test('Duplicate completion events only advance once', () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      // Emit duplicate completed events back-to-back for track A.
      player.emitCompleted(playing: true);
      player.emitCompleted(playing: false);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.currentIndex, 1);
      expect(handler.mediaItem.value?.id, 'B');

      await handler.disposeHandler();
    });

    test('Manual skip during completion transition supersedes and advances',
        () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      final gate = Completer<void>();
      player.gateNextSetSource = gate;

      // Start completion transition to B (stalled at setAudioSource).
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(handler.currentIndex, 1);

      // User manually skips to C while B is still loading.
      final manualSkip = handler.skipToNext();
      gate.complete();
      await manualSkip;

      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, 'C');
      expect(handler.isSkippingNextForTesting, isFalse);

      await handler.disposeHandler();
    });

    test('Failed next-track loading resets _isSkippingNext and _isLoadingTrack',
        () async {
      final player = _AdvancementFakeAudioPlayer();
      final handler = createHandler(player);
      const queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '/music/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '/music/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '/music/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      await handler.play();

      player.throwOnNextSetSource = true;
      player.emitCompleted(playing: true);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(handler.isSkippingNextForTesting, isFalse);
      expect(handler.isLoadingTrack, isFalse);

      // Subsequent manual skip to C still works cleanly.
      await handler.skipToNext();
      expect(handler.currentIndex, 2);
      expect(handler.mediaItem.value?.id, 'C');
      expect(player.playing, isTrue);

      await handler.disposeHandler();
    });
  });
}
