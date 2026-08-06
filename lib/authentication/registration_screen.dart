import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:cmms/models/user_model.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  RegistrationScreenState createState() => RegistrationScreenState();
}

class RegistrationScreenState extends State<RegistrationScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final Logger _logger = Logger(printer: PrettyPrinter());

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final userModel = UserModel(
        id: userCredential.user!.uid,
        username: _usernameController.text.trim(),
        email: _emailController.text.trim(),
        createdAt: DateTime.now(),
        role: UserRole.unassigned.label,
        organization: '-',
      );

      await _firestore.collection('Users').doc(userModel.id).set(userModel.toMap()).then((_) {
        _logger.i('Successfully created user ${userModel.id} with fields: ${userModel.toMap()}');
      }).catchError((e) {
        _logger.e('Failed to create user in Firestore: $e');
        throw e;
      });

      try {
        await NotificationService().initialize();
      } catch (fcmError) {
        _logger.e('Failed to initialize FCM token for new user: $fcmError');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration successful! Please wait for Admin approval.')),
      );

      // Consistent with login: empty facilityId triggers facility selection
      // once an admin assigns an organization/role (previously hardcoded to
      // 'facility1' here, inconsistent with login_screen.dart's '').
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(facilityId: '', role: UserRole.user.label),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _logger.e('Error during registration: $e');
      String errorMessage = 'Failed to register. Please try again.';
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'email-already-in-use':
            errorMessage = 'The email address is already in use.';
            break;
          case 'invalid-email':
            errorMessage = 'The email address is invalid.';
            break;
          case 'weak-password':
            errorMessage = 'The password is too weak.';
            break;
        }
      } else if (e is FirebaseException) {
        errorMessage = 'Firestore error: ${e.message}';
      }
      setState(() => _errorMessage = errorMessage);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = AppBreakpoints.isDesktop(screenWidth);
    final cardWidth = isDesktop ? 460.0 : (AppBreakpoints.isTablet(screenWidth) ? screenWidth * 0.6 : screenWidth * 0.9);

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
                            child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 30),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Join NyumbaSmart',
                          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Register to manage facilities.',
                          style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),
                        AppTextField(
                          controller: _usernameController,
                          label: 'Username',
                          icon: Icons.person_outline,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Please enter a username';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.isEmpty || !RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                              return 'Please enter a valid email address';
                            }
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
                            if (value == null || value.isEmpty || value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          AppErrorBanner(message: _errorMessage!),
                        ],
                        const SizedBox(height: 24),
                        AppGradientButton(
                          label: 'Sign Up',
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _signUp,
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const LoginScreen()),
                              );
                            },
                            child: const Text('Already have an account? Log In'),
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
