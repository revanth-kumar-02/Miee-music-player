import 'dart:async';
import 'dart:math';

import 'package:audio_service/audio_service.dart' hide PlaybackState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../shared/models/music_item.dart';
import 'audio_handler.dart';
import 'playback_state.dart';
import 'queue_manager.dart';
import '../../features/media/providers/media_providers.dart';
import '../../features/media/domain/models.dart';
import '../../features/youtube/providers/youtube_providers.dart';
import '../../features/library/providers/library_providers.dart';

/// Single orchestrator bridging [MieeAudioHandler] with unified Riverpod state.
///
/// CRITICAL DESIGN CONTRACT:
/// [MieeAudioHandler] owns [ProcessingState.completed] and advances the queue
/// via [skipToNext] internally. [PlayerController] must NOT also handle
/// completed → next, as that causes a double-skip (two tracks are skipped).
///
/// [PlayerController] only handles:
/// - RepeatMode.one on completed (seek + play, no skip)
/// - RepeatMode.all wrap-around only when handler signals end-of-queue
class PlayerController extends StateNotifier<PlaybackState> {
  final MieeAudioHandler _handler;
  final QueueManager _queueManager;
  final Ref _ref;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<Duration>? _bufferedSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<MediaItem?>? _mediaItemSub;
  StreamSubscription<String>? _errorSub;

  PlayerController(this._handler, this._queueManager, this._ref)
      : super(PlaybackState.initial()) {
    _init();
  }

  void _init() {
    _queueManager.setQueue([]);
    state = PlaybackState.initial();

    // ── Position stream ───────────────────────────────────────────────────────
    // If the player is actually producing position updates while the UI shows
    // an error, recover the UI state automatically.
    _positionSub = _handler.positionStream.listen((pos) {
      if (state.status == PlaybackStatus.error && pos > Duration.zero) {
        debugLog('[Playback] Position > 0 while in error state — auto-recovering UI');
        state = state.copyWith(
          status: PlaybackStatus.playing,
          clearErrorMessage: true,
        );
      }
      state = state.copyWith(position: pos);
    });

    // ── Duration stream ───────────────────────────────────────────────────────
    _durationSub = _handler.durationStream.listen((dur) {
      if (dur != null && dur > Duration.zero) {
        state = state.copyWith(duration: dur);
      }
    });

    // ── Buffered position stream ──────────────────────────────────────────────
    _bufferedSub = _handler.bufferedPositionStream.listen((buf) {
      state = state.copyWith(bufferedPosition: buf);
    });

    // ── Error stream ──────────────────────────────────────────────────────────
    _errorSub = _handler.errorStream.listen((errorMsg) {
      debugLog('[Playback] Error received in controller: $errorMsg');
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: errorMsg,
      );
    });

    // ── MediaItem stream (track metadata sync) ────────────────────────────────
    _mediaItemSub = _handler.mediaItem.listen((mediaItem) {
      if (mediaItem != null) {
        final queueList = _queueManager.queue;
        final index = queueList.indexWhere((t) => t.id == mediaItem.id);
        if (index >= 0) {
          state = state.copyWith(currentTrack: queueList[index]);
        }
      }
    });

