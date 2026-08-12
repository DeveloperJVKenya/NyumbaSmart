import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/fcm_http_service.dart';
import 'package:cmms/notifications/models/system_notification_model.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';

class NotificationQueueService {
  static final NotificationQueueService _instance = NotificationQueueService._internal();
  factory NotificationQueueService() => _instance;
  NotificationQueueService._internal();

  final Logger _logger = Logger();
  final FCMHttpService _fcmService = FCMHttpService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final List<QueuedNotification> _queue = [];
  Timer? _processingTimer;
  bool _isProcessing = false;

  /// Initialize the queue service
  Future<void> initialize() async {
    try {
      await _fcmService.initialize();
      _startQueueProcessing();
      _logger.i('Notification queue service initialized');
    } catch (e) {
      _logger.e('Failed to initialize notification queue service: $e');
    }
  }

  /// Start processing the queue every 30 seconds
  void _startQueueProcessing() {
    _processingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _processQueue();
    });
  }

  /// Add system notification to queue
  Future<void> queueSystemNotification(SystemNotificationModel notification) async {
    final queuedNotification = QueuedNotification(
      id: notification.id,
      type: NotificationQueueType.system,
      title: notification.title,
      body: notification.body,
      priority: notification.type == SystemNotificationType.alert ? 1 : 2,
      data: {
        'type': 'system',
        'notification_type': notification.type.name,
        'categories': notification.categories.join(','),
        'taskCount': notification.tasks.length.toString(),
        'notificationId': notification.id,
      },
      createdAt: DateTime.now(),
      retryCount: 0,
    );

    _queue.add(queuedNotification);
    _logger.i('System notification queued: ${notification.id}');
    
    // Process immediately if high priority
    if (queuedNotification.priority == 1) {
      _processQueue();
    }
  }

  /// Add custom notification to queue
  Future<void> queueCustomNotification(CustomNotificationModel notification) async {
    final queuedNotification = QueuedNotification(
      id: notification.id,
      type: NotificationQueueType.custom,
      title: notification.title,
      body: notification.body,
      priority: notification.type == CustomNotificationType.alert ? 1 : 
                notification.type == CustomNotificationType.test ? 2 : 3,
      data: {
        'type': 'custom',
        'notification_type': notification.type.name,
        'category': notification.category,
        'component': notification.component,
        'organization': notification.organization,
        'notificationId': notification.id,
      },
      createdAt: DateTime.now(),
      retryCount: 0,
      organization: notification.organization,
    );

    _queue.add(queuedNotification);
    _logger.i('Custom notification queued: ${notification.id}');
    
    // Process immediately if high priority
    if (queuedNotification.priority <= 2) {
      _processQueue();
    }
  }

  /// Process the notification queue
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    _logger.i('Processing notification queue: ${_queue.length} items');

    try {
      // Sort by priority (1 = highest, 3 = lowest)
      _queue.sort((a, b) => a.priority.compareTo(b.priority));

      final toProcess = _queue.take(5).toList(); // Process max 5 at a time
      
      for (final notification in toProcess) {
        try {
          await _processNotification(notification);
          _queue.remove(notification);
        } catch (e) {
          _logger.e('Error processing notification ${notification.id}: $e');
          notification.retryCount++;
          notification.lastError = e.toString();
          notification.lastRetryAt = DateTime.now();

          // Remove if max retries reached
          if (notification.retryCount >= 3) {
            _logger.w('Max retries reached for notification ${notification.id}, removing from queue');
            _queue.remove(notification);
            await _markNotificationAsFailed(notification);
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Process individual notification
  Future<void> _processNotification(QueuedNotification notification) async {
    List<String> targetUsers = [];

    if (notification.type == NotificationQueueType.system) {
      // System notifications are for JV Almacis, the contractor who performs the on-site work.
      final usersSnapshot = await _firestore
          .collection('Users')
          .where('organization', isEqualTo: 'JV Almacis')
          .where('notificationsEnabled', isNotEqualTo: false)
          .get();
      targetUsers = usersSnapshot.docs.map((doc) => doc.id).toList();
    } else {
      // Get organization users for custom notifications
      if (notification.organization != null) {
        final usersSnapshot = await _firestore
            .collection('Users')
            .where('organization', isEqualTo: notification.organization!)
            .where('notificationsEnabled', isNotEqualTo: false)
            .get();
        targetUsers = usersSnapshot.docs.map((doc) => doc.id).toList();
      }
    }

    if (targetUsers.isEmpty) {
      _logger.w('No target users found for notification ${notification.id}');
      return;
    }

    // Send notification
    final result = await _fcmService.sendToMultipleUsers(
      title: notification.title,
      body: notification.body,
      userIds: targetUsers,
      notificationId: notification.id,
      priority: notification.priority == 1 ? 'urgent' : 'normal',
      data: notification.data,
    );

    // Update notification status in Firestore
    await _updateNotificationStatus(notification, result);

    _logger.i('Notification ${notification.id} processed: ${result.sentCount} sent, ${result.failedCount} failed');
  }

  /// Update notification status in Firestore
  Future<void> _updateNotificationStatus(QueuedNotification notification, FCMSendResult result) async {
    final collection = notification.type == NotificationQueueType.system 
        ? 'SystemNotifications' 
        : 'CustomNotifications';

    await _firestore.collection(collection).doc(notification.id).update({
      'isTriggered': true,
      'triggeredAt': FieldValue.serverTimestamp(),
      'sentCount': result.sentCount,
      'failedCount': result.failedCount,
      'lastSentAt': FieldValue.serverTimestamp(),
      'status': 'triggered',
    });
  }

  /// Mark notification as failed
  Future<void> _markNotificationAsFailed(QueuedNotification notification) async {
    final collection = notification.type == NotificationQueueType.system 
        ? 'SystemNotifications' 
        : 'CustomNotifications';

    await _firestore.collection(collection).doc(notification.id).update({
      'status': 'failed',
      'lastError': notification.lastError,
      'lastErrorAt': FieldValue.serverTimestamp(),
      'retryCount': notification.retryCount,
    });
  }

  /// Get queue status
  Map<String, dynamic> getQueueStatus() {
    return {
      'totalItems': _queue.length,
      'highPriority': _queue.where((n) => n.priority == 1).length,
      'mediumPriority': _queue.where((n) => n.priority == 2).length,
      'lowPriority': _queue.where((n) => n.priority == 3).length,
      'isProcessing': _isProcessing,
    };
  }

  void dispose() {
    _processingTimer?.cancel();
  }
}

enum NotificationQueueType { system, custom }

class QueuedNotification {
  final String id;
  final NotificationQueueType type;
  final String title;
  final String body;
  final int priority; // 1 = highest, 3 = lowest
  final Map<String, String> data;
  final DateTime createdAt;
  final String? organization;
  
  int retryCount;
  String? lastError;
  DateTime? lastRetryAt;

  QueuedNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.priority,
    required this.data,
    required this.createdAt,
    this.organization,
    this.retryCount = 0,
    this.lastError,
    this.lastRetryAt,
  });
}
