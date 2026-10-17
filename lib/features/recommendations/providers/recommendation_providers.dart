import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../history/providers/history_providers.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../profile/providers/profile_providers.dart';
import '../../youtube/providers/youtube_providers.dart';
import '../data/recommendation_service.dart';

final recommendationServiceProvider = Provider<RecommendationService>((ref) {
  final ytRepo = ref.watch(youtubeRepositoryProvider);
  final artistRepo = ref.watch(artistRepositoryProvider);
  final historyRepo = ref.watch(listeningHistoryRepositoryProvider);

  return RecommendationService(
    youtubeRepo: ytRepo,
    artistRepo: artistRepo,
    historyRepo: historyRepo,
  );
});

final recommendationSectionsProvider =
    FutureProvider<RecommendationSections>((ref) async {
  final profile = ref.watch(currentUserProfileProvider);
  final service = ref.watch(recommendationServiceProvider);

  return service.getPersonalizedSections(profile: profile);
});
