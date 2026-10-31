import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/widgets/miee_brand_mark.dart';

/// Centralized design tokens for Miee's Stitch Editorial Tactility aesthetic.
abstract class AuthPalette {
  /// Base paper substrate canvas: `#FAF9F7`
  static const Color background = Color(0xFFFAF9F7);

  /// Pure white surface container lowest: `#FFFFFF`
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Thin hairline border: `#E3E2E0`
  static const Color cardBorder = Color(0xFFE3E2E0);

  /// Subtle contact edge shadow
  static const Color cardShadow = Color(0x0C1A0F12);

  /// Bordeaux Accent primary button & brand anchor: `#6E0D25`
  static const Color primaryButton = Color(0xFF6E0D25);
  static const Color primaryButtonHover = Color(0xFF580A1D);
  static const Color primaryButtonDisabled = Color(0x666E0D25);

  /// Punch Crimson highlight & dot: `#BA0032`
  static const Color accent = Color(0xFFBA0032);
  static const Color secondary = Color(0xFFBA0032);

  /// Deep Charcoal neutral text: `#1A0F12`
  static const Color textCocoa = Color(0xFF1A0F12);
  static const Color textPrimary = Color(0xFF1A0F12);

  /// Muted Dust secondary metadata text: `#67595C` / `#736B6E`
  static const Color textMuted = Color(0xFF736B6E);
  static const Color textSecondary = Color(0xFF564243);

  /// Form input background fill: `#FFFFFF`
  static const Color inputFill = Color(0xFFFFFFFF);

  /// Subtle neutral input border: `#E3E2E0`
  static const Color inputBorder = Color(0xFFE3E2E0);

  /// Focused input ring border: `#6E0D25`
  static const Color inputFocusBorder = Color(0xFF6E0D25);

  /// Error color: `#BA1A1A`
  static const Color errorRed = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);
}

/// Shared responsive scaffold for authentication views.
/// Adheres strictly to the Stitch `#FAF9F7` canvas with optional desktop headers/footers.
class AuthScaffold extends StatelessWidget {
  final Widget child;
  final Widget? desktopHeader;
  final Widget? desktopFooter;

  const AuthScaffold({
    super.key,
    required this.child,
    this.desktopHeader,
    this.desktopFooter,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final isDesktop = width >= 900;
    final isCompactHeight = height < 860;

    return Scaffold(
      backgroundColor: AuthPalette.background,
      body: SafeArea(
        child: Column(
          children: [
            if (isDesktop && desktopHeader != null) desktopHeader!,
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isDesktop ? 40.0 : 24.0,
                    vertical: isDesktop
                        ? (isCompactHeight ? 8.0 : 16.0)
                        : 16.0,
                  ),
                  child: child,
                ),
              ),
            ),
            if (isDesktop && desktopFooter != null) desktopFooter!,
          ],
        ),
      ),
    );
  }
}

/// Desktop standard navigation header matching Stitch `16_desktop_miee_web_login_clean_auth.html`.
class AuthDesktopHeader extends StatelessWidget {
  final bool? isCompact;
  const AuthDesktopHeader({super.key, this.isCompact});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final compact = isCompact ?? (height < 860);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 48,
        vertical: compact ? 12 : 20,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          MieeBrandMark.soundwaveWordmark(fontSize: compact ? 22 : 24),
        ],
      ),
    );
  }
}

/// Desktop standard footer matching Stitch `16_desktop_miee_web_login_clean_auth.html`.
class AuthDesktopFooter extends StatelessWidget {
  final bool? isCompact;
  const AuthDesktopFooter({super.key, this.isCompact});

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    final compact = isCompact ?? (height < 860);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 48,
        vertical: compact ? 8 : 16,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '© 2024 miee audio systems inc.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: compact ? 11 : 12,
                  color: AuthPalette.textMuted,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Row(
                children: [
                  _footerLink('Terms', fontSize: compact ? 11 : 12),
                  _dot(),
                  _footerLink('Privacy', fontSize: compact ? 11 : 12),
                  _dot(),
                  _footerLink('Help', fontSize: compact ? 11 : 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footerLink(String label, {double fontSize = 12}) {
    return Text(
      label,
      style: GoogleFonts.plusJakartaSans(
        fontSize: fontSize,
        color: AuthPalette.textMuted,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  Widget _dot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        '•',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 12,
          color: AuthPalette.textMuted,
        ),
      ),
    );
  }


}

/// Clean container matching Stitch:
/// On mobile, borderless full-bleed form width; on desktop, max 440px-460px width.
class AuthCard extends StatelessWidget {
  final Widget child;

  const AuthCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: isDesktop ? 440 : 400,
      ),
      child: child,
    );
  }
}

/// Shared branding header for Miee authentication screens matching Stitch references.
class AuthBrandHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final bool showEmblem;

  const AuthBrandHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.showEmblem = true,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width >= 900;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          isDesktop ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        if (onBack != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: IconButton(
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back_rounded,
                  color: AuthPalette.textPrimary,
                  size: 24,
                ),
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
          ),

        // Brand Emblem (Centered on mobile, hidden or compact if desktop has top bar)
        if (showEmblem && !isDesktop) ...[
          const Center(
            child: MieeBrandMark.emblem(
              emblemSize: 52,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 28),
        ],

        // Heading & Narrative
        Text(
          title,
          textAlign: isDesktop ? TextAlign.left : TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: isDesktop ? 32 : 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: AuthPalette.textPrimary,
            height: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            textAlign: isDesktop ? TextAlign.left : TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: AuthPalette.textSecondary,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

/// Custom input field strictly matching Stitch's 52px rounded-xl design.
class AuthTextField extends StatelessWidget {
  final String label;
  final String hintText;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final String? Function(String?)? validator;
  final double borderRadius;
  final EdgeInsetsGeometry? contentPadding;
  final double? fontSize;
  final double? labelFontSize;
  final Iterable<String>? autofillHints;
  final bool autocorrect;

  const AuthTextField({
    super.key,
    required this.label,
    required this.hintText,
    required this.controller,
    this.prefixIcon,
    this.focusNode,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.validator,
    this.borderRadius = 12.0,
    this.contentPadding,
    this.fontSize,
    this.labelFontSize,
    this.autofillHints,
    this.autocorrect = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: labelFontSize ?? 12,
            fontWeight: FontWeight.w600,
            color: AuthPalette.textPrimary,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          obscureText: obscureText,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          autofillHints: autofillHints,
          autocorrect: autocorrect,
          style: GoogleFonts.plusJakartaSans(
            fontSize: fontSize ?? 14,
            fontWeight: FontWeight.w500,
            color: AuthPalette.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: fontSize ?? 14,
              color: AuthPalette.textMuted.withValues(alpha: 0.6),
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    color: AuthPalette.textMuted,
                    size: 18,
                  )
                : null,
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: AuthPalette.inputFill,
            contentPadding: contentPadding ??
                const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: AuthPalette.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: AuthPalette.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(
                color: AuthPalette.inputFocusBorder,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: AuthPalette.errorRed),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide:
                  const BorderSide(color: AuthPalette.errorRed, width: 1.5),
            ),
            errorStyle: GoogleFonts.plusJakartaSans(
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

/// Primary Pill Button for Authentication submission (`#6E0D25` Bordeaux).
class AuthPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? trailingIcon;
  final double borderRadius;
  final double? height;
  final double? fontSize;

  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.trailingIcon,
    this.borderRadius = 9999.0, // Default pill
    this.height,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height ?? 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AuthPalette.primaryButton,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AuthPalette.primaryButtonDisabled,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: fontSize ?? 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      trailingIcon,
                      size: 17,
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
