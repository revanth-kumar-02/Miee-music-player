import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/youtube_audio_service.dart';
import 'package:Miee/shared/models/track.dart';

class _ReliableMockAudioPlayer extends AudioPlayer {
  bool _isPlaying = false;
  ProcessingState _procState = ProcessingState.idle;
  Duration _pos = Duration.zero;
  final Duration _dur = const Duration(minutes: 3, seconds: 30);
  double _volume = 1.0;

  int playCallCount = 0;
  int pauseCallCount = 0;
  int stopCallCount = 0;
  int setAudioSourceCallCount = 0;
  final List<AudioSource> loadedSources = [];
  final List<Duration?> loadedInitialPositions = [];
  Completer<void>? delayNextSetAudioSource;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _posController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durController =
      StreamController<Duration?>.broadcast();
  final StreamController<PlaybackEvent> _eventController =
      StreamController<PlaybackEvent>.broadcast();
  final StreamController<PlayerException> _errorController =
      StreamController<PlayerException>.broadcast();

  _ReliableMockAudioPlayer() : super(handleInterruptions: false);

  @override
  bool get playing => _isPlaying;

  @override
  ProcessingState get processingState => _procState;

  @override
  Duration get position => _pos;

  @override
  Duration get bufferedPosition => _pos;

  @override
  Duration? get duration => _dur;

  @override
  double get volume => _volume;

  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _posController.stream;

  @override
  Stream<Duration?> get durationStream => _durController.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _eventController.stream;

  @override
  Stream<PlayerException> get errorStream => _errorController.stream;

  void emitPlayerState(bool playing, ProcessingState state) {
    _isPlaying = playing;
    _procState = state;
    _stateController.add(PlayerState(playing, state));
  }

  void emitPosition(Duration pos) {
    _pos = pos;
    _posController.add(pos);
  }

  void emitErrorStream(int code, String message, {int? index = 0}) {
    _errorController.add(PlayerException(code, message, index));
  }

  void emitPlaybackEventError(int code, String message,
      {ProcessingState state = ProcessingState.idle}) {
    _procState = state;
    _isPlaying = false;
    _eventController.add(PlaybackEvent(
      processingState: state,
      errorCode: code,
      errorMessage: message,
      updatePosition: _pos,
      bufferedPosition: _pos,
      duration: _dur,
      currentIndex: 0,
    ));
  }

  void emitLegacyPlaybackEventStreamError(Object error) {
    _eventController.addError(error);
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    setAudioSourceCallCount++;
    loadedSources.add(source);
    loadedInitialPositions.add(initialPosition);
    if (delayNextSetAudioSource != null) {
      await delayNextSetAudioSource!.future;
      delayNextSetAudioSource = null;
    }
    if (initialPosition != null) {
      _pos = initialPosition;
    }
    _procState = ProcessingState.ready;
    return _dur;
  }

