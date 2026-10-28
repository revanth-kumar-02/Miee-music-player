import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/audio/playback_state.dart';
import '../../../core/audio/providers.dart';
import '../../../shared/models/music_item.dart';
import '../../../shared/models/track.dart';
import '../../youtube/domain/youtube_model.dart';
import '../data/room_repository.dart';
import '../domain/room_models.dart';

class RoomState {
  final ListeningRoom? activeRoom;
  final List<RoomMember> members;
  final List<RoomMessage> messages;
  final RoomPlaybackState? playbackState;
  final bool isHost;
  final bool isLoading;
  final bool isSyncing;
  final bool isSendingMessage;
  final String? syncStatusText;
  final String? errorMessage;
  final bool roomEnded;

  const RoomState({
    this.activeRoom,
    this.members = const [],
    this.messages = const [],
    this.playbackState,
    this.isHost = false,
    this.isLoading = false,
    this.isSyncing = false,
    this.isSendingMessage = false,
    this.syncStatusText,
    this.errorMessage,
    this.roomEnded = false,
  });

  RoomState copyWith({
    ListeningRoom? activeRoom,
    bool clearActiveRoom = false,
    List<RoomMember>? members,
    List<RoomMessage>? messages,
    RoomPlaybackState? playbackState,
    bool clearPlaybackState = false,
    bool? isHost,
    bool? isLoading,
    bool? isSyncing,
    bool? isSendingMessage,
    String? syncStatusText,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? roomEnded,
  }) {
    return RoomState(
      activeRoom: clearActiveRoom ? null : (activeRoom ?? this.activeRoom),
      members: members ?? this.members,
      messages: messages ?? this.messages,
      playbackState: clearPlaybackState ? null : (playbackState ?? this.playbackState),
      isHost: isHost ?? this.isHost,
      isLoading: isLoading ?? this.isLoading,
      isSyncing: isSyncing ?? this.isSyncing,
      isSendingMessage: isSendingMessage ?? this.isSendingMessage,
      syncStatusText: syncStatusText ?? this.syncStatusText,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      roomEnded: roomEnded ?? this.roomEnded,
    );
  }
}

class RoomController extends StateNotifier<RoomState> {
  final RoomRepository _repo;
  final Ref _ref;
  RealtimeChannel? _subscription;
  Timer? _seekDebounceTimer;
  DateTime _lastSeekSync = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isApplyingRemoteUpdate = false;
  int _stateRevision = 1;
  int _lastAppliedRevision = 0;

  RoomController(this._repo, this._ref) : super(const RoomState()) {
    _initHostPlaybackListener();
  }

  void _initHostPlaybackListener() {
    _ref.listen<PlaybackState>(playerControllerProvider, (prev, next) {
      if (!state.isHost || state.activeRoom == null || _isApplyingRemoteUpdate) {
        return;
      }
      _onHostPlaybackChanged(prev, next);
    });
  }

  void _onHostPlaybackChanged(PlaybackState? prev, PlaybackState next) {
    final roomId = state.activeRoom?.id;
    if (roomId == null) return;

    final currentTrack = next.currentTrack;
    final isPlaying = next.status == PlaybackStatus.playing;
    final isPaused = next.status == PlaybackStatus.paused;
    final isBuffering = next.status == PlaybackStatus.buffering;

    // Never broadcast 'stopped' while transitioning between tracks on host.
    // Broadcast 'buffering' instead to keep listeners in sync while next track resolves.
    final statusStr = isPlaying
        ? 'playing'
        : (isBuffering ? 'buffering' : (isPaused ? 'paused' : 'buffering'));

    // Check if track changed
    final trackChanged = prev?.currentTrack?.id != currentTrack?.id;
    final statusChanged = prev?.status != next.status;

    // Check if host sought
    final prevPos = prev?.position ?? Duration.zero;
    final posDiff = (next.position - prevPos).inMilliseconds.abs();
    final isSeek = !trackChanged && !statusChanged && posDiff > 2500;

    if (trackChanged || statusChanged) {
      _broadcastHostState(
        roomId: roomId,
        track: currentTrack,
        status: statusStr,
        positionMs: next.position.inMilliseconds,
        durationMs: next.duration.inMilliseconds,
      );
    } else if (isSeek) {
      _seekDebounceTimer?.cancel();
      _seekDebounceTimer = Timer(const Duration(milliseconds: 400), () {
        _broadcastHostState(
          roomId: roomId,
          track: currentTrack,
          status: statusStr,
          positionMs: next.position.inMilliseconds,
          durationMs: next.duration.inMilliseconds,
        );
      });
    }
  }

