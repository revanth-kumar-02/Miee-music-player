import 'package:flutter/foundation.dart';
import '../../../core/audio/playback_state.dart';
import '../../../shared/models/music_item.dart';
import '../../history/domain/listening_history_repository.dart';

/// Accurate listening-time accumulator that guarantees:
/// 1. Only intervals during which playback genuinely progresses are counted.
/// 2. Seeking forward or backward is NOT counted as listened time.
/// 3. Pauses, interruptions, and buffering halt duration accumulation.
/// 4. Flushes safely to [ListeningHistoryRepository] without double-counting.
/// 5. Accurately measures full-session listening duration and completion ratios
///    for completed plays, partial plays, and skips.
class PlaybackAnalyticsTracker {
  final ListeningHistoryRepository _historyRepo;
  final String? Function() _getUid;
  final void Function(String? uid)? _onEventRecorded;

  String? _activeTrackId;
  MusicItem? _activeTrack;
  DateTime? _sessionStartTime;
  Duration _lastPosition = Duration.zero;
  DateTime _lastWallClock = DateTime.now();
  int _sessionListenedSec = 0;
  bool _isPlaying = false;
  bool _hasFlushedActiveSession = false;

  DateTime? get sessionStartTime => _sessionStartTime;

  PlaybackAnalyticsTracker({
    required ListeningHistoryRepository historyRepo,
    required String? Function() getUid,
    void Function(String? uid)? onEventRecorded,
  })  : _historyRepo = historyRepo,
        _getUid = getUid,
        _onEventRecorded = onEventRecorded;

  /// Called on playback state changes (playing, paused, buffering, completed, idle).
  void onPlaybackStatusChanged(PlaybackStatus status, MusicItem? currentTrack) {
    final now = DateTime.now();

    if (status == PlaybackStatus.playing) {
      if (!_isPlaying) {
        _isPlaying = true;
        _lastWallClock = now;
      }
      if (currentTrack != null && currentTrack.id != _activeTrackId) {
        // Track switched while playing
        _flushCurrentSession();
        _startNewSession(currentTrack, now);
      }
    } else {
      // Paused, completed, buffering, or idle
      if (_isPlaying) {
        _isPlaying = false;
        if (status == PlaybackStatus.completed || status == PlaybackStatus.idle) {
          _flushCurrentSession();
        }
      }
    }
  }

  /// Called whenever player reports position progression.
  void onPositionUpdated(Duration newPosition, Duration duration) {
    if (!_isPlaying || _activeTrack == null) {
      _lastPosition = newPosition;
      _lastWallClock = DateTime.now();
      return;
    }

    final now = DateTime.now();
    final wallClockDeltaSec = now.difference(_lastWallClock).inMilliseconds / 1000.0;
    final posDeltaSec = (newPosition - _lastPosition).inMilliseconds / 1000.0;

    // Legitimate audio progression: position delta must be positive AND
    // cannot significantly exceed wall-clock time (accounting for small clock jitter).
    // Seeking forward is NOT credited as listening time.
    if (posDeltaSec > 0 && posDeltaSec <= (wallClockDeltaSec + 1.25)) {
      _sessionListenedSec += posDeltaSec.round();
    }

    _lastPosition = newPosition;
    _lastWallClock = now;
  }

  /// Handles track switching explicitly.
  void onTrackChanged(MusicItem? newTrack) {
    final now = DateTime.now();
    if (_activeTrackId != null && _activeTrackId != newTrack?.id) {
      _flushCurrentSession();
    }
    if (newTrack != null) {
      _startNewSession(newTrack, now);
    }
  }

  void _startNewSession(MusicItem track, DateTime now) {
    _activeTrackId = track.id;
    _activeTrack = track;
    _sessionStartTime = now;
    _lastWallClock = now;
    _sessionListenedSec = 0;
    _hasFlushedActiveSession = false;
  }

  /// Flushes the active session to [ListeningHistoryRepository] if at least 3 seconds of
  /// genuine playback occurred. Guarantees that each listening session produces at most
  /// one feedback event.
  void _flushCurrentSession() {
    if (_hasFlushedActiveSession || _activeTrack == null || _sessionListenedSec < 3) {
      _activeTrackId = null;
      _activeTrack = null;
      _sessionListenedSec = 0;
      return;
    }

    final trackToRecord = _activeTrack!;
    final secondsToRecord = _sessionListenedSec;
    final durSec = _parseDurationSec(trackToRecord.duration);

    _hasFlushedActiveSession = true;

    final uid = _getUid();
    try {
      _historyRepo.recordListeningEvent(
        uid: uid,
        track: trackToRecord,
        listenedSec: secondsToRecord,
        durationSec: durSec > 0 ? durSec : 180,
      );
      _onEventRecorded?.call(uid);
    } catch (e) {
      debugPrint('[PlaybackAnalyticsTracker] Flush error: $e');
    } finally {
      _activeTrackId = null;
      _activeTrack = null;
      _sessionListenedSec = 0;
    }
  }

  int _parseDurationSec(String dur) {
    if (dur.isEmpty) return 180;
    final parts = dur.split(':');
    if (parts.length == 2) {
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    } else if (parts.length == 3) {
      return (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (int.tryParse(parts[2]) ?? 0);
    }
    return 180;
  }

  /// Flushes any pending listening session and releases tracker state.
  void dispose() {
    _flushCurrentSession();
  }
}
