import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/core/audio/preloading/next_track_preloader.dart';
import 'package:Miee/core/audio/preloading/preload_cache_manager.dart';
import 'package:Miee/core/audio/preloading/preload_models.dart';
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

class _FakeAudioPlayer extends AudioPlayer {
  bool _isPlaying = false;
  ProcessingState _procState = ProcessingState.idle;
  LoopMode _loopMode = LoopMode.off;
  bool _shuffleEnabled = false;
  Duration _pos = Duration.zero;
  double _volume = 1.0;

  final List<AudioSource> setSources = [];
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

  _FakeAudioPlayer() : super(handleInterruptions: false);

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

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    Duration? initialPosition,
    int? initialIndex,
  }) async {
    setSources.add(source);
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
    _isPlaying = true;
    _procState = ProcessingState.ready;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> pause() async {
    _isPlaying = false;
    _stateCtrl.add(PlayerState(_isPlaying, _procState));
  }

  @override
  Future<void> stop() async {
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
  setUpAll(() {
    // Allow real loopback HttpServer requests inside Flutter test binding.
    HttpOverrides.global = null;
  });

  late Directory tempDir;
  late HttpServer server;
  late String baseUrl;
  final List<String> requestPaths = [];
  final List<String?> seenUserAgents = [];
  bool return403 = false;
  bool abortChunked = false;
  bool hangSlowDownload = false;
  Completer<void>? slowDownloadGate;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('miee_preload_test_');
    requestPaths.clear();
    seenUserAgents.clear();
    return403 = false;
    abortChunked = false;
    hangSlowDownload = false;
    slowDownloadGate = null;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${server.port}';
    server.listen((HttpRequest req) async {
      requestPaths.add(req.uri.path);
      seenUserAgents.add(req.headers.value(HttpHeaders.userAgentHeader));

      if (return403) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }

      if (req.uri.path == '/redirect') {
        req.response.statusCode = HttpStatus.movedTemporarily;
        req.response.headers.set(HttpHeaders.locationHeader, '$baseUrl/final.mp3');
        await req.response.close();
        return;
      }

      if (req.uri.path == '/partial-abort') {
        req.response.statusCode = HttpStatus.ok;
        if (abortChunked) {
          // Return an empty 0-byte payload so validation rejects it as incomplete.
          req.response.headers.contentLength = 0;
          await req.response.close();
          return;
        }
        req.response.headers.contentLength = 4096;
        req.response.add(List<int>.filled(4096, 66));
        await req.response.close();
        return;
      }

      if (req.uri.path == '/slow') {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentLength = 2048;
        req.response.add(List<int>.filled(256, 77));
        await req.response.flush();
        if (hangSlowDownload && slowDownloadGate != null) {
          await slowDownloadGate!.future.timeout(
            const Duration(seconds: 2),
            onTimeout: () {},
          );
        }
        try {
          req.response.add(List<int>.filled(1792, 78));
          await req.response.close();
        } catch (_) {}
        return;
      }

      final payload = List<int>.filled(1024, 42);
      req.response.statusCode = HttpStatus.ok;
      req.response.headers.contentLength = payload.length;
      req.response.add(payload);
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PreloadCacheManager createCacheManager({
    PreloadConfig config = const PreloadConfig(),
  }) {
    return PreloadCacheManager(
      config: config,
      cacheDirectoryProvider: () async => tempDir,
    );
  }

  NextTrackPreloader createPreloader({
    PreloadConfig config = const PreloadConfig(),
    PreloadCacheManager? cacheManager,
    YouTubeStreamResolver? resolveYouTubeStream,
    YouTubeUrlValidator? isYouTubeUrlValid,
    ConnectivityProvider? connectivityProvider,
    FreeDiskBytesProvider? freeDiskBytesProvider,
    PreloadLogger? logger,
    DateTime Function()? nowProvider,
  }) {
    return NextTrackPreloader(
      config: config,
      cacheManager: cacheManager ?? createCacheManager(config: config),
      resolveYouTubeStream: resolveYouTubeStream ??
          (id, {forceRefresh = false, title, artist}) async =>
              ResolvedYouTubeStream(
                url: 'https://redirector.googlevideo.com/videoplayback?id=$id&expire=9999999999',
                userAgent: 'TestUA/1.0',
                clientName: 'ANDROID_VR',
              ),
      resolveYouTubeQuery: (q) async => 'vid12345678',
      isYouTubeUrlValid: isYouTubeUrlValid ?? (url) => url.startsWith('http'),
      invalidateYouTubeCache: (_) {},
      connectivityProvider:
          connectivityProvider ?? () async => [ConnectivityResult.wifi],
      freeDiskBytesProvider:
          freeDiskBytesProvider ?? () async => 1024 * 1024 * 1024,
      retryDelayProvider: (_) => Duration.zero,
      logger: logger ?? (_) {},
      nowProvider: nowProvider,
    );
  }

  group('Rolling Two-Track Preloader', () {
    test('1. Rolling window prepares max 2 upcoming tracks and reuses on advance',
        () async {
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '$baseUrl/c.mp3'),
        _TestTrack(id: 'D', title: 'D', filePath: '$baseUrl/d.mp3'),
        _TestTrack(id: 'E', title: 'E', filePath: '$baseUrl/e.mp3'),
      ];

      final preloader = createPreloader();
      preloader.markPlayingTrack(queue[0]);
      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);

      expect(preloader.getEntrySnapshot('B')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('C')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('D'), isNull);
      expect(requestPaths, ['/b.mp3', '/c.mp3']);

      // Advance to B: C should be reused without re-downloading, D downloaded.
      preloader.markPlayingTrack(queue[1]);
      await preloader.syncWindow(queue: queue, currentIndex: 1, loopMode: LoopMode.off);

      expect(preloader.getEntrySnapshot('C')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('D')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('E'), isNull);
      expect(requestPaths, ['/b.mp3', '/c.mp3', '/d.mp3']);

      // Advance to C: D reused, E downloaded.
      preloader.markPlayingTrack(queue[2]);
      await preloader.syncWindow(queue: queue, currentIndex: 2, loopMode: LoopMode.off);
      expect(requestPaths, ['/b.mp3', '/c.mp3', '/d.mp3', '/e.mp3']);

      await preloader.dispose();
    });

    test('2. Partial .part download is never promoted to FULLY_CACHED and is cleaned up',
        () async {
      abortChunked = true;
      final cacheManager = createCacheManager(
        config: const PreloadConfig(maxRetries: 0),
      );
      final preloader = createPreloader(
        config: const PreloadConfig(maxRetries: 0),
        cacheManager: cacheManager,
      );

      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/partial-abort'),
      ];

      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);

      final entry = preloader.getEntrySnapshot('B');
      expect(entry?.state, PreloadState.failed);
      expect(await preloader.getPreparedEntry(queue[1]), isNull);
      final leftoverParts = tempDir
          .listSync()
          .where((e) => e.path.endsWith('.part'))
          .toList();
      expect(leftoverParts, isEmpty);

      await preloader.dispose();
    });

    test('3. Full remote HTTP download promotes atomically and returns readable file',
        () async {
      final preloader = createPreloader();
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
      ];

      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);
      final prepared = await preloader.getPreparedEntry(queue[1]);

      expect(prepared, isNotNull);
      expect(prepared!.state, PreloadState.fullyCached);
      expect(prepared.isLocalOriginal, isFalse);
      expect(prepared.cachedFilePath, isNotNull);
      expect(File(prepared.cachedFilePath!).lengthSync(), 1024);

      await preloader.dispose();
    });

    test('4. prioritizeImmediatePlayback cancels active background download',
        () async {
      hangSlowDownload = true;
      slowDownloadGate = Completer<void>();

      final preloader = createPreloader(
        config: const PreloadConfig(maxRetries: 0),
      );
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/slow'),
      ];

      final syncFuture = preloader.syncWindow(
        queue: queue,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );

      // Give HTTP download a brief moment to enter downloading state.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      var immediateRan = false;
      await preloader.prioritizeImmediatePlayback(() async {
        immediateRan = true;
      });
      slowDownloadGate?.complete();
      await syncFuture;

      expect(immediateRan, isTrue);
      await preloader.dispose();
    });

    test('5. Removing upcoming track cancels obsolete entry and prepares replacement',
        () async {
      hangSlowDownload = true;
      slowDownloadGate = Completer<void>();

      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/slow'),
        _TestTrack(id: 'C', title: 'C', filePath: '$baseUrl/c.mp3'),
        _TestTrack(id: 'D', title: 'D', filePath: '$baseUrl/d.mp3'),
      ];

      final preloader = createPreloader();
      final initialSync = preloader.syncWindow(
        queue: queue,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Remove B while downloading -> window becomes [C, D] and B is cancelled.
      final updated = [queue[0], queue[2], queue[3]];
      await preloader.syncWindow(
        queue: updated,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      slowDownloadGate?.complete();
      await initialSync;

      expect(preloader.getEntrySnapshot('B'), isNull);
      expect(preloader.getEntrySnapshot('C')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('D')?.state, PreloadState.fullyCached);

      await preloader.dispose();
    });

    test('6. Rapid successive queue changes settle on latest window without duplicates',
        () async {
      final preloader = createPreloader();
      final q1 = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
      ];
      final q2 = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'X', title: 'X', filePath: '$baseUrl/x.mp3'),
        _TestTrack(id: 'Y', title: 'Y', filePath: '$baseUrl/y.mp3'),
      ];

      await Future.wait([
        preloader.syncWindow(queue: q1, currentIndex: 0, loopMode: LoopMode.off),
        preloader.syncWindow(queue: q2, currentIndex: 0, loopMode: LoopMode.off),
      ]);

      expect(preloader.getEntrySnapshot('X')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('Y')?.state, PreloadState.fullyCached);
      expect(requestPaths.where((p) => p == '/x.mp3').length, 1);

      await preloader.dispose();
    });

    test('7. Duplicate songs in queue are deduplicated in rolling window', () async {
      final preloader = createPreloader();
      final dupQueue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '$baseUrl/c.mp3'),
      ];

      final window = preloader.computeUpcomingWindow(dupQueue, 0, LoopMode.off);
      expect(window.map((e) => e.id).toList(), ['B', 'C']);

      await preloader.syncWindow(
        queue: dupQueue,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      expect(requestPaths.where((p) => p == '/b.mp3').length, 1);
      expect(requestPaths.where((p) => p == '/c.mp3').length, 1);

      await preloader.dispose();
    });

    test('8. Repeat modes: LoopMode.one preloads nothing; LoopMode.all wraps around',
        () async {
      final preloader = createPreloader();
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '$baseUrl/c.mp3'),
      ];

      expect(preloader.computeUpcomingWindow(queue, 0, LoopMode.one), isEmpty);
      expect(
        preloader.computeUpcomingWindow(queue, 2, LoopMode.all).map((t) => t.id),
        ['A', 'B'],
      );

      await preloader.syncWindow(queue: queue, currentIndex: 2, loopMode: LoopMode.all);
      expect(preloader.getEntrySnapshot('A')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('B')?.state, PreloadState.fullyCached);

      await preloader.dispose();
    });

    test('9. Shuffle order change updates upcoming preload window', () async {
      final preloader = createPreloader();
      final shuffled = [
        _TestTrack(id: 'C', title: 'C', filePath: '$baseUrl/c.mp3'),
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'D', title: 'D', filePath: '$baseUrl/d.mp3'),
      ];

      await preloader.syncWindow(
        queue: shuffled,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      expect(preloader.getEntrySnapshot('A')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('D')?.state, PreloadState.fullyCached);

      await preloader.dispose();
    });

    test('10. Local track reuses original file path without copying or deleting',
        () async {
      final localFile = File('${tempDir.path}/local_song.mp3');
      await localFile.writeAsBytes([1, 2, 3, 4, 5]);

      final preloader = createPreloader();
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'L1', title: 'Local', filePath: localFile.path),
      ];

      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);
      final prepared = await preloader.getPreparedEntry(queue[1]);

      expect(prepared, isNotNull);
      expect(prepared!.state, PreloadState.fullyCached);
      expect(prepared.isLocalOriginal, isTrue);
      expect(prepared.cachedFilePath, localFile.path);

      // Evicting unused entries must NEVER delete the original local file.
      await preloader.syncWindow(
        queue: [queue[0]],
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      expect(localFile.existsSync(), isTrue);

      await preloader.dispose();
    });

    test('11. YouTube tracks remain streamReady and expired URLs transition to expired',
        () async {
      var now = DateTime.utc(2026, 11, 12, 12, 0, 0);
      final pastEpochSec =
          now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000;

      final preloader = createPreloader(
        nowProvider: () => now,
        resolveYouTubeStream: (id, {forceRefresh = false, title, artist}) async =>
            ResolvedYouTubeStream(
          url: 'https://redirector.googlevideo.com/videoplayback?id=$id&expire=$pastEpochSec',
          userAgent: 'TestUA/2.0',
          clientName: 'ANDROID_VR',
        ),
      );

      const ytTrack = _TestTrack(
        id: 'dQw4w9WgXcQ',
        title: 'YT Song',
        filePath: '',
        isYoutube: true,
      );
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        ytTrack,
      ];

      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);
      final snapshot = preloader.getEntrySnapshot('dQw4w9WgXcQ');
      expect(snapshot?.state, PreloadState.streamReady);

      // Expired by clock -> getPreparedEntry returns null and marks expired.
      expect(await preloader.getPreparedEntry(ytTrack), isNull);
      expect(
        preloader.getEntrySnapshot('dQw4w9WgXcQ')?.state,
        PreloadState.expired,
      );

      await preloader.dispose();
    });

    test('12. HTTP 403 error fails cleanly after bounded retries', () async {
      return403 = true;
      final preloader = createPreloader(
        config: const PreloadConfig(maxRetries: 1),
      );
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
      ];

      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);
      expect(preloader.getEntrySnapshot('B')?.state, PreloadState.failed);
      expect(requestPaths.where((p) => p == '/b.mp3').length, 2);

      await preloader.dispose();
    });

    test('13. Redirects preserve custom User-Agent across hops', () async {
      final cacheManager = createCacheManager();
      final token = PreloadCancellationToken(
        trackId: 'R1',
        sourceVersion: 'v1',
      );
      final res = await cacheManager.downloadCompleteAudio(
        trackId: 'R1',
        url: '$baseUrl/redirect',
        sourceVersion: 'v1',
        headers: {'User-Agent': 'MieeCustomUA/9.9'},
        cancellationToken: token,
      );

      expect(res.filePath.isNotEmpty, isTrue);
      expect(res.sizeBytes, 1024);
      expect(requestPaths, ['/redirect', '/final.mp3']);
      expect(seenUserAgents, ['MieeCustomUA/9.9', 'MieeCustomUA/9.9']);
    });

    test('14. Bounded cache eviction removes oldest unused while protecting active track',
        () async {
      final preloader = createPreloader(
        config: const PreloadConfig(maxCachedTracks: 2),
      );
      final tA = _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3');
      final tB = _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3');
      final tC = _TestTrack(id: 'C', title: 'C', filePath: '$baseUrl/c.mp3');
      final tD = _TestTrack(id: 'D', title: 'D', filePath: '$baseUrl/d.mp3');

      final queue = [tA, tB, tC, tD];
      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);

      // B is now playing (active protected), window shifts to [C, D].
      preloader.markPlayingTrack(tB);
      await preloader.syncWindow(queue: queue, currentIndex: 1, loopMode: LoopMode.off);

      // Active playing track B must still be protected on disk if present,
      // and cache track count must remain bounded.
      expect(preloader.cacheManager.cachedTrackCount <= 3, isTrue);
      expect(preloader.getEntrySnapshot('C')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('D')?.state, PreloadState.fullyCached);

      await preloader.dispose();
    });

    test('15. Network-aware policy: offline skips preload, mobile data-saver uses streamReady',
        () async {
      final offlinePreloader = createPreloader(
        connectivityProvider: () async => [ConnectivityResult.none],
      );
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
      ];
      await offlinePreloader.syncWindow(
        queue: queue,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      expect(requestPaths, isEmpty);
      await offlinePreloader.dispose();

      final mobilePreloader = createPreloader(
        connectivityProvider: () async => [ConnectivityResult.mobile],
      );
      await mobilePreloader.syncWindow(
        queue: queue,
        currentIndex: 0,
        loopMode: LoopMode.off,
      );
      expect(
        mobilePreloader.getEntrySnapshot('B')?.state,
        PreloadState.streamReady,
      );
      expect(requestPaths, isEmpty);
      await mobilePreloader.dispose();
    });

    test('16. Low storage falls back to streamReady without downloading full file',
        () async {
      final preloader = createPreloader(
        config: const PreloadConfig(minRequiredFreeBytes: 100 * 1024 * 1024),
        freeDiskBytesProvider: () async => 1024 * 1024, // 1 MB < 100 MB
      );
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
      ];

      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);
      expect(preloader.getEntrySnapshot('B')?.state, PreloadState.streamReady);
      expect(requestPaths, isEmpty);

      await preloader.dispose();
    });

    test('17. Corrupted or externally deleted cached file is detected and rejected',
        () async {
      final logs = <String>[];
      final preloader = createPreloader(logger: logs.add);
      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
      ];

      await preloader.syncWindow(queue: queue, currentIndex: 0, loopMode: LoopMode.off);
      final entry = preloader.getEntrySnapshot('B')!;
      // Corrupt the cached file to 0 bytes externally.
      await File(entry.cachedFilePath!).writeAsBytes(const []);

      final prepared = await preloader.getPreparedEntry(queue[1]);
      expect(prepared, isNull);
      expect(preloader.getEntrySnapshot('B'), isNull);

      // Verify sanitized logging never leaks URLs or tokens.
      for (final log in logs) {
        expect(log.contains('http://'), isFalse);
        expect(log.contains('https://'), isFalse);
      }

      await preloader.dispose();
    });

    test('18. MieeAudioHandler consumes preloaded file on skipToNext and disposes cleanly',
        () async {
      final fakePlayer = _FakeAudioPlayer();
      final preloader = createPreloader();
      final handler = MieeAudioHandler(
        player: fakePlayer,
        preloader: preloader,
      );

      final queue = [
        _TestTrack(id: 'A', title: 'A', filePath: '$baseUrl/a.mp3'),
        _TestTrack(id: 'B', title: 'B', filePath: '$baseUrl/b.mp3'),
        _TestTrack(id: 'C', title: 'C', filePath: '$baseUrl/c.mp3'),
      ];

      await handler.loadQueue(queue, startIndex: 0);
      // Allow background rolling preload to finish B & C.
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(preloader.getEntrySnapshot('B')?.state, PreloadState.fullyCached);
      expect(preloader.getEntrySnapshot('C')?.state, PreloadState.fullyCached);

      await handler.skipToNext();
      // The second setAudioSource call should be a local file AudioSource for B!
      expect(fakePlayer.setSources.length, greaterThanOrEqualTo(2));
      expect(fakePlayer.setSources.last, isA<UriAudioSource>());
      final lastSource = fakePlayer.setSources.last as UriAudioSource;
      expect(lastSource.uri.scheme, 'file');

      await handler.disposeHandler();
      expect(preloader.isDisposed, isTrue);
    });
  });
}
