import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:logger/logger.dart';

class NotificationPersistenceService {
  static final NotificationPersistenceService _instance = NotificationPersistenceService._internal();
  factory NotificationPersistenceService() => _instance;
  NotificationPersistenceService._internal();

  final Logger _logger = Logger();
  SharedPreferences? _prefs;

  static const String _notificationsKey = 'persistent_notifications';
  static const String _unreadCountKey = 'unread_notification_count';

  /// Initialize the persistence service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _logger.i('✅ NotificationPersistenceService initialized');
    } catch (e) {
      _logger.e('💥 Failed to initialize NotificationPersistenceService: $e');
      rethrow;
    }
  }

  /// Store notification
  Future<void> storeNotification({
    required String id,
    required String title,
    required String body,
    required bool isUrgent,
    required Map<String, String> data,
    required DateTime timestamp,
  }) async {
    try {
      if (_prefs == null) await initialize();

      final notifications = await getStoredNotifications();
      
      final notification = PersistentNotification(
        id: id,
        title: title,
        body: body,
        isUrgent: isUrgent,
        data: data,
        timestamp: timestamp,
        isRead: false,
      );

      // Remove existing notification with same ID
      notifications.removeWhere((n) => n.id == id);
      
      // Add new notification
      notifications.add(notification);

      // Keep only last 50 notifications
      if (notifications.length > 50) {
        notifications.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        notifications.removeRange(50, notifications.length);
      }

      // Save to preferences
      final jsonList = notifications.map((n) => n.toJson()).toList();
      await _prefs!.setString(_notificationsKey, jsonEncode(jsonList));

      // Update unread count
      await _updateUnreadCount();

      _logger.i('💾 Notification stored: $title (ID: $id)');
    } catch (e) {
      _logger.e('❌ Error storing notification: $e');
    }
  }

  /// Get stored notifications
  Future<List<PersistentNotification>> getStoredNotifications() async {
    try {
      if (_prefs == null) await initialize();

      final jsonString = _prefs!.getString(_notificationsKey);
      if (jsonString == null) return [];

      final jsonList = jsonDecode(jsonString) as List;
      return jsonList.map((json) => PersistentNotification.fromJson(json)).toList();
    } catch (e) {
      _logger.e('❌ Error getting stored notifications: $e');
      return [];
    }
  }

  /// Mark notification as read
  Future<void> markAsRead(String id) async {
    try {
      final notifications = await getStoredNotifications();
      final index = notifications.indexWhere((n) => n.id == id);
      
      if (index != -1) {
        notifications[index] = notifications[index].copyWith(isRead: true);
        
        // Save updated notifications
        final jsonList = notifications.map((n) => n.toJson()).toList();
        await _prefs!.setString(_notificationsKey, jsonEncode(jsonList));

        // Update unread count
        await _updateUnreadCount();

        _logger.i('✅ Notification marked as read: $id');
      }
    } catch (e) {
      _logger.e('❌ Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    try {
      final notifications = await getStoredNotifications();
      final updatedNotifications = notifications.map((n) => n.copyWith(isRead: true)).toList();
      
      // Save updated notifications
      final jsonList = updatedNotifications.map((n) => n.toJson()).toList();
      await _prefs!.setString(_notificationsKey, jsonEncode(jsonList));

      // Update unread count
      await _updateUnreadCount();

      _logger.i('✅ All notifications marked as read');
    } catch (e) {
      _logger.e('❌ Error marking all notifications as read: $e');
    }
  }

  /// Get unread notifications
  Future<List<PersistentNotification>> getUnreadNotifications() async {
    final notifications = await getStoredNotifications();
    return notifications.where((n) => !n.isRead).toList();
  }

  /// Get unread count
  Future<int> getUnreadCount() async {
    final unreadNotifications = await getUnreadNotifications();
    return unreadNotifications.length;
  }

  /// Update unread count
  Future<void> _updateUnreadCount() async {
    final count = await getUnreadCount();
    await _prefs!.setInt(_unreadCountKey, count);
  }

  /// Clear old notifications (older than 30 days)
  Future<void> clearOldNotifications() async {
    try {
      final notifications = await getStoredNotifications();
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      
      final filteredNotifications = notifications
          .where((n) => n.timestamp.isAfter(cutoffDate))
          .toList();

      // Save filtered notifications
      final jsonList = filteredNotifications.map((n) => n.toJson()).toList();
      await _prefs!.setString(_notificationsKey, jsonEncode(jsonList));

      _logger.i('🧹 Cleared ${notifications.length - filteredNotifications.length} old notifications');
    } catch (e) {
      _logger.e('❌ Error clearing old notifications: $e');
    }
  }
}

class PersistentNotification {
  final String id;
  final String title;
  final String body;
  final bool isUrgent;
  final Map<String, String> data;
  final DateTime timestamp;
  final bool isRead;

  PersistentNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.isUrgent,
    required this.data,
    required this.timestamp,
    required this.isRead,
  });

  PersistentNotification copyWith({
    String? id,
    String? title,
    String? body,
    bool? isUrgent,
    Map<String, String>? data,
    DateTime? timestamp,
    bool? isRead,
  }) {
    return PersistentNotification(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      isUrgent: isUrgent ?? this.isUrgent,
      data: data ?? this.data,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'isUrgent': isUrgent,
      'data': data,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
    };
  }

  factory PersistentNotification.fromJson(Map<String, dynamic> json) {
    return PersistentNotification(
      id: json['id'],
      title: json['title'],
      body: json['body'],
      isUrgent: json['isUrgent'],
      data: Map<String, String>.from(json['data']),
      timestamp: DateTime.parse(json['timestamp']),
      isRead: json['isRead'],
    );
  }
}
