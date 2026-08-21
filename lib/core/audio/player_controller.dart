import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart' hide PlaybackState;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../shared/models/music_item.dart';
import 'audio_handler.dart';
import 'online_playback_service.dart';
import 'youtube_player_widget.dart';
import 'playback_state.dart';
import 'queue_manager.dart';
import '../../features/media/providers/media_providers.dart';
import '../../features/media/domain/models.dart';
import '../../features/youtube/providers/youtube_providers.dart';
import '../../features/library/providers/library_providers.dart';

/// Single orchestrator bridging local [MieeAudioHandler] and [OnlinePlaybackService]
/// with unified Riverpod state.
class PlayerController extends StateNotifier<PlaybackState> {
  final MieeAudioHandler _handler;
  final QueueManager _queueManager;
  final Ref _ref;
  final OnlinePlaybackService _onlineService;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<String>? _errorSub;

  StreamSubscription<Duration>? _onlinePosSub;
  StreamSubscription<Duration>? _onlineDurSub;
  StreamSubscription<bool>? _onlinePlayingSub;
  StreamSubscription<String?>? _onlineErrorSub;

  PlayerController(this._handler, this._queueManager, this._ref)
      : _onlineService = createOnlinePlaybackService(),
        super(PlaybackState.initial()) {
    _init();
  }

