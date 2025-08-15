import 'package:cloud_firestore/cloud_firestore.dart';

enum CustomNotificationType {
  notification,
  alert,
  test,
}

enum CustomNotificationStatus {
  pending,
  triggered,
  read,
  failed,
  cancelled,
}

class ReadByUser {
  final String userId;
  final String userName;
  final DateTime readAt;

  ReadByUser({
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

  factory ReadByUser.fromMap(Map<String, dynamic> map) {
    return ReadByUser(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Unknown User',
      readAt: (map['readAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class CustomNotificationModel {
  final String id;
  final String title;
  final String body;
  final String category;
  final String component;
  final String intervention;
  final int frequency;
  final DateTime lastInspectionDate;
  final DateTime notificationDate;
  final DateTime alertDate;
  final DateTime nextInspectionDate;
  final DateTime createdAt;
  final String createdBy;
  final String organization;
  final CustomNotificationType type;
  final bool isActive;
  final bool isTriggered;
  final CustomNotificationStatus status;
  final int sentCount;
  final int failedCount;
  final int retryCount;
  final List<ReadByUser> readByUsers;
  final DateTime? triggeredAt;
  final DateTime? lastSentAt;
  final DateTime? updatedAt;
  final String? updatedBy;
  final String? lastError;
  final DateTime? lastErrorAt;

  CustomNotificationModel({
    required this.id,
    required this.title,
    required this.body,
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequency,
    required this.lastInspectionDate,
    required this.notificationDate,
    required this.alertDate,
    required this.nextInspectionDate,
    required this.createdAt,
    required this.createdBy,
    required this.organization,
    this.type = CustomNotificationType.notification,
    this.isActive = true,
    this.isTriggered = false,
    this.status = CustomNotificationStatus.pending,
    this.sentCount = 0,
    this.failedCount = 0,
    this.retryCount = 0,
    this.readByUsers = const [],
    this.triggeredAt,
    this.lastSentAt,
    this.updatedAt,
    this.updatedBy,
    this.lastError,
    this.lastErrorAt,
  });

  // Computed properties
  bool get isOverdue {
    final now = DateTime.now();
    return nextInspectionDate.isBefore(now) && !isTriggered;
  }

  bool get isDueToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDate = DateTime(nextInspectionDate.year, nextInspectionDate.month, nextInspectionDate.day);
    return dueDate.isAtSameMomentAs(today);
  }

  bool get isDueSoon {
    final now = DateTime.now();
    final daysDifference = nextInspectionDate.difference(now).inDays;
    return daysDifference <= 7 && daysDifference >= 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'body': body,
      'category': category,
      'component': component,
      'intervention': intervention,
      'frequency': frequency,
      'lastInspectionDate': Timestamp.fromDate(lastInspectionDate),
      'notificationDate': Timestamp.fromDate(notificationDate),
      'alertDate': Timestamp.fromDate(alertDate),
      'nextInspectionDate': Timestamp.fromDate(nextInspectionDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'organization': organization,
      'type': type.name,
      'isActive': isActive,
      'isTriggered': isTriggered,
      'status': status.name,
      'sentCount': sentCount,
      'failedCount': failedCount,
      'retryCount': retryCount,
      'readByUsers': readByUsers.map((user) => user.toMap()).toList(),
      'triggeredAt': triggeredAt != null ? Timestamp.fromDate(triggeredAt!) : null,
      'lastSentAt': lastSentAt != null ? Timestamp.fromDate(lastSentAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'updatedBy': updatedBy,
      'lastError': lastError,
      'lastErrorAt': lastErrorAt != null ? Timestamp.fromDate(lastErrorAt!) : null,
    };
  }

  factory CustomNotificationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return CustomNotificationModel(
      id: doc.id,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      category: data['category'] ?? '',
      component: data['component'] ?? '',
      intervention: data['intervention'] ?? '',
      frequency: data['frequency'] ?? 1,
      lastInspectionDate: (data['lastInspectionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notificationDate: (data['notificationDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      alertDate: (data['alertDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nextInspectionDate: (data['nextInspectionDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      organization: data['organization'] ?? '',
      type: CustomNotificationType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => CustomNotificationType.notification,
      ),
      isActive: data['isActive'] ?? true,
      isTriggered: data['isTriggered'] ?? false,
      status: CustomNotificationStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => CustomNotificationStatus.pending,
      ),
      sentCount: data['sentCount'] ?? 0,
      failedCount: data['failedCount'] ?? 0,
      retryCount: data['retryCount'] ?? 0,
      readByUsers: (data['readByUsers'] as List<dynamic>?)
          ?.map((user) => ReadByUser.fromMap(user as Map<String, dynamic>))
          .toList() ?? [],
      triggeredAt: (data['triggeredAt'] as Timestamp?)?.toDate(),
      lastSentAt: (data['lastSentAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      updatedBy: data['updatedBy'],
      lastError: data['lastError'],
      lastErrorAt: (data['lastErrorAt'] as Timestamp?)?.toDate(),
    );
  }

  CustomNotificationModel copyWith({
    String? id,
    String? title,
    String? body,
    String? category,
    String? component,
    String? intervention,
    int? frequency,
    DateTime? lastInspectionDate,
    DateTime? notificationDate,
    DateTime? alertDate,
    DateTime? nextInspectionDate,
    DateTime? createdAt,
    String? createdBy,
    String? organization,
    CustomNotificationType? type,
    bool? isActive,
    bool? isTriggered,
    CustomNotificationStatus? status,
    int? sentCount,
    int? failedCount,
    int? retryCount,
    List<ReadByUser>? readByUsers,
    DateTime? triggeredAt,
    DateTime? lastSentAt,
    DateTime? updatedAt,
    String? updatedBy,
    String? lastError,
    DateTime? lastErrorAt,
  }) {
    return CustomNotificationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      category: category ?? this.category,
      component: component ?? this.component,
      intervention: intervention ?? this.intervention,
      frequency: frequency ?? this.frequency,
      lastInspectionDate: lastInspectionDate ?? this.lastInspectionDate,
      notificationDate: notificationDate ?? this.notificationDate,
      alertDate: alertDate ?? this.alertDate,
      nextInspectionDate: nextInspectionDate ?? this.nextInspectionDate,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      organization: organization ?? this.organization,
      type: type ?? this.type,
      isActive: isActive ?? this.isActive,
      isTriggered: isTriggered ?? this.isTriggered,
      status: status ?? this.status,
      sentCount: sentCount ?? this.sentCount,
      failedCount: failedCount ?? this.failedCount,
      retryCount: retryCount ?? this.retryCount,
      readByUsers: readByUsers ?? this.readByUsers,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      lastSentAt: lastSentAt ?? this.lastSentAt,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      lastError: lastError ?? this.lastError,
      lastErrorAt: lastErrorAt ?? this.lastErrorAt,
    );
  }
}
