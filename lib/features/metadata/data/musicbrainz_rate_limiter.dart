import 'dart:async';
import 'package:flutter/foundation.dart';

/// Thread-safe asynchronous rate limiter ensuring compliance with MusicBrainz's
/// strict public web service policy: maximum 1 request per second (1000ms interval).
///
/// Prevents HTTP 503 ("The MusicBrainz web server is currently busy") by queuing
/// concurrent calls and executing them sequentially with a guaranteed spacing.
class MusicBrainzRateLimiter {
  static final MusicBrainzRateLimiter _instance = MusicBrainzRateLimiter._internal();
  factory MusicBrainzRateLimiter({Duration? minInterval}) {
    if (minInterval != null) {
      return MusicBrainzRateLimiter.withInterval(minInterval);
    }
    return _instance;
  }

  MusicBrainzRateLimiter._internal() : _minInterval = const Duration(milliseconds: 1050);

  @visibleForTesting
  MusicBrainzRateLimiter.withInterval(Duration interval) : _minInterval = interval;

  final Duration _minInterval;
  DateTime _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
  Future<void> _lastFuture = Future<void>.value();

  /// Enqueues [action] and executes it once the rate-limit window has cleared.
  Future<T> schedule<T>(Future<T> Function() action) {
    final completer = Completer<T>();

    _lastFuture = _lastFuture.then((_) async {
      final now = DateTime.now();
      final elapsed = now.difference(_lastRequestTime);

      if (elapsed < _minInterval) {
        final waitDuration = _minInterval - elapsed;
        await Future<void>.delayed(waitDuration);
      }

      _lastRequestTime = DateTime.now();

      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });

    return completer.future;
  }

  @visibleForTesting
  void reset() {
    _lastRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
    _lastFuture = Future<void>.value();
  }
}