  @override
  Future<void> play() async {
    playCallCount++;
    _isPlaying = true;
    _procState = ProcessingState.ready;
    _stateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCallCount++;
    _isPlaying = false;
    _stateController.add(PlayerState(false, _procState));
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    _isPlaying = false;
    _procState = ProcessingState.idle;
    _stateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    if (position != null) {
      _pos = position;
      _posController.add(position);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _posController.close();
    await _durController.close();
    await _eventController.close();
    await _errorController.close();
  }
}

Track _ytTrack(String videoId, {String title = 'Test Song'}) => Track(
      id: 'youtube_$videoId',
      title: title,
      artist: 'Test Artist',
      imageUrl: '',
      duration: '03:30',
      filePath: 'https://youtube.com/watch?v=$videoId',
    );

Track _localTrack(String id, String path) => Track(
      id: id,
      title: 'Local Song',
      artist: 'Local Artist',
      imageUrl: '',
      duration: '03:30',
      filePath: path,
    );

StreamManifest _fakeManifest(String videoId, String streamUrl) {
  final info = AudioOnlyStreamInfo.fromJson({
    'videoId': {'value': videoId},
    'tag': 140,
    'url': streamUrl,
    'container': {'name': 'mp4'},
    'size': {'totalBytes': 3000000},
    'bitrate': {'bitsPerSecond': 128000},
    'audioCodec': 'mp4a.40.2',
    'qualityLabel': 'medium',
    'fragments': const <dynamic>[],
    'codec': 'audio/mp4',
    'audioTrack': null,
  });
  return StreamManifest([info]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Ensure real loopback HTTP test servers are reachable during unit tests.
  HttpOverrides.global = null;

  late _ReliableMockAudioPlayer mockPlayer;
  late MieeAudioHandler handler;
  late YouTubeAudioService ytService;

  setUp(() {
    ytService = YouTubeAudioService();
    ytService.clearCache();
    ytService.resetTestingHooks();
    mockPlayer = _ReliableMockAudioPlayer();
    handler = MieeAudioHandler(player: mockPlayer);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    ytService.resetTestingHooks();
    ytService.clearCache();
    await handler.disposeHandler();
  });

  group('YouTube Playback Reliability Fixes (1-9)', () {
    test('1. errorStream recovery invalidates cache, refreshes URL, and resumes at saved position', () async {
      const videoId = 'KtlgYxa6BMU';
      const initialUrl =
          'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=initial';
      const refreshedUrl =
          'https://rr2---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=refreshed';

      ytService.cacheUrlForTesting(videoId, initialUrl);

      int fetchCalls = 0;
      ytService.manifestFetcherForTesting = (vid, clients) async {
        fetchCalls++;
        if (clients != null && clients.contains(kVisionOsClient)) {
          return _fakeManifest(vid, refreshedUrl);
        }
        return null;
      };

      await handler.loadQueue([_ytTrack(videoId)]);
      await handler.play();
      mockPlayer.emitPosition(const Duration(seconds: 68));
      await pumpEventQueue();

      expect(handler.loadedAudioTrackId, equals('youtube_$videoId'));
      expect(mockPlayer.setAudioSourceCallCount, equals(1));

      // Native ExoPlayer failure emitted via errorStream (not playbackEventStream.onError)
      mockPlayer.emitErrorStream(-1004, 'HttpDataSourceException');
      await pumpEventQueue(times: 30);

      expect(fetchCalls, equals(1));
      expect(mockPlayer.setAudioSourceCallCount, equals(2));
      expect(mockPlayer.loadedInitialPositions.last, equals(const Duration(seconds: 68)));
      expect(
        (mockPlayer.loadedSources.last as UriAudioSource).uri.toString(),
        equals(refreshedUrl),
      );
      expect(mockPlayer.playCallCount, equals(2));
      expect(handler.isRecovering, isFalse);
    });

    test('2. PlaybackEvent.errorCode recovery triggers recovery and avoids emitting idle mid-recovery', () async {
      const videoId = '7wtfhZwyrcc';
      const initialUrl =
          'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=v1';
      const refreshedUrl =
          'https://rr2---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=v2';

      ytService.cacheUrlForTesting(videoId, initialUrl);

      final manifestCompleter = Completer<StreamManifest?>();
      ytService.manifestFetcherForTesting = (vid, clients) async {
        if (clients != null && clients.contains(kVisionOsClient)) {
          return manifestCompleter.future;
        }
        return null;
      };

      await handler.loadQueue([_ytTrack(videoId)]);
      await handler.play();
      mockPlayer.emitPosition(const Duration(seconds: 52));
      await pumpEventQueue();

      final observedStates = <AudioProcessingState>[];
      final sub = handler.playbackState.listen((s) => observedStates.add(s.processingState));

      mockPlayer.emitPlaybackEventError(-1004, 'Source error', state: ProcessingState.idle);
      mockPlayer.emitPlayerState(false, ProcessingState.idle);
      await pumpEventQueue();

      // Recovery must hold AudioProcessingState.buffering and NEVER emit idle to AudioService.
      expect(handler.isRecovering, isTrue);
      expect(observedStates, isNot(contains(AudioProcessingState.idle)));
      expect(handler.playbackState.value.processingState, equals(AudioProcessingState.buffering));
      expect(handler.playbackState.value.playing, isTrue);

      manifestCompleter.complete(_fakeManifest(videoId, refreshedUrl));
      await pumpEventQueue(times: 30);
      await sub.cancel();

      expect(mockPlayer.setAudioSourceCallCount, equals(2));
      expect(handler.playbackState.value.processingState, equals(AudioProcessingState.ready));
      expect(mockPlayer.playing, isTrue);
    });

    test('3. Duplicate error suppression runs single recovery when multiple channels fire together', () async {
      const videoId = 'dQw4w9WgXcQ';
      const initialUrl =
          'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=v1';
      const refreshedUrl =
          'https://rr2---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=v2';

      ytService.cacheUrlForTesting(videoId, initialUrl);

      int manifestResolutions = 0;
      ytService.manifestFetcherForTesting = (vid, clients) async {
        if (clients != null && clients.contains(kVisionOsClient)) {
          manifestResolutions++;
          return _fakeManifest(vid, refreshedUrl);
        }
        return null;
      };

      await handler.loadQueue([_ytTrack(videoId)]);
      await handler.play();
      mockPlayer.emitPosition(const Duration(seconds: 31));
      await pumpEventQueue();

      // Fire both Android error channels together, then immediately emit an overlapping error
      // (all representing the same failure within the debounce/recovery window).
      mockPlayer.emitPlaybackEventError(-1004, 'HttpDataSourceException');
      mockPlayer.emitErrorStream(-1004, 'HttpDataSourceException');
      mockPlayer.emitPlaybackEventError(-1004, 'HttpDataSourceException');
      await pumpEventQueue(times: 30);
      // Even immediately after fast recovery finishes, same failure signature inside 2s is suppressed.
      mockPlayer.emitErrorStream(-1004, 'HttpDataSourceException');
      await pumpEventQueue(times: 20);

      expect(manifestResolutions, equals(1));
      expect(mockPlayer.setAudioSourceCallCount, equals(2));
      expect(mockPlayer.playCallCount, equals(2));
    });

    test('4. Recovery while buffering resumes at current position once stream error arrives', () async {
      const videoId = 'o0LydWpBQts';
      const initialUrl =
          'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=buf1';
      const recoveredUrl =
          'https://rr2---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=buf2';

      ytService.cacheUrlForTesting(videoId, initialUrl);
      ytService.manifestFetcherForTesting = (vid, clients) async {
        if (clients != null && clients.contains(kVisionOsClient)) {
          return _fakeManifest(vid, recoveredUrl);
        }
        return null;
      };

      await handler.loadQueue([_ytTrack(videoId)]);
      await handler.play();
      mockPlayer.emitPosition(const Duration(seconds: 95));
      mockPlayer.emitPlayerState(true, ProcessingState.buffering);
      await pumpEventQueue();

      // Error strikes mid-buffering before 12s watchdog expires.
      mockPlayer.emitErrorStream(-1004, 'Socket reset while buffering');
      await pumpEventQueue(times: 30);

      expect(mockPlayer.setAudioSourceCallCount, equals(2));
      expect(mockPlayer.loadedInitialPositions.last, equals(const Duration(seconds: 95)));
      expect(mockPlayer.playCallCount, equals(2));
      expect(handler.bufferingWatchdogTimerForTesting, isNull);
    });

    test('5. HTTP 403 fallback rejection prevents returning or caching broken fallback streams', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final seenUserAgents = <String>[];
      server.listen((req) async {
        seenUserAgents.add(req.headers.value('user-agent') ?? '');
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
      });

      const videoId = 'fb403test01';
      final fallback403Url = 'http://127.0.0.1:${server.port}/audio?expire=2524608000&c=ANDROID';

      ytService.manifestFetcherForTesting = (vid, clients) async {
        if (clients != null && clients.contains(kVisionOsClient)) {
          throw Exception('VISIONOS blocked');
        }
        return _fakeManifest(vid, fallback403Url);
      };

      final resolved = await ytService.getAudioStream(videoId, forceRefresh: true);

      expect(resolved, isNull);
      expect(ytService.isCached(videoId), isFalse);
      expect(seenUserAgents, contains(kYouTubeAndroidUserAgent));
    });

    test('6. User-Agent matching propagates client UA and disables Dart proxy on Android only', () async {
      // Platform proxy policy verification
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(MieeAudioHandler.shouldUseProxyForRequestHeaders, isFalse);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      expect(MieeAudioHandler.shouldUseProxyForRequestHeaders, isTrue);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      expect(MieeAudioHandler.shouldUseProxyForRequestHeaders, isTrue);
      debugDefaultTargetPlatformOverride = null;

      // Real HTTP 302 redirect + 206 Partial Content check for ANDROID_SDKLESS fallback
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final fallbackUAs = <String>[];
      server.listen((req) async {
        if (req.uri.path == '/redirect') {
          req.response.statusCode = HttpStatus.found;
          req.response.headers.set('location', 'http://127.0.0.1:${server.port}/media');
          await req.response.close();
          return;
        }
        fallbackUAs.add(req.headers.value('user-agent') ?? '');
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.contentType = ContentType('audio', 'mp4');
        req.response.add(List<int>.filled(1024, 0x2A));
        await req.response.close();
      });

      const fallbackVid = 'fb206test01';
      final redirectFallbackUrl =
          'http://127.0.0.1:${server.port}/redirect?expire=2524608000&c=ANDROID';

      ytService.manifestFetcherForTesting = (vid, clients) async {
        if (clients != null && clients.contains(kVisionOsClient)) {
          throw Exception('VISIONOS unavailable');
        }
        if (clients != null && clients.contains(kAndroidSdklessClient)) {
          return _fakeManifest(vid, redirectFallbackUrl);
        }
        return null;
      };

      await handler.loadQueue([_ytTrack(fallbackVid)]);
      final loadedAndroidSource = mockPlayer.loadedSources.last as UriAudioSource;
      expect(loadedAndroidSource.headers?['User-Agent'], equals(kYouTubeAndroidUserAgent));
      expect(fallbackUAs, contains(kYouTubeAndroidUserAgent));

      // Verify VISIONOS preserves VISIONOS User-Agent
      const visionVid = 'visionok001';
      const visionUrl =
          'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000&c=VISIONOS';
      ytService.cacheUrlForTesting(visionVid, visionUrl);
      await handler.loadQueue([_ytTrack(visionVid)]);
      final loadedVisionSource = mockPlayer.loadedSources.last as UriAudioSource;
      expect(loadedVisionSource.headers?['User-Agent'], equals(kYouTubeVisionOsUserAgent));
    });

    test('7. Concurrent skipToNext, completed pause suppression, position guard, and supersede safety', () async {
      final t1 = _localTrack('local_1', 'C:/music/1.mp3');
      final t2 = _localTrack('local_2', 'C:/music/2.mp3');
      final t3 = _localTrack('local_3', 'C:/music/3.mp3');

      await handler.loadQueue([t1, t2, t3], startIndex: 0);
      await handler.play();

      // Clear stale pause intent check: pause first, then loading new track must clear it.
      await handler.pause();
      expect(handler.userExplicitlyPaused, isTrue);

      // Delay t2 loading while holding completed state and firing concurrent skipToNext calls.
      final gate = Completer<void>();
      mockPlayer.delayNextSetAudioSource = gate;
      mockPlayer.emitPlayerState(true, ProcessingState.completed);
      final pauseCountAtComplete = mockPlayer.pauseCallCount;

      final f1 = handler.skipToNext();
      final f2 = handler.skipToNext();

      // While t2 is loading, _onPositionChanged must not overwrite lastValidPosition or leak idle.
      handler.setLastValidPositionForTesting(const Duration(seconds: 44));
      mockPlayer.emitPosition(const Duration(seconds: 199));
      expect(handler.lastValidPosition, equals(const Duration(seconds: 44)));
      expect(
        handler.playbackState.value.processingState,
        isNot(equals(AudioProcessingState.idle)),
      );

      gate.complete();
      await Future.wait([f1, f2]);

      expect(handler.currentIndex, equals(1), reason: 'Concurrent skipToNext must advance once');
      expect(
        mockPlayer.pauseCallCount,
        equals(pauseCountAtComplete),
        reason: 'fadeOutAndPause must not call pause() when already completed',
      );
      expect(handler.userExplicitlyPaused, isFalse);

      // Superseded track load must never call play() for stale track.
      final slowLoadGate = Completer<void>();
      mockPlayer.delayNextSetAudioSource = slowLoadGate;
      final playCountBeforeSupersede = mockPlayer.playCallCount;

      final slowSkip = handler.skipToQueueItem(0);
      await pumpEventQueue();
      // Immediately supersede with fast skip to index 2.
      mockPlayer.delayNextSetAudioSource = null;
      await handler.skipToQueueItem(2);
      final playCountAfterFastSkip = mockPlayer.playCallCount;

      slowLoadGate.complete();
      await slowSkip;

      expect(handler.currentIndex, equals(2));
      expect(mockPlayer.playCallCount, equals(playCountAfterFastSkip));
      expect(playCountAfterFastSkip, equals(playCountBeforeSupersede + 1));
    });

    test('8. Local playback preservation skips YouTube resolver and emits errors cleanly', () async {
      bool ytInvoked = false;
      ytService.manifestFetcherForTesting = (vid, clients) async {
        ytInvoked = true;
        return null;
      };

      final local = _localTrack('local_preserve_1', 'C:/audio/track.mp3');
      await handler.loadQueue([local], initialPosition: const Duration(seconds: 42));
      await handler.play();

      expect(ytInvoked, isFalse);
      expect(mockPlayer.loadedSources.single, isA<ProgressiveAudioSource>());
      expect(handler.lastValidPosition, equals(const Duration(seconds: 42)));

      final errors = <String>[];
      final errSub = handler.errorStream.listen(errors.add);
      mockPlayer.emitErrorStream(-1001, 'File missing');
      await pumpEventQueue(times: 10);
      await errSub.cancel();

      expect(errors, contains('File missing'));
      expect(handler.isRecovering, isFalse);
    });

    test('9. Background playback recovery restores stream after error unless user explicitly paused', () async {
      const videoId = 'bgVid000001';
      const initialUrl =
          'https://rr1---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=bg1';
      const freshUrl =
          'https://rr2---sn-test.googlevideo.com/videoplayback?expire=2524608000&tag=bg2';

      ytService.cacheUrlForTesting(videoId, initialUrl);
      ytService.manifestFetcherForTesting = (vid, clients) async {
        if (clients != null && clients.contains(kVisionOsClient)) {
          return _fakeManifest(vid, freshUrl);
        }
        return null;
      };

      await handler.loadQueue([_ytTrack(videoId)]);
      await handler.play();
      mockPlayer.emitPosition(const Duration(seconds: 112));
      await pumpEventQueue();

      // Background mid-song error: must auto-recover and resume.
      mockPlayer.emitErrorStream(-1004, 'Background socket closed');
      mockPlayer.emitPlayerState(false, ProcessingState.idle);
      await pumpEventQueue(times: 30);

      expect(mockPlayer.playing, isTrue);
      expect(mockPlayer.loadedInitialPositions.last, equals(const Duration(seconds: 112)));

      // Explicit pause before error: recovery may refresh source, but MUST stay paused.
      await handler.pause();
      expect(handler.userExplicitlyPaused, isTrue);
      final playsBeforePausedError = mockPlayer.playCallCount;

      await Future<void>.delayed(const Duration(milliseconds: 550));
      mockPlayer.emitErrorStream(-1004, 'Stale socket while paused');
      await pumpEventQueue(times: 30);

      expect(mockPlayer.playCallCount, equals(playsBeforePausedError));
      expect(mockPlayer.playing, isFalse);
    });
  });
}
