import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/utils/timezone_utils.dart';
import 'package:cmms/notifications/services/fcm_http_service.dart';
import 'package:cmms/notifications/services/notification_service.dart' show NotificationService;
import 'package:cmms/notifications/services/system_tray_notification_service.dart';
import 'package:cmms/notifications/models/system_notification_model.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';

class RealtimeNotificationMonitor {
  static final RealtimeNotificationMonitor _instance = RealtimeNotificationMonitor._internal();
  factory RealtimeNotificationMonitor() => _instance;
  RealtimeNotificationMonitor._internal();

  final Logger _logger = Logger();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FCMHttpService _fcmService = FCMHttpService();
  final SystemTrayNotificationService _systemTrayService = SystemTrayNotificationService();

  Timer? _monitoringTimer;
  StreamSubscription<QuerySnapshot>? _systemNotificationSubscription;
  StreamSubscription<QuerySnapshot>? _customNotificationSubscription;

  bool _isInitialized = false;
  bool _isMonitoring = false;
  String _userOrganization = '';

  // Both the 30s periodic timer and the realtime Firestore listener independently run the same
  // due-check logic, so a notification becoming due right as both happen to fire can otherwise
  // get triggered (and sent) twice. This tracks ids currently being processed so the second
  // caller skips instead of racing the first to the same Firestore update.
  final Set<String> _triggeringIds = {};

  /// Initialize the real-time monitor
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _logger.i('🚀 Initializing RealtimeNotificationMonitor...');

      // Get user organization
      await _getUserOrganization();

      // Initialize FCM service
      try {
        await _fcmService.initialize();
        _logger.i('✅ FCM service initialized for monitor');
      } catch (e) {
        _logger.w('⚠️ FCM service not available: $e');
      }

      // Initialize system tray service
      await _systemTrayService.initialize();
      _logger.i('✅ System tray service initialized');

      // Start monitoring
      await _startMonitoring();

