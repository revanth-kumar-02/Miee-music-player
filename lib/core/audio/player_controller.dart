import 'dart:async';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import '../../shared/models/mock_data.dart';
import '../../shared/models/track.dart';
import 'audio_player_service.dart';
import 'playback_state.dart';
import 'queue_manager.dart';

/// Single orchestrator class managing playback state notifications,
/// routing events between [AudioPlayerService] streams and [QueueManager] queues.
class PlayerController extends StateNotifier<PlaybackState> {
  final AudioPlayerService _service;
  final QueueManager _queueManager;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  PlayerController(this._service, this._queueManager) : super(PlaybackState.initial()) {
    _init();
  }

  void _init() {
    // Bootstrap the player controller with the mock featured track
    _queueManager.setQueue([
      MockData.featuredTrack,
      ...MockData.favoriteSongs,
    ]);

    state = PlaybackState(
      status: PlaybackStatus.paused,
      currentTrack: MockData.featuredTrack,
      duration: const Duration(minutes: 2, seconds: 52), // matching mock duration
    );

    // Listen to positions, durations, and status updates
    _positionSub = _service.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
    });

    _durationSub = _service.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    _bufferedSub = _service.bufferedPositionStream.listen((buf) {
      state = state.copyWith(bufferedPosition: buf);
    });

    _playerStateSub = _service.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      PlaybackStatus status = PlaybackStatus.idle;

      switch (processingState) {
        case ProcessingState.idle:
          status = PlaybackStatus.idle;
          break;
        case ProcessingState.loading:
          status = PlaybackStatus.loading;
          break;
        case ProcessingState.buffering:
          status = PlaybackStatus.buffering;
          break;
        case ProcessingState.ready:
          status = isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused;
          break;
        case ProcessingState.completed:
          status = PlaybackStatus.completed;
          break;
      }

      state = state.copyWith(status: status);

      // Handle auto-advance on playback completion
      if (status == PlaybackStatus.completed) {
        if (state.repeatMode == RepeatMode.one) {
          seek(Duration.zero);
          play();
        } else {
          next();
        }
      }
    });
  }

  /// Sets the active queue.
  void setQueue(List<Track> tracks, {int startIndex = 0}) {
    _queueManager.setQueue(tracks, startIndex: startIndex);
    final track = _queueManager.currentTrack;
    if (track != null) {
      playTrack(track);
    }
  }

  /// Selects a track from a list, updates the queue, and begins playback.
  void selectTrack(Track track, List<Track> currentList) {
    final index = currentList.indexWhere((t) => t.id == track.id);
    setQueue(currentList, startIndex: index >= 0 ? index : 0);
  }

  /// Plays a specific track. If filePath is not available, streams a fallback audio test link.
  Future<void> playTrack(Track track) async {
    state = state.copyWith(
      status: PlaybackStatus.loading,
      currentTrack: track,
      position: Duration.zero,
    );

    try {
      final source = track.filePath ?? 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3';
      await _service.setSource(source);
      await _service.play();
    } catch (e) {
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Play current track.
  Future<void> play() async {
    if (state.status == PlaybackStatus.idle && state.currentTrack != null) {
      await playTrack(state.currentTrack!);
    } else {
      await _service.play();
    }
  }

  /// Pause current track.
  Future<void> pause() async {
    await _service.pause();
  }

  /// Stop playback.
  Future<void> stop() async {
    await _service.stop();
    state = state.copyWith(
      status: PlaybackStatus.idle,
      position: Duration.zero,
    );
  }

  /// Seek to custom timestamp.
  Future<void> seek(Duration position) async {
    await _service.seek(position);
  }

  /// Skips to the next track.
  Future<void> next() async {
    if (state.isShuffleEnabled) {
      final queue = _queueManager.queue;
      if (queue.length > 1) {
        final random = Random();
        int nextIndex = _queueManager.currentIndex;
        while (nextIndex == _queueManager.currentIndex) {
          nextIndex = random.nextInt(queue.length);
        }
        _queueManager.setIndex(nextIndex);
        final nextTrack = _queueManager.currentTrack;
        if (nextTrack != null) {
          await playTrack(nextTrack);
        }
        return;
      }
    }

    final nextTrack = _queueManager.next();
    if (nextTrack != null) {
      await playTrack(nextTrack);
    } else {
      // Loop back to index 0 if RepeatMode.all is active
      if (state.repeatMode == RepeatMode.all && _queueManager.queue.isNotEmpty) {
        _queueManager.setIndex(0);
        final firstTrack = _queueManager.currentTrack;
        if (firstTrack != null) {
          await playTrack(firstTrack);
        }
      }
    }
  }

  /// Skips to the previous track.
  Future<void> previous() async {
    // Restart song if played for more than 3 seconds
    if (state.position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }

    if (state.isShuffleEnabled) {
      final queue = _queueManager.queue;
      if (queue.length > 1) {
        final random = Random();
        int prevIndex = _queueManager.currentIndex;
        while (prevIndex == _queueManager.currentIndex) {
          prevIndex = random.nextInt(queue.length);
        }
        _queueManager.setIndex(prevIndex);
        final prevTrack = _queueManager.currentTrack;
        if (prevTrack != null) {
          await playTrack(prevTrack);
        }
        return;
      }
    }

    final prevTrack = _queueManager.previous();
    if (prevTrack != null) {
      await playTrack(prevTrack);
    } else {
      // Wrap around to end if RepeatMode.all is active
      if (state.repeatMode == RepeatMode.all && _queueManager.queue.isNotEmpty) {
        _queueManager.setIndex(_queueManager.queue.length - 1);
        final lastTrack = _queueManager.currentTrack;
        if (lastTrack != null) {
          await playTrack(lastTrack);
        }
      }
    }
  }

  /// Toggles shuffle mode.
  void toggleShuffle() {
    final isShuffle = !state.isShuffleEnabled;
    state = state.copyWith(isShuffleEnabled: isShuffle);
  }

  /// Toggles repeat mode.
  void toggleRepeatMode() {
    RepeatMode nextMode;
    switch (state.repeatMode) {
      case RepeatMode.off:
        nextMode = RepeatMode.all;
        break;
      case RepeatMode.all:
        nextMode = RepeatMode.one;
        break;
      case RepeatMode.one:
        nextMode = RepeatMode.off;
        break;
    }
    state = state.copyWith(repeatMode: nextMode);
  }

  /// Clears the active queue.
  void clearQueue() {
    _queueManager.clear();
    state = state.copyWith(
      currentTrack: null,
      status: PlaybackStatus.idle,
      position: Duration.zero,
      duration: Duration.zero,
    );
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedSub?.cancel();
    _playerStateSub?.cancel();
    super.dispose();
  }
}
