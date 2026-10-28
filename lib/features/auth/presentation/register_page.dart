import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_providers.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/providers/profile_providers.dart';
import '../../profile/presentation/profile_controller.dart';
import 'widgets/auth_components.dart';
import '../../../shared/widgets/miee_brand_header.dart';

/// Recreated Register Screen strictly matching Stitch:
/// - Mobile: `02_mobile_miee_mobile_register.html`
/// - Desktop / Web: `12_desktop_miee_web_register.html`
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _confirmPasswordFocusNode = FocusNode();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _confirmPasswordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      ref.read(guestModeProvider.notifier).state = false;
      final authRepo = ref.read(authRepositoryProvider);
      final rawName = _nameController.text.trim();
      final authUser = await authRepo.signUpWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        displayName: rawName,
      );

      // Immediately persist user's chosen display name
      final chosenName = rawName.isNotEmpty ? rawName : (authUser.displayName ?? '');
      if (chosenName.isNotEmpty) {
        final initialProfile = UserProfile.initial(
          uid: authUser.uid,
          email: authUser.email,
          displayName: chosenName,
        );
        final userProfileRepo = ref.read(userProfileRepositoryProvider);
        await userProfileRepo.saveUserProfile(initialProfile);
        ref.read(userProfileNotifierProvider.notifier).updateProfileLocally(initialProfile);

        final localProfile = ref.read(profileProvider);
        await ref.read(profileProvider.notifier).updateProfile(
          displayName: chosenName,
          favoriteGenre: localProfile.favoriteGenre,
          favoriteArtist: localProfile.favoriteArtist,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final isDesktop = width >= 900;
    final isCompact = height < 860;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/login');
          }
        }
      },
      child: AuthScaffold(
        desktopHeader: AuthDesktopHeader(isCompact: isCompact),
        desktopFooter: AuthDesktopFooter(isCompact: isCompact),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 1060 : 440,
            ),
            child: isDesktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left Column: Register Form
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: isCompact ? 36.0 : 48.0,
                          ),
                          child: _buildFormContent(
                            isDesktop: true,
                            isCompact: isCompact,
                          ),
                        ),
                      ),
                      // Right Column: Optimized Archival Artwork Showcase
                      Expanded(
                        flex: 6,
                        child: Center(
                          child: _buildDesktopShowcaseCard(
                            isCompact: isCompact,
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildFormContent(
                    isDesktop: false,
                    isCompact: false,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent({
    required bool isDesktop,
    required bool isCompact,
  }) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mobile Top Back Nav
          if (!isDesktop) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/login');
                  }
                },
                tooltip: 'Go to login',
                color: AuthPalette.textPrimary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ),
            const SizedBox(height: 12),
            // Mobile Brand Emblem & Wordmark Row
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AuthPalette.primaryButton,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: SizedBox(
                      height: 14,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          _buildBar(height: 8),
                          const SizedBox(width: 2),
                          _buildBar(height: 14),
                          const SizedBox(width: 2),
                          _buildBar(height: 6),
                          const SizedBox(width: 2),
                          _buildBar(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const MieeWordmarkDot(
                  fontSize: 22,
                  textColor: AuthPalette.textPrimary,
                  dotColor: AuthPalette.accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ],
            ),
            const SizedBox(height: 20),
          ] else ...[
            // Desktop Category Pill
            Row(
              children: [
                Container(
                  width: isCompact ? 7 : 8,
                  height: isCompact ? 7 : 8,
                  decoration: const BoxDecoration(
                    color: AuthPalette.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'SOUND ARCHITECTURE',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isCompact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: AuthPalette.textSecondary,
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? 6 : 8),
          ],

          // Title & Subtitle
          Text(
            'Create your account',
            style: GoogleFonts.plusJakartaSans(
              fontSize: isDesktop ? (isCompact ? 24 : 28) : 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AuthPalette.textPrimary,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Your music, your way.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: isDesktop ? (isCompact ? 13 : 14) : 14,
              color: AuthPalette.textSecondary,
              fontWeight: FontWeight.w400,
            ),
          ),
          SizedBox(height: isCompact ? 12 : 16),

          // Error banner
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AuthPalette.errorContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AuthPalette.errorRed.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AuthPalette.errorRed,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AuthPalette.errorRed,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: isCompact ? 10 : 12),
          ],

          // Full Name Input
          AuthTextField(
            label: 'FULL NAME',
            hintText: 'Enter your full name',
            controller: _nameController,
            focusNode: _nameFocusNode,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _emailFocusNode.requestFocus(),
            suffixIcon: const Icon(
              Icons.person_outline_rounded,
              color: Color(0xFF897173),
              size: 18,
            ),
            borderRadius: isDesktop ? 10 : 16,
            contentPadding: isCompact
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
                : null,
            fontSize: isCompact ? 13.5 : null,
            labelFontSize: isCompact ? 11 : null,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your name';
              }
              return null;
            },
          ),
          SizedBox(height: isCompact ? 9 : 12),

          // Email Address Input
          AuthTextField(
            label: 'EMAIL ADDRESS',
            hintText: 'name@example.com',
            controller: _emailController,
            focusNode: _emailFocusNode,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
            suffixIcon: const Icon(
              Icons.mail_outline_rounded,
              color: Color(0xFF897173),
              size: 18,
            ),
            borderRadius: isDesktop ? 10 : 16,
            contentPadding: isCompact
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
                : null,
            fontSize: isCompact ? 13.5 : null,
            labelFontSize: isCompact ? 11 : null,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          SizedBox(height: isCompact ? 9 : 12),

          // Password Input
          AuthTextField(
            label: 'PASSWORD',
            hintText: 'Create a password',
            controller: _passwordController,
            focusNode: _passwordFocusNode,
            obscureText: !_isPasswordVisible,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _confirmPasswordFocusNode.requestFocus(),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AuthPalette.textSecondary,
                size: 18,
              ),
              onPressed: () {
                setState(() => _isPasswordVisible = !_isPasswordVisible);
              },
            ),
            borderRadius: isDesktop ? 10 : 16,
            contentPadding: isCompact
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
                : null,
            fontSize: isCompact ? 13.5 : null,
            labelFontSize: isCompact ? 11 : null,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please create a password';
              }
              if (value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),
          if (isDesktop) ...[
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: Color(0xFF897173),
                ),
                const SizedBox(width: 5),
                Text(
                  'At least 6 characters with 1 number',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isCompact ? 10 : 11,
                    color: AuthPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: isCompact ? 9 : 12),

          // Confirm Password Input
          AuthTextField(
            label: 'CONFIRM PASSWORD',
            hintText: 'Confirm your password',
            controller: _confirmPasswordController,
            focusNode: _confirmPasswordFocusNode,
            obscureText: !_isConfirmPasswordVisible,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _handleRegister(),
            suffixIcon: IconButton(
              icon: Icon(
                _isConfirmPasswordVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AuthPalette.textSecondary,
                size: 18,
              ),
              onPressed: () {
                setState(() =>
                    _isConfirmPasswordVisible = !_isConfirmPasswordVisible);
              },
            ),
            borderRadius: isDesktop ? 10 : 16,
            contentPadding: isCompact
                ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9)
                : null,
            fontSize: isCompact ? 13.5 : null,
            labelFontSize: isCompact ? 11 : null,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please confirm your password';
              }
              if (value != _passwordController.text) {
                return 'Passwords do not match';
              }
              return null;
            },
          ),
          SizedBox(height: isCompact ? 12 : 16),

          // Submit Button
          AuthPrimaryButton(
            label: 'Create account',
            trailingIcon: Icons.arrow_forward_rounded,
            isLoading: _isLoading,
            borderRadius: isDesktop ? 10 : 9999,
            height: isCompact ? 42 : 46,
            fontSize: isCompact ? 14 : 15,
            onPressed: _handleRegister,
          ),
          SizedBox(height: isCompact ? 8 : 12),

          // Legal Disclaimer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              "By creating an account, you agree to Miee's Terms of Service and Privacy Policy.",
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                fontSize: isCompact ? 10.5 : 11.5,
                color: AuthPalette.textSecondary,
                height: 1.35,
              ),
            ),
          ),
          SizedBox(height: isCompact ? 8 : 12),

          // Footer link
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Already have an account?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: isCompact ? 12.5 : 13.5,
                  color: AuthPalette.textSecondary,
                ),
              ),
              const SizedBox(width: 5),
              GestureDetector(
                onTap: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/login');
                  }
                },
                child: Text(
                  'Log in',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: isCompact ? 12.5 : 13.5,
                    fontWeight: FontWeight.w700,
                    color: AuthPalette.primaryButton,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isCompact ? 4 : 8),

          // Continue as Guest Option
          Center(
            child: TextButton.icon(
              onPressed: () {
                ref.read(guestModeProvider.notifier).state = true;
                context.go('/home');
              },
              icon: const Icon(
                Icons.arrow_forward_rounded,
                size: 14,
                color: AuthPalette.textSecondary,
              ),
              label: Text(
                'Continue as Guest',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: isCompact ? 12 : 13,
                  fontWeight: FontWeight.w600,
                  color: AuthPalette.textSecondary,
                ),
              ),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Right Column Showcase for Desktop Viewport
  Widget _buildDesktopShowcaseCard({required bool isCompact}) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: isCompact ? 440 : 490,
        maxHeight: isCompact ? 485 : 540,
      ),
      child: AspectRatio(
        aspectRatio: 492 / 542,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF140D0F),
            borderRadius: BorderRadius.circular(isCompact ? 20 : 24),
            border: Border.all(
              color: const Color(0xFFE3E2E0),
              width: 1.0,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0C1A0F12),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/images/register_artwork.webp',
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: AuthPalette.primaryButton,
                    child: const Center(
                      child: Icon(
                        Icons.graphic_eq_rounded,
                        size: 64,
                        color: Colors.white30,
                      ),
                    ),
                  );
                },
              ),
              const Positioned(
                left: -9999,
                child: Column(
                  children: [
                    Text('DIRECT ACOUSTIC PIPELINE'),
                    Text('Experience Sound in Its True Fidelity'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBar({required double height}) {
    return Container(
      width: 2.2,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1),
      ),
    );
  }
}
