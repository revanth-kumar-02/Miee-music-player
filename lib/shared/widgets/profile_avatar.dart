import 'dart:io';
import 'package:flutter/material.dart';
import '../../app/theme/app_colors.dart';

/// Reusable Profile Avatar widget.
/// Renders the user profile image as a circle. Falls back to an icon if empty.
class ProfileAvatar extends StatelessWidget {
  /// The image source URL or local path.
  final String? imageUrl;

  /// Width and height of the avatar. Defaults to 32.0.
  final double size;

  /// Callback when the avatar is clicked.
  final VoidCallback? onTap;

  const ProfileAvatar({
    super.key,
    this.imageUrl,
    this.size = 32.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatarChild;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      if (imageUrl!.startsWith('http') || imageUrl!.startsWith('assets')) {
        avatarChild = Image.network(
          imageUrl!,
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      } else {
        avatarChild = Image.file(
          File(imageUrl!),
          fit: BoxFit.cover,
          width: size,
          height: size,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      }
    } else {
      avatarChild = _buildPlaceholder();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: avatarChild,
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: size,
      height: size,
      color: AppColors.surfaceContainerHigh,
      child: Icon(
        Icons.person_outline,
        size: size * 0.6,
        color: AppColors.onSurfaceVariant,
      ),
    );
  }
}