      _isInitialized = true;
      _logger.i('🎉 RealtimeNotificationMonitor initialized successfully');
    } catch (e) {
      _logger.e('💥 Failed to initialize RealtimeNotificationMonitor: $e');
      rethrow;
    }
  }

  /// Get user organization
  Future<void> _getUserOrganization() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await _firestore.collection('Users').doc(user.uid).get();
        if (userDoc.exists) {
          _userOrganization = userDoc.data()?['organization'] ?? '';
          _logger.i('👤 User organization: $_userOrganization');
        }
      } catch (e) {
        _logger.e('❌ Error getting user organization: $e');
      }
    }
  }

  /// Start real-time monitoring
  Future<void> _startMonitoring() async {
    if (_isMonitoring) return;

    try {
      _logger.i('🔄 Starting real-time notification monitoring...');

      // Start periodic timer for date comparison (every 30 seconds)
      _monitoringTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _performDateComparison();
      });

      // Set up Firestore listeners
      _setupFirestoreListeners();

      _isMonitoring = true;
      _logger.i('✅ Real-time monitoring started');

      // Perform initial check
      await _performDateComparison();
    } catch (e) {
      _logger.e('💥 Error starting monitoring: $e');
    }
  }

  /// Set up Firestore listeners for real-time updates
  void _setupFirestoreListeners() {
    try {
      // System notifications are built from the maintenance-task catalog — JV Almacis is the
      // contractor who performs the on-site work across every client facility, so only their
      // staff need a live listener for these.
      if (_userOrganization == NotificationService.contractorOrganization) {
        _systemNotificationSubscription = _firestore
            .collection('SystemNotifications')
            .where('isActive', isEqualTo: true)
            .where('isTriggered', isEqualTo: false)
            .snapshots()
            .listen(
          (snapshot) {
            _logger.i('📡 System notifications update: ${snapshot.docs.length} active notifications');
            _handleSystemNotificationUpdates(snapshot);
          },
          onError: (error) {
            _logger.e('❌ System notification listener error: $error');
          },
        );
      }

      // Listen to custom notifications for user's organization. Test notifications are excluded —
      // they're one-shot, sent immediately by the onTestNotificationCreated Cloud Function the
      // instant a user presses "send test", and must never be re-picked-up by this recurring
      // due-date check (which otherwise replays any test doc still isTriggered:false on every
      // app launch and every 30s tick, since its notificationDate is permanently "now"/in the past).
      if (_userOrganization.isNotEmpty) {
        _customNotificationSubscription = _firestore
            .collection('CustomNotifications')
            .where('organization', isEqualTo: _userOrganization)
            .where('isActive', isEqualTo: true)
            .where('isTriggered', isEqualTo: false)
            .where('type', isNotEqualTo: 'test')
            .snapshots()
            .listen(
          (snapshot) {
            _logger.i('📡 Custom notifications update: ${snapshot.docs.length} active notifications for $_userOrganization');
            _handleCustomNotificationUpdates(snapshot);
          },
          onError: (error) {
            _logger.e('❌ Custom notification listener error: $error');
          },
        );
      }

      _logger.i('🎧 Firestore listeners set up successfully');
    } catch (e) {
      _logger.e('💥 Error setting up Firestore listeners: $e');
    }
  }

  /// Handle system notification updates
  void _handleSystemNotificationUpdates(QuerySnapshot snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
        final notification = SystemNotificationModel.fromFirestore(change.doc);
        _logger.i('🔔 System notification update: ${notification.id} - ${notification.title}');
        
        // Check if this notification should be triggered
        _checkAndTriggerSystemNotification(notification, change.doc);
      }
    }
  }

  /// Handle custom notification updates
  void _handleCustomNotificationUpdates(QuerySnapshot snapshot) {
    for (final change in snapshot.docChanges) {
      if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
        final notification = CustomNotificationModel.fromFirestore(change.doc);
        _logger.i('🔔 Custom notification update: ${notification.id} - ${notification.title}');
        
        // Check if this notification should be triggered
        _checkAndTriggerCustomNotification(notification, change.doc);
      }
    }
  }

  /// Perform date comparison with device local time
  Future<void> _performDateComparison() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      _logger.i('⏰ Performing date comparison at: ${now.toString()}');
      _logger.i('📅 Today (local): ${TimezoneUtils.formatForDisplay(today)}');

      // System notifications are for the contractor (JV Almacis) who does the on-site work.
      if (_userOrganization == NotificationService.contractorOrganization) {
        await _checkSystemNotifications(today);
      }

      // Check custom notifications
      if (_userOrganization.isNotEmpty) {
        await _checkCustomNotifications(today);
      }

    } catch (e) {
      _logger.e('💥 Error in date comparison: $e');
    }
  }

  /// Check system notifications for triggering
  Future<void> _checkSystemNotifications(DateTime today) async {
    try {
      final query = await _firestore
          .collection('SystemNotifications')
          .where('isActive', isEqualTo: true)
          .where('isTriggered', isEqualTo: false)
          .get();

      _logger.i('🔍 Checking ${query.docs.length} system notifications...');

      for (final doc in query.docs) {
        final notification = SystemNotificationModel.fromFirestore(doc);
        await _checkAndTriggerSystemNotification(notification, doc);
      }
    } catch (e) {
      _logger.e('❌ Error checking system notifications: $e');
    }
  }

  /// Check custom notifications for triggering
  Future<void> _checkCustomNotifications(DateTime today) async {
    try {
      final query = await _firestore
          .collection('CustomNotifications')
          .where('organization', isEqualTo: _userOrganization)
          .where('isActive', isEqualTo: true)
          .where('isTriggered', isEqualTo: false)
          .where('type', isNotEqualTo: 'test')
          .get();

      _logger.i('🔍 Checking ${query.docs.length} custom notifications for $_userOrganization...');

      for (final doc in query.docs) {
        final notification = CustomNotificationModel.fromFirestore(doc);
        await _checkAndTriggerCustomNotification(notification, doc);
      }
    } catch (e) {
      _logger.e('❌ Error checking custom notifications: $e');
    }
  }

  /// Check and trigger system notification if due
  Future<void> _checkAndTriggerSystemNotification(
    SystemNotificationModel notification,
    DocumentSnapshot doc,
  ) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      
      // Parse dates using TimezoneUtils
      final notificationDate = TimezoneUtils.parseFirestoreDate(data['notificationDate']);
      final alertDate = TimezoneUtils.parseFirestoreDate(data['alertDate']);

      if (notificationDate == null) {
        _logger.w('⚠️ Could not parse notification date for system notification ${doc.id}');
        return;
      }

      bool shouldTrigger = false;
      String triggerReason = '';

      // Check if notification date is due (today or past)
      if (TimezoneUtils.isDue(notificationDate)) {
        shouldTrigger = true;
        triggerReason = 'notification_due';
        _logger.i('📅 System notification ${doc.id} is due: ${TimezoneUtils.formatForDisplay(notificationDate)}');
      }
      // Check if alert date is due
      else if (alertDate != null && TimezoneUtils.isDue(alertDate)) {
        shouldTrigger = true;
        triggerReason = 'alert_due';
        _logger.i('🚨 System notification ${doc.id} alert is due: ${TimezoneUtils.formatForDisplay(alertDate)}');
      }

      if (shouldTrigger) {
        if (!_triggeringIds.add(doc.id)) return; // Already being processed by the other path.
        try {
          await _triggerSystemNotification(notification, doc, triggerReason);
        } finally {
          _triggeringIds.remove(doc.id);
        }
      }
    } catch (e) {
      _logger.e('💥 Error checking system notification ${doc.id}: $e');
    }
  }

  /// Check and trigger custom notification if due
  Future<void> _checkAndTriggerCustomNotification(
    CustomNotificationModel notification,
    DocumentSnapshot doc,
  ) async {
    try {
      final data = doc.data() as Map<String, dynamic>;
      
      // Parse dates using TimezoneUtils
      final notificationDate = TimezoneUtils.parseFirestoreDate(data['notificationDate']);
      final alertDate = TimezoneUtils.parseFirestoreDate(data['alertDate']);

      if (notificationDate == null) {
        _logger.w('⚠️ Could not parse notification date for custom notification ${doc.id}');
        return;
      }

      bool shouldTrigger = false;
      String triggerReason = '';

      // Check if notification date is due (today or past)
      if (TimezoneUtils.isDue(notificationDate)) {
        shouldTrigger = true;
        triggerReason = 'notification_due';
        _logger.i('📅 Custom notification ${doc.id} is due: ${TimezoneUtils.formatForDisplay(notificationDate)}');
      }
      // Check if alert date is due
      else if (alertDate != null && TimezoneUtils.isDue(alertDate)) {
        shouldTrigger = true;
        triggerReason = 'alert_due';
        _logger.i('🚨 Custom notification ${doc.id} alert is due: ${TimezoneUtils.formatForDisplay(alertDate)}');
      }

      if (shouldTrigger) {
        if (!_triggeringIds.add(doc.id)) return; // Already being processed by the other path.
        try {
          await _triggerCustomNotification(notification, doc, triggerReason);
        } finally {
          _triggeringIds.remove(doc.id);
        }
      }
    } catch (e) {
      _logger.e('💥 Error checking custom notification ${doc.id}: $e');
    }
  }

  /// Trigger system notification
  Future<void> _triggerSystemNotification(
    SystemNotificationModel notification,
    DocumentSnapshot doc,
    String reason,
  ) async {
    try {
      _logger.i('🔥 Triggering system notification ${doc.id} - Reason: $reason');

      // Update isTriggered field in Firestore
      await doc.reference.update({
        'isTriggered': true,
        'triggeredAt': FieldValue.serverTimestamp(),
        'status': 'triggered',
        'triggerReason': reason,
        'triggeredBy': 'system_monitor',
      });

      _logger.i('✅ System notification ${doc.id} marked as triggered in Firestore');

      // Get target users — the contractor (JV Almacis) who performs the on-site work.
      final targetUsers = await _getContractorUsers();
      
      if (targetUsers.isNotEmpty) {
        // Send FCM notification using the correct method
        await _fcmService.sendToMultipleUsers(
          title: notification.title,
          body: notification.body,
          userIds: targetUsers,
          notificationId: doc.id,
          priority: notification.type == SystemNotificationType.alert ? 'urgent' : 'normal',
          data: {
            'type': 'system',
            'notification_type': notification.type.name,
            'categories': notification.categories.join(','),
            'taskCount': notification.tasks.length.toString(),
            'notificationId': doc.id,
          },
        );

        // Show system tray notification
        await _systemTrayService.showSystemTrayNotification(
          id: doc.id.hashCode,
          title: notification.title,
          body: notification.body,
          isUrgent: notification.type == SystemNotificationType.alert,
          data: {'notificationId': doc.id, 'type': 'system'},
        );

        // Update sent count
        await doc.reference.update({
          'sentCount': targetUsers.length,
          'lastSentAt': FieldValue.serverTimestamp(),
        });

        _logger.i('📤 System notification sent to ${targetUsers.length} users');
      } else {
        _logger.w('⚠️ No notifiable users found for system notification');
      }
    } catch (e) {
      _logger.e('💥 Error triggering system notification ${doc.id}: $e');
      
      // Mark as failed
      try {
        await doc.reference.update({
          'status': 'failed',
          'lastError': e.toString(),
          'lastErrorAt': FieldValue.serverTimestamp(),
        });
      } catch (updateError) {
        _logger.e('Failed to update error status: $updateError');
      }
    }
  }

  /// Trigger custom notification
  Future<void> _triggerCustomNotification(
    CustomNotificationModel notification,
    DocumentSnapshot doc,
    String reason,
  ) async {
    try {
      _logger.i('🔥 Triggering custom notification ${doc.id} - Reason: $reason');

      // Update isTriggered field in Firestore
      await doc.reference.update({
        'isTriggered': true,
        'triggeredAt': FieldValue.serverTimestamp(),
        'status': 'triggered',
        'triggerReason': reason,
        'triggeredBy': 'system_monitor',
      });

      _logger.i('✅ Custom notification ${doc.id} marked as triggered in Firestore');

      // Get target users from organization
      final targetUsers = await _getOrganizationUsers(notification.organization);
      
      if (targetUsers.isNotEmpty) {
        // Send FCM notification using the correct method
        await _fcmService.sendToMultipleUsers(
          title: notification.title,
          body: notification.body,
          userIds: targetUsers,
          notificationId: doc.id,
          priority: notification.type == CustomNotificationType.alert ? 'urgent' : 'normal',
          data: {
            'type': 'custom',
            'notification_type': notification.type.name,
            'category': notification.category,
            'component': notification.component,
            'organization': notification.organization,
            'notificationId': doc.id,
          },
        );

        // Show system tray notification
        await _systemTrayService.showSystemTrayNotification(
          id: doc.id.hashCode,
          title: notification.title,
          body: notification.body,
          isUrgent: notification.type == CustomNotificationType.alert,
          data: {'notificationId': doc.id, 'type': 'custom'},
        );

        // Update sent count
        await doc.reference.update({
          'sentCount': targetUsers.length,
          'lastSentAt': FieldValue.serverTimestamp(),
        });

        _logger.i('📤 Custom notification sent to ${targetUsers.length} users in ${notification.organization}');
      } else {
        _logger.w('⚠️ No users found for organization: ${notification.organization}');
      }
    } catch (e) {
      _logger.e('💥 Error triggering custom notification ${doc.id}: $e');
      
      // Mark as failed
      try {
        await doc.reference.update({
          'status': 'failed',
          'lastError': e.toString(),
          'lastErrorAt': FieldValue.serverTimestamp(),
        });
      } catch (updateError) {
        _logger.e('Failed to update error status: $updateError');
      }
    }
  }

  /// Get JV Almacis (contractor) users — the team that acts on maintenance-task notifications.
  Future<List<String>> _getContractorUsers() async {
    try {
      final usersSnapshot = await _firestore
          .collection('Users')
          .where('organization', isEqualTo: NotificationService.contractorOrganization)
          .where('notificationsEnabled', isNotEqualTo: false)
          .get();

      final userIds = usersSnapshot.docs.map((doc) => doc.id).toList();
      _logger.i('👥 Found ${userIds.length} contractor users');
      return userIds;
    } catch (e) {
      _logger.e('❌ Error getting notifiable users: $e');
      return [];
    }
  }

  /// Get organization users
  Future<List<String>> _getOrganizationUsers(String organization) async {
    try {
      final usersSnapshot = await _firestore
          .collection('Users')
          .where('organization', isEqualTo: organization)
          .where('notificationsEnabled', isNotEqualTo: false)
          .get();

      final userIds = usersSnapshot.docs.map((doc) => doc.id).toList();
      _logger.i('👥 Found ${userIds.length} users in $organization');
      return userIds;
    } catch (e) {
      _logger.e('❌ Error getting users for $organization: $e');
      return [];
    }
  }

  /// Stop monitoring
  void stopMonitoring() {
    _logger.i('🛑 Stopping real-time notification monitoring...');
    
    _monitoringTimer?.cancel();
    _systemNotificationSubscription?.cancel();
    _customNotificationSubscription?.cancel();
    
    _isMonitoring = false;
    _logger.i('✅ Monitoring stopped');
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    _systemTrayService.dispose();
    _isInitialized = false;
    _logger.i('🗑️ RealtimeNotificationMonitor disposed');
  }

  /// Get monitoring status
  Map<String, dynamic> getStatus() {
    return {
      'isInitialized': _isInitialized,
      'isMonitoring': _isMonitoring,
      'userOrganization': _userOrganization,
      'hasSystemListener': _systemNotificationSubscription != null,
      'hasCustomListener': _customNotificationSubscription != null,
    };
  }
}