  Future<void> _broadcastHostState({
    required String roomId,
    required MusicItem? track,
    required String status,
    required int positionMs,
    required int durationMs,
  }) async {
    final queueSnapshot = _ref.read(queueManagerProvider).queue;
    final queueMaps = queueSnapshot.map((t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'imageUrl': t.imageUrl,
      'durationMs': _parseDurationMs(t.duration),
      'isYoutube': t.isYoutube,
    }).toList();

    _stateRevision++;
    final roomPlayback = RoomPlaybackState(
      roomId: roomId,
      currentTrackId: track?.id,
      title: track?.title,
      artist: track?.artist,
      imageUrl: track?.imageUrl,
      durationMs: durationMs,
      isYoutube: track?.isYoutube ?? true,
      queue: queueMaps,
      playbackStatus: status,
      positionMs: positionMs,
      revision: _stateRevision,
      updatedAt: DateTime.now(),
    );

    try {
      await _repo.updatePlaybackState(roomPlayback);
      state = state.copyWith(playbackState: roomPlayback);
    } catch (e) {
      debugPrint('[RoomController] Broadcast host state failed: $e');
    }
  }

  /// Creates a listening room with capacity between 1 and 5.
  Future<ListeningRoom> createRoom({
    required String name,
    int capacity = 5,
    bool clearQueue = true,
  }) async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      _stateRevision = 1;
      _lastAppliedRevision = 0;
      _ref.read(playerControllerProvider.notifier).setRoomListener(false);

      if (clearQueue) {
        final playerCtrl = _ref.read(playerControllerProvider.notifier);
        playerCtrl.clearQueue();
      }

      final room = await _repo.createRoom(name: name, capacity: capacity);
      final members = await _repo.getRoomMembers(room.id);
      final messages = await _repo.getRoomMessages(room.id);

      state = state.copyWith(
        activeRoom: room,
        members: members,
        messages: messages,
        isHost: true,
        isLoading: false,
        roomEnded: false,
        syncStatusText: 'Hosting Room',
      );

      _startSubscription(room.id);

      // Initialize room state with currently active track if any
      final currentPlayback = _ref.read(playerControllerProvider);
      await _broadcastHostState(
        roomId: room.id,
        track: currentPlayback.currentTrack,
        status: currentPlayback.status == PlaybackStatus.playing ? 'playing' : 'paused',
        positionMs: currentPlayback.position.inMilliseconds,
        durationMs: currentPlayback.duration.inMilliseconds,
      );

