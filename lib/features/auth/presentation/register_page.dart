import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_providers.dart';
import '../../legal/presentation/legal_document_page.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/providers/profile_providers.dart';
import '../../profile/presentation/profile_controller.dart';
import 'widgets/auth_components.dart';

/// Faithfully implemented Register Screen reproducing the reference design:
/// - Edge-to-edge vinyl turntable hero photograph (`register_vinyl.png`)
/// - Warm ivory panel overlapping the hero with 32px rounded top corners
/// - Identical Miee branding emblem + `miee.` typography
/// - "Create your account" heading & subtitle
/// - EXACTLY THREE fields: Full Name, Email, Password (no confirm password)
/// - Dynamic password validation indicator ("At least 8 characters with a letter and a number.")
/// - Cobalt pill "Create account →" button
/// - Terms of Service & Privacy Policy in-app navigation
/// - Horizontal "or" divider
/// - Outlined pill "▷ Continue as Guest" button
/// - "Already have an account? Log in" link
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

  final _nameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  void _onPasswordChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  bool get _isPasswordValid {
    final text = _passwordController.text;
    final hasMinLength = text.length >= 8;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(text);
    final hasNumber = RegExp(r'[0-9]').hasMatch(text);
    return hasMinLength && hasLetter && hasNumber;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isPasswordValid) {
      setState(() {
        _errorMessage =
            'Password must be at least 8 characters with a letter and a number.';
      });
      return;
    }

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

      // Persist chosen display name
      final chosenName =
          rawName.isNotEmpty ? rawName : (authUser.displayName ?? '');
      if (chosenName.isNotEmpty) {
        final initialProfile = UserProfile.initial(
          uid: authUser.uid,
          email: authUser.email,
          displayName: chosenName,
        );
        final userProfileRepo = ref.read(userProfileRepositoryProvider);
        await userProfileRepo.saveUserProfile(initialProfile);
        ref
            .read(userProfileNotifierProvider.notifier)
            .updateProfileLocally(initialProfile);

        final localProfile = ref.read(profileProvider);
        await ref.read(profileProvider.notifier).updateProfile(
              displayName: chosenName,
              favoriteGenre: localProfile.favoriteGenre,
              favoriteArtist: localProfile.favoriteArtist,
            );
      }

      // Notify password managers that registration succeeded
      TextInput.finishAutofillContext(shouldSave: true);
    } catch (e) {
      TextInput.finishAutofillContext(shouldSave: false);
      if (mounted) {
        final str = e.toString().toLowerCase();
        String message = e.toString().replaceFirst('Exception: ', '');
        if (str.contains('socketexception') ||
            str.contains('failed host lookup') ||
            str.contains('no address associated') ||
            str.contains('network is unreachable') ||
            str.contains('connection refused') ||
            str.contains('clientexception')) {
          message =
              'Unable to reach the server. Please check your internet connection or Private DNS settings, or tap "Continue as Guest".';
        }
        setState(() {
          _errorMessage = message;
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
    final heroHeight = (height * 0.34).clamp(240.0, 360.0);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: PopScope(
        canPop: context.canPop(),
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/login');
          }
        },
        child: Scaffold(
          backgroundColor: MieeAuthTheme.background,
          body: isDesktop
              ? _buildDesktopLayout(height: height)
              : _buildMobileLayout(heroHeight: heroHeight),
        ),
      ),
    );
  }

  /// Mobile layout with overlapping ivory panel onto the vinyl turntable hero image.
  Widget _buildMobileLayout({required double heroHeight}) {
    const overlap = 32.0;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Stack(
        children: [
          // Top Hero: Edge-to-edge vinyl turntable photograph
          SizedBox(
            width: double.infinity,
            height: heroHeight,
            child: Image.asset(
              'assets/images/auth/register_vinyl.png',
              width: double.infinity,
              height: heroHeight,
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
          if (Navigator.of(context).canPop())
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: CircleAvatar(
                  backgroundColor: Colors.black.withValues(alpha: 0.35),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/login');
                      }
                    },
                  ),
                ),
              ),
            ),

          // Ivory Registration Panel with rounded top corners overlapping the image
          Padding(
            padding: EdgeInsets.only(top: heroHeight - overlap),
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: MieeAuthTheme.panelSurface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Miee Branding: Blue Square Soundwave Emblem + miee. Wordmark
                  const MieeAuthBrandMark(
                    emblemSize: 40,
                    fontSize: 28,
                  ),
                  const SizedBox(height: 18),

                  // Heading
                  Text(
                    'Create your account',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      color: MieeAuthTheme.textPrimary,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Subtitle
                  Text(
                    'A home for all the music you love.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: MieeAuthTheme.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Interactive Registration Form
                  _buildForm(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Desktop layout with dual-pane composition.
  Widget _buildDesktopLayout({required double height}) {
    final isCompact = height < 860;
    return Column(
      children: [
        AuthDesktopHeader(isCompact: isCompact),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left Column: Register Form
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36.0),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const MieeAuthBrandMark(
                              emblemSize: 42,
                              fontSize: 30,
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Create your account',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                                color: MieeAuthTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'A home for all the music you love.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: MieeAuthTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _buildForm(),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Right Column: Vinyl Showcase
                  Expanded(
                    flex: 6,
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(
                          maxWidth: 480,
                          maxHeight: 560,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 32,
                              offset: Offset(0, 12),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/images/auth/register_vinyl.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AuthDesktopFooter(isCompact: isCompact),
      ],
    );
  }

  /// EXACTLY THREE FIELDS Form with Dynamic Validation, Legal Links, and Guest Action.
  Widget _buildForm() {
    final isPasswordValid = _isPasswordValid;

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Error banner
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: MieeAuthTheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: MieeAuthTheme.errorRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: MieeAuthTheme.errorRed,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: MieeAuthTheme.errorRed,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Field 1: Full Name
            AuthTextField(
              label: 'FULL NAME',
              showLabel: false,
              hintText: 'Enter your full name',
              controller: _nameController,
              focusNode: _nameFocusNode,
              keyboardType: TextInputType.name,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              prefixIcon: Icons.person_outline_rounded,
              onFieldSubmitted: (_) => _emailFocusNode.requestFocus(),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your full name';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Field 2: Email
            AuthTextField(
              label: 'EMAIL ADDRESS',
              showLabel: false,
              hintText: 'Enter your email',
              controller: _emailController,
              focusNode: _emailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              autocorrect: false,
              prefixIcon: Icons.mail_outline_rounded,
              onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
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
            const SizedBox(height: 14),

            // Field 3: Password (NO Confirm Password!)
            AuthTextField(
              label: 'PASSWORD',
              showLabel: false,
              hintText: 'Create a password',
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              autocorrect: false,
              prefixIcon: Icons.lock_outline_rounded,
              onFieldSubmitted: (_) => _handleRegister(),
              suffixIcon: IconButton(
                icon: Icon(
                  _isPasswordVisible
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: MieeAuthTheme.fieldIcon,
                  size: 20,
                ),
                onPressed: () {
                  setState(() => _isPasswordVisible = !_isPasswordVisible);
                },
                tooltip:
                    _isPasswordVisible ? 'Hide password' : 'Show password',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please create a password';
                }
                return null;
              },
            ),
            const SizedBox(height: 10),

            // Dynamic Password Requirement Indicator
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  isPasswordValid
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: isPasswordValid
                      ? MieeAuthTheme.successGreen
                      : MieeAuthTheme.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'At least 8 characters with a letter and a number.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: isPasswordValid
                          ? MieeAuthTheme.successGreen
                          : MieeAuthTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Primary Action Button: "Create account →"
            AuthPrimaryButton(
              label: 'Create account',
              trailingIcon: Icons.arrow_forward_rounded,
              isLoading: _isLoading,
              onPressed: _handleRegister,
            ),
            const SizedBox(height: 16),

            // Terms of Service & Privacy Policy Disclaimers
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    "By creating an account, you agree to Miee's ",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: MieeAuthTheme.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const LegalDocumentPage(
                            initialTab: LegalTab.termsOfService,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'Terms of Service',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: MieeAuthTheme.cobaltBlue,
                      ),
                    ),
                  ),
                  Text(
                    ' and ',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: MieeAuthTheme.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => const LegalDocumentPage(
                            initialTab: LegalTab.privacyPolicy,
                          ),
                        ),
                      );
                    },
                    child: Text(
                      'Privacy Policy',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: MieeAuthTheme.cobaltBlue,
                      ),
                    ),
                  ),
                  Text(
                    '.',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      color: MieeAuthTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Horizontal "or" divider
            const MieeOrDivider(),
            const SizedBox(height: 20),

            // Guest Option: "▷ Continue as Guest"
            MieeGuestOutlineButton(
              onPressed: () {
                ref.read(guestModeProvider.notifier).state = true;
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            ),
            const SizedBox(height: 20),

            // Footer Link: "Already have an account? Log in"
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Already have an account? ',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: MieeAuthTheme.textSecondary,
                    ),
                  ),
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
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: MieeAuthTheme.cobaltBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
