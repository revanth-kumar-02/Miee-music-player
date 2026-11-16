import 'package:flutter/foundation.dart';
import '../../shared/models/music_item.dart';

/// Centralized diagnostic logging for Miee's playback queue.
///
/// Records every queue initialization, insertion, deduplication, autoplay check,
/// removal, and reordering with structured `[QueueDiag]` prefixes for full traceability.
class QueueDiagnostics {
  /// Logs when the queue is initialized or replaced.
  static void logQueueCreation({
    required String reason,
    required List<MusicItem> tracks,
    required int startIndex,
    String? playingFrom,
  }) {
    debugPrint(
      '[QueueDiag] QUEUE_INIT: reason="$reason", size=${tracks.length}, '
      'startIndex=$startIndex, playingFrom="$playingFrom", '
      'firstTrack="${tracks.isNotEmpty ? tracks[startIndex.clamp(0, tracks.length - 1)].title : 'none'}" '
      '(${tracks.isNotEmpty ? tracks[startIndex.clamp(0, tracks.length - 1)].id : ''})',
    );
  }

  /// Logs when a track is inserted into the queue (manual or automatic).
  static void logTrackInsertion({
    required MusicItem track,
    required String reason,
    required bool userInitiated,
    String? recommendationSource,
    int? indexBefore,
    int? indexAfter,
  }) {
    debugPrint(
      '[QueueDiag] TRACK_INSERTED: title="${track.title}", id="${track.id}", '
      'source="${track.isYoutube ? 'youtube' : 'local'}", reason="$reason", '
      'userInitiated=$userInitiated, recSource="$recommendationSource", '
      'indexBefore=$indexBefore, indexAfter=$indexAfter',
    );
  }

  /// Logs when a candidate track is rejected as a duplicate.
  static void logDuplicateRejected({
    required MusicItem track,
    required String duplicateReason,
  }) {
    debugPrint(
      '[QueueDiag] DUPLICATE_REJECTED: title="${track.title}", id="${track.id}", '
      'reason="$duplicateReason"',
    );
  }

  /// Logs when an autoplay check is evaluated.
  static void logAutoplayCheck({
    required bool enabled,
    required int remaining,
    required String? activeTrackId,
    required String reason,
  }) {
    debugPrint(
      '[QueueDiag] AUTOPLAY_CHECK: enabled=$enabled, remaining=$remaining, '
      'activeTrackId="$activeTrackId", reason="$reason"',
    );
  }

  /// Logs when the queue order is modified by user drag-and-drop.
  static void logQueueReorder({
    required int oldIndex,
    required int newIndex,
    required int queueLength,
  }) {
    debugPrint(
      '[QueueDiag] QUEUE_REORDER: oldIndex=$oldIndex, newIndex=$newIndex, totalSize=$queueLength',
    );
  }

  /// Logs when a track is explicitly removed from the queue.
  static void logTrackRemoved({
    required int index,
    required MusicItem removedTrack,
    required int remainingSize,
  }) {
    debugPrint(
      '[QueueDiag] TRACK_REMOVED: index=$index, title="${removedTrack.title}", '
      'id="${removedTrack.id}", remainingSize=$remainingSize',
    );
  }
}