    // ── PlayerState stream (the authoritative playback state source) ──────────
    _playerStateSub = _handler.playerStateStream.listen((playerState) {
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

      final isHealthy = status == PlaybackStatus.playing ||
          status == PlaybackStatus.buffering ||
          status == PlaybackStatus.paused;

      state = state.copyWith(
        status: status,
        // Clear any stale error message when playback is healthy
        clearErrorMessage: isHealthy,
      );

      // ── Completion handling ───────────────────────────────────────────────
      // IMPORTANT: MieeAudioHandler.skipToNext() is already called by the
      // handler on completed. PlayerController must NOT call next() here.
      //
      // The ONLY thing PlayerController handles on completed is RepeatMode.one:
      // seek to start and re-play the same track without involving the handler's
      // skip logic.
      if (status == PlaybackStatus.completed) {
        if (state.repeatMode == RepeatMode.one) {
          debugLog('[Playback] RepeatMode.one — seeking to start');
          seek(Duration.zero);
          play();
        }
        // RepeatMode.all and RepeatMode.off are handled entirely in
        // MieeAudioHandler.skipToNext() — do NOT duplicate here.
      }
    });
  }

  // ── Queue management ─────────────────────────────────────────────────────

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

  // ── Playback ──────────────────────────────────────────────────────────────

  Future<void> playTrack(MusicItem track) async {
    state = state.copyWith(
      status: PlaybackStatus.loading,
      currentTrack: track,
      position: Duration.zero,
      clearErrorMessage: true,
    );

    try {
      final resolvedTrack = await _resolveSource(track);

      final index = _queueManager.currentIndex;
      if (index >= 0 && index < _queueManager.queue.length) {
        _queueManager.replaceTrackAt(index, resolvedTrack);
      }

      state = state.copyWith(currentTrack: resolvedTrack);

      final queueSnapshot = _queueManager.queue;
      final startIdx = index >= 0 ? index : 0;
      await _handler.loadQueue(queueSnapshot, startIndex: startIdx);
      await _handler.play();
    } catch (e) {
      debugLog('[Playback] playTrack failed: $e');
      state = state.copyWith(
        status: PlaybackStatus.error,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  /// Resolves the best source for [track] based on the user's source preference.
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

    // Default: prefer local
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
      final results = await repo.search('$title $artist');
      if (results.isNotEmpty) return results.first;
    } catch (_) {}
    return null;
  }

  Future<void> play() async {
    if (state.status == PlaybackStatus.idle && state.currentTrack != null) {
      await playTrack(state.currentTrack!);
    } else {
      await _handler.play();
    }
  }

  Future<void> pause() async {
    await _handler.pause();
  }

  Future<void> stop() async {
    await _handler.stop();
    state = state.copyWith(
      status: PlaybackStatus.idle,
      position: Duration.zero,
    );
  }

  Future<void> seek(Duration position) async {
    await _handler.seek(position);
    state = state.copyWith(position: position);
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> next() async {
    if (state.isShuffleEnabled) {
      final queueList = _queueManager.queue;
      if (queueList.length > 1) {
        final random = Random();
        int nextIndex = _queueManager.currentIndex;
        while (nextIndex == _queueManager.currentIndex) {
          nextIndex = random.nextInt(queueList.length);
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
    } else if (state.repeatMode == RepeatMode.all &&
        _queueManager.queue.isNotEmpty) {
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
      final queueList = _queueManager.queue;
      if (queueList.length > 1) {
        final random = Random();
        int prevIndex = _queueManager.currentIndex;
        while (prevIndex == _queueManager.currentIndex) {
          prevIndex = random.nextInt(queueList.length);
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
    } else if (state.repeatMode == RepeatMode.all &&
        _queueManager.queue.isNotEmpty) {
      final lastIdx = _queueManager.queue.length - 1;
      _queueManager.setIndex(lastIdx);
      final lastTrack = _queueManager.currentTrack;
      if (lastTrack != null) await playTrack(lastTrack);
    }
  }

  // ── Modes ──────────────────────────────────────────────────────────────────

  Future<void> toggleShuffle() async {
    final isShuffle = !state.isShuffleEnabled;
    state = state.copyWith(isShuffleEnabled: isShuffle);
    await _handler.setShuffleMode(
      isShuffle
          ? AudioServiceShuffleMode.all
          : AudioServiceShuffleMode.none,
    );
    debugLog('[Playback] Shuffle toggled: $isShuffle');
  }

  Future<void> toggleRepeatMode() async {
    RepeatMode nextMode;
    AudioServiceRepeatMode serviceMode;

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
    debugLog('[Playback] Repeat mode toggled: $nextMode');
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
    state = state.copyWith(
      currentTrack: null,
      status: PlaybackStatus.idle,
      position: Duration.zero,
      duration: Duration.zero,
    );
  }

  // ── Disposal ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _bufferedSub?.cancel();
    _playerStateSub?.cancel();
    _mediaItemSub?.cancel();
    _errorSub?.cancel();
    super.dispose();
  }
}

// ignore: avoid_print
void debugLog(String msg) => print(msg);
