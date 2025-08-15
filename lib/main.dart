//import 'package:cmms/authentication/splashscreen.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cmms/notifications/services/notification_scheduler_service.dart';
import 'package:cmms/notifications/services/background_notification_service.dart';
import 'package:cmms/notifications/services/notification_queue_service.dart';
import 'package:cmms/notifications/services/realtime_notification_monitor.dart';
import 'package:cmms/notifications/services/system_tray_notification_service.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/authentication/registration_screen.dart';
import 'package:cmms/developer/maintenance_tasks_screen.dart';
import 'package:cmms/notifications/screens/notification_settings_screen.dart';
import 'package:cmms/notifications/screens/notification_status_screen.dart';
import 'package:cmms/notifications/services/fcm_http_service.dart';
import 'package:cmms/notifications/services/system_notification_service.dart';
import 'package:cmms/notifications/widgets/floating_notification_widget.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'firebase_options.dart';
import 'package:cmms/authentication/welcome_screen.dart';
import 'package:cmms/authentication/need_account_screen.dart';

// Background message handler (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Check if notifications are enabled
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool('notifications_enabled') ?? true;
  if (!enabled) return;

  // Increment notification count for background messages
  final currentCount = prefs.getInt('notification_count') ?? 0;
  await prefs.setInt('notification_count', currentCount + 1);

  final logger = Logger();
  logger.i('Handling background message: ${message.messageId}');
}

// Background task dispatcher for WorkManager
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final logger = Logger();

    try {
      logger.i('🚀 Background task started: $task with data: $inputData');

      // Initialize Firebase for background context
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      logger.i('✅ Firebase initialized in background task');

      switch (task) {
        case 'daily_notification_check':
          logger.i('📅 Processing daily notification check...');
          await NotificationSchedulerService.processDailyNotificationCheck();
          logger.i('✅ Daily notification check completed');
          break;

        case 'test_notification_task':
          final notificationId = inputData?['notification_id'] as String?;
          logger.i('🧪 Processing test notification: $notificationId');

          if (notificationId != null) {
            await NotificationSchedulerService.processTestNotification(notificationId);
            logger.i('✅ Test notification processed successfully: $notificationId');
          } else {
            logger.e('❌ Test notification task missing notification_id');
            return false;
          }
          break;

        case 'cleanupExpiredNotifications':
          logger.i('🧹 Processing cleanup task...');
          await BackgroundNotificationService.cleanupExpiredNotifications();
          logger.i('✅ Cleanup task completed');
          break;

        case 'processNotificationQueue':
          logger.i('🔄 Processing notification queue task...');
          await BackgroundNotificationService.processNotificationQueue();
          logger.i('✅ Queue processing task completed');
          break;

        case 'background_notification_service':
          logger.i('🔧 Processing background notification service task...');
          final success = await BackgroundNotificationService.handleBackgroundTask(inputData ?? {});
          logger.i(success ? '✅ Background service task completed' : '❌ Background service task failed');
          return success;

        default:
          logger.w('⚠️ Unknown background task: $task');
          return false;
      }

      logger.i('🎉 Background task $task completed successfully');
      return true;

    } catch (e, stackTrace) {
      logger.e('💥 Background task $task failed: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  });
}

// Initialize the notification channel for Android
const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'maintenance_channel',
  'Maintenance Notifications',
  description: 'Notifications for maintenance task reminders',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
  ledColor: Colors.blueGrey,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final logger = Logger();

  // Clear Firestore persistence before any Firestore operations
  try {
    await FirebaseFirestore.instance.clearPersistence();
    logger.i('Firestore cache cleared on app start');
  } catch (e, stackTrace) {
    logger.e('Error clearing Firestore cache: $e', stackTrace: stackTrace);
  }

  // Set up background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize WorkManager with the callback dispatcher
  if (!kIsWeb) {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    logger.i('WorkManager initialized');
  }

  // Initialize local notifications (mobile only)
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

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        logger.i('Local notification tapped: ${response.payload}');
        NotificationService().resetNotificationCount();
      },
    );

    // Create Android notification channel
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Set foreground notification options
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  // Initialize all notification services
  await _initializeNotificationServicesOptimized();

  runApp(const MyApp());
}

/// Initialize all notification services
Future<void> _initializeNotificationServicesOptimized() async {
  final logger = Logger();

  try {
    logger.i('🚀 Starting optimized notification services initialization...');

    // Phase 1: Initialize critical services first
    await NotificationService().initialize();
    logger.i('✅ Regular notification service initialized');

    await SystemTrayNotificationService().initialize();
    logger.i('✅ System tray notification service initialized');

    // Phase 2: Initialize remaining services in background
    Future.microtask(() async {
      try {
        await FCMHttpService().initialize();
        logger.i('✅ FCM HTTP service initialized');

        await NotificationQueueService().initialize();
        logger.i('✅ Notification queue service initialized');

        await NotificationSchedulerService().initialize();
        logger.i('✅ Notification scheduler service initialized');

        await BackgroundNotificationService().initialize();
        logger.i('✅ Background notification service initialized');

        await RealtimeNotificationMonitor().initialize();
        logger.i('🎯 Real-time notification monitor initialized');

        await SystemNotificationService().initialize();
        logger.i('✅ System notification service initialized');

        logger.i('🎉 All background notification services initialization completed');
      } catch (e) {
        logger.e('💥 Error during background service initialization: $e');
      }
    });

    logger.i('✅ Core notification services initialized, background services loading...');
  } catch (e) {
    logger.e('💥 Error during core notification services initialization: $e');
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
    RealtimeNotificationMonitor().dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        _logger.i('📱 App resumed - reinitializing real-time monitor');
        RealtimeNotificationMonitor().initialize();
        break;
      case AppLifecycleState.paused:
        _logger.i('📱 App paused - real-time monitor continues in background');
        break;
      case AppLifecycleState.detached:
        _logger.i('📱 App detached - disposing real-time monitor');
        RealtimeNotificationMonitor().dispose();
        break;
      default:
        break;
    }
  }

  void _setupForegroundMessageHandling() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      _logger.i('📨 Received foreground message: ${message.notification?.title}');

      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('notifications_enabled') ?? true;
      if (!enabled) return;

      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      await NotificationService().incrementNotificationCount();

      if (kIsWeb) {
        _logger.i('🌐 Web notification will be handled by service worker');
      } else {
        if (notification != null && android != null) {
          await SystemTrayNotificationService().showSystemTrayNotification(
            id: notification.hashCode,
            title: notification.title ?? 'Maintenance Notification',
            body: notification.body ?? 'You have a new maintenance notification',
            isUrgent: message.data['priority'] == 'urgent',
            data: message.data.map((key, value) => MapEntry(key, value.toString())),
          );

          _logger.i('🔔 System tray notification shown for foreground message');
        }
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _logger.i('👆 Notification opened app: ${message.notification?.title}');
      NotificationService().resetNotificationCount();

      Future.delayed(const Duration(milliseconds: 500), () {
        navigatorKey.currentState?.pushNamed('/notification-status');
      });
    });

    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _logger.i('🚀 App opened from terminated state via notification: ${message.notification?.title}');
        NotificationService().resetNotificationCount();

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
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.poppinsTextTheme(),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueGrey,
          brightness: Brightness.light,
        ),
      ),
      home: const WelcomeScreen(),
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