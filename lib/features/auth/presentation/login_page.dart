import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_providers.dart';
import 'widgets/auth_components.dart';

/// Recreated Login Screen strictly matching Stitch:
/// - Mobile: `17_mobile_miee_mobile_login.html`
/// - Desktop / Web: `16_desktop_miee_web_login_clean_auth.html`
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
      // Notify password managers (Google Password Manager on Android & browsers on Web)
      // that login succeeded and credentials can be saved/updated.
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
          message = 'Unable to reach the server. Please check your internet connection or Private DNS settings, or tap "Continue as Guest".';
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
          backgroundColor: AuthPalette.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AuthPalette.cardBorder, width: 1),
          ),
          title: Text(
            'Reset Password',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AuthPalette.textPrimary,
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
                    color: AuthPalette.textMuted,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  autocorrect: false,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AuthPalette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Email address',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      color: AuthPalette.textMuted.withValues(alpha: 0.6),
                      fontSize: 13.5,
                    ),
                    filled: true,
                    fillColor: AuthPalette.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AuthPalette.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: AuthPalette.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AuthPalette.inputFocusBorder,
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
                          ? const Color(0xFF2E7D32)
                          : AuthPalette.errorRed,
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
                  color: AuthPalette.textMuted,
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
                backgroundColor: AuthPalette.primaryButton,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
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
    final isCompact = height < 860;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          SystemNavigator.pop();
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
                      // Left Column: Login Form
                      Expanded(
                        flex: 5,
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: isCompact ? 36.0 : 48.0,
                          ),
                          child: _buildFormContent(isDesktop: true),
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
                : _buildFormContent(isDesktop: false),
          ),
        ),
      ),
    );
  }

  Widget _buildFormContent({required bool isDesktop}) {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Branding & Title Header
            AuthBrandHeader(
              title: 'Welcome back',
              subtitle: 'Pick up where the music left off.',
              showEmblem: !isDesktop,
            ),

            // Error banner
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AuthPalette.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AuthPalette.errorRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AuthPalette.errorRed,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12.5,
                          color: AuthPalette.errorRed,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Email Input (52px rounded-xl)
            AuthTextField(
              label: 'Email address',
              hintText: isDesktop ? 'name@example.com' : 'Enter your email',
              controller: _emailController,
              focusNode: _emailFocusNode,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email, AutofillHints.username],
              autocorrect: false,
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
            const SizedBox(height: 16),

            // Password Input (52px rounded-xl)
            AuthTextField(
              label: 'Password',
              hintText: 'Enter your password',
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              obscureText: !_isPasswordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              autocorrect: false,
              onFieldSubmitted: (_) => _handleLogin(),
            suffixIcon: IconButton(
              icon: Icon(
                _isPasswordVisible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AuthPalette.textMuted,
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
          const SizedBox(height: 10),

          // Remember Me Checkbox & Forgot Password Row
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
                            activeColor: AuthPalette.primaryButton,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            side: const BorderSide(
                              color: AuthPalette.inputBorder,
                              width: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Remember me',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: AuthPalette.textMuted,
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AuthPalette.primaryButton,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Solid Bordeaux Pill "Log in" Button
          AuthPrimaryButton(
            label: 'Log in',
            trailingIcon: isDesktop ? Icons.arrow_forward_rounded : null,
            isLoading: _isLoading,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 24),

          // Footer: Don't have an account? Create account
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "Don't have an account?",
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AuthPalette.textMuted,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => context.go('/register'),
                child: Text(
                  'Create account',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AuthPalette.primaryButton,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Continue as Guest Option
          Center(
            child: TextButton.icon(
              onPressed: () {
                ref.read(guestModeProvider.notifier).state = true;
                context.go('/home');
              },
              icon: const Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AuthPalette.textMuted,
              ),
              label: Text(
                'Continue as Guest',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AuthPalette.textMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildDesktopShowcaseCard({required bool isCompact}) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: isCompact ? 440 : 490,
        maxHeight: isCompact ? 478 : 533,
      ),
      child: AspectRatio(
        aspectRatio: 500 / 544,
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
          child: Image.asset(
            'assets/images/login_artwork.webp',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) => Container(
              color: AuthPalette.primaryButton,
              child: const Center(
                child: Icon(
                  Icons.music_note_rounded,
                  size: 64,
                  color: Colors.white30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

