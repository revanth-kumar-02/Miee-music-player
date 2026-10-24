import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';
import '../data/supabase_listening_history_repository.dart';
import '../domain/listening_event.dart';
import '../domain/listening_history_repository.dart';

final listeningHistoryRepositoryProvider = Provider<ListeningHistoryRepository>((ref) {
  return SupabaseListeningHistoryRepository();
});

final recentListeningHistoryProvider = FutureProvider<List<ListeningEvent>>((ref) async {
  final user = ref.watch(currentAuthUserProvider);
  final repo = ref.watch(listeningHistoryRepositoryProvider);
  return repo.getRecentHistory(uid: user?.uid);
});
