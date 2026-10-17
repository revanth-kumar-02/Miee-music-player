import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../shared/widgets/miee_logo.dart';

/// Centralized design tokens for Miee's reference aesthetic.
abstract class AuthPalette {
  /// Vanilla Cream background canvas: `#F8F1E8`
  static const Color background = Color(0xFFF8F1E8);

  /// Card surface
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Subtle card and container border
  static const Color cardBorder = Color(0xFFE7DED5);

  /// Soft warm card elevation shadow
  static const Color cardShadow = Color(0x0F3A252B);

  /// Cocoa Plum primary button action: `#3A252B`
  static const Color primaryButton = Color(0xFF3A252B);
  static const Color primaryButtonHover = Color(0xFF2B1A20);
  static const Color primaryButtonDisabled = Color(0xFF75656A);

  /// Dusty Rose brand accent & links: `#D78D9B`
  static const Color accent = Color(0xFFD78D9B);

  /// Soft Clay secondary accent: `#E9C9B7`
  static const Color softClay = Color(0xFFE9C9B7);

  /// Cocoa Plum primary text: `#3A252B`
  static const Color textCocoa = Color(0xFF3A252B);

  /// Muted Mauve secondary text: `#75656A`
  static const Color textMuted = Color(0xFF75656A);

  /// Form input background fill
  static const Color inputFill = Color(0xFFFCFAF7);

  /// Subtle neutral input border
  static const Color inputBorder = Color(0xFFE7DED5);

  /// Focused input ring border
  static const Color inputFocusBorder = Color(0xFF3A252B);

  /// Error color
  static const Color errorRed = Color(0xFFBA3A37);
  static const Color errorContainer = Color(0xFFFDF3F2);
}

/// Shared responsive wrapper for authentication views.
/// Renders the reference's decorative warm-toned background with oversized abstract shapes.
class AuthScaffold extends StatelessWidget {
  final Widget child;

  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;

