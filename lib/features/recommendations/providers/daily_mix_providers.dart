import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../history/providers/history_providers.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../youtube/providers/youtube_providers.dart';
import '../data/daily_mix_repository.dart';
import '../data/daily_mix_service.dart';
import '../domain/daily_mix.dart';
import 'recommendation_providers.dart';

final dailyMixRepositoryProvider = Provider<DailyMixRepository>((ref) {
  return DailyMixRepository();
});

final dailyMixServiceProvider = Provider<DailyMixService>((ref) {
  final candidateRanker = ref.watch(candidateRankerProvider);
  final scorer = ref.watch(recommendationScorerProvider);
  final repository = ref.watch(dailyMixRepositoryProvider);
  final tasteRepo = ref.watch(tasteProfileRepositoryProvider);
  final historyRepo = ref.watch(listeningHistoryRepositoryProvider);
  final trendingService = ref.watch(trendingMusicServiceProvider);
  final artistRepo = ref.watch(artistRepositoryProvider);
  final youtubeRepo = ref.watch(youtubeRepositoryProvider);
  final recService = ref.watch(recommendationServiceProvider);

  return DailyMixService(
    candidateRanker: candidateRanker,
    scorer: scorer,
    repository: repository,
    tasteRepo: tasteRepo,
    historyRepo: historyRepo,
    trendingService: trendingService,
    artistRepo: artistRepo,
    youtubeRepo: youtubeRepo,
    recommendationService: recService,
  );
});

/// Async notifier managing Daily Mix snapshots and explicit user refreshes.
class DailyMixNotifier extends AsyncNotifier<DailyMixSnapshot> {
  int _requestGeneration = 0;
  bool _isDisposed = false;

  @override
  Future<DailyMixSnapshot> build() async {
    final currentGen = ++_requestGeneration;
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
    });

    final authState = ref.watch(authControllerProvider);
    final initiatingUserId = authState.user?.id ?? '';
    final profile = ref.watch(currentUserProfileProvider);
    final service = ref.watch(dailyMixServiceProvider);

    final snapshot = await service.getDailyMixes(
      userId: initiatingUserId,
      profile: profile,
      forceRefresh: false,
    );

    // Validate after async boundary
    if (_isDisposed) return snapshot;
    final currentUserId = ref.read(authControllerProvider).user?.id ?? '';
    if (currentGen != _requestGeneration || currentUserId != initiatingUserId) {
      // Discard stale result if user changed or newer request superseded
      if (currentUserId.isNotEmpty) {
        return service.getDailyMixes(
          userId: currentUserId,
          profile: ref.read(currentUserProfileProvider),
          forceRefresh: false,
        );
      }
      return DailyMixSnapshot.empty(currentUserId);
    }

    return snapshot;
  }

  /// Explicit manual refresh requested by the user.
  Future<void> refresh() async {
    final currentGen = ++_requestGeneration;
    final authState = ref.read(authControllerProvider);
    final initiatingUserId = authState.user?.id ?? '';
    final profile = ref.read(currentUserProfileProvider);
    final service = ref.read(dailyMixServiceProvider);

    state = const AsyncValue.loading();
    try {
      final snapshot = await service.getDailyMixes(
        userId: initiatingUserId,
        profile: profile,
        forceRefresh: true,
      );

      // Verify before committing:
      // 1. Notifier has not been disposed or invalidated
      // 2. Request generation still matches latest request
      // 3. Current authenticated user matches initiating user
      if (_isDisposed) return;
      if (currentGen != _requestGeneration) {
        return;
      }
      final currentUserId = ref.read(authControllerProvider).user?.id ?? '';
      if (currentUserId != initiatingUserId) {
        return;
      }

      state = AsyncValue.data(snapshot);
    } catch (e, st) {
      if (_isDisposed) return;
      if (currentGen != _requestGeneration) return;
      final currentUserId = ref.read(authControllerProvider).user?.id ?? '';
      if (currentUserId != initiatingUserId) return;

      state = AsyncValue.error(e, st);
    }
  }
}

final dailyMixSnapshotProvider =
    AsyncNotifierProvider<DailyMixNotifier, DailyMixSnapshot>(DailyMixNotifier.new);

/// Convenience provider returning the list of Daily Mixes.
final dailyMixesProvider = FutureProvider<List<DailyMix>>((ref) async {
  final snapshot = await ref.watch(dailyMixSnapshotProvider.future);
  return snapshot.mixes;
});

