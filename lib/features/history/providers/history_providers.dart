import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/listening_history_repository.dart';
import '../domain/listening_event.dart';

final listeningHistoryRepositoryProvider = Provider<ListeningHistoryRepository>((ref) {
  return FirestoreListeningHistoryRepository();
});

final recentListeningHistoryProvider = FutureProvider<List<ListeningEvent>>((ref) async {
  final user = ref.watch(currentAuthUserProvider);
  final repo = ref.watch(listeningHistoryRepositoryProvider);
  return repo.getRecentHistory(uid: user?.uid);
});
