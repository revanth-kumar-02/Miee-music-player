import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../shared/widgets/miee_brand_header.dart';
import '../../../../shared/widgets/miee_brand_mark.dart';

/// Nordic Cobalt & Warm Ivory Authentication Design Tokens.
abstract class MieeAuthTheme {
  /// Warm Ivory / Cream Substrate Canvas: `#FCF3EE` (seamlessly blends with `login_collage.png`)
  static const Color background = Color(0xFFFCF3EE);

  /// Panel Surface: `#FCF4EF` (warm ivory registration sheet)
  static const Color panelSurface = Color(0xFFFCF4EF);

  /// Signature Nordic Cobalt Blue: `#0038BA`
  static const Color cobaltBlue = Color(0xFF0038BA);
  static const Color primaryButton = Color(0xFF0038BA);
  static const Color primaryButtonDisabled = Color(0x660038BA);

  /// Deep Charcoal Text: `#111111`
  static const Color textPrimary = Color(0xFF111111);

  /// Secondary Body / Subtitle: `#6E6966`
  static const Color textSecondary = Color(0xFF6E6966);

  /// Muted Text / Placeholder: `#8B8580`
  static const Color textMuted = Color(0xFF8B8580);

  /// Field Fill: `#FEF6F2`
  static const Color fieldFill = Color(0xFFFEF6F2);

  /// Subtle Field Hairline Border: `#EADBCE`
  static const Color fieldBorder = Color(0xFFEADBCE);

  /// Focused Field Border: `#0038BA`
  static const Color fieldFocusedBorder = Color(0xFF0038BA);

  /// Field Leading Icon: `#5A524E`
  static const Color fieldIcon = Color(0xFF5A524E);

  /// Guest Button Border: `#DFD5CC`
  static const Color guestBorder = Color(0xFFDFD5CC);

  /// Dynamic Password Requirement Success: `#16A34A`
  static const Color successGreen = Color(0xFF16A34A);

  /// Error Banner Red: `#DC2626`
  static const Color errorRed = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEE2E2);
}

/// Centralized design tokens for Miee's Stitch Editorial aesthetic (retained for backward compatibility).
abstract class AuthPalette {
  /// Base paper substrate canvas: `#FAF8F5`
  static const Color background = Color(0xFFFAF8F5);

  /// Pure white surface container: `#FFFFFF`
  static const Color cardSurface = Color(0xFFFFFFFF);

  /// Thin hairline border: `#E3E2E0`
  static const Color cardBorder = Color(0xFFE3E2E0);

  /// Subtle contact edge shadow
  static const Color cardShadow = Color(0x0C1A0F12);

  /// Signature Nordic Cobalt primary: `#0047FF`
  static const Color primaryButton = Color(0xFF0047FF);
  static const Color primaryButtonHover = Color(0xFF003ECC);
  static const Color primaryButtonDisabled = Color(0x660047FF);

  /// Highlight & dot: `#0047FF`
  static const Color accent = Color(0xFF0047FF);
  static const Color secondary = Color(0xFF0047FF);

  /// Deep Charcoal neutral text: `#111111`
  static const Color textCocoa = Color(0xFF111111);
  static const Color textPrimary = Color(0xFF111111);

  /// Muted Dust secondary metadata text: `#6E6966`
  static const Color textMuted = Color(0xFF6E6966);
  static const Color textSecondary = Color(0xFF6E6966);

  /// Form input background fill: `#FBF8F5`
  static const Color inputFill = Color(0xFFFBF8F5);

  /// Subtle neutral input border: `#E8E0D8`
  static const Color inputBorder = Color(0xFFE8E0D8);

  /// Focused input ring border: `#0047FF`
  static const Color inputFocusBorder = Color(0xFF0047FF);

  /// Error color: `#DC2626`
  static const Color errorRed = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEE2E2);
}

/// Faithful reproduction of the Miee Brand Mark:
/// Cobalt blue rounded square with 5 white soundwave bars + `miee.` typography.
class MieeAuthBrandMark extends StatelessWidget {
  final double emblemSize;
  final double fontSize;

  const MieeAuthBrandMark({
    super.key,
    this.emblemSize = 38,
    this.fontSize = 26,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Blue rounded square emblem with white soundwave
        Container(
          width: emblemSize,
          height: emblemSize,
          decoration: BoxDecoration(
            color: MieeAuthTheme.cobaltBlue,
            borderRadius: BorderRadius.circular(emblemSize * 0.28),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _bar(6),
                const SizedBox(width: 2.2),
                _bar(13),
                const SizedBox(width: 2.2),
                _bar(18),
                const SizedBox(width: 2.2),
                _bar(13),
                const SizedBox(width: 2.2),
                _bar(6),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        MieeWordmarkDot(
          fontSize: fontSize,
          textColor: MieeAuthTheme.textPrimary,
          dotColor: MieeAuthTheme.cobaltBlue,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.6,
        ),
      ],
    );
  }

  Widget _bar(double height) {
    return Container(
      width: 2.4,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1.2),
      ),
    );
  }
}

