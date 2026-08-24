import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cmms/notifications/models/delivery_log.dart';
import 'package:cmms/notifications/models/digest_item.dart';
import 'package:cmms/notifications/models/engagement_stats.dart';
import 'package:cmms/notifications/models/facility_notification.dart';

/// Thin, singleton wrapper around the consolidated notifications pipeline: per-user digests
/// (`NotificationDigests/{userId}/items`) delivered and re-triggered entirely by the
/// `checkDueNotifications` Cloud Function, plus the facility-level audit trail
/// (`facilities/{facilityId}/notifications`). All due/alert detection, grouping, and re-trigger
/// logic lives server-side now — this class only registers the device for delivery (FCM token,
/// permissions, local channels) and reads/writes the per-user state a client is actually allowed
/// to touch (its own read receipts).
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  final Logger _logger = Logger();

  static const String _notificationEnabledKey = 'notifications_enabled';
  static const String _soundEnabledKey = 'notification_sound_enabled';
  static const String _vibrationEnabledKey = 'notification_vibration_enabled';
  static const String _screenWakeEnabledKey = 'notification_screen_wake_enabled';

  // The web push certificate key for this Firebase project — required to obtain an FCM token on
  // web (mobile/desktop don't need it).
  static const String _webVapidKey =
      'BJr44Q87YwuvqcYpKTyV_fMt3lvtUSHtOr60R2U5vpnLHx8YZLf84m8DqQB_YNoRt_v1CuYHzbnyUt9-z99TzS4';

  bool _isInitialized = false;

  /// Registers this device for push delivery: local notification channels, permissions, and an
  /// FCM token saved to the signed-in user's `Users` doc (which is what every Cloud Function send
  /// path reads to find recipients). Idempotent — many screens/widgets may call this on mount.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    await _createNotificationChannels();
    await _requestPermissions();
    await _registerFcmToken();

    _messaging.onTokenRefresh.listen((newToken) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      try {
        await _firestore.collection('Users').doc(user.uid).update({
          'fcmToken': newToken,
          'platform': kIsWeb ? 'web' : 'mobile',
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        _logger.e('Error updating refreshed FCM token: $e');
      }
    });

    // A user might sign in after initialize() already ran once this session (initialize() is
    // guarded to run only once) — catch that moment and register the token then too.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) _registerFcmToken();
    });
  }

  Future<void> _requestPermissions() async {
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true, provisional: false);
      if (!kIsWeb) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (e) {
      _logger.e('Error requesting notification permissions: $e');
    }
  }

  Future<void> _registerFcmToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final token = kIsWeb ? await _messaging.getToken(vapidKey: _webVapidKey) : await _messaging.getToken();
      if (token == null) return;

      await _firestore.collection('Users').doc(user.uid).set({
        'fcmToken': token,
        'platform': kIsWeb ? 'web' : 'mobile',
        'notificationsEnabled': await areNotificationsEnabled(),
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logger.e('Error registering FCM token: $e');
    }
  }

  /// Two Android channels — normal and urgent — matching exactly what the Cloud Functions'
  /// `android.notification.channelId` payload specifies, so a locally-shown notification (e.g.
  /// the system tray fallback) never disagrees with what FCM itself filed the push under.
  Future<void> _createNotificationChannels() async {
    if (kIsWeb) return;
    // See lib/main.dart's matching comment: this must be the monochrome ic_stat_notify
    // silhouette, not the launcher icon, or Android renders it as a gray blob.
    const androidSettings = AndroidInitializationSettings('ic_stat_notify');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifications.initialize(
      settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    const normalChannel = AndroidNotificationChannel(
      'maintenance_normal',
      'Maintenance Notifications',
      description: 'Regular maintenance task reminders',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    const urgentChannel = AndroidNotificationChannel(
      'maintenance_urgent',
      'Urgent Maintenance Alerts',
      description: 'Urgent maintenance alerts requiring immediate attention',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin.createNotificationChannel(normalChannel);
    await androidPlugin.createNotificationChannel(urgentChannel);
  }

  // ---- Digest reads/writes (NotificationDigests/{userId}/items) ----

  Stream<List<DigestItem>> watchDigests(String userId) {
    return _firestore
        .collection('NotificationDigests')
        .doc(userId)
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(DigestItem.fromFirestore).toList());
  }

  Stream<int> watchUnreadCount(String userId) {
    return _firestore
        .collection('NotificationDigests')
        .doc(userId)
        .collection('items')
        .where('readAt', isNull: true)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Future<void> markDigestRead(String userId, String digestId) async {
    try {
      await _firestore
          .collection('NotificationDigests')
          .doc(userId)
          .collection('items')
          .doc(digestId)
          .update({'readAt': FieldValue.serverTimestamp()});
    } catch (e) {
      _logger.e('Error marking digest $digestId as read: $e');
    }
  }

  // ---- Facility notification audit trail (facilities/{facilityId}/notifications) ----

  Stream<List<FacilityNotification>> watchFacilityNotifications(String facilityId) {
    return _firestore
        .collection('facilities')
        .doc(facilityId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snap) => snap.docs.map((d) => FacilityNotification.fromFirestore(d, facilityId)).toList());
  }

  /// Creates a facility-scoped custom notification. The `onCustomNotificationCreated` Cloud
  /// Function trigger fans this out to every JV Almacis user's digest and sends FCM immediately.
  Future<void> createCustomNotification({
    required String facilityId,
    required String title,
    required String body,
    String priority = 'normal',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final notification = FacilityNotification(
      id: '',
      facilityId: facilityId,
      type: 'custom',
      category: 'manual',
      title: title,
      body: body,
      taskIds: const [],
      isAlert: priority == 'urgent',
      priority: priority,
      createdAt: DateTime.now(),
      createdBy: user?.uid,
    );
    await _firestore
        .collection('facilities')
        .doc(facilityId)
        .collection('notifications')
        .add(notification.toCreateMap());
  }

  /// Sends a test push to the caller's own device(s) via the `sendTestNotification` Cloud
  /// Function — replaces the old client-side direct-FCM-HTTP path that bundled a service-account
  /// credential in the app.
  Future<Map<String, dynamic>> sendTestNotification() async {
    final callable = FirebaseFunctions.instance.httpsCallable('sendTestNotification');
    final result = await callable.call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  // ---- Delivery audit log (NotificationDeliveryLogs) — developer/admin only per Firestore rules ----

  /// Recent send-runs (test, digest, alert, custom, retrigger) with a per-recipient breakdown of
  /// who actually received the push versus who was skipped/failed and why. Firestore rules
  /// restrict reads to developer/admin accounts.
  Stream<List<DeliveryLog>> watchRecentDeliveryLogs({int limit = 30}) {
    return _firestore
        .collection('NotificationDeliveryLogs')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(DeliveryLog.fromFirestore).toList());
  }

  // ---- Delivery receipts (NotificationDeliveryReceipts) — proof a device actually got a push ----

  /// Called the moment this device actually receives a push (foreground `onMessage`, or the
  /// native background handler) — writes proof-of-receipt separate from the server's "FCM
  /// accepted it for delivery" record, so Delivery & Recipients can distinguish "sent" from
  /// "confirmed on device". No-op if the message carried no `runId` (e.g. a push from before this
  /// field existed) or no signed-in user.
  Future<void> markDelivered({required String? runId, String? platform}) async {
    if (runId == null || runId.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('NotificationDeliveryReceipts').doc('${runId}_${user.uid}').set({
        'runId': runId,
        'userId': user.uid,
        'platform': platform ?? (kIsWeb ? 'web' : 'mobile'),
        'deliveredAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logger.e('Error recording delivery receipt for runId $runId: $e');
    }
  }

  /// One-shot lookup for the Delivery & Recipients screen: did [userId]'s device actually
  /// confirm receipt of the push tied to [runId]? Returns null if no receipt exists yet (either
  /// still in flight to an offline/closed device, or genuinely never arrived).
  Future<DateTime?> fetchDeliveryReceipt({required String runId, required String userId}) async {
    final doc = await _firestore.collection('NotificationDeliveryReceipts').doc('${runId}_$userId').get();
    final data = doc.data();
    if (data == null) return null;
    final deliveredAt = data['deliveredAt'];
    return deliveredAt is Timestamp ? deliveredAt.toDate() : null;
  }

  // ---- Read/open engagement stats (NotificationEngagementStats) — developer/admin only ----

  /// The latest daily read/open engagement summary, written by the
  /// `aggregateNotificationEngagement` Cloud Function. Null before the function's first run, or
  /// if the doc doesn't exist yet for a fresh environment.
  Future<EngagementStats?> fetchEngagementStats() async {
    final doc = await _firestore.collection('NotificationEngagementStats').doc('latest').get();
    if (!doc.exists) return null;
    return EngagementStats.fromFirestore(doc);
  }

  // ---- Local preferences ----

  Future<bool> areNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationEnabledKey) ?? true;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationEnabledKey, enabled);

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await _firestore.collection('Users').doc(user.uid).update({
          'notificationsEnabled': enabled,
          'lastSettingsUpdate': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        _logger.e('Error updating notification settings in Firestore: $e');
      }
    }
    if (!enabled) await _localNotifications.cancelAll();
  }

  Future<bool> isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true;
  }

  Future<void> setSoundEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
  }

  Future<bool> isVibrationEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_vibrationEnabledKey) ?? true;
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_vibrationEnabledKey, enabled);
  }

  Future<bool> isScreenWakeEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_screenWakeEnabledKey) ?? true;
  }

  Future<void> setScreenWakeEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenWakeEnabledKey, enabled);
  }
}
