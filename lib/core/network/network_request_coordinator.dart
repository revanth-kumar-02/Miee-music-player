import 'dart:async';
import 'dart:collection';

/// Priority levels for network requests to prevent background discovery
/// from starving user-initiated playback or interactive search.
enum NetworkPriority {
  /// Highest: User-selected track playback stream/source resolution.
  playbackResolution(0),

  /// High: User-initiated search queries.
  userSearch(1),

  /// Medium: Live autocomplete suggestions and progressive metadata enrichment.
  suggestionsAndEnrichment(2),

  /// Low: Home background recommendations, Daily Mixes, and chart pre-resolution.
  backgroundDiscovery(3);

  const NetworkPriority(this.rank);
  final int rank;
}

class _QueuedRequest<T> {
  final NetworkPriority priority;
  final int sequence;
  final Future<T> Function() task;
  final Completer<T> completer;

  _QueuedRequest({
    required this.priority,
    required this.sequence,
    required this.task,
    required this.completer,
  });
}

/// Bounded, priority-aware concurrency coordinator for network-bound operations.
///
/// Ensures interactive playback resolution and user search execute ahead of
/// background recommendation work while avoiding starvation of lower-priority tasks.
class NetworkRequestCoordinator {
  static final NetworkRequestCoordinator instance = NetworkRequestCoordinator();

  final int maxConcurrent;
  final int reservedInteractiveSlots;

  int _activeCount = 0;
  int _sequenceCounter = 0;
  final List<_QueuedRequest<dynamic>> _pending = [];
  final Queue<DateTime> _recentBackgroundTimestamps = Queue<DateTime>();

  NetworkRequestCoordinator({
    this.maxConcurrent = 4,
    this.reservedInteractiveSlots = 1,
  })  : assert(maxConcurrent >= 2),
        assert(reservedInteractiveSlots >= 0 &&
            reservedInteractiveSlots < maxConcurrent);

  int get activeCount => _activeCount;
  int get pendingCount => _pending.length;

  /// Runs [task] according to [priority] within the bounded concurrency pool.
  Future<T> run<T>(
    Future<T> Function() task, {
    NetworkPriority priority = NetworkPriority.userSearch,
  }) {
    if (_canStartImmediately(priority)) {
      return _executeNow(task);
    }

    final completer = Completer<T>();
    _pending.add(
      _QueuedRequest<T>(
        priority: priority,
        sequence: _sequenceCounter++,
        task: task,
        completer: completer,
      ),
    );
    _pending.sort((a, b) {
      final pCmp = a.priority.rank.compareTo(b.priority.rank);
      return pCmp != 0 ? pCmp : a.sequence.compareTo(b.sequence);
    });
    return completer.future;
  }

  bool _canStartImmediately(NetworkPriority priority) {
    if (_activeCount >= maxConcurrent) return false;
    final isBackground = priority == NetworkPriority.backgroundDiscovery ||
        priority == NetworkPriority.suggestionsAndEnrichment;
    if (!isBackground) return true;

    // Reserve capacity for interactive requests when interactive work is queued
    // or when total active slots would leave zero headroom.
    final hasInteractivePending = _pending.any(
      (q) =>
          q.priority == NetworkPriority.playbackResolution ||
          q.priority == NetworkPriority.userSearch,
    );
    if (hasInteractivePending) return false;
    return _activeCount < (maxConcurrent - reservedInteractiveSlots);
  }

  Future<T> _executeNow<T>(Future<T> Function() task) async {
    _activeCount++;
    try {
      return await task();
    } finally {
      _activeCount--;
      _pumpQueue();
    }
  }

  void _pumpQueue() {
    while (_pending.isNotEmpty && _activeCount < maxConcurrent) {
      final nextIndex = _pending.indexWhere(
        (q) => _canStartImmediately(q.priority),
      );
      if (nextIndex < 0) break;

      final next = _pending.removeAt(nextIndex);
      if (next.priority == NetworkPriority.backgroundDiscovery) {
        _recentBackgroundTimestamps.addLast(DateTime.now());
        if (_recentBackgroundTimestamps.length > 32) {
          _recentBackgroundTimestamps.removeFirst();
        }
      }

      _activeCount++;
      Future<void>(() async {
        try {
          final result = await next.task();
          if (!next.completer.isCompleted) {
            next.completer.complete(result);
          }
        } catch (e, st) {
          if (!next.completer.isCompleted) {
            next.completer.completeError(e, st);
          }
        } finally {
          _activeCount--;
          _pumpQueue();
        }
      });
    }
  }
}
