import 'dart:async';
import 'package:cmms/authentication/splashscreen.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cmms/notifications/services/system_tray_notification_service.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/developer/maintenance_tasks_screen.dart';
import 'package:cmms/notifications/screens/notification_settings_screen.dart';
import 'package:cmms/notifications/screens/notification_status_screen.dart';
import 'package:cmms/notifications/widgets/floating_notification_widget.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'firebase_options.dart';
import 'package:cmms/authentication/need_account_screen.dart';
import 'package:cmms/theme/app_theme.dart';

// Background message handler (must be top-level). Due/alert/custom notifications are entirely
// server-driven now (see functions/index.js checkDueNotifications / onCustomNotificationCreated),
// so this only needs to respect the user's notification toggle — there's no client-side due-task
// detection left to run here.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool('notifications_enabled') ?? true;
  if (!enabled) return;

  final logger = Logger();
  logger.i('Handling background message: ${message.messageId}');

  // Proof-of-receipt for a backgrounded/closed native app — this is the isolate FCM actually
  // wakes for that case, and FirebaseAuth's persisted session is available here without the user
  // re-signing in. (Not reachable on web: a backgrounded/closed browser tab is handled entirely
  // by the JS service worker, which can't run this Dart callback.)
  await NotificationService().markDelivered(runId: message.data['runId']);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  if (!kIsWeb) {
    const androidInitializationSettings = AndroidInitializationSettings('@mipmap/launcher_icon');
    const iosInitializationSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initializationSettings = InitializationSettings(
      android: androidInitializationSettings,
      iOS: iosInitializationSettings,
    );

    await FlutterLocalNotificationsPlugin().initialize(settings: initializationSettings);

    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  runApp(const ProviderScope(child: MyApp()));

  // Device registration (FCM token, permissions, local channels) isn't needed for the first
  // frame — kick it off after the UI is already painting instead of blocking runApp() behind it.
  unawaited(_initializeNotificationServices());
}

Future<void> _initializeNotificationServices() async {
  final logger = Logger();
  try {
    await NotificationService().initialize();
    await SystemTrayNotificationService().initialize();
    logger.i('Notification services initialized');
  } catch (e) {
    logger.e('Error initializing notification services: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final Logger _logger = Logger();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupForegroundMessageHandling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _setupForegroundMessageHandling() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _logger.i('Received foreground message: ${message.notification?.title}');

      // Ack receipt for every platform, including web — this runs with a live signed-in session
      // regardless of the notifications-enabled toggle below (the push was still received; a
      // disabled toggle only suppresses local display, it shouldn't hide that delivery worked).
      await NotificationService().markDelivered(runId: message.data['runId']);

      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notifications_enabled') ?? true;
      if (!enabled) return;

      final notification = message.notification;
      if (kIsWeb || notification == null) {
        // Web foreground display is handled by the service worker; the in-app floating banner
        // (backed by the NotificationDigests stream) covers the rest.
        return;
      }

      await SystemTrayNotificationService().showDigestNotification(
        id: notification.hashCode,
        title: notification.title ?? 'Maintenance Notification',
        body: notification.body ?? 'You have a new maintenance notification',
        isUrgent: message.data['priority'] == 'urgent',
      );
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logger.i('Notification opened app: ${message.notification?.title}');
      Future.delayed(const Duration(milliseconds: 500), () {
        navigatorKey.currentState?.pushNamed('/notification-status');
      });
    });

    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _logger.i('App opened from terminated state via notification: ${message.notification?.title}');
        Future.delayed(const Duration(seconds: 2), () {
          navigatorKey.currentState?.pushNamed('/notification-status');
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NyumbaSmart',
      navigatorKey: navigatorKey,
      theme: AppTheme.light,
      home: const SplashScreen(),
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const FloatingNotificationWidget(),
          ],
        );
      },
      routes: {
        '/home': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as String?;
          return DashboardScreen(facilityId: args ?? '', role: '');
        },
        '/login': (context) => const LoginScreen(),
        '/registration': (context) => const RegistrationScreen(),
        '/maintenance-tasks': (context) => const MaintenanceTasksScreen(),
        '/notification-status': (context) => const NotificationStatusScreen(),
        '/notification-settings': (context) => const NotificationSettingsScreen(),
        '/needAccount': (context) => const NeedAccountScreen(),
      },
    );
  }
}
