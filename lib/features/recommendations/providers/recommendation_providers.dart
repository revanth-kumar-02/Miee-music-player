import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';
import '../../history/data/supabase_listening_history_repository.dart';
import '../../history/providers/history_providers.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../youtube/providers/youtube_providers.dart';
import '../data/recommendation_service.dart';
import '../data/taste_profile_repository.dart';
import '../data/trending_music_service.dart';
import '../domain/affinity_calculator.dart';
import '../domain/candidate_ranker.dart';
import '../domain/recommendation_diversity_filter.dart';
import '../domain/recommendation_scorer.dart';
import '../domain/user_taste_profile.dart';

/// Scorer provider
final recommendationScorerProvider = Provider<RecommendationScorer>((ref) {
  return const RecommendationScorer();
});

/// Diversity filter provider
final recommendationDiversityFilterProvider =
    Provider<RecommendationDiversityFilter>((ref) {
  return const RecommendationDiversityFilter();
});

/// Candidate ranker provider
final candidateRankerProvider = Provider<CandidateRanker>((ref) {
  final scorer = ref.watch(recommendationScorerProvider);
  final filter = ref.watch(recommendationDiversityFilterProvider);
  return CandidateRanker(scorer: scorer, diversityFilter: filter);
});

final trendingMusicServiceProvider = Provider<TrendingMusicService>((ref) {
  return TrendingMusicService();
});

final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  final ytRepo = ref.watch(youtubeRepositoryProvider);
  final artistRepo = ref.watch(artistRepositoryProvider);
  final historyRepo = ref.watch(listeningHistoryRepositoryProvider);
  final trendingService = ref.watch(trendingMusicServiceProvider);
  final tasteRepo = ref.watch(tasteProfileRepositoryProvider);
  final candidateRanker = ref.watch(candidateRankerProvider);

  return RecommendationService(
    youtubeRepo: ytRepo,
    artistRepo: artistRepo,
    historyRepo: historyRepo,
    trendingService: trendingService,
    tasteRepo: tasteRepo,
    candidateRanker: candidateRanker,
  );
});

final recommendationSectionsProvider =
    FutureProvider<RecommendationSections>((ref) async {
  final profile = ref.watch(currentUserProfileProvider);
  final service = ref.watch(recommendationServiceProvider);

  return service.getPersonalizedSections(profile: profile);
});

/// Deterministic affinity calculator instance provider (configurable half-life & sigmoid scale)
final affinityCalculatorProvider = Provider<AffinityCalculator>((ref) {
  return const AffinityCalculator(
    halfLifeDays: 14.0,
    sigmoidScale: 0.5,
  );
});

/// Taste profile repository provider
final tasteProfileRepositoryProvider = Provider<TasteProfileRepository>((ref) {
  final historyRepo = ref.watch(listeningHistoryRepositoryProvider);
  final calculator = ref.watch(affinityCalculatorProvider);

  return TasteProfileRepository(
    historyRepo: historyRepo is SupabaseListeningHistoryRepository
        ? historyRepo
        : SupabaseListeningHistoryRepository(),
    affinityCalculator: calculator,
  );
});

/// Reactive taste profile provider scoped strictly to the authenticated user ID
final userTasteProfileProvider = FutureProvider<UserTasteProfile>((ref) async {
  final user = ref.watch(currentAuthUserProvider);
  if (user == null || user.uid.isEmpty) {
    return UserTasteProfile.empty('');
  }

  final repo = ref.watch(tasteProfileRepositoryProvider);
  return repo.getProfile(user.uid);
});