  void _init() {
    _queueManager.setQueue([]);
    state = PlaybackState.initial();

    // 1. Mirror local audio handler streams into Riverpod state
    _positionSub = _handler.positionStream.listen((pos) {
      if (state.currentTrack != null && !state.currentTrack!.isYoutube) {
        if (state.status == PlaybackStatus.error && pos > Duration.zero) {
          state = state.copyWith(status: PlaybackStatus.playing, errorMessage: null);
        }
        state = state.copyWith(position: pos);
      }
    });

    _durationSub = _handler.durationStream.listen((dur) {
      if (state.currentTrack != null && !state.currentTrack!.isYoutube && dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    _bufferedSub = _handler.bufferedPositionStream.listen((buf) {
      if (state.currentTrack != null && !state.currentTrack!.isYoutube) {
        state = state.copyWith(bufferedPosition: buf);
      }
    });

    _errorSub = _handler.errorStream.listen((errorMsg) {
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: errorMsg,
      );
    });

    _mediaItemSub = _handler.mediaItem.listen((mediaItem) {
      if (mediaItem != null) {
        final queue = _queueManager.queue;
        final index = queue.indexWhere((t) => t.id == mediaItem.id);
        if (index >= 0) {
          state = state.copyWith(currentTrack: queue[index]);
        }
      }
    });

    _playerStateSub = _handler.playerStateStream.listen((playerState) {
      if (state.currentTrack != null && state.currentTrack!.isYoutube) return;

      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      PlaybackStatus status;
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

      if (status == PlaybackStatus.completed) {
        if (state.repeatMode == RepeatMode.one) {
          seek(Duration.zero);
          play();
        } else {
          next();
        }
      }
    });

    // 2. Mirror online YouTube player streams into Riverpod state
    _onlinePosSub = _onlineService.positionStream.listen((pos) {
      if (state.currentTrack != null && state.currentTrack!.isYoutube) {
        state = state.copyWith(position: pos);
      }
    });

    _onlineDurSub = _onlineService.durationStream.listen((dur) {
      if (state.currentTrack != null && state.currentTrack!.isYoutube) {
        state = state.copyWith(duration: dur);
      }
    });

    _onlinePlayingSub = _onlineService.isPlayingStream.listen((isPlaying) {
      if (state.currentTrack != null && state.currentTrack!.isYoutube) {
        state = state.copyWith(
          status: isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
        );
      }
    });

    _onlineErrorSub = _onlineService.errorStream.listen((err) {
      if (err != null) {
        state = state.copyWith(
          status: PlaybackStatus.error,
          errorMessage: err,
        );
      }
    });
  }

  // -- Queue management --------------------------------------------------------

  void setQueue(List<MusicItem> tracks, {int startIndex = 0}) {
    _queueManager.setQueue(tracks, startIndex: startIndex);
    final track = _queueManager.currentTrack;
    if (track != null) {
      playTrack(track);
    }
  }

  void selectTrack(MusicItem track, List<MusicItem> currentList) {
    final index = currentList.indexWhere((t) => t.id == track.id);
    setQueue(currentList, startIndex: index >= 0 ? index : 0);
  }

  // -- Playback ----------------------------------------------------------------

  Future<void> playTrack(MusicItem track) async {
    state = state.copyWith(
      status: PlaybackStatus.loading,
      currentTrack: track,
      position: Duration.zero,
      errorMessage: null,
    );

    try {
      final resolvedTrack = await _resolveSource(track);

      final index = _queueManager.currentIndex;
      if (index >= 0 && index < _queueManager.queue.length) {
        _queueManager.replaceTrackAt(index, resolvedTrack);
      }

      state = state.copyWith(currentTrack: resolvedTrack);

      if (resolvedTrack.isYoutube) {
        // YouTube track -> use OnlinePlaybackService
        await _handler.pause();
        final videoId = resolvedTrack.id.startsWith('youtube_')
            ? resolvedTrack.id.replaceFirst('youtube_', '')
            : resolvedTrack.id;

        await _onlineService.loadVideo(videoId);
        await _onlineService.play();
        state = state.copyWith(status: PlaybackStatus.playing);
      } else {
        // Local track -> use MieeAudioHandler / just_audio
        await _onlineService.stop();
        final queue = _queueManager.queue;
        await _handler.loadQueue(queue, startIndex: index >= 0 ? index : 0);
        await _handler.play();
      }
    } catch (e) {
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<MusicItem> _resolveSource(MusicItem track) async {
    final mode = _ref.read(sourceSelectionProvider);

    if (mode == 'preferLocal' || mode == 'smart' || mode == 'alwaysLocal') {
      if (!track.isYoutube) return track;
      final localMatch = _findLocalVersion(track.title, track.artist);
      if (localMatch != null) return localMatch;
      return track;
    }

    if (mode == 'preferYouTube' || mode == 'alwaysYouTube') {
      if (track.isYoutube) return track;
      final ytMatch = await _findYouTubeVersion(track.title, track.artist);
      if (ytMatch != null) return ytMatch;
      return track;
    }

    final localMatch = _findLocalVersion(track.title, track.artist);
    if (localMatch != null) return localMatch;
    return track;
  }

  MediaSong? _findLocalVersion(String title, String artist) {
    try {
      final localSongs = _ref.read(songsProvider);
      final cleanTitle = title.trim().toLowerCase();
      final cleanArtist = artist.trim().toLowerCase();

      for (final song in localSongs) {
        if (song.title.trim().toLowerCase() == cleanTitle &&
            song.artist.trim().toLowerCase() == cleanArtist) {
          return song;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<MusicItem?> _findYouTubeVersion(String title, String artist) async {
    try {
      final repo = _ref.read(youtubeRepositoryProvider);
      final query = '$title $artist';
      final results = await repo.search(query);
      if (results.isNotEmpty) return results.first;
    } catch (_) {}
    return null;
  }

  Future<void> play() async {
    if (state.currentTrack != null && state.currentTrack!.isYoutube) {
      await _onlineService.play();
      state = state.copyWith(status: PlaybackStatus.playing);
    } else {
      if (state.status == PlaybackStatus.idle && state.currentTrack != null) {
        await playTrack(state.currentTrack!);
      } else {
        await _handler.play();
      }
    }
  }

  Future<void> pause() async {
    if (state.currentTrack != null && state.currentTrack!.isYoutube) {
      await _onlineService.pause();
      state = state.copyWith(status: PlaybackStatus.paused);
    } else {
      await _handler.pause();
    }
  }

  Future<void> stop() async {
    await _onlineService.stop();
    await _handler.stop();
    state = state.copyWith(status: PlaybackStatus.idle, position: Duration.zero);
  }

  Future<void> seek(Duration position) async {
    if (state.currentTrack != null && state.currentTrack!.isYoutube) {
      await _onlineService.seek(position);
    } else {
      await _handler.seek(position);
    }
    state = state.copyWith(position: position);
  }

  // -- Navigation --------------------------------------------------------------

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
        if (nextTrack != null) await playTrack(nextTrack);
        return;
      }
    }

    final nextTrack = _queueManager.next();
    if (nextTrack != null) {
      await playTrack(nextTrack);
    } else if (state.repeatMode == RepeatMode.all && _queueManager.queue.isNotEmpty) {
      _queueManager.setIndex(0);
      final firstTrack = _queueManager.currentTrack;
      if (firstTrack != null) await playTrack(firstTrack);
    }
  }

  Future<void> previous() async {
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
        if (prevTrack != null) await playTrack(prevTrack);
        return;
      }
    }

    final prevTrack = _queueManager.previous();
    if (prevTrack != null) {
      await playTrack(prevTrack);
    } else if (state.repeatMode == RepeatMode.all && _queueManager.queue.isNotEmpty) {
      final lastIdx = _queueManager.queue.length - 1;
      _queueManager.setIndex(lastIdx);
      final lastTrack = _queueManager.currentTrack;
      if (lastTrack != null) await playTrack(lastTrack);
    }
  }

  // -- Modes -------------------------------------------------------------------

  Future<void> toggleShuffle() async {
    final isShuffle = !state.isShuffleEnabled;
    state = state.copyWith(isShuffleEnabled: isShuffle);
    await _handler.setShuffleMode(
      isShuffle ? AudioServiceShuffleMode.all : AudioServiceShuffleMode.none,
    );
  }

  Future<void> toggleRepeatMode() async {
    RepeatMode nextMode = RepeatMode.off;
    AudioServiceRepeatMode serviceMode = AudioServiceRepeatMode.none;

    switch (state.repeatMode) {
      case RepeatMode.off:
        nextMode = RepeatMode.all;
        serviceMode = AudioServiceRepeatMode.all;
        break;
      case RepeatMode.all:
        nextMode = RepeatMode.one;
        serviceMode = AudioServiceRepeatMode.one;
        break;
      case RepeatMode.one:
        nextMode = RepeatMode.off;
        serviceMode = AudioServiceRepeatMode.none;
        break;
    }

    state = state.copyWith(repeatMode: nextMode);
    await _handler.setRepeatMode(serviceMode);
  }

  Future<void> addTrackToQueue(MusicItem track) async {
    _queueManager.addTrack(track);
    await _handler.appendTrack(track);
    if (state.currentTrack == null) {
      await playTrack(track);
    }
  }

  Future<void> removeTrackAt(int index) async {
    _queueManager.removeTrackAt(index);
    await _handler.removeTrackAt(index);
    if (_queueManager.queue.isEmpty) {
      clearQueue();
    } else {
      final current = _queueManager.currentTrack;
      if (state.currentTrack != current) {
        state = state.copyWith(currentTrack: current);
      }
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    _queueManager.reorder(oldIndex, newIndex);
    await _handler.reorderQueue(oldIndex, newIndex);
    state = state.copyWith(currentTrack: _queueManager.currentTrack);
  }

  void clearQueue() {
    _queueManager.clear();
    _onlineService.stop();
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
    _mediaItemSub?.cancel();
    _errorSub?.cancel();

    _onlinePosSub?.cancel();
    _onlineDurSub?.cancel();
    _onlinePlayingSub?.cancel();
    _onlineErrorSub?.cancel();
    _onlineService.dispose();
    super.dispose();
  }
}
