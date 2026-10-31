import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/utils/platform_file_helper.dart';

/// Reusable, cross-platform Profile Avatar widget.
/// Renders the user profile image inside a consistent circular shape.
/// Supports remote network URLs, Web base64 data URIs, native filesystem paths,
/// and asset images, with graceful initial/icon fallbacks.
class ProfileAvatar extends StatelessWidget {
  /// The image source URL, data URI, or local file path.
  final String? imageUrl;

  /// Width and height of the avatar. Defaults to 32.0.
  final double size;

  /// Optional user initials to show in fallback state (e.g. 'R').
  final String? fallbackInitials;

  /// Callback when the avatar is clicked.
  final VoidCallback? onTap;

  /// Optional border color for the circular avatar.
  final Color? borderColor;

  /// Optional border width. Defaults to 0.0 (no border).
  final double borderWidth;

  const ProfileAvatar({
    super.key,
    this.imageUrl,
    this.size = 32.0,
    this.fallbackInitials,
    this.onTap,
    this.borderColor,
    this.borderWidth = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatarContent = _buildImageContent();

    final avatarCircle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: borderWidth > 0 && borderColor != null
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: avatarContent,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: avatarCircle,
      );
    }

    return avatarCircle;
  }

  Widget _buildImageContent() {
    final url = imageUrl?.trim();

    if (url == null || url.isEmpty) {
      return _buildFallback();
    }

    // 1. Data URI (base64 image, ideal for Web)
    if (url.startsWith('data:image/')) {
      try {
        final commaIndex = url.indexOf(',');
        final base64Data = commaIndex != -1 ? url.substring(commaIndex + 1) : url;
        final bytes = base64Decode(base64Data);
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) => _buildFallback(),
        );
      } catch (_) {
        return _buildFallback();
      }
    }

    // 2. Remote HTTP/HTTPS URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }

    // 3. Local Asset image
    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        fit: BoxFit.cover,
        width: size,
        height: size,
        errorBuilder: (context, error, stackTrace) => _buildFallback(),
      );
    }

    // 4. Native Filesystem Path (Non-web only)
    if (!kIsWeb) {
      return PlatformFileHelper.buildFileImage(
        path: url,
        size: size,
        errorBuilder: _buildFallback,
      );
    }

    // Default fallback on unsupported configurations
    return _buildFallback();
  }

  Widget _buildFallback() {
    final initials = fallbackInitials?.trim();

    if (initials != null && initials.isNotEmpty) {
      final letter = initials[0].toUpperCase();
      return Container(
        width: size,
        height: size,
        color: const Color(0xFF4B0014), // Stitch primary bordeaux
        child: Center(
          child: Text(
            letter,
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: size * 0.44,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      color: const Color(0xFF4B0014), // Stitch primary bordeaux
      child: Center(
        child: Icon(
          Icons.person,
          size: size * 0.6,
          color: Colors.white,
        ),
      ),
    );
  }
}
