import 'dart:async';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/fcm_http_service.dart';
import 'package:cmms/notifications/models/system_notification_model.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';
import 'package:cmms/notifications/utils/timezone_utils.dart';
import 'package:cmms/notifications/services/notification_queue_service.dart';

class NotificationSchedulerService {
  static final NotificationSchedulerService _instance = NotificationSchedulerService._internal();
  factory NotificationSchedulerService() => _instance;
  NotificationSchedulerService._internal();

  final Logger _logger = Logger();
  final FCMHttpService _fcmService = FCMHttpService();
  
  static const String _dailyNotificationCheck = 'daily_notification_check';
  static const String _testNotificationTask = 'test_notification_task';

  /// Initialize the notification scheduler
  Future<void> initialize() async {
    try {
      // Try to initialize FCM service, but don't fail if it's not configured
      try {
        await _fcmService.initialize();
        _logger.i('FCM service initialized for scheduler');
      } catch (e) {
        _logger.w('FCM service not available for scheduler: $e');
        // Continue without FCM - notifications will be stored but not sent
      }
      
      await _scheduleDaily12AMCheck();
      _logger.i('Notification scheduler initialized');
    } catch (e) {
      _logger.e('Failed to initialize notification scheduler: $e');
      rethrow;
    }
  }

  /// Schedule daily notification check at 12:00 AM
  Future<void> _scheduleDaily12AMCheck() async {
    // Cancel existing daily task
    await Workmanager().cancelByUniqueName(_dailyNotificationCheck);
    
    // Calculate next 12:00 AM
    final now = DateTime.now();
    var next12AM = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);
    
    // If it's already past 12:00 AM today, schedule for today
    if (now.hour == 0 && now.minute < 5) {
      next12AM = DateTime(now.year, now.month, now.day, 0, 0, 0);
    }

    final delay = next12AM.difference(now);
    
    // Schedule one-time task for next 12:00 AM
    await Workmanager().registerOneOffTask(
      _dailyNotificationCheck,
      _dailyNotificationCheck,
      initialDelay: delay,
      inputData: {
        'task_type': 'daily_12am_check',
        'scheduled_for': next12AM.toIso8601String(),
      },
    );

