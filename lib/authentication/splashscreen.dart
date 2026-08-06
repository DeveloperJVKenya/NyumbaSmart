import 'package:cmms/notifications/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/welcome_screen.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:cmms/theme/app_theme.dart';

/// App-launch auth gate. Shows the branded splash while resolving
/// sign-in/role state, then routes straight to the dashboard for an
/// already-authenticated user, or to the marketing welcome flow otherwise —
/// closing the previous gap where every launch forced a tap through the
/// welcome carousel even for signed-in users.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => SplashScreenState();
}

class SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _textFade;
  final Logger _logger = Logger(printer: PrettyPrinter());

  bool _navigationCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    )..forward();

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)),
    );
    _textFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.4, 1.0, curve: Curves.easeIn)),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigateToDashboard(UserRoleInfo info) {
    if (!mounted || _navigationCompleted) return;
    _navigationCompleted = true;
    _logger.i('Splash: navigating to dashboard with role ${info.roleLabel}');
    NotificationService().initialize().catchError((e) {
      _logger.e('FCM init failed during splash: $e');
    });
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DashboardScreen(facilityId: '', role: info.roleLabel),
      ),
    );
  }

  void _navigateToWelcome() {
    if (!mounted || _navigationCompleted) return;
    _navigationCompleted = true;
    _logger.i('Splash: no signed-in user, navigating to welcome');
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _navigateToWelcome());
          return _buildSplash();
        }
        final roleAsync = ref.watch(currentUserRoleProvider);
        return roleAsync.when(
          data: (info) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _navigateToDashboard(info));
            return _buildSplash();
          },
          loading: () => _buildSplash(),
          error: (e, st) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _navigateToWelcome());
            return _buildSplash();
          },
        );
      },
      loading: () => _buildSplash(),
      error: (e, st) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _navigateToWelcome());
        return _buildSplash();
      },
    );
  }

  Widget _buildSplash() {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppColors.heroGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _logoScale,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 30,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Image.asset('assets/icons/icon.png', width: 88, height: 88),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FadeTransition(
                opacity: _textFade,
                child: Text(
                  'NyumbaSmart',
                  style: GoogleFonts.poppins(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FadeTransition(
                opacity: _textFade,
                child: Text(
                  'Facility Management Made Simple',
                  style: GoogleFonts.poppins(fontSize: 15, color: Colors.white.withValues(alpha: 0.85)),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              FadeTransition(
                opacity: _textFade,
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
