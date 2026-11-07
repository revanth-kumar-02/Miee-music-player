import 'dart:async';

/// Global rate limiter to ensure strict adherence to external API policies,
/// specifically the MusicBrainz requirement of at most 1 request per second.
class ArtworkRateLimiter {
  final Duration interval;
  DateTime _lastExecution = DateTime.fromMillisecondsSinceEpoch(0);
  Completer<void>? _currentWait;

  ArtworkRateLimiter({this.interval = const Duration(milliseconds: 1000)});

  /// Executes [action] after ensuring at least [interval] has passed
  /// since the completion of the last request.
  Future<T> run<T>(Future<T> Function() action) async {
    while (_currentWait != null) {
      await _currentWait!.future;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_lastExecution);
    if (elapsed < interval) {
      final waitDuration = interval - elapsed;
      final completer = Completer<void>();
      _currentWait = completer;
      await Future<void>.delayed(waitDuration);
      _currentWait = null;
      completer.complete();
    }

    _lastExecution = DateTime.now();
    try {
      return await action();
    } finally {
      _lastExecution = DateTime.now();
    }
  }

  void reset() {
    _lastExecution = DateTime.fromMillisecondsSinceEpoch(0);
    _currentWait = null;
  }
}
