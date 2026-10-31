import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/platform_file_helper.dart';

import '../../../core/sync/supabase_config.dart';
import '../../auth/providers/auth_providers.dart';
import '../presentation/profile_controller.dart';
import '../presentation/widgets/profile_picture_crop_dialog.dart';
import '../providers/profile_providers.dart';

class ProfileImageResult {
  final bool isSuccess;
  final bool isCancelled;
  final String? savedPathOrUrl;
  final String? errorMessage;

  const ProfileImageResult._({
    required this.isSuccess,
    this.isCancelled = false,
    this.savedPathOrUrl,
    this.errorMessage,
  });

  factory ProfileImageResult.success(String pathOrUrl) =>
      ProfileImageResult._(isSuccess: true, savedPathOrUrl: pathOrUrl);

  factory ProfileImageResult.cancelled() =>
      const ProfileImageResult._(isSuccess: false, isCancelled: true);

  factory ProfileImageResult.error(String message) =>
      ProfileImageResult._(isSuccess: false, errorMessage: message);
}

/// Centralized service handling profile picture selection, interactive cropping,
/// cross-platform persistence (Android filesystem + Web base64 data URI), and cloud synchronization.
class ProfileImageService {
  static final ImagePicker _picker = ImagePicker();

  /// Maximum allowed raw image size before rejection (15 MB)
  static const int maxFileSizeBytes = 15 * 1024 * 1024;

  /// Launches the image picker, validates the selected image, opens the interactive
  /// crop dialog, persists the resulting cropped JPEG, and synchronizes profile state.
  static Future<ProfileImageResult> selectAndCropProfilePicture({
    required BuildContext context,
    required WidgetRef ref,
    required ImageSource source,
  }) async {
    try {
      // 1. Pick image using platform picker
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 95,
      );

      if (pickedFile == null) {
        return ProfileImageResult.cancelled();
      }

      // 2. Read raw bytes (cross-platform compatible: works on web, Android, iOS)
      final Uint8List rawBytes = await pickedFile.readAsBytes();
      if (rawBytes.lengthInBytes < 16) {
        return ProfileImageResult.error('The selected file is too small or invalid.');
      }

      if (rawBytes.lengthInBytes > maxFileSizeBytes) {
        return ProfileImageResult.error(
          'Image size exceeds 15MB limit. Please select a smaller photo.',
        );
      }

      // 3. Fast validation: ensure image can be decoded
      img.Image? probe;
      try {
        probe = img.decodeImage(rawBytes);
      } catch (_) {
        return ProfileImageResult.error(
          'Unsupported or corrupted image file format.',
        );
      }

      if (probe == null) {
        return ProfileImageResult.error(
          'Unsupported or corrupted image file format.',
        );
      }

      if (!context.mounted) return ProfileImageResult.cancelled();

      // 4. Open interactive WhatsApp / Instagram style circular crop dialog
      final Uint8List? croppedBytes = await ProfilePictureCropDialog.show(
        context,
        rawBytes,
      );

      if (croppedBytes == null || croppedBytes.isEmpty) {
        return ProfileImageResult.cancelled();
      }

      // 5. Cross-platform persistence
      String savedPathOrReference;

      if (kIsWeb) {
        // Web platform: Store as optimized base64 data URI in Hive
        final base64String = base64Encode(croppedBytes);
        savedPathOrReference = 'data:image/jpeg;base64,$base64String';
      } else {
        // Android / Desktop / iOS: Save to application documents directory
        final appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final targetPath = '${appDir.path}/profile_avatar_$timestamp.jpg';

        savedPathOrReference = await PlatformFileHelper.writeBytes(targetPath, croppedBytes);

        // Clean up previous avatar file if exists
        final currentPath = ref.read(profileProvider).profilePicturePath;
        if (currentPath != null &&
            currentPath.isNotEmpty &&
            !currentPath.startsWith('http') &&
            !currentPath.startsWith('data:')) {
          await PlatformFileHelper.delete(currentPath);
        }
      }

      // 6. Optional cloud upload to Supabase Storage if user is authenticated
      final authUser = ref.read(currentAuthUserProvider);
      if (authUser != null && SupabaseConfig.hasActiveSupabase) {
        try {
          final client = Supabase.instance.client;
          final cloudFileName = 'avatar_${authUser.uid}.jpg';

          await client.storage.from('avatars').uploadBinary(
                cloudFileName,
                croppedBytes,
                fileOptions: const FileOptions(
                  upsert: true,
                  contentType: 'image/jpeg',
                ),
              );

          final publicUrl =
              client.storage.from('avatars').getPublicUrl(cloudFileName);

          // Update cloud UserProfile record
          final userProfileRepo = ref.read(userProfileRepositoryProvider);
          final existingCloud =
              await userProfileRepo.getUserProfile(authUser.uid);
          if (existingCloud != null) {
            final updatedCloud = existingCloud.copyWith(avatarUrl: publicUrl);
            await userProfileRepo.saveUserProfile(updatedCloud);
            ref
                .read(userProfileNotifierProvider.notifier)
                .updateProfileLocally(updatedCloud);
          }
        } catch (e) {
          debugPrint(
            '[ProfileImageService] Cloud avatar upload warning: $e (persisted locally)',
          );
        }
      }

      // 7. Update local reactive ProfileController & state
      final activeProfile = ref.read(profileProvider);
      await ref.read(profileProvider.notifier).updateProfile(
            displayName: activeProfile.displayName,
            username: activeProfile.username,
            profilePicturePath: savedPathOrReference,
            favoriteGenre: activeProfile.favoriteGenre,
            favoriteArtist: activeProfile.favoriteArtist,
          );

      // Also ensure cloud notifier state is refreshed locally
      final cloudProfileState = ref.read(userProfileNotifierProvider).profile;
      if (cloudProfileState != null) {
        ref.read(userProfileNotifierProvider.notifier).updateProfileLocally(
              cloudProfileState.copyWith(avatarUrl: savedPathOrReference),
            );
      }

      return ProfileImageResult.success(savedPathOrReference);
    } catch (e) {
      debugPrint('[ProfileImageService] Failed to crop and save profile image: $e');
      return ProfileImageResult.error('Failed to process image: ${e.toString()}');
    }
  }

  /// Removes the custom profile photo and restores default avatar.
  static Future<void> removeProfilePicture(WidgetRef ref) async {
    final currentPath = ref.read(profileProvider).profilePicturePath;

    // Delete local file on non-web if present
    if (!kIsWeb &&
        currentPath != null &&
        currentPath.isNotEmpty &&
        !currentPath.startsWith('http') &&
        !currentPath.startsWith('data:')) {
      await PlatformFileHelper.delete(currentPath);
    }

    // Reset local profile
    await ref.read(profileProvider.notifier).removeProfilePicture();

    // Reset cloud profile avatarUrl if authenticated
    final authUser = ref.read(currentAuthUserProvider);
    if (authUser != null && SupabaseConfig.hasActiveSupabase) {
      try {
        final userProfileRepo = ref.read(userProfileRepositoryProvider);
        final existingCloud =
            await userProfileRepo.getUserProfile(authUser.uid);
        if (existingCloud != null) {
          final updatedCloud = existingCloud.copyWith(avatarUrl: null);
          await userProfileRepo.saveUserProfile(updatedCloud);
          ref
              .read(userProfileNotifierProvider.notifier)
              .updateProfileLocally(updatedCloud);
        }
      } catch (_) {}
    }
  }
}
