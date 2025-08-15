import 'package:cloud_firestore/cloud_firestore.dart';

enum SystemNotificationStatus { scheduled, triggered, read, expired }
enum SystemNotificationType { notification, alert }

class SystemNotificationModel {
  final String id;
  final String title;
  final String body;
  final DateTime notificationDate;
  final DateTime alertDate;
  final DateTime nextInspectionDate;
  final List<String> categories;
  final List<SystemNotificationTask> tasks;
  final SystemNotificationStatus status;
  final SystemNotificationType type;
  final bool isTriggered;
  final bool isActive;
  final DateTime? triggeredAt;
  final DateTime? expiryDate;
  final int sentCount;
  final int failedCount;
  final DateTime? lastSentAt;
  final List<SystemNotificationReadInfo> readByUsers;
  final DateTime createdAt;
  final String createdBy;
  final int retryCount;
  final DateTime? lastRetryAt;

  SystemNotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.notificationDate,
    required this.alertDate,
    required this.nextInspectionDate,
    required this.categories,
    required this.tasks,
    this.status = SystemNotificationStatus.scheduled,
    this.type = SystemNotificationType.notification,
    this.isTriggered = false,
    this.isActive = true,
    this.triggeredAt,
    this.expiryDate,
    this.sentCount = 0,
    this.failedCount = 0,
    this.lastSentAt,
    this.readByUsers = const [],
    required this.createdAt,
    required this.createdBy,
    this.retryCount = 0,
    this.lastRetryAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'notificationDate': Timestamp.fromDate(notificationDate),
      'alertDate': Timestamp.fromDate(alertDate),
      'nextInspectionDate': Timestamp.fromDate(nextInspectionDate),
      'categories': categories,
      'tasks': tasks.map((task) => task.toMap()).toList(),
      'taskCount': tasks.length,
      'status': status.name,
      'type': type.name,
      'isTriggered': isTriggered,
      'isActive': isActive,
      'triggeredAt': triggeredAt != null ? Timestamp.fromDate(triggeredAt!) : null,
      'expiryDate': expiryDate != null ? Timestamp.fromDate(expiryDate!) : null,
      'sentCount': sentCount,
      'failedCount': failedCount,
      'lastSentAt': lastSentAt != null ? Timestamp.fromDate(lastSentAt!) : null,
      'readByUsers': readByUsers.map((r) => r.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'retryCount': retryCount,
      'lastRetryAt': lastRetryAt != null ? Timestamp.fromDate(lastRetryAt!) : null,
    };
  }

  factory SystemNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final tasksList = data['tasks'] as List<dynamic>? ?? [];
    final readByUsersList = data['readByUsers'] as List<dynamic>? ?? [];

    return SystemNotificationModel(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      notificationDate: (data['notificationDate'] as Timestamp).toDate(),
      alertDate: (data['alertDate'] as Timestamp).toDate(),
      nextInspectionDate: (data['nextInspectionDate'] as Timestamp).toDate(),
      categories: List<String>.from(data['categories'] ?? []),
      tasks: tasksList.map((t) => SystemNotificationTask.fromMap(t as Map<String, dynamic>)).toList(),
      status: SystemNotificationStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => SystemNotificationStatus.scheduled,
      ),
      type: SystemNotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => SystemNotificationType.notification,
      ),
      isTriggered: data['isTriggered'] ?? false,
      isActive: data['isActive'] ?? true,
      triggeredAt: data['triggeredAt'] != null ? (data['triggeredAt'] as Timestamp).toDate() : null,
      expiryDate: data['expiryDate'] != null ? (data['expiryDate'] as Timestamp).toDate() : null,
      sentCount: data['sentCount'] ?? 0,
      failedCount: data['failedCount'] ?? 0,
      lastSentAt: data['lastSentAt'] != null ? (data['lastSentAt'] as Timestamp).toDate() : null,
      readByUsers: readByUsersList.map((r) => SystemNotificationReadInfo.fromMap(r as Map<String, dynamic>)).toList(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      createdBy: data['createdBy'] ?? '',
      retryCount: data['retryCount'] ?? 0,
      lastRetryAt: data['lastRetryAt'] != null ? (data['lastRetryAt'] as Timestamp).toDate() : null,
    );
  }

  bool get isRead => readByUsers.isNotEmpty;
  bool get isOverdue => DateTime.now().isAfter(nextInspectionDate) && !isTriggered;
  bool get isDueToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final notifDate = DateTime(notificationDate.year, notificationDate.month, notificationDate.day);
    return today.isAtSameMomentAs(notifDate);
  }
}

class SystemNotificationTask {
  final String category;
  final String component;
  final String intervention;
  final int frequency;
  final DateTime lastInspectionDate;

  SystemNotificationTask({
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequency,
    required this.lastInspectionDate,
  });

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'component': component,
      'intervention': intervention,
      'frequency': frequency,
      'lastInspectionDate': Timestamp.fromDate(lastInspectionDate),
    };
  }

  factory SystemNotificationTask.fromMap(Map<String, dynamic> map) {
    return SystemNotificationTask(
      category: map['category'] ?? '',
      component: map['component'] ?? '',
      intervention: map['intervention'] ?? '',
      frequency: map['frequency'] ?? 0,
      lastInspectionDate: (map['lastInspectionDate'] as Timestamp).toDate(),
    );
  }
}

class SystemNotificationReadInfo {
  final String userId;
  final String userName;
  final DateTime readAt;

  SystemNotificationReadInfo({
    required this.userId,
    required this.userName,
    required this.readAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'readAt': Timestamp.fromDate(readAt),
    };
  }

  factory SystemNotificationReadInfo.fromMap(Map<String, dynamic> map) {
    return SystemNotificationReadInfo(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Unknown User',
      readAt: (map['readAt'] as Timestamp).toDate(),
    );
  }
}
