import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/models/system_notification_model.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';
import 'package:cmms/notifications/services/system_notification_service.dart';
import 'package:cmms/notifications/services/custom_notification_service.dart';
import 'package:cmms/notifications/screens/system_notification_detail_screen.dart';
import 'package:cmms/notifications/screens/custom_notification_detail_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class FloatingNotificationWidget extends StatefulWidget {
  const FloatingNotificationWidget({super.key});

  @override
  State<FloatingNotificationWidget> createState() => _FloatingNotificationWidgetState();
}

class _FloatingNotificationWidgetState extends State<FloatingNotificationWidget>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _shakeController;

  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _shakeAnimation;

  Timer? _dismissTimer;
  bool _isDismissed = false;
  bool _isPersistent = false;

  final SystemNotificationService _systemService = SystemNotificationService();
  final CustomNotificationService _customService = CustomNotificationService();
  final Logger _logger = Logger();

  String _userOrganization = '';

  @override
  void initState() {
    super.initState();
    _getUserOrganization();
    _initializeAnimations();
  }

  Future<void> _getUserOrganization() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
        if (userDoc.exists) {
          setState(() {
            _userOrganization = userDoc.data()?['organization'] ?? '';
          });
        }
      } catch (e) {
        _logger.e('Error getting user organization: $e');
      }
    }
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Enhanced slide animation with bounce
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -2.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.7,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.elasticOut,
    ));

    // Pulsing animation for urgent notifications
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // Shake animation for critical notifications
    _shakeAnimation = Tween<double>(
      begin: -5.0,
      end: 5.0,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticInOut,
    ));
  }

  @override
  void dispose() {
    _slideController.dispose();
    _pulseController.dispose();
    _shakeController.dispose();
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _startAnimations(bool isUrgent, bool isOverdue) {
    if (_isDismissed) return;

    _slideController.forward();

    // Start pulsing for urgent notifications
    if (isUrgent || isOverdue) {
      _isPersistent = true;
      _pulseController.repeat(reverse: true);

      // Shake for overdue notifications
      if (isOverdue) {
        _shakeController.repeat(reverse: true);
      }
    } else {
      // Auto-dismiss normal notifications after 10 seconds
      _dismissTimer = Timer(const Duration(seconds: 10), () {
        if (!_isDismissed && mounted) {
          _dismissNotification();
        }
      });
    }
  }

  void _dismissNotification() {
    if (_isDismissed) return;

    setState(() {
      _isDismissed = true;
    });

    _slideController.reverse();
    _pulseController.stop();
    _shakeController.stop();
    _dismissTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (_userOrganization.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<dynamic>>(
      stream: _getCombinedNotifications(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty || _isDismissed) {
          return const SizedBox.shrink();
        }

        final notifications = snapshot.data!;
        if (notifications.isEmpty) {
          return const SizedBox.shrink();
        }

        // Get the most recent/urgent notification
        final latestNotification = notifications.first;

        bool isSystemNotification = latestNotification is SystemNotificationModel;
        bool isUrgent = false;
        bool isOverdue = false;
        String title = '';
        String body = '';

        if (isSystemNotification) {
          final sysNotif = latestNotification;
          isUrgent = sysNotif.type == SystemNotificationType.alert;
          isOverdue = sysNotif.isOverdue;
          title = sysNotif.title;
          body = sysNotif.body;
        } else {
          final customNotif = latestNotification as CustomNotificationModel;
          isUrgent = customNotif.type == CustomNotificationType.alert;
          isOverdue = customNotif.isOverdue;
          title = customNotif.title;
          body = customNotif.body;
        }

        // Start animations when notification appears
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_slideController.isAnimating && !_slideController.isCompleted) {
            _startAnimations(isUrgent, isOverdue);
          }
        });

        return Positioned(
          top: kIsWeb ? 20 : MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: SlideTransition(
            position: _slideAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: AnimatedBuilder(
                        animation: _shakeAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(_shakeAnimation.value, 0),
                            child: _buildNotificationBanner(
                              latestNotification,
                              isSystemNotification,
                              isUrgent,
                              isOverdue,
                              title,
                              body,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Stream<List<dynamic>> _getCombinedNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    // Combine system and custom notifications
    final systemStream = _userOrganization == 'JV Almacis' 
        ? _systemService.getActiveNotifications()
        : Stream<List<SystemNotificationModel>>.value([]);

    final customStream = _customService.getCustomNotifications(_userOrganization);

    return StreamZip([systemStream, customStream]).map((results) {
      final systemNotifications = results[0] as List<SystemNotificationModel>;
      final customNotifications = results[1] as List<CustomNotificationModel>;

      // Filter for triggered notifications only
      final triggeredSystem = systemNotifications.where((n) => n.isTriggered).toList();
      final triggeredCustom = customNotifications.where((n) => n.isTriggered).toList();

      // Combine and sort by triggered time
      final combined = <dynamic>[...triggeredSystem, ...triggeredCustom];
      combined.sort((a, b) {
        final aTime = a.triggeredAt ?? a.notificationDate;
        final bTime = b.triggeredAt ?? b.notificationDate;
        return bTime.compareTo(aTime); // Most recent first
      });

      return combined;
    });
  }

  Widget _buildNotificationBanner(
    dynamic notification,
    bool isSystemNotification,
    bool isUrgent,
    bool isOverdue,
    String title,
    String body,
  ) {
    Color backgroundColor;
    Color accentColor;
    IconData iconData;
    String statusText;
    String emoji;

    if (isOverdue) {
      backgroundColor = Colors.red[700]!;
      accentColor = Colors.red[900]!;
      iconData = Icons.error;
      statusText = 'OVERDUE';
      emoji = '🚨';
    } else if (isUrgent) {
      backgroundColor = Colors.orange[600]!;
      accentColor = Colors.orange[800]!;
      iconData = Icons.warning;
      statusText = 'ALERT';
      emoji = '⚠️';
    } else {
      backgroundColor = Colors.blueGrey[600]!;
      accentColor = Colors.blueGrey[800]!;
      iconData = Icons.notifications_active;
      statusText = 'REMINDER';
      emoji = '🔧';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Calculate responsive dimensions
        final maxWidth = constraints.maxWidth;
        final contentPadding = maxWidth * 0.04; // 4% of available width
        final iconSize = maxWidth * 0.06; // 6% of available width
        final fontSize = maxWidth * 0.035; // 3.5% of available width

        return Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(16),
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: Container(
            width: maxWidth,
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              minHeight: 80,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [backgroundColor, accentColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: InkWell(
              onTap: () => _openNotificationDetails(context, notification, isSystemNotification),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(contentPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Animated notification icon
                        Container(
                          padding: EdgeInsets.all(iconSize * 0.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: const Duration(milliseconds: 1200),
                            builder: (context, value, child) {
                              return Transform.rotate(
                                angle: value * 0.1,
                                child: Icon(
                                  iconData,
                                  color: Colors.white,
                                  size: iconSize,
                                ),
                              );
                            },
                          ),
                        ),
                        SizedBox(width: contentPadding),

                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$emoji Maintenance $statusText',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: fontSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: fontSize * 0.6,
                                      vertical: fontSize * 0.2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      _isPersistent ? 'URGENT' : 'NOW',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: fontSize * 0.7,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: contentPadding * 0.3),
                              Text(
                                body,
                                style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: fontSize * 0.85,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        SizedBox(width: contentPadding * 0.5),

                        // Close button
                        GestureDetector(
                          onTap: _dismissNotification,
                          child: Container(
                            padding: EdgeInsets.all(fontSize * 0.4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: fontSize * 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: contentPadding * 0.8),

                    // Action buttons
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: fontSize * 0.6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.touch_app,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: fontSize * 0.8,
                                ),
                                SizedBox(width: fontSize * 0.3),
                                Text(
                                  'Tap to view details',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: fontSize * 0.75,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openNotificationDetails(BuildContext context, dynamic notification, bool isSystemNotification) {
    // Mark as read
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (isSystemNotification) {
        _systemService.markNotificationAsRead(notification.id, user.uid);
      } else {
        _customService.markNotificationAsRead(notification.id, user.uid);
      }
    }

    // Navigate to detail screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => isSystemNotification
            ? SystemNotificationDetailScreen(notification: notification)
            : CustomNotificationDetailScreen(notification: notification),
      ),
    );

    // Dismiss the floating notification
    _dismissNotification();
  }
}

// Helper class for combining streams
class StreamZip {
  final List<Stream> streams;

  StreamZip(this.streams);

  Stream<List> map(List Function(List) mapper) {
    return Stream.periodic(const Duration(seconds: 1)).asyncMap((_) async {
      final results = <dynamic>[];
      for (final stream in streams) {
        await for (final value in stream.take(1)) {
          results.add(value);
          break;
        }
      }
      return mapper(results);
    });
  }
}
