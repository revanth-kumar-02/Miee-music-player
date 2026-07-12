import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../shared/models/music_item.dart';
import 'youtube_audio_resolver.dart';

/// Duration for fast-forward and rewind operations.
const _kSkipDuration = Duration(seconds: 10);

/// [MieeAudioHandler] is the single audio engine for Miee.
///
/// It subclasses [BaseAudioHandler] from `audio_service` to:
/// - Provide a persistent foreground service with a media-style notification.
/// - Route system/Bluetooth/headset media button events.
/// - Expose the current [MediaItem] (title, artist, artwork) to the OS.
/// - Maintain audio focus via `audio_session`.
///
/// All UI components communicate with this handler indirectly through
/// [PlayerController] which observes its [playbackState] and [mediaItem] streams.
class MieeAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  /// Current ordered queue of tracks.
  final List<MusicItem> _queue = [];
  int _currentIndex = -1;

  /// Controller to stream playback/resolution errors to PlayerController.
  final StreamController<String> _errorController = StreamController<String>.broadcast();
  Stream<String> get errorStream => _errorController.stream;

  // Stream subscriptions
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  MieeAudioHandler() {
    _listenToPlayerStreams();
    queue.add([]);
    debugPrint('STARTUP: MieeAudioHandler() constructed');
  }

  /// Must be called once after [AudioService.init] completes.
  ///
  /// Configures the audio session for music playback and wires up
  /// interruption/noise-becoming-noisy handlers. Calling this from
  /// inside the constructor while [AudioService.init] is still running
  /// creates a deadlock — [AudioSession.instance] waits for audio focus
  /// from the same foreground service that is still being initialized.
  Future<void> initialize() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _player.pause();
        } else {
          if (event.type == AudioInterruptionType.pause ||
              event.type == AudioInterruptionType.duck) {
            _player.play();
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) => _player.pause());
      debugPrint('STARTUP: MieeAudioHandler.initialize() done');
    } catch (e) {
      debugPrint('STARTUP: MieeAudioHandler.initialize() error: $e');
    }
  }

  void _listenToPlayerStreams() {
    _playerStateSub = _player.playerStateStream.listen(_onPlayerStateChanged);
    _positionSub = _player.positionStream.listen(_onPositionChanged);
    _durationSub = _player.durationStream.listen(_onDurationChanged);
  }

  void _onPlayerStateChanged(PlayerState playerState) {
    _pushPlaybackState(playerState: playerState);
    if (playerState.processingState == ProcessingState.completed) {
      skipToNext();
    }
  }

  void _onPositionChanged(Duration position) {
    _pushPlaybackState();
  }

  void _onDurationChanged(Duration? duration) {
    final current = mediaItem.value;
    if (current != null && duration != null) {
      mediaItem.add(current.copyWith(duration: duration));
    }
  }

  void _pushPlaybackState({PlayerState? playerState}) {
    final ps = playerState ?? PlayerState(_player.playing, _player.processingState);
    final isPlaying = ps.playing;
    final processingState = ps.processingState;

    AudioProcessingState audioProcessingState;
    switch (processingState) {
      case ProcessingState.idle:
        audioProcessingState = AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        audioProcessingState = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        audioProcessingState = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        audioProcessingState = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        audioProcessingState = AudioProcessingState.completed;
        break;
    }

    final controls = [
      MediaControl.skipToPrevious,
      if (isPlaying) MediaControl.pause else MediaControl.play,
      MediaControl.skipToNext,
    ];

    const systemActions = {
      MediaAction.seek,
      MediaAction.seekForward,
      MediaAction.seekBackward,
      MediaAction.setRepeatMode,
      MediaAction.setShuffleMode,
    };

    playbackState.add(
      PlaybackState(
        controls: controls,
        systemActions: systemActions,
        processingState: audioProcessingState,
        playing: isPlaying,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _currentIndex,
      ),
    );
  }

  Future<void> loadQueue(List<MusicItem> tracks, {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    queue.add(_queue.map(_trackToMediaItem).toList());
    await _loadCurrentTrack();
  }

  Future<void> appendTrack(MusicItem track) async {
    _queue.add(track);
    queue.add(_queue.map(_trackToMediaItem).toList());
  }

  Future<void> removeTrackAt(int index) async {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
      queue.add(_queue.map(_trackToMediaItem).toList());
    }
  }

  Future<void> _loadCurrentTrack() async {
    if (_queue.isEmpty || _currentIndex < 0) return;
    final track = _queue[_currentIndex];
    debugPrint('PLAYBACK: Selected Track ID: ${track.id}, Title: "${track.title}" by "${track.artist}"');
    mediaItem.add(_trackToMediaItem(track));
    _pushPlaybackState(playerState: PlayerState(false, ProcessingState.loading));
    try {
      final path = track.filePath;
      if (track.isYoutube) {
        // Resolve the actual audio stream URL from the YouTube video ID.
        final videoId = track.id.startsWith('youtube_')
            ? track.id.replaceFirst('youtube_', '')
            : path.contains('watch?v=')
                ? Uri.parse(path).queryParameters['v'] ?? track.id
                : track.id;
        
        debugPrint('PLAYBACK: YouTube Video ID parsed: $videoId');
        debugPrint('PLAYBACK: Fetching stream manifest for YouTube ID: $videoId...');
        
        String audioUrl = await YouTubeAudioResolver.instance.resolve(videoId);
        debugPrint('PLAYBACK: Selected audio stream URL: $audioUrl');
        
        try {
          debugPrint('PLAYBACK: Loading audio URL into just_audio with browser headers...');
          await _player.setUrl(
            audioUrl,
            headers: {
              'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
              'Accept': '*/*',
              'Connection': 'keep-alive',
            },
          );
        } catch (loadErr) {
          debugPrint('PLAYBACK WARNING: Initial setUrl failed: $loadErr. Clearing video cache and retrying...');
          YouTubeAudioResolver.instance.clearVideoCache(videoId);
          
          audioUrl = await YouTubeAudioResolver.instance.resolve(videoId);
          debugPrint('PLAYBACK: Retrying selected audio stream URL: $audioUrl');
          
          await _player.setUrl(
            audioUrl,
            headers: {
              'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1',
              'Accept': '*/*',
              'Connection': 'keep-alive',
            },
          );
        }
        
        debugPrint('PLAYBACK: Audio source loaded successfully for YouTube ID: $videoId');
      } else if (path.isNotEmpty && !path.startsWith('http')) {
        debugPrint('PLAYBACK: Loading local file audio source: $path');
        await _player.setAudioSource(AudioSource.file(path));
        debugPrint('PLAYBACK: Local audio source loaded successfully.');
      } else if (path.isNotEmpty) {
        debugPrint('PLAYBACK: Loading remote URL audio source: $path');
        await _player.setUrl(path);
        debugPrint('PLAYBACK: Remote audio source loaded successfully.');
      } else {
        throw Exception('Track "${track.title}" has no valid file path or source.');
      }
    } on PlayerException catch (e, stack) {
      debugPrint('PLAYBACK ERROR: just_audio PlayerException! Code: ${e.code}, Message: ${e.message}');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      playbackState.add(
        playbackState.value.copyWith(processingState: AudioProcessingState.error),
      );
      _errorController.add('Playback Error: ${e.message} (Code: ${e.code})');
      rethrow;
    } catch (e, stack) {
      debugPrint('PLAYBACK ERROR: _loadCurrentTrack failed: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      
      playbackState.add(
        playbackState.value.copyWith(processingState: AudioProcessingState.error),
      );
      _errorController.add(e.toString().replaceFirst('Exception: ', ''));
      rethrow; // Propagate exception to playTrack
    }
  }

  MediaItem _trackToMediaItem(MusicItem track) {
    Uri? artUri;
    if (track.imageUrl.isNotEmpty) {
      if (track.imageUrl.startsWith('http')) {
        artUri = Uri.parse(track.imageUrl);
      } else {
        artUri = Uri.file(track.imageUrl);
      }
    }
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      artUri: artUri,
      extras: {'filePath': track.filePath},
    );
  }

  @override
  Future<void> play() async {
    debugPrint('PLAYBACK: play() called. Player status: playing=${_player.playing}, processingState=${_player.processingState}');
    try {
      await _player.play();
      debugPrint('PLAYBACK: Playback started successfully.');
    } catch (e, stack) {
      debugPrint('PLAYBACK ERROR: play() failed: $e');
      if (kDebugMode) debugPrintStack(stackTrace: stack);
      _errorController.add(e.toString().replaceFirst('Exception: ', ''));
      rethrow;
    }
  }

  @override
  Future<void> pause() async {
    debugPrint('PLAYBACK: pause() called.');
    await _player.pause();
  }

  @override
  Future<void> stop() async {
    debugPrint('PLAYBACK: stop() called.');
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    debugPrint('PLAYBACK: seek() called to: $position');
    await _player.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('PLAYBACK ERROR: skipToNext failed: $e');
      }
    } else {
      await _player.stop();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return;
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
      try {
        await _loadCurrentTrack();
        await play();
      } catch (e) {
        debugPrint('PLAYBACK ERROR: skipToPrevious failed: $e');
      }
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    try {
      await _loadCurrentTrack();
      await play();
    } catch (e) {
      debugPrint('PLAYBACK ERROR: skipToQueueItem failed: $e');
    }
  }

  @override
  Future<void> fastForward() async {
    final target = _player.position + _kSkipDuration;
    final duration = _player.duration ?? Duration.zero;
    await _player.seek(target < duration ? target : duration);
  }

  @override
  Future<void> rewind() async {
    final target = _player.position - _kSkipDuration;
    await _player.seek(target > Duration.zero ? target : Duration.zero);
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    LoopMode loopMode;
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        loopMode = LoopMode.off;
        break;
      case AudioServiceRepeatMode.one:
        loopMode = LoopMode.one;
        break;
      case AudioServiceRepeatMode.all:
      case AudioServiceRepeatMode.group:
        loopMode = LoopMode.all;
        break;
    }
    await _player.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode != AudioServiceShuffleMode.none;
    await _player.setShuffleModeEnabled(enabled);
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  bool get isPlaying => _player.playing;
  Duration get position => _player.position;
  int get currentIndex => _currentIndex;
  List<MusicItem> get currentQueue => List.unmodifiable(_queue);

  void jumpToIndex(int index) {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
    }
  }

  @override
  Future<void> onTaskRemoved() async => stop();

  Future<void> disposeHandler() async {
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _errorController.close();
    await _player.dispose();
  }
}