/// Custom input field matching the reference designs:
/// 16px radius, subtle border, leading icon, clean hint.
class AuthTextField extends StatelessWidget {
  final String label;
  final String hintText;
  final bool showLabel;
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
    this.showLabel = true,
    required this.controller,
    this.prefixIcon,
    this.focusNode,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.validator,
    this.borderRadius = 16.0,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLabel) ...[
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: labelFontSize ?? 12,
              fontWeight: FontWeight.w600,
              color: MieeAuthTheme.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
        ],
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
            fontSize: fontSize ?? 15,
            fontWeight: FontWeight.w500,
            color: MieeAuthTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: fontSize ?? 14.5,
              fontWeight: FontWeight.w400,
              color: MieeAuthTheme.textMuted,
            ),
            prefixIcon: prefixIcon != null
                ? Padding(
                    padding: const EdgeInsets.only(left: 14, right: 12),
                    child: Icon(
                      prefixIcon,
                      color: MieeAuthTheme.fieldIcon,
                      size: 20,
                    ),
                  )
                : null,
            prefixIconConstraints: const BoxConstraints(
              minWidth: 46,
              minHeight: 20,
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: MieeAuthTheme.fieldFill,
            contentPadding: contentPadding ??
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: MieeAuthTheme.fieldBorder, width: 1.2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: MieeAuthTheme.fieldBorder, width: 1.2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(
                color: MieeAuthTheme.fieldFocusedBorder,
                width: 1.5,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide: const BorderSide(color: MieeAuthTheme.errorRed, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(borderRadius),
              borderSide:
                  const BorderSide(color: MieeAuthTheme.errorRed, width: 1.5),
            ),
            errorStyle: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: MieeAuthTheme.errorRed,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }
}

/// Primary Pill Button with Cobalt Blue fill and forward arrow (`→`).
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
    this.trailingIcon = Icons.arrow_forward_rounded,
    this.borderRadius = 27.0, // Default 54px pill
    this.height = 54,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height ?? 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: MieeAuthTheme.cobaltBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: MieeAuthTheme.primaryButtonDisabled,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: fontSize ?? 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (trailingIcon != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      trailingIcon,
                      size: 18,
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Outlined Guest Action Pill Button with Play Triangle icon.
class MieeGuestOutlineButton extends StatelessWidget {
  final VoidCallback onPressed;
  final double height;

  const MieeGuestOutlineButton({
    super.key,
    required this.onPressed,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: MieeAuthTheme.guestBorder, width: 1.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(height / 2),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.play_arrow_outlined,
              size: 20,
              color: MieeAuthTheme.textPrimary,
            ),
            const SizedBox(width: 8),
            Text(
              'Continue as Guest',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: MieeAuthTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal divider with centered "or" label.
class MieeOrDivider extends StatelessWidget {
  const MieeOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Divider(
            color: MieeAuthTheme.guestBorder,
            thickness: 1,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: MieeAuthTheme.textMuted,
            ),
          ),
        ),
        const Expanded(
          child: Divider(
            color: MieeAuthTheme.guestBorder,
            thickness: 1,
          ),
        ),
      ],
    );
  }
}

/// Shared responsive scaffold for authentication views (retained for compatibility).
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
    final isDesktop = width >= 900;

    return Scaffold(
      backgroundColor: MieeAuthTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            if (isDesktop && desktopHeader != null) desktopHeader!,
            Expanded(
              child: Center(
                child: SingleChildScrollView(
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

/// Desktop standard navigation header.
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

/// Desktop standard footer.
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
                  color: MieeAuthTheme.textMuted,
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
        color: MieeAuthTheme.textMuted,
        fontWeight: FontWeight.w400,
      ),
    );
  }

  Widget _dot() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        '•',
        style: TextStyle(
          fontSize: 12,
          color: MieeAuthTheme.textMuted,
        ),
      ),
    );
  }
}

/// Clean container for forms.
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

/// Shared branding header for authentication screens.
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showEmblem) ...[
          const MieeAuthBrandMark(),
          const SizedBox(height: 18),
        ],
        Text(
          title,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            color: MieeAuthTheme.textPrimary,
            height: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: MieeAuthTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}
