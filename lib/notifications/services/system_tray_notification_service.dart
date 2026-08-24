import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';

/// Thin wrapper around `flutter_local_notifications` for showing a system tray notification when
/// a digest push arrives in the foreground (background/closed-app delivery is handled by FCM +
/// the platform directly). Uses the same two channels — `maintenance_normal`/`maintenance_urgent`
/// — as the Cloud Functions' FCM payload and [NotificationService]'s local channel setup, so a
/// locally-shown notification never disagrees with what the push itself specified. All
/// notifications share one Android notification group so a re-trigger arriving before the
/// original digest is dismissed stacks cleanly instead of cluttering the tray.
class SystemTrayNotificationService {
  static final SystemTrayNotificationService _instance = SystemTrayNotificationService._internal();
  factory SystemTrayNotificationService() => _instance;
  SystemTrayNotificationService._internal();

  static const String _groupKey = 'maintenance_digest_group';
  static const int _summaryId = 0;

  final Logger _logger = Logger();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  /// [onTap] fires when the user taps a foreground-shown tray notification —
  /// previously nothing was wired up here at all, so those taps silently did
  /// nothing. Callers pass a navigation callback (see main.dart).
  Future<void> initialize({void Function()? onTap}) async {
    if (_isInitialized || kIsWeb) return;
    try {
      // See lib/main.dart's matching comment: this must be the monochrome ic_stat_notify
      // silhouette, not the launcher icon, or Android renders it as a gray blob.
      const androidSettings = AndroidInitializationSettings('ic_stat_notify');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: androidSettings, iOS: iosSettings),
        onDidReceiveNotificationResponse: (response) => onTap?.call(),
      );
      _isInitialized = true;
      _logger.i('SystemTrayNotificationService initialized');
    } catch (e) {
      _logger.e('Failed to initialize SystemTrayNotificationService: $e');
    }
  }

  Future<void> showDigestNotification({
    required int id,
    required String title,
    required String body,
    bool isUrgent = false,
  }) async {
    if (!_isInitialized || kIsWeb) return;

    try {
      final androidDetails = AndroidNotificationDetails(
        isUrgent ? 'maintenance_urgent' : 'maintenance_normal',
        isUrgent ? 'Urgent Maintenance Alerts' : 'Maintenance Notifications',
        channelDescription: isUrgent ? 'Urgent maintenance alerts requiring immediate attention' : 'Regular maintenance task reminders',
        importance: isUrgent ? Importance.max : Importance.high,
        priority: isUrgent ? Priority.max : Priority.high,
        groupKey: _groupKey,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      );
      const iosDetails = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true);

      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: androidDetails, iOS: iosDetails),
      );

      // A group summary is required on Android for individual notifications sharing a groupKey
      // to actually stack under one entry instead of appearing as separate tray items.
      final summaryDetails = AndroidNotificationDetails(
        isUrgent ? 'maintenance_urgent' : 'maintenance_normal',
        isUrgent ? 'Urgent Maintenance Alerts' : 'Maintenance Notifications',
        groupKey: _groupKey,
        setAsGroupSummary: true,
        importance: isUrgent ? Importance.max : Importance.high,
      );
      await _plugin.show(
        id: _summaryId,
        title: 'Maintenance Notifications',
        body: 'You have new maintenance notifications',
        notificationDetails: NotificationDetails(android: summaryDetails),
      );
    } catch (e) {
      _logger.e('Error showing system tray notification: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!_isInitialized || kIsWeb) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      _logger.e('Error cancelling notifications: $e');
    }
  }

  bool get isInitialized => _isInitialized;
}
