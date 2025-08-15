import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/notifications/services/notification_scheduler_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cmms/notifications/models/system_notification_model.dart';
import 'package:cmms/notifications/models/maintenance_task_model.dart';
import 'package:cmms/notifications/utils/date_calculator.dart';
import 'package:cmms/notifications/services/fcm_http_service.dart';
import 'package:cmms/notifications/services/background_notification_service.dart';
import 'package:cmms/notifications/services/notification_queue_service.dart';

class SystemNotificationService {
  static final SystemNotificationService _instance = SystemNotificationService._internal();
  factory SystemNotificationService() => _instance;
  SystemNotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FCMHttpService _fcmService = FCMHttpService();
  final BackgroundNotificationService _backgroundService = BackgroundNotificationService();
  final Logger _logger = Logger();

  static const String _autoNotificationEnabledKey = 'system_auto_notifications_enabled';

  /// Initialize the service
  Future<void> initialize() async {
    try {
      // Initialize FCM HTTP service
      await _fcmService.initialize();

      // Initialize background service
      await _backgroundService.initialize();

      _logger.i('System notification service initialized');
    } catch (e) {
      _logger.e('Failed to initialize system notification service: $e');
      rethrow;
    }
  }

  /// Check if auto notifications are enabled
  Future<bool> areAutoNotificationsEnabled() async {
    try {
      final doc = await _firestore.collection('SystemSettings').doc('notifications').get();
      if (doc.exists) {
        return doc.data()?['autoNotificationsEnabled'] ?? false;
      }
      return false;
    } catch (e) {
      _logger.e('Error checking auto notifications status: $e');
      return false;
    }
  }

  /// Set auto notifications enabled status
  Future<void> setAutoNotificationsEnabled(bool enabled) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      await _firestore.collection('SystemSettings').doc('notifications').set({
        'autoNotificationsEnabled': enabled,
        'lastUpdatedBy': user.uid,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoNotificationEnabledKey, enabled);

      _logger.i('Auto notifications ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      _logger.e('Error setting auto notifications: $e');
      rethrow;
    }
  }

  /// Generate system notifications
  Future<void> generateSystemNotifications() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      _logger.i('Starting system notification generation...');

      // Get all maintenance tasks
      final tasksSnapshot = await _firestore.collection('Maintenance_Tasks').get();
      final tasks = tasksSnapshot.docs
          .map((doc) => MaintenanceTaskModel.fromFirestore(doc))
          .toList();

      if (tasks.isEmpty) {
        _logger.w('No maintenance tasks found');
        return;
      }

      // Clear existing system notifications
      await _clearExistingSystemNotifications();

      // Group tasks by frequency
      final Map<int, List<MaintenanceTaskModel>> tasksByFrequency = {};
      for (final task in tasks) {
        if (!tasksByFrequency.containsKey(task.frequency)) {
          tasksByFrequency[task.frequency] = [];
        }
        tasksByFrequency[task.frequency]!.add(task);
      }

      final currentYear = DateTime.now().year;
      final generatedNotifications = <SystemNotificationModel>[];

      // Generate notifications for each frequency
      for (final entry in tasksByFrequency.entries) {
        final frequency = entry.key;
        final frequencyTasks = entry.value;

        // Get next schedule for this frequency
        final nextSchedule = NotificationDateCalculator.getNextScheduleForFrequency(
          frequencyMonths: frequency,
          year: currentYear,
        );

        if (nextSchedule.isEmpty) continue;

        final notificationDate = nextSchedule['notificationDate']!;
        final alertDate = nextSchedule['alertDate']!;
        final nextInspectionDate = nextSchedule['nextInspectionDate']!;

        // Group tasks by category for this frequency
        final categories = frequencyTasks.map((t) => t.category).toSet().toList();

        // Create notification
        final notification = SystemNotificationModel(
          id: '',
          title: 'Maintenance Tasks Due',
          body: '${frequencyTasks.length} tasks in ${categories.length} categories need attention',
          notificationDate: notificationDate,
          alertDate: alertDate,
          nextInspectionDate: nextInspectionDate,
          categories: categories,
          tasks: frequencyTasks.map((task) => SystemNotificationTask(
            category: task.category,
            component: task.component,
            intervention: task.intervention,
            frequency: task.frequency,
            lastInspectionDate: NotificationDateCalculator.getYearStartDate(currentYear),
          )).toList(),
          createdAt: DateTime.now(),
          createdBy: user.uid,
        );

        generatedNotifications.add(notification);

        // Create alert notification
        final alertNotification = SystemNotificationModel(
          id: '',
          title: 'Maintenance Alert - Due Tomorrow!',
          body: '${frequencyTasks.length} maintenance tasks are due tomorrow - immediate attention required!',
          notificationDate: alertDate,
          alertDate: alertDate,
          nextInspectionDate: nextInspectionDate,
          categories: categories,
          tasks: frequencyTasks.map((task) => SystemNotificationTask(
            category: task.category,
            component: task.component,
            intervention: task.intervention,
            frequency: task.frequency,
            lastInspectionDate: NotificationDateCalculator.getYearStartDate(currentYear),
          )).toList(),
          type: SystemNotificationType.alert,
          createdAt: DateTime.now(),
          createdBy: user.uid,
        );

        generatedNotifications.add(alertNotification);
      }

      // Save notifications to Firestore
      final batch = _firestore.batch();
      for (final notification in generatedNotifications) {
        final docRef = _firestore.collection('SystemNotifications').doc();
        batch.set(docRef, notification.toMap());
      }
      await batch.commit();