    return Scaffold(
      backgroundColor: AuthPalette.background,
      body: Stack(
        children: [
          // Background abstract shapes painter
          Positioned.fill(
            child: CustomPaint(
              painter: _WarmAbstractBackgroundPainter(),
            ),
          ),

          // Foreground form content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isCompact ? 20.0 : 32.0,
                  vertical: 24.0,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paints oversized warm abstract shapes matching the reference login screen.
class _WarmAbstractBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Soft Clay curve on top-right
    final paint1 = Paint()
      ..color = const Color(0xFFE9C9B7).withOpacity(0.35)
      ..style = PaintingStyle.fill;
    final path1 = Path()
      ..moveTo(w * 0.6, 0)
      ..cubicTo(w * 0.7, h * 0.25, w, h * 0.15, w, h * 0.45)
      ..lineTo(w, 0)
      ..close();
    canvas.drawPath(path1, paint1);

    // 2. Dusty Rose wave on bottom-left
    final paint2 = Paint()
      ..color = const Color(0xFFD78D9B).withOpacity(0.20)
      ..style = PaintingStyle.fill;
    final path2 = Path()
      ..moveTo(0, h * 0.4)
      ..cubicTo(w * 0.25, h * 0.55, w * 0.15, h * 0.85, 0, h)
      ..close();
    canvas.drawPath(path2, paint2);

    // 3. Cocoa Plum soft curve on bottom-right
    final paint3 = Paint()
      ..color = const Color(0xFF3A252B).withOpacity(0.08)
      ..style = PaintingStyle.fill;
    final path3 = Path()
      ..moveTo(w, h * 0.65)
      ..cubicTo(w * 0.8, h * 0.8, w * 0.85, h, w, h)
      ..close();
    canvas.drawPath(path3, paint3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Shared centered card container constrained to ~440px with responsive padding.
class AuthCard extends StatelessWidget {
  final Widget child;

  const AuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 600;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Container(
        decoration: BoxDecoration(
          color: AuthPalette.cardSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AuthPalette.cardBorder,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AuthPalette.cardShadow,
              blurRadius: 36,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 24.0 : 36.0,
          vertical: isCompact ? 28.0 : 36.0,
        ),
        child: child,
      ),
    );
  }
}

/// Shared branding header for Miee authentication screens.
class AuthBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  const AuthBrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: InkWell(
                onTap: onBack,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.arrow_back_rounded,
                        size: 18,
                        color: AuthPalette.textCocoa,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Back',
                        style: GoogleFonts.geist(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AuthPalette.textCocoa,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // Miee Wave Symbol + Logo Wordmark
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const MieeWaveSymbol(size: 32, color: AuthPalette.accent),
              const SizedBox(width: 8),
              Text(
                'miee',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: AuthPalette.textCocoa,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // Tagline
        Center(
          child: Text(
            'Your personal sound sanctuary',
            textAlign: TextAlign.center,
            style: GoogleFonts.geist(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: AuthPalette.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Welcome Back / Page Heading
        Text(
          title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AuthPalette.textCocoa,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: GoogleFonts.geist(
              fontSize: 13,
              color: AuthPalette.textMuted,
            ),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

/// Shared custom styled text field for authentication forms.
class AuthTextField extends StatelessWidget {
  final String label;
  final String hintText;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final IconData prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.controller,
    required this.prefixIcon,
    this.focusNode,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.geist(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AuthPalette.textCocoa,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          style: GoogleFonts.geist(
            fontSize: 14,
            color: AuthPalette.textCocoa,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.geist(
              fontSize: 13.5,
              color: AuthPalette.textMuted.withOpacity(0.6),
            ),
            prefixIcon: Icon(
              prefixIcon,
              color: AuthPalette.textMuted,
              size: 19,
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: AuthPalette.inputFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AuthPalette.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AuthPalette.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(
                color: AuthPalette.inputFocusBorder,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AuthPalette.errorRed),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AuthPalette.errorRed, width: 1.5),
            ),
            errorStyle: GoogleFonts.geist(
              fontSize: 12,
              color: AuthPalette.errorRed,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

/// Primary Cocoa Plum button for Authentication submission.
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AuthPalette.primaryButton,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AuthPalette.primaryButtonDisabled,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.geist(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}

/// Social Provider authentication buttons (Google, GitHub, Email).
class AuthSocialButtons extends StatelessWidget {
  final VoidCallback onGooglePressed;
  final VoidCallback? onGithubPressed;
  final VoidCallback? onEmailPressed;

  const AuthSocialButtons({
    super.key,
    required this.onGooglePressed,
    this.onGithubPressed,
    this.onEmailPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // "or continue with" divider
        Row(
          children: [
            const Expanded(
              child: Divider(color: AuthPalette.cardBorder, height: 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'or continue with',
                style: GoogleFonts.geist(
                  fontSize: 12,
                  color: AuthPalette.textMuted,
                ),
              ),
            ),
            const Expanded(
              child: Divider(color: AuthPalette.cardBorder, height: 1),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Social icon buttons row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialCircle(
              icon: Icons.g_mobiledata_rounded,
              iconSize: 28,
              onPressed: onGooglePressed,
              tooltip: 'Sign in with Google',
            ),
            if (onGithubPressed != null) ...[
              const SizedBox(width: 14),
              _buildSocialCircle(
                icon: Icons.code_rounded,
                iconSize: 20,
                onPressed: onGithubPressed!,
                tooltip: 'Sign in with GitHub',
              ),
            ],
            if (onEmailPressed != null) ...[
              const SizedBox(width: 14),
              _buildSocialCircle(
                icon: Icons.mail_outline_rounded,
                iconSize: 20,
                onPressed: onEmailPressed!,
                tooltip: 'Sign in with Email',
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSocialCircle({
    required IconData icon,
    required double iconSize,
    required VoidCallback onPressed,
    required String tooltip,
  }) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AuthPalette.inputFill,
        shape: BoxShape.circle,
        border: Border.all(color: AuthPalette.cardBorder, width: 1.0),
      ),
      child: IconButton(
        icon: Icon(icon, size: iconSize, color: AuthPalette.textCocoa),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
