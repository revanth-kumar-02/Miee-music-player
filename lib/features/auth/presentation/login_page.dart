import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_providers.dart';
import 'widgets/auth_components.dart';

/// Faithfully implemented Login Screen reproducing the reference design:
/// - Editorial collage hero image (`login_collage.png`)
/// - Warm ivory background (`#FAF8F5`)
/// - Cobalt blue Miee branding emblem + `miee.` typography
/// - "Welcome back" heading & subtitle
/// - Email & Password inputs with leading icons
/// - Remember me & Forgot password
/// - Cobalt pill "Log in →" button
/// - "Don't have an account? Create account"
/// - Outlined pill "▷ Continue as Guest" button
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isPasswordVisible = false;
  bool _rememberMe = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      ref.read(guestModeProvider.notifier).state = false;
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      // Notify password managers that login succeeded
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

  void _showForgotPasswordDialog() {
    final resetEmailController =
        TextEditingController(text: _emailController.text);
    bool isSending = false;
    String? dialogMessage;
    bool isSuccess = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: MieeAuthTheme.panelSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: MieeAuthTheme.fieldBorder, width: 1),
          ),
          title: Text(
            'Reset Password',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: MieeAuthTheme.textPrimary,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enter your account email to receive a password reset link.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    color: MieeAuthTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14.5,
                    color: MieeAuthTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Email address',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: MieeAuthTheme.textMuted,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: MieeAuthTheme.fieldFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: MieeAuthTheme.fieldBorder,
                        width: 1.2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: MieeAuthTheme.fieldBorder,
                        width: 1.2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: MieeAuthTheme.cobaltBlue,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                if (dialogMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    dialogMessage!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: isSuccess
                          ? MieeAuthTheme.successGreen
                          : MieeAuthTheme.errorRed,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: GoogleFonts.plusJakartaSans(
                  color: MieeAuthTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      final email = resetEmailController.text.trim();
                      if (email.isEmpty || !email.contains('@')) {
                        setDialogState(() {
                          dialogMessage =
                              'Please enter a valid email address.';
                          isSuccess = false;
                        });
                        return;
                      }

                      setDialogState(() {
                        isSending = true;
                        dialogMessage = null;
                      });

                      try {
                        final authRepo = ref.read(authRepositoryProvider);
                        await authRepo.sendPasswordResetEmail(email);
                        setDialogState(() {
                          isSending = false;
                          isSuccess = true;
                          dialogMessage =
                              'Reset link sent! Please check your inbox.';
                        });
                      } catch (e) {
                        setDialogState(() {
                          isSending = false;
                          isSuccess = false;
                          dialogMessage =
                              e.toString().replaceFirst('Exception: ', '');
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: MieeAuthTheme.cobaltBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Send Reset Link',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final height = media.size.height;
    final isDesktop = width >= 900;
    final heroHeight = (height * 0.38).clamp(280.0, 420.0);

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
            SystemNavigator.pop();
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

  /// Mobile layout faithfully matching the reference design.
  Widget _buildMobileLayout({required double heroHeight}) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Top Hero: Editorial Collage Image
          Stack(
            children: [
              SizedBox(
                width: double.infinity,
                height: heroHeight,
                child: Image.asset(
                  'assets/images/auth/login_collage.png',
                  width: double.infinity,
                  height: heroHeight,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
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
                            context.go('/home');
                          }
                        },
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Main Form Section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),

                // Miee Branding: Blue Square Soundwave Emblem + miee. Wordmark
                const MieeAuthBrandMark(
                  emblemSize: 40,
                  fontSize: 28,
                ),
                const SizedBox(height: 18),

                // Main Heading
                Text(
                  'Welcome back',
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
                  'Pick up where the music left off.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: MieeAuthTheme.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),

                // Interactive Form
                _buildForm(),
                const SizedBox(height: 28),
              ],
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
                  // Left Column: Login Form
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
                              'Welcome back',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                                color: MieeAuthTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pick up where the music left off.',
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

                  // Right Column: Collage Showcase
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
                          'assets/images/auth/login_collage.png',
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
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

  /// Form inputs, controls, primary submit, and secondary actions.
  Widget _buildForm() {
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

            // Field 1: Email
            AuthTextField(
              label: 'Email address',
              showLabel: false,
              hintText: 'Enter your email',
              controller: _emailController,
              focusNode: _emailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
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

            // Field 2: Password
            AuthTextField(
              label: 'Password',
              showLabel: false,
              hintText: 'Enter your password',
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              autocorrect: false,
              prefixIcon: Icons.lock_outline_rounded,
              onFieldSubmitted: (_) => _handleLogin(),
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
                  return 'Please enter your password';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Controls: Remember me checkbox + Forgot password link
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: InkWell(
                    onTap: () => setState(() => _rememberMe = !_rememberMe),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: _rememberMe,
                              onChanged: (val) {
                                setState(() => _rememberMe = val ?? false);
                              },
                              activeColor: MieeAuthTheme.cobaltBlue,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                              side: const BorderSide(
                                color: MieeAuthTheme.fieldBorder,
                                width: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Remember me',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: MieeAuthTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showForgotPasswordDialog,
                  child: Text(
                    'Forgot password?',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: MieeAuthTheme.cobaltBlue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),

            // Primary Button: "Log in →"
            AuthPrimaryButton(
              label: 'Log in',
              trailingIcon: Icons.arrow_forward_rounded,
              isLoading: _isLoading,
              onPressed: _handleLogin,
            ),
            const SizedBox(height: 20),

            // Secondary Action 1: "Don't have an account? Create account"
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    "Don't have an account? ",
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: MieeAuthTheme.textSecondary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.go('/register'),
                    child: Text(
                      'Create account',
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
            const SizedBox(height: 18),

            // Secondary Action 2: "▷ Continue as Guest"
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
          ],
        ),
      ),
    );
  }
}
