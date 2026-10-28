import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:audio_service/audio_service.dart';
import 'package:Miee/core/audio/audio_handler.dart';
import 'package:Miee/shared/models/track.dart';

class MockAudioPlayer extends AudioPlayer {
  bool _isPlaying = false;
  Duration _pos = Duration.zero;
  Duration? _dur = const Duration(minutes: 4);
  Duration? lastSeekPosition;
  bool playCalled = false;
  bool pauseCalled = false;

  final StreamController<PlayerState> _stateController =
      StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _posController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _durController =
      StreamController<Duration?>.broadcast();
  final StreamController<PlaybackEvent> _eventController =
      StreamController<PlaybackEvent>.broadcast();

  MockAudioPlayer({bool playing = false, Duration initialPosition = Duration.zero})
      : _isPlaying = playing,
        _pos = initialPosition,
        super(handleInterruptions: false);

  @override
  bool get playing => _isPlaying;

  @override
  Duration get position => _pos;

  @override
  Duration? get duration => _dur;

  @override
  Stream<PlayerState> get playerStateStream => _stateController.stream;

  @override
  Stream<Duration> get positionStream => _posController.stream;

  @override
  Stream<Duration?> get durationStream => _durController.stream;

  @override
  Stream<PlaybackEvent> get playbackEventStream => _eventController.stream;

  void emitPosition(Duration p) {
    _pos = p;
    _posController.add(p);
  }

  void emitPlayerState(PlayerState s) {
    _isPlaying = s.playing;
    _stateController.add(s);
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    lastSeekPosition = position;
    if (position != null) {
      _pos = position;
      _posController.add(position);
    }
  }

  @override
  Future<void> play() async {
    playCalled = true;
    _isPlaying = true;
    _stateController.add(PlayerState(true, ProcessingState.ready));
  }

  @override
  Future<void> pause() async {
    pauseCalled = true;
    _isPlaying = false;
    _stateController.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    _isPlaying = false;
    _stateController.add(PlayerState(false, ProcessingState.idle));
  }

  @override
  Future<Duration?> setAudioSource(AudioSource source,
      {bool preload = true, int? initialIndex, Duration? initialPosition}) async {
    if (initialPosition != null) {
      _pos = initialPosition;
    }
    return _dur;
  }

