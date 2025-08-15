import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/utils/timezone_utils.dart';
import 'package:cmms/notifications/services/notification_queue_service.dart';
import 'package:cmms/notifications/models/system_notification_model.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';

class BackgroundTaskHandler {
  static final Logger _logger = Logger();

  /// Process daily notification check at 12:00 AM
  static Future<bool> processDailyNotificationCheck() async {
    try {
      _logger.i('🔄 Starting daily notification check...');

      // Ensure Firebase is initialized
      await Firebase.initializeApp();
      
      final firestore = FirebaseFirestore.instance;
      final queueService = NotificationQueueService();
      await queueService.initialize();

      final today = TimezoneUtils.getTodayMidnight();
      _logger.i('📅 Checking notifications for date: ${TimezoneUtils.formatForDisplay(today)}');

      // Process system notifications
      await _processSystemNotifications(firestore, queueService, today);

      // Process custom notifications
      await _processCustomNotifications(firestore, queueService, today);

      _logger.i('✅ Daily notification check completed successfully');
      return true;
    } catch (e, stackTrace) {
      _logger.e('💥 Error in daily notification check: $e', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  /// Process system notifications
  static Future<void> _processSystemNotifications(
    FirebaseFirestore firestore,
    NotificationQueueService queueService,
    DateTime today,
  ) async {
    try {
      // Get due system notifications
      final dueNotificationsQuery = await firestore
          .collection('SystemNotifications')
          .where('isTriggered', isEqualTo: false)
          .where('isActive', isEqualTo: true)
          .get();

      _logger.i('📋 Found ${dueNotificationsQuery.docs.length} system notifications to check');

      for (final doc in dueNotificationsQuery.docs) {
        try {
          final notification = SystemNotificationModel.fromFirestore(doc);
          
          // Parse notification date
          final notificationDate = TimezoneUtils.parseFirestoreDate(doc.data()['notificationDate']);
          final alertDate = TimezoneUtils.parseFirestoreDate(doc.data()['alertDate']);

          if (notificationDate == null) {
            _logger.w('⚠️ Could not parse notification date for ${doc.id}');
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
              'title': 'URGENT: ${notification.title}',
              'body': 'Due Tomorrow! ${notification.body}',
            });
          }

          if (shouldTrigger) {
            _logger.i('🔔 Triggering system notification ${doc.id} - Reason: $triggerReason');
            
            // Add to queue for processing
            final updatedNotification = SystemNotificationModel.fromFirestore(doc);
            await queueService.queueSystemNotification(updatedNotification);
          }
        } catch (e) {
          _logger.e('Error processing system notification ${doc.id}: $e');
        }
      }
    } catch (e) {
      _logger.e('Error processing system notifications: $e');
    }
  }

  /// Process custom notifications
  static Future<void> _processCustomNotifications(
    FirebaseFirestore firestore,
    NotificationQueueService queueService,
    DateTime today,
  ) async {
    try {
      // Get due custom notifications (excluding test notifications)
      final dueNotificationsQuery = await firestore
          .collection('CustomNotifications')
          .where('isTriggered', isEqualTo: false)
          .where('isActive', isEqualTo: true)
          .where('type', isNotEqualTo: 'test')
          .get();

      _logger.i('📋 Found ${dueNotificationsQuery.docs.length} custom notifications to check');

      for (final doc in dueNotificationsQuery.docs) {
        try {
          final notification = CustomNotificationModel.fromFirestore(doc);
          
          // Parse notification date
          final notificationDate = TimezoneUtils.parseFirestoreDate(doc.data()['notificationDate']);
          final alertDate = TimezoneUtils.parseFirestoreDate(doc.data()['alertDate']);

          if (notificationDate == null) {
            _logger.w('⚠️ Could not parse notification date for ${doc.id}');
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
              'title': 'URGENT: ${notification.component} Maintenance',
              'body': 'Due Tomorrow! ${notification.intervention} required for ${notification.component}',
            });
          }

          if (shouldTrigger) {
            _logger.i('🔔 Triggering custom notification ${doc.id} - Reason: $triggerReason');
            
            // Add to queue for processing
            final updatedNotification = CustomNotificationModel.fromFirestore(doc);
            await queueService.queueCustomNotification(updatedNotification);
          }
        } catch (e) {
          _logger.e('Error processing custom notification ${doc.id}: $e');
        }
      }
    } catch (e) {
      _logger.e('Error processing custom notifications: $e');
    }
  }

  /// Process test notification
  static Future<bool> processTestNotification(String notificationId) async {
    try {
      _logger.i('🧪 Processing test notification: $notificationId');

      await Firebase.initializeApp();
      final firestore = FirebaseFirestore.instance;
      final queueService = NotificationQueueService();
      await queueService.initialize();

      // Get the test notification
      final notificationDoc = await firestore
          .collection('CustomNotifications')
          .doc(notificationId)
          .get();

      if (!notificationDoc.exists) {
        _logger.w('❌ Test notification not found: $notificationId');
        return false;
      }

      final notification = CustomNotificationModel.fromFirestore(notificationDoc);

      if (notification.type != CustomNotificationType.test) {
        _logger.w('⚠️ Notification is not a test notification: $notificationId');
        return false;
      }

      // Add to queue for immediate processing
      await queueService.queueCustomNotification(notification);

      _logger.i('✅ Test notification queued successfully: $notificationId');
      return true;
    } catch (e, stackTrace) {
      _logger.e('💥 Error processing test notification $notificationId: $e', 
                error: e, stackTrace: stackTrace);
      return false;
    }
  }
}
