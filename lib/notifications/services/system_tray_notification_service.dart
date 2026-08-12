import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart'; // Import for Color class

class SystemTrayNotificationService {
  static final SystemTrayNotificationService _instance = SystemTrayNotificationService._internal();
  factory SystemTrayNotificationService() => _instance;
  SystemTrayNotificationService._internal();

  final Logger _logger = Logger();
  FlutterLocalNotificationsPlugin? _flutterLocalNotificationsPlugin;
  bool _isInitialized = false;

  /// Initialize the system tray notification service
  Future<void> initialize() async {
    if (_isInitialized || kIsWeb) return;

    try {
      _logger.i('🚀 Initializing SystemTrayNotificationService...');

      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

      // Android initialization settings
      const androidInitializationSettings = AndroidInitializationSettings('@mipmap/launcher_icon');

      // iOS initialization settings
      const iosInitializationSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // Combined initialization settings
      const initializationSettings = InitializationSettings(
        android: androidInitializationSettings,
        iOS: iosInitializationSettings,
      );

      // Initialize the plugin
      await _flutterLocalNotificationsPlugin!.initialize(
        settings: initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channel for Android
      await _createNotificationChannel();

      _isInitialized = true;
      _logger.i('✅ SystemTrayNotificationService initialized successfully');
    } catch (e) {
      _logger.e('💥 Failed to initialize SystemTrayNotificationService: $e');
      rethrow;
    }
  }

  /// Create notification channel for Android
  Future<void> _createNotificationChannel() async {
    if (kIsWeb) return;

    try {
      const androidNotificationChannel = AndroidNotificationChannel(
        'maintenance_channel',
        'Maintenance Notifications',
        description: 'Notifications for maintenance task reminders',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        ledColor: Color(0xFF607D8B), // Colors.blueGrey
      );

      await _flutterLocalNotificationsPlugin
          ?.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidNotificationChannel);

      _logger.i('✅ Android notification channel created');
    } catch (e) {
      _logger.e('💥 Error creating notification channel: $e');
    }
  }

  /// Handle notification tap
  void _onNotificationTapped(NotificationResponse response) {
    _logger.i('📱 Notification tapped: ${response.payload}');
    // Handle notification tap - could navigate to specific screen
    // This would typically be handled by the main app
  }

  /// Show system tray notification
  Future<void> showSystemTrayNotification({
    required int id,
    required String title,
    required String body,
    bool isUrgent = false,
    Map<String, String>? data,
  }) async {
    if (!_isInitialized || kIsWeb) {
      _logger.w('⚠️ SystemTrayNotificationService not initialized or running on web');
      return;
    }

    try {
      // Android notification details
      final androidNotificationDetails = AndroidNotificationDetails(
        'maintenance_channel',
        'Maintenance Notifications',
        channelDescription: 'Notifications for maintenance task reminders',
        importance: isUrgent ? Importance.max : Importance.high,
        priority: isUrgent ? Priority.max : Priority.high,
        playSound: true,
        enableVibration: true,
        color: const Color(0xFF607D8B), // Colors.blueGrey
        ledColor: const Color(0xFF607D8B),
        ledOnMs: 1000,
        ledOffMs: 500,
        ticker: title,
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: title,
          summaryText: isUrgent ? 'URGENT' : 'Maintenance',
        ),
      );

      // iOS notification details
      const iosNotificationDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      // Combined notification details
      final notificationDetails = NotificationDetails(
        android: androidNotificationDetails,
        iOS: iosNotificationDetails,
      );

      // Show the notification
      await _flutterLocalNotificationsPlugin!.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: notificationDetails,
        payload: data?.toString(),
      );

      _logger.i('🔔 System tray notification shown: $title');
    } catch (e) {
      _logger.e('💥 Error showing system tray notification: $e');
    }
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(int id) async {
    if (!_isInitialized || kIsWeb) return;

    try {
      await _flutterLocalNotificationsPlugin!.cancel(id: id);
      _logger.i('❌ Notification cancelled: $id');
    } catch (e) {
      _logger.e('💥 Error cancelling notification: $e');
    }
  }

  /// Cancel all notifications
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized || kIsWeb) return;

    try {
      await _flutterLocalNotificationsPlugin!.cancelAll();
      _logger.i('❌ All notifications cancelled');
    } catch (e) {
      _logger.e('💥 Error cancelling all notifications: $e');
    }
  }

  /// Get pending notifications
  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (!_isInitialized || kIsWeb) return [];

    try {
      final pendingNotifications = await _flutterLocalNotificationsPlugin!.pendingNotificationRequests();
      _logger.i('📋 Found ${pendingNotifications.length} pending notifications');
      return pendingNotifications;
    } catch (e) {
      _logger.e('💥 Error getting pending notifications: $e');
      return [];
    }
  }

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    if (!_isInitialized || kIsWeb) return false;

    try {
      final androidImplementation = _flutterLocalNotificationsPlugin!
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      
      if (androidImplementation != null) {
        return await androidImplementation.areNotificationsEnabled() ?? false;
      }
      
      return true; // Assume enabled for iOS
    } catch (e) {
      _logger.e('💥 Error checking notification permissions: $e');
      return false;
    }
  }

  /// Request notification permissions (iOS)
  Future<bool> requestPermissions() async {
    if (!_isInitialized || kIsWeb) return false;

    try {
      final iosImplementation = _flutterLocalNotificationsPlugin!
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      
      if (iosImplementation != null) {
        final result = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        _logger.i('📱 iOS notification permissions: $result');
        return result ?? false;
      }
      
      return true; // Android doesn't need explicit permission request
    } catch (e) {
      _logger.e('💥 Error requesting notification permissions: $e');
      return false;
    }
  }

  /// Dispose resources
  void dispose() {
    _isInitialized = false;
    _logger.i('🗑️ SystemTrayNotificationService disposed');
  }

  /// Get initialization status
  bool get isInitialized => _isInitialized;
}
