import 'package:flutter_riverpod/flutter_riverpod.dart';

enum SyncStatus { idle, syncing, success, error }

class SyncState {
  final SyncStatus status;
  final String? message;
  final DateTime? lastSynced;

  const SyncState({
    required this.status,
    this.message,
    this.lastSynced,
  });

  factory SyncState.initial() {
    return const SyncState(status: SyncStatus.idle);
  }

  SyncState copyWith({
    SyncStatus? status,
    String? message,
    DateTime? lastSynced,
  }) {
    return SyncState(
      status: status ?? this.status,
      message: message ?? this.message,
      lastSynced: lastSynced ?? this.lastSynced,
    );
  }
}

class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier() : super(SyncState.initial());

  void setSyncing() {
    state = state.copyWith(status: SyncStatus.syncing);
  }

  void setSuccess(DateTime lastSynced) {
    state = state.copyWith(status: SyncStatus.success, lastSynced: lastSynced);
  }

  void setError(String message) {
    state = state.copyWith(status: SyncStatus.error, message: message);
  }

  void reset() {
    state = SyncState.initial();
  }
}

final syncStateProvider = StateNotifierProvider<SyncStateNotifier, SyncState>((ref) {
  return SyncStateNotifier();
});
