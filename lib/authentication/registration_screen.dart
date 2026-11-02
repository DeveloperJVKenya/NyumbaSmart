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
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
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
      // pushAndRemoveUntil clears Welcome/Login/Registration from the stack
      // so the back button can't land on a stale auth screen.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (context) => DashboardScreen(facilityId: '', role: UserRole.user.label),
        ),
        (route) => false,
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
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Brand header
                        Center(
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: AppColors.primaryGradient,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.3),
                                  blurRadius: 18,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white, size: 32),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          'Create Account',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 26, fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary, letterSpacing: -0.5),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Join NyumbaSmart facility management',
                          style: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 30),
                        AppTextField(
                          controller: _usernameController,
                          label: 'Full name',
                          icon: Icons.person_outline,
                          focusNode: _usernameFocusNode,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_emailFocusNode),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Please enter your name';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _emailController,
                          label: 'Email address',
                          icon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          focusNode: _emailFocusNode,
                          textInputAction: TextInputAction.next,
                          onFieldSubmitted: (_) =>
                              FocusScope.of(context).requestFocus(_passwordFocusNode),
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
                          focusNode: _passwordFocusNode,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) { if (!_isLoading) _signUp(); },
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
                          const SizedBox(height: 14),
                          AppErrorBanner(message: _errorMessage!),
                        ],
                        const SizedBox(height: 24),
                        AppGradientButton(
                          label: 'Create Account',
                          icon: Icons.person_add_alt_1_rounded,
                          isLoading: _isLoading,
                          onPressed: _isLoading ? null : _signUp,
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('Already have an account?',
                                style: GoogleFonts.poppins(
                                    fontSize: 13, color: AppColors.textSecondary)),
                            TextButton(
                              onPressed: () => Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => const LoginScreen())),
                              style: TextButton.styleFrom(
                                  padding: const EdgeInsets.only(left: 4)),
                              child: Text('Sign In',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary)),
                            ),
                          ],
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