      return room;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      rethrow;
    }
  }

  /// Joins a room using a unique 6-character code.
  Future<void> joinRoom(String joinCode) async {
    state = state.copyWith(isLoading: true, clearErrorMessage: true);
    try {
      final result = await _repo.joinRoom(joinCode);
      final roomId = result['room_id'] as String;
      final role = result['role'] as String? ?? 'listener';
      final isHost = role == 'host';

      final room = await _repo.getRoom(roomId);
      if (room == null || room.status != 'active') {
        throw Exception('Room is not active or has ended.');
      }

      final members = await _repo.getRoomMembers(roomId);
      final playbackState = await _repo.getRoomState(roomId);
      final messages = await _repo.getRoomMessages(roomId);

      _lastAppliedRevision = playbackState?.revision ?? 0;
      if (!isHost) {
        _ref.read(playerControllerProvider.notifier).setRoomListener(true);
      }

      state = state.copyWith(
        activeRoom: room,
        members: members,
        messages: messages,
        playbackState: playbackState,
        isHost: isHost,
        isLoading: false,
        roomEnded: false,
        syncStatusText: isHost ? 'Hosting Room' : 'Connected as Listener',
      );

      _startSubscription(roomId);

      // If listener, synchronize to existing playback state immediately
      if (!isHost && playbackState != null) {
        unawaited(_syncListenerPlayback(playbackState));
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
      rethrow;
    }
  }

  void _startSubscription(String roomId) {
    _subscription?.unsubscribe();
    _subscription = _repo.subscribeToRoom(
      roomId: roomId,
      onStateChanged: (newState) {
        if (newState.revision <= _lastAppliedRevision) {
          debugPrint(
            '[RoomController] Discarding stale state update '
            '(incoming rev ${newState.revision} <= applied $_lastAppliedRevision)',
          );
          return;
        }
        _lastAppliedRevision = newState.revision;
        state = state.copyWith(playbackState: newState);
        if (!state.isHost) {
          _syncListenerPlayback(newState);
        }
      },
      onMembersChanged: () async {
        try {
          final members = await _repo.getRoomMembers(roomId);
          state = state.copyWith(members: members);
        } catch (_) {}
      },
      onMessageReceived: (newMsg) {
        final existing = state.messages;
        if (!existing.any((m) => m.id == newMsg.id)) {
          state = state.copyWith(messages: [...existing, newMsg]);
        }
      },
      onRoomEnded: () {
        state = state.copyWith(
          roomEnded: true,
          syncStatusText: 'Room has ended',
        );
        _cleanupSubscription();
      },
    );
  }

  Future<void> _syncListenerPlayback(RoomPlaybackState remoteState) async {
    if (state.isHost || state.activeRoom == null) return;

    final playerCtrl = _ref.read(playerControllerProvider.notifier);
    final localState = _ref.read(playerControllerProvider);
    final currentLocalTrack = localState.currentTrack;

    _isApplyingRemoteUpdate = true;
    state = state.copyWith(isSyncing: true, syncStatusText: 'Syncing with host...');

    try {
      // 1. Sync remote queue to listener's local QueueManager
      final remoteQueue = remoteState.queue;
      if (remoteQueue.isNotEmpty) {
        final queueManager = _ref.read(queueManagerProvider);
        final tracks = remoteQueue.map((m) => _buildTrackFromQueueMap(m)).toList();
        final currentIdx = tracks.indexWhere(
          (t) => isSameTrackId(t.id, remoteState.currentTrackId ?? ''),
        );
        queueManager.setQueue(tracks, startIndex: currentIdx >= 0 ? currentIdx : 0);
      }

      // 2. Check if track needs to change
      final remoteTrackId = remoteState.currentTrackId;
      if (remoteTrackId != null &&
          (currentLocalTrack == null ||
              !isSameTrackId(currentLocalTrack.id, remoteTrackId))) {
        final trackToPlay = _buildTrackFromRemote(remoteState);
        await playerCtrl.playTrack(trackToPlay, playingFrom: 'Room: ${state.activeRoom?.name}');
      }

      // 3. Play / Pause status synchronization
      final isRemotePlaying = remoteState.playbackStatus == 'playing';
      final isLocalPlaying = localState.status == PlaybackStatus.playing;

      if (isRemotePlaying && !isLocalPlaying) {
        await playerCtrl.play();
      } else if (!isRemotePlaying && isLocalPlaying) {
        await playerCtrl.pause();
      }

      // 4. Position drift correction with clock skew protection
      final now = DateTime.now();
      final rawElapsed = now.difference(remoteState.updatedAt).inMilliseconds;
      // Clamp between 0 and 15 seconds to mitigate clock discrepancies across devices
      final elapsedSinceUpdate = rawElapsed.clamp(0, 15000);
      final expectedPosMs = isRemotePlaying
          ? (remoteState.positionMs + elapsedSinceUpdate)
          : remoteState.positionMs;

      final localPosMs = localState.position.inMilliseconds;
      final drift = (localPosMs - expectedPosMs).abs();

      // Only seek if drift > 3500ms and last seek was not within 3 seconds
      final canSeek = now.difference(_lastSeekSync).inSeconds >= 3;
      if (drift > 3500 && canSeek) {
        _lastSeekSync = now;
        final maxDur = remoteState.durationMs > 0 ? remoteState.durationMs : expectedPosMs;
        final targetPosition = Duration(
          milliseconds: expectedPosMs.clamp(0, maxDur),
        );
        await playerCtrl.seek(targetPosition);
      }

      state = state.copyWith(
        isSyncing: false,
        syncStatusText: isRemotePlaying ? 'In Sync with Host' : 'Host Paused',
      );
    } catch (e) {
      debugPrint('[RoomController] Listener sync error: $e');
      state = state.copyWith(
        isSyncing: false,
        syncStatusText: 'Sync Error',
      );
    } finally {
      _isApplyingRemoteUpdate = false;
    }
  }

  static int _parseDurationMs(String durationStr) {
    final parts = durationStr.split(':');
    if (parts.length == 2) {
      final m = int.tryParse(parts[0]) ?? 0;
      final s = int.tryParse(parts[1]) ?? 0;
      return (m * 60 + s) * 1000;
    } else if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2]) ?? 0;
      return (h * 3600 + m * 60 + s) * 1000;
    }
    return 0;
  }

  static String _formatDurationString(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  MusicItem _buildTrackFromQueueMap(Map<String, dynamic> m) {
    final id = m['id'] as String? ?? 'unknown';
    final isYoutube = m['isYoutube'] as bool? ?? true;
    final title = m['title'] as String? ?? 'Unknown Song';
    final artist = m['artist'] as String? ?? 'Artist';
    final imageUrl = m['imageUrl'] as String? ?? '';
    final durationMs = (m['durationMs'] as num?)?.toInt() ?? 0;
    final formattedDuration = _formatDurationString(durationMs);

    if (isYoutube) {
      final cleanId = id.startsWith('youtube_') ? id.replaceFirst('youtube_', '') : id;
      return YouTubeVideo(
        id: cleanId,
        title: title,
        channelTitle: artist,
        thumbnailUrl: imageUrl,
        duration: formattedDuration,
        viewCount: '',
      );
    } else {
      return Track(
        id: id,
        title: title,
        artist: artist,
        imageUrl: imageUrl,
        duration: formattedDuration,
      );
    }
  }

  MusicItem _buildTrackFromRemote(RoomPlaybackState s) {
    final rawId = s.currentTrackId ?? 'unknown';
    final cleanId = rawId.startsWith('youtube_') ? rawId.replaceFirst('youtube_', '') : rawId;
    final formattedDuration = _formatDurationString(s.durationMs);

    if (s.isYoutube) {
      return YouTubeVideo(
        id: cleanId,
        title: s.title ?? 'Unknown Song',
        channelTitle: s.artist ?? 'Miee Host',
        thumbnailUrl: s.imageUrl ?? '',
        duration: formattedDuration,
        viewCount: '',
      );
    } else {
      return Track(
        id: rawId,
        title: s.title ?? 'Unknown Song',
        artist: s.artist ?? 'Miee Host',
        imageUrl: s.imageUrl ?? '',
        duration: formattedDuration,
      );
    }
  }

  /// Sends a live text chat message to the room.
  Future<void> sendChatMessage(String content) async {
    final roomId = state.activeRoom?.id;
    final text = content.trim();
    if (roomId == null || text.isEmpty) return;

    state = state.copyWith(isSendingMessage: true);
    try {
      final msg = await _repo.sendMessage(
        roomId: roomId,
        content: text,
      );
      final existing = state.messages;
      if (!existing.any((m) => m.id == msg.id)) {
        state = state.copyWith(messages: [...existing, msg]);
      }
    } catch (e) {
      debugPrint('[RoomController] sendChatMessage error: $e');
      rethrow;
    } finally {
      state = state.copyWith(isSendingMessage: false);
    }
  }

  /// Sends a rich song suggestion to the room with track metadata.
  Future<void> sendSongSuggestion(MusicItem track, {String? note}) async {
    final roomId = state.activeRoom?.id;
    if (roomId == null) return;

    state = state.copyWith(isSendingMessage: true);
    try {
      final text = (note != null && note.trim().isNotEmpty)
          ? note.trim()
          : 'Can we play "${track.title}"?';
      final msg = await _repo.sendMessage(
        roomId: roomId,
        content: text,
        type: 'song_suggestion',
        trackId: track.id,
        trackTitle: track.title,
        trackArtist: track.artist,
        trackImageUrl: track.imageUrl,
        isYoutube: track.isYoutube,
      );
      final existing = state.messages;
      if (!existing.any((m) => m.id == msg.id)) {
        state = state.copyWith(messages: [...existing, msg]);
      }
    } catch (e) {
      debugPrint('[RoomController] sendSongSuggestion error: $e');
      rethrow;
    } finally {
      state = state.copyWith(isSendingMessage: false);
    }
  }

  /// Host action: Play any track in the room, immediately synchronizing all listeners.
  Future<void> hostPlayTrack(MusicItem track) async {
    if (!state.isHost || state.activeRoom == null) return;
    final playerCtrl = _ref.read(playerControllerProvider.notifier);
    await playerCtrl.playTrack(track, playingFrom: 'Room: ${state.activeRoom?.name}');
  }

  /// Host action: Play a track that was suggested in chat.
  Future<void> hostPlaySuggestedTrack(RoomMessage message) async {
    if (!state.isHost || state.activeRoom == null || !message.isSongSuggestion) return;
    final track = _buildTrackFromSuggestion(message);
    await hostPlayTrack(track);
  }

  /// Host action: Append a track to the room queue.
  Future<void> hostQueueTrack(MusicItem track) async {
    if (!state.isHost || state.activeRoom == null) return;
    final playerCtrl = _ref.read(playerControllerProvider.notifier);
    await playerCtrl.addTrackToQueue(track);

    final currentPlayback = _ref.read(playerControllerProvider);
    await _broadcastHostState(
      roomId: state.activeRoom!.id,
      track: currentPlayback.currentTrack,
      status: currentPlayback.status == PlaybackStatus.playing ? 'playing' : 'paused',
      positionMs: currentPlayback.position.inMilliseconds,
      durationMs: currentPlayback.duration.inMilliseconds,
    );
  }

  /// Host action: Remove a track from the room queue by index.
  Future<void> hostRemoveQueueTrack(int index) async {
    if (!state.isHost || state.activeRoom == null) return;
    final playerCtrl = _ref.read(playerControllerProvider.notifier);
    await playerCtrl.removeTrackAt(index);

    final currentPlayback = _ref.read(playerControllerProvider);
    await _broadcastHostState(
      roomId: state.activeRoom!.id,
      track: currentPlayback.currentTrack,
      status: currentPlayback.status == PlaybackStatus.playing ? 'playing' : 'paused',
      positionMs: currentPlayback.position.inMilliseconds,
      durationMs: currentPlayback.duration.inMilliseconds,
    );
  }

  /// Host action: Clear all tracks from the room queue.
  Future<void> hostClearQueue() async {
    if (!state.isHost || state.activeRoom == null) return;
    final playerCtrl = _ref.read(playerControllerProvider.notifier);
    playerCtrl.clearQueue();

    final currentPlayback = _ref.read(playerControllerProvider);
    await _broadcastHostState(
      roomId: state.activeRoom!.id,
      track: currentPlayback.currentTrack,
      status: currentPlayback.status == PlaybackStatus.playing ? 'playing' : 'paused',
      positionMs: currentPlayback.position.inMilliseconds,
      durationMs: currentPlayback.duration.inMilliseconds,
    );
  }

  /// Host action: Immediately play a track from the room queue at [index].
  Future<void> hostPlayQueueTrack(int index) async {
    if (!state.isHost || state.activeRoom == null) return;
    final playerCtrl = _ref.read(playerControllerProvider.notifier);
    await playerCtrl.skipToQueueItem(index);

    final currentPlayback = _ref.read(playerControllerProvider);
    await _broadcastHostState(
      roomId: state.activeRoom!.id,
      track: currentPlayback.currentTrack,
      status: currentPlayback.status == PlaybackStatus.playing ? 'playing' : 'paused',
      positionMs: currentPlayback.position.inMilliseconds,
      durationMs: currentPlayback.duration.inMilliseconds,
    );
  }

  /// Host action: Append a suggested track to the room queue.
  Future<void> hostQueueSuggestedTrack(RoomMessage message) async {
    if (!state.isHost || state.activeRoom == null || !message.isSongSuggestion) return;
    final track = _buildTrackFromSuggestion(message);
    await hostQueueTrack(track);
  }

  MusicItem _buildTrackFromSuggestion(RoomMessage msg) {
    final rawId = msg.trackId ?? 'unknown';
    final cleanId = rawId.startsWith('youtube_') ? rawId.replaceFirst('youtube_', '') : rawId;
    if (msg.isYoutube) {
      return YouTubeVideo(
        id: cleanId,
        title: msg.trackTitle ?? 'Suggested Song',
        channelTitle: msg.trackArtist ?? 'Artist',
        thumbnailUrl: msg.trackImageUrl ?? '',
        duration: '3:30',
        viewCount: '',
      );
    } else {
      return Track(
        id: rawId,
        title: msg.trackTitle ?? 'Suggested Song',
        artist: msg.trackArtist ?? 'Artist',
        imageUrl: msg.trackImageUrl ?? '',
        duration: '3:30',
      );
    }
  }

  /// Leaves the current room and restores normal local state.
  Future<void> leaveRoom() async {
    final roomId = state.activeRoom?.id;
    if (roomId == null) return;

    _cleanupSubscription();
    try {
      await _repo.leaveRoom(roomId);
    } catch (e) {
      debugPrint('[RoomController] leaveRoom error: $e');
    }

    state = const RoomState();
  }

  /// Ends the current room (Host only).
  Future<void> endRoom() async {
    final roomId = state.activeRoom?.id;
    if (roomId == null || !state.isHost) return;

    _cleanupSubscription();
    try {
      await _repo.endRoom(roomId);
    } catch (e) {
      debugPrint('[RoomController] endRoom error: $e');
    }

    state = const RoomState();
  }

  void _cleanupSubscription() {
    _subscription?.unsubscribe();
    _subscription = null;
    _seekDebounceTimer?.cancel();
    final activeRoomId = state.activeRoom?.id;
    if (activeRoomId != null) {
      unawaited(_repo.unsubscribeChannel(activeRoomId));
    }
    _lastAppliedRevision = 0;
    _ref.read(playerControllerProvider.notifier).setRoomListener(false);
  }

  @override
  void dispose() {
    _cleanupSubscription();
    super.dispose();
  }
}

final roomRepositoryProvider = Provider<RoomRepository>((ref) {
  return RoomRepository();
});

final roomControllerProvider = StateNotifierProvider<RoomController, RoomState>((ref) {
  final repo = ref.watch(roomRepositoryProvider);
  return RoomController(repo, ref);
});

final activeRoomProvider = Provider<ListeningRoom?>((ref) {
  return ref.watch(roomControllerProvider).activeRoom;
});

final roomMembersProvider = Provider<List<RoomMember>>((ref) {
  return ref.watch(roomControllerProvider).members;
});

final roomPlaybackStateProvider = Provider<RoomPlaybackState?>((ref) {
  return ref.watch(roomControllerProvider).playbackState;
});

final isRoomHostProvider = Provider<bool>((ref) {
  return ref.watch(roomControllerProvider).isHost;
});
