import 'profile_model.dart';

abstract class ProfileRepository {
  Future<ProfileModel> getProfile({String? userId, bool isGuest = false});
  Future<void> saveProfile(ProfileModel profile);
}
