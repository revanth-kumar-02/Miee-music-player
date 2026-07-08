import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Monitors internet connectivity changes using connectivity_plus.
class NetworkMonitor {
  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();

  NetworkMonitor() {
    _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((result) => result != ConnectivityResult.none);
      _controller.add(isOnline);
    });
  }

  Stream<bool> get onConnectivityChanged => _controller.stream;

  Future<bool> get isConnected async {
    final results = await _connectivity.checkConnectivity();
    return results.any((result) => result != ConnectivityResult.none);
  }
}

final networkMonitorProvider = Provider<NetworkMonitor>((ref) {
  return NetworkMonitor();
});
