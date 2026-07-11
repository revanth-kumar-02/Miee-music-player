import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../../shared/models/music_item.dart';

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
    mediaItem.add(_trackToMediaItem(track));
    _pushPlaybackState(playerState: PlayerState(false, ProcessingState.loading));
    try {
      final path = track.filePath;
      if (path.isNotEmpty && !path.startsWith('http')) {
        // Local file — use AudioSource.file for proper URI handling on Android
        await _player.setAudioSource(AudioSource.file(path));
      } else if (path.isNotEmpty) {
        // Remote URL (YouTube stream etc.)
        await _player.setUrl(path);
      } else {
        // No valid source — emit error state so the UI can react
        debugPrint('MieeAudioHandler: track "${track.title}" has no filePath');
        playbackState.add(
          playbackState.value.copyWith(processingState: AudioProcessingState.error),
        );
        return;
      }
    } catch (e, stack) {
      debugPrint('MieeAudioHandler: _loadCurrentTrack error: $e\n$stack');
      playbackState.add(
        playbackState.value.copyWith(processingState: AudioProcessingState.error),
      );
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
  Future<void> play() async => _player.play();

  @override
  Future<void> pause() async => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _loadCurrentTrack();
      await _player.play();
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
      await _loadCurrentTrack();
      await _player.play();
    } else {
      await _player.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await _loadCurrentTrack();
    await _player.play();
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
    await _player.dispose();
  }
}
