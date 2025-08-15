import 'package:cmms/notifications/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cmms/authentication/welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  SplashScreenState createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _damageOpacityAnimation;
  late Animation<double> _repairScaleAnimation;
  late Animation<double> _textFadeAnimation;
  final Logger _logger = Logger(printer: PrettyPrinter());

  String? _currentRole;
  bool _navigationCompleted = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    );

    _damageOpacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut),
      ),
    );

    _repairScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 0.8, curve: Curves.easeOutBack),
      ),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 0.9, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _initializeAuthAndRoleCheck();
    });
  }

  Future<void> _initializeAuthAndRoleCheck() async {
    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(Persistence.LOCAL);
      }

      await Future.delayed(const Duration(seconds: 2));
      
      User? user = FirebaseAuth.instance.currentUser;
      _logger.i('Current user: ${user?.uid ?? 'null'}');
      
      if (user == null) {
        _navigateToWelcome('No user logged in');
        return;
      }

      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();
      if (!userDoc.exists) {
        _navigateToWelcome('User not registered');
        return;
      }

      try {
        _logger.i('Initializing FCM token during splash for user: ${user.uid}');
        await NotificationService().initialize();
        _logger.i('FCM token successfully initialized during splash for user: ${user.uid}');
      } catch (fcmError) {
        _logger.e('Failed to initialize FCM token during splash: $fcmError');
      }

      await _determineUserRole(user.uid);
      
      await Future.delayed(const Duration(seconds: 3));
      
      if (!_navigationCompleted) {
        _navigateBasedOnRole();
      }
    } catch (e) {
      _logger.e('Error in auth initialization: $e');
      if (!_navigationCompleted) {
        _navigateToWelcome('Authentication error: $e');
      }
    }
  }

  Future<void> _determineUserRole(String uid) async {
    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('Admins')
          .doc(uid)
          .get();
      
      final developerDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(uid)
          .get();
      
      final technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(uid)
          .get();
      
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(uid)
          .get();

      if (mounted) {
        setState(() {
          if (adminDoc.exists) {
            _currentRole = 'Admin';
            _logger.i('User is an Admin');
          } else if (developerDoc.exists) {
            _currentRole = 'Technician';
            _logger.i('User is a Developer (treated as Technician)');
          } else if (technicianDoc.exists) {
            _currentRole = 'Technician';
            _logger.i('User is a Technician');
          } else if (userDoc.exists && userDoc.data()?['role'] == 'Technician') {
            _currentRole = 'Technician';
            _logger.i('User has Technician role in Users collection');
          } else {
            _currentRole = 'User';
            _logger.i('User has default User role');
          }
        });
      }

      _listenToRoleChanges(uid);
    } catch (e) {
      _logger.e('Error determining user role: $e');
      _currentRole = 'User';
    }
  }

  void _listenToRoleChanges(String uid) {
    FirebaseFirestore.instance.collection('Users').doc(uid).snapshots().listen(
      (DocumentSnapshot snapshot) {
        if (!mounted || _navigationCompleted) return;

        final newRole = snapshot.exists ? snapshot.get('role') : 'User';
        if (newRole != _currentRole) {
          setState(() {
            _currentRole = newRole;
            _logger.i('Role updated to: $newRole');
          });
          _navigateBasedOnRole();
        }
      },
      onError: (error) {
        _logger.e('Error listening to role changes: $error');
      },
    );
  }

  void _navigateBasedOnRole() {
    if (!mounted || _navigationCompleted) return;
    _navigationCompleted = true;

    _logger.i('Navigating to dashboard with role: ${_currentRole ?? 'User'}');
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => DashboardScreen(
          facilityId: '',
          role: _currentRole ?? 'User',
        ),
      ),
    );
  }

  void _navigateToWelcome(String message) {
    if (mounted && !_navigationCompleted) {
      _navigationCompleted = true;
      _logger.i('Navigating to welcome: $message');
      
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const WelcomeScreen()),
      );
      
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                FadeTransition(
                  opacity: _damageOpacityAnimation,
                  child: Image.asset(
                    'assets/damage.png',
                    width: 200,
                    height: 200,
                  ),
                ),
                ScaleTransition(
                  scale: _repairScaleAnimation,
                  child: Image.asset(
                    'assets/repair.png',
                    width: 200,
                    height: 200,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FadeTransition(
              opacity: _textFadeAnimation,
              child: Text(
                'NyumbaSmart',
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FadeTransition(
              opacity: _textFadeAnimation,
              child: Text(
                'Facility Management Made Simple',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.blueGrey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}