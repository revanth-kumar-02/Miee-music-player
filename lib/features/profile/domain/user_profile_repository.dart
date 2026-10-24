import '../../onboarding/domain/artist_model.dart';
import 'user_profile.dart';

abstract class UserProfileRepository {
  Future<UserProfile?> getUserProfile(String uid);
  Future<void> saveUserProfile(UserProfile profile);
  Future<UserProfile> completeOnboarding({
    required String uid,
    required List<ArtistSummary> artists,
    String? displayName,
    String? email,
  });
  Future<void> clearCache(String uid);
}
