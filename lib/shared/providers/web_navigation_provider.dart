import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Immutable state representing in-app web navigation history.
@immutable
class WebNavigationState {
  final List<String> history;
  final int currentIndex;

  const WebNavigationState({
    this.history = const [],
    this.currentIndex = -1,
  });

  bool get canGoBack => currentIndex > 0;

  bool get canGoForward =>
      currentIndex >= 0 && currentIndex < history.length - 1;

  String? get currentRoute =>
      (currentIndex >= 0 && currentIndex < history.length)
          ? history[currentIndex]
          : null;

  WebNavigationState copyWith({
    List<String>? history,
    int? currentIndex,
  }) {
    return WebNavigationState(
      history: history ?? this.history,
      currentIndex: currentIndex ?? this.currentIndex,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WebNavigationState &&
          runtimeType == other.runtimeType &&
          listEquals(history, other.history) &&
          currentIndex == other.currentIndex;

  @override
  int get hashCode => Object.hash(Object.hashAll(history), currentIndex);
}

/// Notifier that manages desktop web navigation history synchronization.
class WebNavigationNotifier extends StateNotifier<WebNavigationState> {
  WebNavigationNotifier() : super(const WebNavigationState());

  bool _isNavigatingInternally = false;

  /// Records a route update observed from the router or shell.
  /// Handles new destinations, browser Back/Forward synchronization,
  /// and deduplication.
  void recordRoute(String location) {
    final route = _normalize(location);
    if (route.isEmpty) return;

    if (_isNavigatingInternally) {
      _isNavigatingInternally = false;
      // If the route matches our expected destination, our index is already updated
      if (state.currentRoute == route) return;
    }

    // Deduplicate consecutive identical visits
    if (state.history.isNotEmpty && state.currentRoute == route) {
      return;
    }

    // 1. Check if browser Back button was used
    if (state.currentIndex > 0 &&
        state.history[state.currentIndex - 1] == route) {
      state = state.copyWith(currentIndex: state.currentIndex - 1);
      return;
    }

    // 2. Check if browser Forward button was used
    if (state.currentIndex >= 0 &&
        state.currentIndex < state.history.length - 1 &&
        state.history[state.currentIndex + 1] == route) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
      return;
    }

    // 3. Initial route entry
    if (state.history.isEmpty) {
      state = WebNavigationState(
        history: [route],
        currentIndex: 0,
      );
      return;
    }

    // 4. New route navigation: truncate any forward history and append
    final truncated = state.history.sublist(0, state.currentIndex + 1);
    final newHistory = List<String>.from(truncated)..add(route);
    state = WebNavigationState(
      history: newHistory,
      currentIndex: newHistory.length - 1,
    );
  }

  /// Navigates to the previous in-app destination.
  void goBack(BuildContext context) {
    if (!state.canGoBack) return;
    final targetIndex = state.currentIndex - 1;
    final targetRoute = state.history[targetIndex];
    _isNavigatingInternally = true;
    state = state.copyWith(currentIndex: targetIndex);
    context.go(targetRoute);
  }

  /// Navigates to the next in-app destination (after navigating back).
  void goForward(BuildContext context) {
    if (!state.canGoForward) return;
    final targetIndex = state.currentIndex + 1;
    final targetRoute = state.history[targetIndex];
    _isNavigatingInternally = true;
    state = state.copyWith(currentIndex: targetIndex);
    context.go(targetRoute);
  }

  /// Resets history state (useful for tests or logout).
  void reset() {
    _isNavigatingInternally = false;
    state = const WebNavigationState();
  }

  static String _normalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length > 1 && trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}

/// Provider for desktop web navigation state and actions.
final webNavigationProvider =
    StateNotifierProvider<WebNavigationNotifier, WebNavigationState>((ref) {
  return WebNavigationNotifier();
});