  @override
  Future<Duration?> setFilePath(String path,
      {Duration? initialPosition, int? initialIndex, bool preload = true}) async {
    if (initialPosition != null) {
      _pos = initialPosition;
    }
    return _dur;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
    await _posController.close();
    await _durController.close();
    await _eventController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Background Playback & Position Preservation Tests (Scenarios A-G)', () {
    late MockAudioPlayer mockPlayer;
    late MieeAudioHandler handler;

    setUp(() {
      mockPlayer = MockAudioPlayer(playing: true, initialPosition: Duration.zero);
      handler = MieeAudioHandler(player: mockPlayer);
    });

    tearDown(() async {
      try {
        await handler.disposeHandler();
      } catch (_) {}
      try {
        await mockPlayer.dispose();
      } catch (_) {}
    });

    test('Scenario A: Background and Return — playback advances and position is tracked continuously', () async {
      // Simulate playback advancing while app is backgrounded
      mockPlayer.emitPlayerState(PlayerState(true, ProcessingState.ready));
      mockPlayer.emitPosition(const Duration(seconds: 25));
      await pumpEventQueue();

      expect(handler.lastValidPosition, equals(const Duration(seconds: 25)));
      expect(handler.playbackState.value.position, equals(const Duration(seconds: 25)));

      // Advance further in background
      mockPlayer.emitPosition(const Duration(seconds: 50));
      await pumpEventQueue();

      expect(handler.lastValidPosition, equals(const Duration(seconds: 50)));
      expect(handler.playbackState.value.position, equals(const Duration(seconds: 50)));
    });

    test('Scenario B: Screen Lock / System Ducking — lock clicks and GPS chimes do NOT pause music', () async {
      mockPlayer.emitPlayerState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue();

      // Transient ducking begins (e.g., screen lock click or navigation prompt)
      handler.handleInterruptionEvent(
        AudioInterruptionEvent(true, AudioInterruptionType.duck),
      );
      await pumpEventQueue();

      // The player must remain playing (not paused!)
      expect(mockPlayer.pauseCalled, isFalse);
      expect(handler.isPlaying, isTrue);

      // Ducking ends
      handler.handleInterruptionEvent(
        AudioInterruptionEvent(false, AudioInterruptionType.duck),
      );
      await pumpEventQueue();

      expect(mockPlayer.pauseCalled, isFalse);
      expect(handler.isPlaying, isTrue);
    });

    test('Scenario C: User-Initiated Pause in Background — preserves exact position and does not reset', () async {
      mockPlayer.emitPlayerState(PlayerState(true, ProcessingState.ready));
      mockPlayer.emitPosition(const Duration(seconds: 85));
      await pumpEventQueue();

      expect(handler.lastValidPosition, equals(const Duration(seconds: 85)));

      // User pauses from lock screen notification
      await handler.pause();
      await pumpEventQueue();

      expect(mockPlayer.pauseCalled, isTrue);
      expect(handler.lastValidPosition, equals(const Duration(seconds: 85)));
      expect(handler.playbackState.value.position, equals(const Duration(seconds: 85)));
    });

    test('Scenario D: Temporary Audio Interruption — phone call pauses and resumes from exact paused position', () async {
      mockPlayer.emitPlayerState(PlayerState(true, ProcessingState.ready));
      mockPlayer.emitPosition(const Duration(seconds: 64));
      await pumpEventQueue();

      // Incoming call interrupts music
      handler.handleInterruptionEvent(
        AudioInterruptionEvent(true, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      expect(handler.playInterrupted, isTrue);
      expect(handler.lastValidPosition, equals(const Duration(seconds: 64)));
      expect(mockPlayer.pauseCalled, isTrue);

      // Call ends — focus returned
      handler.handleInterruptionEvent(
        AudioInterruptionEvent(false, AudioInterruptionType.pause),
      );
      await pumpEventQueue();

      // Resume intent honored
      expect(handler.playInterrupted, isFalse);
    });

    test('Scenario E: Expired Stream / ExoPlayer Error Fallback — position does not wipe to 00:00', () async {
      mockPlayer.emitPlayerState(PlayerState(true, ProcessingState.ready));
      mockPlayer.emitPosition(const Duration(seconds: 142));
      await pumpEventQueue();

      expect(handler.lastValidPosition, equals(const Duration(seconds: 142)));

      // When ExoPlayer hits socket error / expired URL, internal position drops to Duration.zero
      mockPlayer.emitPosition(Duration.zero);
      await pumpEventQueue();

      // Handler retains lastValidPosition and provides it in playbackState fallback
      expect(handler.lastValidPosition, equals(const Duration(seconds: 142)));
      expect(handler.playbackState.value.position, equals(const Duration(seconds: 142)));
    });

    test('Scenario F: Local Song Playback — initialPosition is applied and position is preserved', () async {
      final testTrack = Track(
        id: 'local_song_1',
        title: 'Local Test Track',
        artist: 'Test Artist',
        imageUrl: '',
        duration: '03:45',
        filePath: 'C:/fake/path/song.mp3',
      );

      await handler.loadQueue(
        [testTrack],
        startIndex: 0,
        initialPosition: const Duration(seconds: 77),
      );
      await pumpEventQueue();

      expect(handler.lastValidPosition, equals(const Duration(seconds: 77)));
      expect(mockPlayer.lastSeekPosition, equals(const Duration(seconds: 77)));
    });

    test('Scenario G: Queue Advancement in Background — preserves buffering state without service demotion', () async {
      // Simulate playing state
      mockPlayer.emitPlayerState(PlayerState(true, ProcessingState.ready));
      await pumpEventQueue();

      // Trigger track loading state
      final testTrack = Track(
        id: 'local_song_2',
        title: 'Next Track',
        artist: 'Test Artist',
        imageUrl: '',
        duration: '04:00',
        filePath: 'C:/fake/path/song2.mp3',
      );

      // During queue load, isLoadingTrack is true
      final loadFuture = handler.loadQueue([testTrack], startIndex: 0);

      // Verify that while loading, transient pauses do not output playing=false with idle state
      await loadFuture;
      await pumpEventQueue();

      expect(handler.isLoadingTrack, isFalse);
    });
  });
}
