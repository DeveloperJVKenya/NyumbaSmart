import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => LoginScreenState();
}

class LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final Logger _logger = Logger();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfAlreadySignedIn());
  }

  Future<void> _redirectIfAlreadySignedIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    try {
      final info = await ref.read(roleServiceProvider).resolveOnce(user.uid);
      NotificationService().initialize().catchError((e) {
        _logger.e('FCM init failed for existing session: $e');
      });
      if (mounted) _navigateToDashboard(info.roleLabel);
    } catch (e) {
      _logger.e('Error resolving role for existing session: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      _logger.i('User logged in successfully: ${userCredential.user?.uid}');

      try {
        await NotificationService().initialize();
      } catch (fcmError) {
        _logger.e('Failed to initialize FCM token after login: $fcmError');
      }

      final info = await ref.read(roleServiceProvider).resolveOnce(userCredential.user!.uid);

      if (mounted) _navigateToDashboard(info.roleLabel);
    } on FirebaseAuthException catch (e) {
      _logger.e('Firebase Auth error: ${e.code} - ${e.message}');
      setState(() {
        switch (e.code) {
          case 'user-not-found':
            _errorMessage = 'No user found with this email address.';
            break;
          case 'wrong-password':
            _errorMessage = 'Incorrect password.';
            break;
          case 'invalid-email':
            _errorMessage = 'Invalid email address.';
            break;
          case 'user-disabled':
            _errorMessage = 'This user account has been disabled.';
            break;
          case 'too-many-requests':
            _errorMessage = 'Too many failed login attempts. Please try again later.';
            break;
          default:
            _errorMessage = 'Login failed: ${e.message}';
        }
      });
    } catch (e) {
      _logger.e('General login error: $e');
      setState(() => _errorMessage = 'An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToDashboard(String role) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DashboardScreen(facilityId: '', role: role),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = AppBreakpoints.isDesktop(screenWidth);
    final cardWidth = isDesktop ? 440.0 : (AppBreakpoints.isTablet(screenWidth) ? screenWidth * 0.6 : screenWidth * 0.9);

    return Scaffold(
      body: AppAuthBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardWidth),
                child: AppCard(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 30),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Welcome Back',
                          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to continue to NyumbaSmart',
                          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Please enter your email';
                            if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) return 'Enter a valid email';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _passwordController,
                          label: 'Password',
                          icon: Icons.lock_outline,
                          obscureText: _obscurePassword,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) return 'Please enter your password';
                            return null;
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          AppErrorBanner(message: _errorMessage!),
                        ],
                        const SizedBox(height: 24),
                        AppGradientButton(
                          label: 'Login',
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _handleLogin,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RegistrationScreen()),
                              );
                            },
                            child: const Text('Need an account? Sign Up'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