      // Enable auto notifications
      await setAutoNotificationsEnabled(true);

      _logger.i('Generated ${generatedNotifications.length} system notifications');
    } catch (e) {
      _logger.e('Error generating system notifications: $e');
      rethrow;
    }
  }

  /// Regenerate system notifications
  Future<void> regenerateSystemNotifications() async {
    await generateSystemNotifications();
  }

  /// Clear existing system notifications
  Future<void> _clearExistingSystemNotifications() async {
    try {
      final existingNotifications = await _firestore
          .collection('SystemNotifications')
          .where('isTriggered', isEqualTo: false)
          .get();

      if (existingNotifications.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (final doc in existingNotifications.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        _logger.i('Cleared ${existingNotifications.docs.length} existing notifications');
      }
    } catch (e) {
      _logger.e('Error clearing existing notifications: $e');
    }
  }

  /// Send system notification using queue service
  Future<void> sendSystemNotification(String notificationId) async {
    try {
      // Get notification details
      final notificationDoc = await _firestore
          .collection('SystemNotifications')
          .doc(notificationId)
          .get();

      if (!notificationDoc.exists) {
        throw Exception('Notification not found');
      }

      final notification = SystemNotificationModel.fromFirestore(notificationDoc);

      // Add to queue for processing
      final queueService = NotificationQueueService();
      await queueService.initialize();
      await queueService.queueSystemNotification(notification);

      _logger.i('System notification queued for sending: $notificationId');
    } catch (e) {
      _logger.e('Error sending system notification: $e');
      rethrow;
    }
  }

  /// Send test notification - FIXED VERSION
  Future<bool> sendTestNotification({
    String? userId,
    String title = 'Test System Notification',
    String body = 'This is a test notification from the CMMS system',
  }) async {
    try {
      final targetUserId = userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (targetUserId == null) {
        _logger.e('No user ID provided for test notification');
        return false;
      }

      return await _fcmService.sendTestNotification(
        userId: targetUserId,
        title: title,
        body: body,
      );
    } catch (e) {
      _logger.e('Error sending test notification: $e');
      return false;
    }
  }

  /// Manually trigger notification check - FIXED VERSION
  Future<void> triggerNotificationCheck() async {
    try {
      // Process daily notification check immediately
      await NotificationSchedulerService.processDailyNotificationCheck();
      _logger.i('Manual notification check triggered');
    } catch (e) {
      _logger.e('Error triggering notification check: $e');
      rethrow;
    }
  }

  /// Mark notification as read by user
  Future<void> markNotificationAsRead(String notificationId, String userId) async {
    try {
      // Get user name
      String userName = 'Unknown User';
      try {
        final userDoc = await _firestore.collection('Users').doc(userId).get();
        if (userDoc.exists) {
          final userData = userDoc.data()!;
          userName = userData['name'] ?? userData['email'] ?? 'Unknown User';
        }
      } catch (e) {
        _logger.w('Could not fetch user name for $userId: $e');
      }

      final notificationRef = _firestore.collection('SystemNotifications').doc(notificationId);

      await _firestore.runTransaction((transaction) async {
        final doc = await transaction.get(notificationRef);
        if (!doc.exists) return;

        final data = doc.data()!;
        final readByUsers = List<Map<String, dynamic>>.from(data['readByUsers'] ?? []);

        // Check if user already read this notification
        final existingIndex = readByUsers.indexWhere((r) => r['userId'] == userId);
        if (existingIndex == -1) {
          // Add new read info
          readByUsers.add({
            'userId': userId,
            'userName': userName,
            'readAt': FieldValue.serverTimestamp(),
          });

          transaction.update(notificationRef, {
            'readByUsers': readByUsers,
            'status': readByUsers.isNotEmpty ? 'read' : 'triggered',
          });
        }
      });

      _logger.i('Notification $notificationId marked as read by user $userName ($userId)');
    } catch (e) {
      _logger.e('Error marking notification as read: $e');
    }
  }

  /// Get system notifications stream
  Stream<List<SystemNotificationModel>> getSystemNotifications() {
    return _firestore
        .collection('SystemNotifications')
        .where('isActive', isEqualTo: true)
        .orderBy('notificationDate', descending: false)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SystemNotificationModel.fromFirestore(doc))
            .where((notification) =>
                 NotificationDateCalculator.isDateInFuture(notification.notificationDate) ||
                 notification.isTriggered)
            .toList());
  }

  /// Get active notifications (for floating widget)
  Stream<List<SystemNotificationModel>> getActiveNotifications() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _firestore
        .collection('SystemNotifications')
        .where('notificationDate', isLessThanOrEqualTo: Timestamp.fromDate(today))
        .where('isTriggered', isEqualTo: true)
        .where('isActive', isEqualTo: true)
        .orderBy('notificationDate', descending: false)
        .orderBy('triggeredAt', descending: true)
        .limit(5)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SystemNotificationModel.fromFirestore(doc))
            .toList());
  }

  /// Get notification by ID
  Future<SystemNotificationModel?> getNotificationById(String notificationId) async {
    try {
      final doc = await _firestore.collection('SystemNotifications').doc(notificationId).get();
      if (doc.exists) {
        return SystemNotificationModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      _logger.e('Error getting notification by ID: $e');
      return null;
    }
  }

  void dispose() {
    // Clean up any resources if needed
  }
}