    _logger.i('Scheduled daily 12:00 AM notification check for: $next12AM');
  }

  /// Schedule test notification (2 minutes delay)
  Future<void> scheduleTestNotification(String notificationId) async {
    try {
      final taskId = '${_testNotificationTask}_$notificationId';
      
      await Workmanager().registerOneOffTask(
        taskId,
        _testNotificationTask,
        initialDelay: const Duration(minutes: 2),
        inputData: {
          'task_type': 'test_notification',
          'notification_id': notificationId,
          'scheduled_at': DateTime.now().toIso8601String(),
        },
      );
      
      _logger.i('Scheduled test notification $notificationId for 2 minutes with task ID: $taskId');
    } catch (e) {
      _logger.e('Error scheduling test notification: $e');
      rethrow;
    }
  }

  /// Process daily notification check at 12:00 AM - UPDATED VERSION
  static Future<void> processDailyNotificationCheck() async {
    final logger = Logger();
    
    try {
      logger.i('🔄 Processing daily 12:00 AM notification check...');
      
      // Ensure Firebase is initialized in background context
      await Firebase.initializeApp();
      logger.i('✅ Firebase initialized for daily check');
      
      final firestore = FirebaseFirestore.instance;
      final queueService = NotificationQueueService();
      
      // Initialize queue service
      try {
        await queueService.initialize();
        logger.i('✅ Queue service initialized for daily check');
      } catch (e) {
        logger.w('⚠️ Queue service not available for daily check: $e');
        // Continue without queue - direct processing
      }
      
      final today = TimezoneUtils.getTodayMidnight();
      logger.i('📅 Checking notifications for date: ${TimezoneUtils.formatForDisplay(today)}');

      // Process system notifications
      await _processSystemNotifications(firestore, queueService, today, logger);

      // Process custom notifications
      await _processCustomNotifications(firestore, queueService, today, logger);

      // Reschedule for next day
      await NotificationSchedulerService()._scheduleDaily12AMCheck();

      logger.i('✅ Daily notification check completed successfully');
    } catch (e, stackTrace) {
      logger.e('💥 Error in daily notification check: $e', error: e, stackTrace: stackTrace);
      rethrow; // Let WorkManager handle the retry
    }
  }

  /// Process test notification - ENHANCED VERSION WITH BETTER ERROR HANDLING
  static Future<void> processTestNotification(String notificationId) async {
    final logger = Logger();
    
    try {
      logger.i('🧪 Starting test notification processing for: $notificationId');
      
      // Ensure Firebase is initialized
      await Firebase.initializeApp();
      logger.i('✅ Firebase initialized for test notification');
      
      final firestore = FirebaseFirestore.instance;
      final queueService = NotificationQueueService();
      
      // Try to initialize queue service
      bool queueAvailable = false;
      try {
        await queueService.initialize();
        queueAvailable = true;
        logger.i('✅ Queue service initialized for test notification');
      } catch (e) {
        logger.w('⚠️ Queue service not available for test notification: $e');
      }
      
      // Get the test notification
      final notificationDoc = await firestore
          .collection('CustomNotifications')
          .doc(notificationId)
          .get();
      
      if (!notificationDoc.exists) {
        logger.w('❌ Test notification not found: $notificationId');
        return;
      }

      final notification = CustomNotificationModel.fromFirestore(notificationDoc);
      logger.i('📋 Retrieved notification: ${notification.title} for org: ${notification.organization}');

      if (notification.type != CustomNotificationType.test) {
        logger.w('⚠️ Notification is not a test notification: $notificationId');
        return;
      }

      // Get users from the same organization
      final usersSnapshot = await firestore
          .collection('Users')
          .where('organization', isEqualTo: notification.organization)
          .where('notificationsEnabled', isNotEqualTo: false)
          .get();
      
      final targetUsers = usersSnapshot.docs.map((doc) => doc.id).toList();
      logger.i('👥 Found ${targetUsers.length} target users for organization: ${notification.organization}');

      if (targetUsers.isEmpty) {
        logger.w('⚠️ No target users found for test notification');
        // Still mark as triggered even if no users
        await firestore.collection('CustomNotifications').doc(notificationId).update({
          'isTriggered': true,
          'triggeredAt': FieldValue.serverTimestamp(),
          'sentCount': 0,
          'failedCount': 0,
          'lastSentAt': FieldValue.serverTimestamp(),
          'status': 'triggered',
        });
        logger.i('✅ Test notification marked as triggered (no users)');
        return;
      }

      if (queueAvailable) {
        // Use queue service for reliable delivery
        await queueService.queueCustomNotification(notification);
        logger.i('📤 Test notification added to queue for processing');
      } else {
        // Direct processing fallback
        await _processTestNotificationDirect(firestore, notification, targetUsers, logger);
      }

      logger.i('✅ Test notification processing completed: $notificationId');
    } catch (e, stackTrace) {
      logger.e('💥 Error processing test notification $notificationId: $e',
               error: e, stackTrace: stackTrace);
      
      // Try to mark as failed in database
      try {
        await FirebaseFirestore.instance
            .collection('CustomNotifications')
            .doc(notificationId)
            .update({
          'status': 'failed',
          'lastError': e.toString(),
          'lastErrorAt': FieldValue.serverTimestamp(),
        });
        logger.i('📝 Marked notification as failed in database');
      } catch (updateError) {
        logger.e('Failed to update error status: $updateError');
      }
      
      rethrow; // Let WorkManager handle the retry
    }
  }

  /// Direct test notification processing (fallback)
  static Future<void> _processTestNotificationDirect(
    FirebaseFirestore firestore,
    CustomNotificationModel notification,
    List<String> targetUsers,
    Logger logger,
  ) async {
    try {
      final fcmService = FCMHttpService();
      await fcmService.initialize();

      final result = await fcmService.sendToMultipleUsers(
        title: notification.title,
        body: notification.body,
        userIds: targetUsers,
        notificationId: notification.id,
        priority: 'urgent',
        data: {
          'type': 'test',
          'organization': notification.organization,
          'notificationId': notification.id,
        },
      );

      // Update notification status
      await firestore.collection('CustomNotifications').doc(notification.id).update({
        'isTriggered': true,
        'triggeredAt': FieldValue.serverTimestamp(),
        'sentCount': result.sentCount,
        'failedCount': result.failedCount,
        'lastSentAt': FieldValue.serverTimestamp(),
        'status': 'triggered',
      });

      logger.i('📤 Direct FCM notification sent: ${result.sentCount} successful, ${result.failedCount} failed');
    } catch (e) {
      logger.e('❌ Failed direct test notification processing: $e');
      
      // Mark as failed
      await firestore.collection('CustomNotifications').doc(notification.id).update({
        'status': 'failed',
        'lastError': e.toString(),
        'lastErrorAt': FieldValue.serverTimestamp(),
        'sentCount': 0,
        'failedCount': targetUsers.length,
      });
      
      rethrow;
    }
  }

  /// Process system notifications for the day - UPDATED VERSION
  static Future<void> _processSystemNotifications(
    FirebaseFirestore firestore,
    NotificationQueueService? queueService,
    DateTime today,
    Logger logger,
  ) async {
    try {
      // Get due system notifications using flexible date parsing
      final allSystemNotifications = await firestore
          .collection('SystemNotifications')
          .where('isTriggered', isEqualTo: false)
          .where('isActive', isEqualTo: true)
          .get();

      logger.i('📋 Found ${allSystemNotifications.docs.length} system notifications to check');

      int processedCount = 0;
      for (final doc in allSystemNotifications.docs) {
        try {
          final data = doc.data();
          
          // Parse notification date using TimezoneUtils
          final notificationDate = TimezoneUtils.parseFirestoreDate(data['notificationDate']);
          final alertDate = TimezoneUtils.parseFirestoreDate(data['alertDate']);

          if (notificationDate == null) {
            logger.w('⚠️ Could not parse notification date for ${doc.id}');
            continue;
          }

          bool shouldTrigger = false;
          String triggerReason = '';

          // Check if notification is due
          if (TimezoneUtils.isDue(notificationDate)) {
            shouldTrigger = true;
            triggerReason = 'notification_due';
          }
          // Check if alert is due
          else if (alertDate != null && TimezoneUtils.isDue(alertDate)) {
            shouldTrigger = true;
            triggerReason = 'alert_due';
            
            // Convert to alert
            await doc.reference.update({
              'type': 'alert',
              'title': 'URGENT: ${data['title'] ?? 'Maintenance Alert'}',
              'body': 'Due Tomorrow! ${data['body'] ?? 'Maintenance tasks require immediate attention'}',
            });
          }

          if (shouldTrigger) {
            logger.i('🔔 Triggering system notification ${doc.id} - Reason: $triggerReason');
            
            final notification = SystemNotificationModel.fromFirestore(doc);
            
            if (queueService != null) {
              await queueService.queueSystemNotification(notification);
            } else {
              await _processSystemNotificationDirect(firestore, notification, logger);
            }
            
            processedCount++;
          }
        } catch (e) {
          logger.e('Error processing system notification ${doc.id}: $e');
        }
      }

      logger.i('✅ Processed $processedCount system notifications');
    } catch (e) {
      logger.e('Error processing system notifications: $e');
    }
  }

  /// Process custom notifications for the day - UPDATED VERSION
  static Future<void> _processCustomNotifications(
    FirebaseFirestore firestore,
    NotificationQueueService? queueService,
    DateTime today,
    Logger logger,
  ) async {
    try {
      // Get due custom notifications (excluding test notifications)
      final allCustomNotifications = await firestore
          .collection('CustomNotifications')
          .where('isTriggered', isEqualTo: false)
          .where('isActive', isEqualTo: true)
          .where('type', isNotEqualTo: 'test')
          .get();

      logger.i('📋 Found ${allCustomNotifications.docs.length} custom notifications to check');

      int processedCount = 0;
      for (final doc in allCustomNotifications.docs) {
        try {
          final data = doc.data();
          
          // Parse notification date using TimezoneUtils
          final notificationDate = TimezoneUtils.parseFirestoreDate(data['notificationDate']);
          final alertDate = TimezoneUtils.parseFirestoreDate(data['alertDate']);

          if (notificationDate == null) {
            logger.w('⚠️ Could not parse notification date for ${doc.id}');
            continue;
          }

          bool shouldTrigger = false;
          String triggerReason = '';

          // Check if notification is due
          if (TimezoneUtils.isDue(notificationDate)) {
            shouldTrigger = true;
            triggerReason = 'notification_due';
          }
          // Check if alert is due
          else if (alertDate != null && TimezoneUtils.isDue(alertDate)) {
            shouldTrigger = true;
            triggerReason = 'alert_due';
            
            // Convert to alert
            await doc.reference.update({
              'type': 'alert',
              'title': 'URGENT: ${data['component'] ?? 'Component'} Maintenance',
              'body': 'Due Tomorrow! ${data['intervention'] ?? 'Maintenance'} required for ${data['component'] ?? 'component'}',
            });
          }

          if (shouldTrigger) {
            logger.i('🔔 Triggering custom notification ${doc.id} - Reason: $triggerReason');
            
            final notification = CustomNotificationModel.fromFirestore(doc);
            
            if (queueService != null) {
              await queueService.queueCustomNotification(notification);
            } else {
              await _processCustomNotificationDirect(firestore, notification, logger);
            }
            
            processedCount++;
          }
        } catch (e) {
          logger.e('Error processing custom notification ${doc.id}: $e');
        }
      }

      logger.i('✅ Processed $processedCount custom notifications');
    } catch (e) {
      logger.e('Error processing custom notifications: $e');
    }
  }

  /// Direct system notification processing (fallback)
  static Future<void> _processSystemNotificationDirect(
    FirebaseFirestore firestore,
    SystemNotificationModel notification,
    Logger logger,
  ) async {
    try {
      final fcmService = FCMHttpService();
      await fcmService.initialize();

      // Get JV Almacis users
      final usersSnapshot = await firestore
          .collection('Users')
          .where('organization', isEqualTo: 'JV Almacis')
          .where('notificationsEnabled', isNotEqualTo: false)
          .get();

      final targetUsers = usersSnapshot.docs.map((doc) => doc.id).toList();

      if (targetUsers.isEmpty) {
        logger.w('No JV Almacis users found for system notification');
        return;
      }

      final result = await fcmService.sendToMultipleUsers(
        title: notification.title,
        body: notification.body,
        userIds: targetUsers,
        notificationId: notification.id,
        priority: notification.type == SystemNotificationType.alert ? 'urgent' : 'normal',
        data: {
          'type': 'system',
          'notification_type': notification.type.name,
          'categories': notification.categories.join(','),
          'taskCount': notification.tasks.length.toString(),
          'notificationId': notification.id,
        },
      );

      await firestore.collection('SystemNotifications').doc(notification.id).update({
        'isTriggered': true,
        'triggeredAt': FieldValue.serverTimestamp(),
        'sentCount': result.sentCount,
        'failedCount': result.failedCount,
        'lastSentAt': FieldValue.serverTimestamp(),
        'status': 'triggered',
      });

      logger.i('System notification ${notification.id} sent: ${result.sentCount} successful, ${result.failedCount} failed');
    } catch (e) {
      logger.e('Error in direct system notification processing: $e');
      rethrow;
    }
  }

  /// Direct custom notification processing (fallback)
  static Future<void> _processCustomNotificationDirect(
    FirebaseFirestore firestore,
    CustomNotificationModel notification,
    Logger logger,
  ) async {
    try {
      final fcmService = FCMHttpService();
      await fcmService.initialize();

      // Get users from organization
      final usersSnapshot = await firestore
          .collection('Users')
          .where('organization', isEqualTo: notification.organization)
          .where('notificationsEnabled', isNotEqualTo: false)
          .get();

      final targetUsers = usersSnapshot.docs.map((doc) => doc.id).toList();

      if (targetUsers.isEmpty) {
        logger.w('No users found for organization: ${notification.organization}');
        return;
      }

      final result = await fcmService.sendToMultipleUsers(
        title: notification.title,
        body: notification.body,
        userIds: targetUsers,
        notificationId: notification.id,
        priority: notification.type == CustomNotificationType.alert ? 'urgent' : 'normal',
        data: {
          'type': 'custom',
          'notification_type': notification.type.name,
          'category': notification.category,
          'component': notification.component,
          'organization': notification.organization,
          'notificationId': notification.id,
        },
      );

      await firestore.collection('CustomNotifications').doc(notification.id).update({
        'isTriggered': true,
        'triggeredAt': FieldValue.serverTimestamp(),
        'sentCount': result.sentCount,
        'failedCount': result.failedCount,
        'lastSentAt': FieldValue.serverTimestamp(),
        'status': 'triggered',
      });

      logger.i('Custom notification ${notification.id} sent to ${notification.organization}: ${result.sentCount} successful, ${result.failedCount} failed');
    } catch (e) {
      logger.e('Error in direct custom notification processing: $e');
      rethrow;
    }
  }
}
