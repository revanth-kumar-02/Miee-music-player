import 'profile_model.dart';

abstract class ProfileRepository {
  Future<ProfileModel> getProfile();
  Future<void> saveProfile(ProfileModel profile);
}
