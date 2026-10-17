import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../providers/auth_providers.dart';
import 'widgets/auth_components.dart';

/// Recreated Login Screen matching the reference design.
/// - Oversized warm-toned abstract shapes background
/// - Miee wave ribbon mark + "miee" serif wordmark
/// - "Welcome Back" serif heading + "Sign in to continue your music journey."
/// - Email & Password fields
/// - "Remember me" checkbox & "Forgot Password?" link
/// - Solid Cocoa Plum "Sign In" button
/// - "or continue with" social buttons (Google, GitHub, Email)
/// - "Don't have an account? Create Account" link in Dusty Rose
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
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  void _handleGoogleSignIn() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Sign-In is not configured for this environment.'),
        backgroundColor: AppColors.cocoaPlum,
      ),
    );
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
            style: GoogleFonts.playfairDisplay(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AuthPalette.textCocoa,
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
                  style: GoogleFonts.geist(
                    fontSize: 13.5,
                    color: AuthPalette.textMuted,
                  ),
                ),
                AppSpacing.heightMd,
                TextField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  style: GoogleFonts.geist(
                    fontSize: 14,
                    color: AuthPalette.textCocoa,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Email address',
                    hintStyle: GoogleFonts.geist(
                      color: AuthPalette.textMuted.withOpacity(0.6),
                      fontSize: 13.5,
                    ),
                    filled: true,
                    fillColor: AuthPalette.inputFill,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
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
                  ),
                ),
                if (dialogMessage != null) ...[
                  AppSpacing.heightSm,
                  Row(
                    children: [
                      Icon(
                        isSuccess
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: isSuccess
                            ? Colors.green[700]
                            : AuthPalette.errorRed,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dialogMessage!,
                          style: GoogleFonts.geist(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSuccess
                                ? Colors.green[700]
                                : AuthPalette.errorRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actionsPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                foregroundColor: AuthPalette.textMuted,
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSending
                  ? null
                  : () async {
                      if (resetEmailController.text.trim().isEmpty) return;
                      setDialogState(() {
                        isSending = true;
                        dialogMessage = null;
                      });
                      try {
                        final authRepo = ref.read(authRepositoryProvider);
                        await authRepo.sendPasswordResetEmail(
                          resetEmailController.text.trim(),
                        );
                        setDialogState(() {
                          isSending = false;
                          isSuccess = true;
                          dialogMessage = 'Reset email sent! Please check your inbox.';
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
                  borderRadius: BorderRadius.circular(8),
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
                  : const Text('Send Reset Link'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      child: AuthCard(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Miee Brand Header
              const AuthBrandHeader(
                title: 'Welcome Back',
                subtitle: 'Sign in to continue your music journey.',
              ),

              // Error Banner
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AuthPalette.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AuthPalette.errorRed.withOpacity(0.3)),
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
                          style: GoogleFonts.geist(
                            fontSize: 12.5,
                            color: AuthPalette.errorRed,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Email Input
              AuthTextField(
                label: 'Email address',
                hintText: 'Enter your email',
                controller: _emailController,
                focusNode: _emailFocusNode,
                prefixIcon: Icons.mail_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onFieldSubmitted: (_) => _passwordFocusNode.requestFocus(),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter your email';
                  }
                  if (!val.contains('@') || !val.contains('.')) {
                    return 'Please enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password Input
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Password',
                    style: GoogleFonts.geist(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AuthPalette.textCocoa,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _passwordController,
                    focusNode: _passwordFocusNode,
                    obscureText: !_isPasswordVisible,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _handleLogin(),
                    style: GoogleFonts.geist(
                      fontSize: 14,
                      color: AuthPalette.textCocoa,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter your password',
                      hintStyle: GoogleFonts.geist(
                        fontSize: 13.5,
                        color: AuthPalette.textMuted.withOpacity(0.6),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        color: AuthPalette.textMuted,
                        size: 19,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordVisible
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: AuthPalette.textMuted,
                          size: 19,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordVisible = !_isPasswordVisible;
                          });
                        },
                      ),
                      filled: true,
                      fillColor: AuthPalette.inputFill,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AuthPalette.inputBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AuthPalette.inputBorder),
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
                        borderSide: const BorderSide(
                          color: AuthPalette.errorRed,
                          width: 1.5,
                        ),
                      ),
                      errorStyle: GoogleFonts.geist(
                        fontSize: 12,
                        color: AuthPalette.errorRed,
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Remember Me Checkbox & Forgot Password Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _rememberMe,
                          activeColor: AuthPalette.accent,
                          checkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                          side: const BorderSide(
                            color: AuthPalette.inputBorder,
                            width: 1.5,
                          ),
                          onChanged: (val) {
                            setState(() => _rememberMe = val ?? true);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Remember me',
                        style: GoogleFonts.geist(
                          fontSize: 12.5,
                          color: AuthPalette.textCocoa,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _showForgotPasswordDialog,
                    child: Text(
                      'Forgot Password?',
                      style: GoogleFonts.geist(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: AuthPalette.accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Solid Cocoa Plum "Sign In" Button
              AuthPrimaryButton(
                label: 'Sign In',
                isLoading: _isLoading,
                onPressed: _handleLogin,
              ),
              const SizedBox(height: 20),

              // Social Sign In (Google)
              AuthSocialButtons(
                onGooglePressed: _handleGoogleSignIn,
                onGithubPressed: null,
                onEmailPressed: null,
              ),
              const SizedBox(height: 20),

              // "Don't have an account? Create Account" Footer
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account?",
                    style: GoogleFonts.geist(
                      fontSize: 13,
                      color: AuthPalette.textMuted,
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => context.push('/register'),
                    child: Text(
                      'Create Account',
                      style: GoogleFonts.geist(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AuthPalette.accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
