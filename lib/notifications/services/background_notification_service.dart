import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/notification_scheduler_service.dart';
import 'package:cmms/notifications/services/notification_queue_service.dart';

class BackgroundNotificationService {
  static final BackgroundNotificationService _instance = BackgroundNotificationService._internal();
  factory BackgroundNotificationService() => _instance;
  BackgroundNotificationService._internal();

  final Logger _logger = Logger();
  
  static const String _cleanupTask = 'cleanupExpiredNotifications';
  static const String _queueProcessingTask = 'processNotificationQueue';

  /// Initialize background tasks
  Future<void> initialize() async {
    try {
      // Workmanager has no real OS-level background execution on web — main.dart deliberately
      // skips Workmanager().initialize() there, so registering tasks here would throw
      // 'WorkmanagerWeb.initialize() must be called before registering tasks.'
      if (!kIsWeb) {
        await Workmanager().initialize(
          callbackDispatcher,
        );

        // Schedule periodic tasks
        await _schedulePeriodicTasks();
      }

      // Initialize the notification scheduler
      await NotificationSchedulerService().initialize();

      // Initialize notification queue service
      await NotificationQueueService().initialize();

      _logger.i('Background notification service initialized');
    } catch (e) {
      _logger.e('Failed to initialize background service: $e');
      rethrow;
    }
  }

  /// Schedule periodic background tasks
  Future<void> _schedulePeriodicTasks() async {
    // Cleanup expired notifications daily
    await Workmanager().registerPeriodicTask(
      _cleanupTask,
      _cleanupTask,
      frequency: const Duration(days: 1),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: true,
        requiresStorageNotLow: false,
      ),
      inputData: {
        'task_type': 'cleanup_notifications',
        'scheduled_at': DateTime.now().toIso8601String(),
      },
    );

    // Process notification queue every 30 minutes
    await Workmanager().registerPeriodicTask(
      _queueProcessingTask,
      _queueProcessingTask,
      frequency: const Duration(minutes: 30),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      inputData: {
        'task_type': 'process_queue',
        'scheduled_at': DateTime.now().toIso8601String(),
      },
    );

    _logger.i('Periodic background tasks scheduled');
  }

  /// Cancel all background tasks
  Future<void> cancelAllTasks() async {
    if (kIsWeb) return;
    await Workmanager().cancelAll();
    _logger.i('All background tasks cancelled');
  }

  /// Clean up expired notifications
  static Future<void> cleanupExpiredNotifications() async {
    final logger = Logger();

    try {
      logger.i('🧹 Cleaning up expired notifications...');

      final firestore = FirebaseFirestore.instance;
      final now = DateTime.now();

      // Clean up old custom notifications (older than 30 days and triggered)
      final expiredCustomQuery = await firestore
          .collection('CustomNotifications')
          .where('isTriggered', isEqualTo: true)
          .where('triggeredAt', isLessThan: Timestamp.fromDate(now.subtract(const Duration(days: 30))))
          .get();

      if (expiredCustomQuery.docs.isNotEmpty) {
        final batch = firestore.batch();

        for (final doc in expiredCustomQuery.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        logger.i('🗑️ Cleaned up ${expiredCustomQuery.docs.length} expired custom notifications');
      }

      // Clean up old system notifications (older than 90 days)
      final oldSystemQuery = await firestore
          .collection('SystemNotifications')
          .where('createdAt', isLessThan: Timestamp.fromDate(now.subtract(const Duration(days: 90))))
          .get();

      if (oldSystemQuery.docs.isNotEmpty) {
        final batch = firestore.batch();

        for (final doc in oldSystemQuery.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        logger.i('🗑️ Cleaned up ${oldSystemQuery.docs.length} old system notifications');
      }

      // Clean up failed notifications (older than 7 days)
      final failedNotificationsQuery = await firestore
          .collection('CustomNotifications')
          .where('status', isEqualTo: 'failed')
          .where('lastErrorAt', isLessThan: Timestamp.fromDate(now.subtract(const Duration(days: 7))))
          .get();

      if (failedNotificationsQuery.docs.isNotEmpty) {
        final batch = firestore.batch();

        for (final doc in failedNotificationsQuery.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
        logger.i('🗑️ Cleaned up ${failedNotificationsQuery.docs.length} failed notifications');
      }

      logger.i('✅ Cleanup completed successfully');
    } catch (e) {
      logger.e('💥 Error in cleanupExpiredNotifications: $e');
    }
  }

  /// Process notification queue
  static Future<void> processNotificationQueue() async {
    final logger = Logger();

    try {
      logger.i('🔄 Processing notification queue...');

      // Initialize Firebase
      await Firebase.initializeApp();

      // Initialize and process queue
      final queueService = NotificationQueueService();
      await queueService.initialize();

      // The queue service will automatically process items
      final status = queueService.getQueueStatus();
      logger.i('📊 Queue status: ${status['totalItems']} total, ${status['highPriority']} high priority');

      logger.i('✅ Queue processing completed');
    } catch (e) {
      logger.e('💥 Error processing notification queue: $e');
    }
  }

  /// Handle background task (called from main.dart dispatcher)
  static Future<bool> handleBackgroundTask(Map<String, dynamic> inputData) async {
    final logger = Logger();

    try {
      final taskType = inputData['task_type'] as String?;
      logger.i('🔧 Handling background task: $taskType');

      switch (taskType) {
        case 'cleanup_notifications':
          await cleanupExpiredNotifications();
          break;
        case 'process_queue':
          await processNotificationQueue();
          break;
        default:
          logger.w('⚠️ Unknown background task type: $taskType');
          return false;
      }

      return true;
    } catch (e) {
      logger.e('💥 Error in handleBackgroundTask: $e');
      return false;
    }
  }
}

/// Background task callback dispatcher - UPDATED VERSION
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final logger = Logger();

    try {
      logger.i('🚀 Background task started: $task with data: $inputData');

      // Initialize Firebase for background context
      await Firebase.initializeApp();
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
