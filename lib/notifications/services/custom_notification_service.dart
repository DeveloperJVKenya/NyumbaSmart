import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';
import 'package:cmms/notifications/utils/date_calculator.dart';
import 'package:cmms/notifications/services/fcm_http_service.dart';
import 'package:cmms/notifications/services/system_tray_notification_service.dart';

class CustomNotificationService {
  static final CustomNotificationService _instance = CustomNotificationService._internal();
  factory CustomNotificationService() => _instance;
  CustomNotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Logger _logger = Logger();
  final FCMHttpService _fcmService = FCMHttpService();
  final SystemTrayNotificationService _systemTrayService = SystemTrayNotificationService();

  /// Initialize the service
  Future<void> initialize() async {
    try {
      await _fcmService.initialize();
      await _systemTrayService.initialize();
      _logger.i('✅ CustomNotificationService initialized');
    } catch (e) {
      _logger.e('💥 Failed to initialize CustomNotificationService: $e');
      rethrow;
    }
  }

  /// Create a new custom notification
  Future<String> createCustomNotification({
    required String category,
    required String component,
    required String intervention,
    required int frequency,
    required DateTime lastInspectionDate,
    required String organization,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Calculate notification dates
      final dates = NotificationDateCalculator.calculateNotificationDates(
        lastInspectionDate: lastInspectionDate,
        frequencyMonths: frequency,
      );

      final notification = CustomNotificationModel(
        id: '',
        title: 'Maintenance Due: $component',
        body: '$intervention required for $component in $category',
        category: category,
        component: component,
        intervention: intervention,
        frequency: frequency,
        lastInspectionDate: lastInspectionDate,
        notificationDate: dates['notificationDate']!,
        alertDate: dates['alertDate']!,
        nextInspectionDate: dates['nextInspectionDate']!,
        type: CustomNotificationType.notification,
        createdAt: DateTime.now(),
        createdBy: user.uid,
        organization: organization,
      );

      final docRef = await _firestore.collection('CustomNotifications').add(notification.toMap());
      
      _logger.i('✅ Custom notification created: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      _logger.e('💥 Error creating custom notification: $e');
      rethrow;
    }
  }

  /// Edit an existing custom notification
  Future<void> editCustomNotification({
    required String notificationId,
    required String category,
    required String component,
    required String intervention,
    required int frequency,
    required DateTime lastInspectionDate,
  }) async {
    try {
      // Calculate new notification dates
      final dates = NotificationDateCalculator.calculateNotificationDates(
        lastInspectionDate: lastInspectionDate,
        frequencyMonths: frequency,
      );

      final updateData = {
        'title': 'Maintenance Due: $component',
        'body': '$intervention required for $component in $category',
        'category': category,
        'component': component,
        'intervention': intervention,
        'frequency': frequency,
        'lastInspectionDate': Timestamp.fromDate(lastInspectionDate),
        'notificationDate': Timestamp.fromDate(dates['notificationDate']!),
        'alertDate': Timestamp.fromDate(dates['alertDate']!),
        'nextInspectionDate': Timestamp.fromDate(dates['nextInspectionDate']!),
        'updatedAt': FieldValue.serverTimestamp(),
        // Reset trigger status if dates changed
        'isTriggered': false,
        'triggeredAt': null,
        'status': 'active',
      };

      await _firestore.collection('CustomNotifications').doc(notificationId).update(updateData);
      
      _logger.i('✅ Custom notification updated: $notificationId');
    } catch (e) {
      _logger.e('💥 Error updating custom notification: $e');
      rethrow;
    }
  }

  /// Delete a custom notification
  Future<void> deleteCustomNotification(String notificationId) async {
    try {
      await _firestore.collection('CustomNotifications').doc(notificationId).delete();
      _logger.i('✅ Custom notification deleted: $notificationId');
    } catch (e) {
      _logger.e('💥 Error deleting custom notification: $e');
      rethrow;
    }
  }

  /// Get custom notifications by type for an organization
  Stream<List<CustomNotificationModel>> getCustomNotificationsByType(
    String organization,
    CustomNotificationType type,
  ) {
    return _firestore
        .collection('CustomNotifications')
        .where('organization', isEqualTo: organization)
        .where('type', isEqualTo: type.name)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CustomNotificationModel.fromFirestore(doc)).toList();
    });
  }

  /// Get all custom notifications for an organization
  Stream<List<CustomNotificationModel>> getCustomNotifications(String organization) {
    return _firestore
        .collection('CustomNotifications')
        .where('organization', isEqualTo: organization)
        .where('isActive', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => CustomNotificationModel.fromFirestore(doc)).toList();
    });
  }

  /// Send a test notification
  Future<List<String>> sendTestNotification(String organization) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // A Cloud Function (onTestNotificationCreated) sends the real FCM push the instant this
      // document is created — that's what actually reaches a backgrounded/closed app, unlike
      // the previous client-side "wait 2 minutes then poll" approach, which could only ever
      // fire while the app itself was still running.
      final now = DateTime.now();

      final testNotification = CustomNotificationModel(
        id: '',
        title: 'Test Notification',
        body: 'This is a test notification to verify the system is working correctly.',
        category: 'Test',
        component: 'System Test',
        intervention: 'Verify notification delivery',
        frequency: 1,
        lastInspectionDate: now,
        notificationDate: now,
        alertDate: now,
        nextInspectionDate: now,
        type: CustomNotificationType.test,
        createdAt: now,
        createdBy: user.uid,
        organization: organization,
      );

      final docRef = await _firestore.collection('CustomNotifications').add(testNotification.toMap());

      _logger.i('✅ Test notification created: ${docRef.id}');
      return [docRef.id];
    } catch (e) {
      _logger.e('💥 Error sending test notification: $e');
      rethrow;
    }
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId, String userId) async {
    try {
      final userDoc = await _firestore.collection('Users').doc(userId).get();
      final userName = userDoc.exists ? (userDoc.data() != null ? userDoc.data()!['name'] : 'Unknown User') : 'Unknown User';

      await _firestore.collection('CustomNotifications').doc(notificationId).update({
        'readByUsers': FieldValue.arrayUnion([
          {
            'userId': userId,
            'userName': userName,
            'readAt': Timestamp.now(),
          }
        ]),
      });

      _logger.i('✅ Custom notification marked as read: $notificationId by $userId');
    } catch (e) {
      _logger.e('💥 Error marking custom notification as read: $e');
      rethrow;
    }
  }

  /// Get notification statistics
  Future<Map<String, int>> getNotificationStats(String organization) async {
    try {
      final snapshot = await _firestore
          .collection('CustomNotifications')
          .where('organization', isEqualTo: organization)
          .where('isActive', isEqualTo: true)
          .get();

      int total = snapshot.docs.length;
      int triggered = 0;
      int pending = 0;
      int overdue = 0;

      for (final doc in snapshot.docs) {
        final notification = CustomNotificationModel.fromFirestore(doc);
        
        if (notification.isTriggered) {
          triggered++;
        } else if (notification.isOverdue) {
          overdue++;
        } else {
          pending++;
        }
      }

      return {
        'total': total,
        'triggered': triggered,
        'pending': pending,
        'overdue': overdue,
      };
    } catch (e) {
      _logger.e('💥 Error getting notification stats: $e');
      return {
        'total': 0,
        'triggered': 0,
        'pending': 0,
        'overdue': 0,
      };
    }
  }

  /// Dispose resources
  void dispose() {
    _systemTrayService.dispose();
    _logger.i('🗑️ CustomNotificationService disposed');
  }
}
