import 'package:cloud_firestore/cloud_firestore.dart';

/// One maintenance task rolled into a facility's contribution to a digest, stored inline in
/// [DigestFacilityGroup.items] — see `NotificationDigests/{userId}/items/{digestId}` in
/// functions/index.js for the server-side shape this mirrors.
class DigestTaskItem {
  final String taskId;
  final String category;
  final String component;
  final String intervention;
  final DateTime? dueDate;
  final bool isAlert;

  const DigestTaskItem({
    required this.taskId,
    required this.category,
    required this.component,
    required this.intervention,
    this.dueDate,
    required this.isAlert,
  });

  factory DigestTaskItem.fromMap(Map<String, dynamic> map) {
    final dueDateRaw = map['dueDate'];
    return DigestTaskItem(
      taskId: map['taskId'] ?? '',
      category: map['category'] ?? '',
      component: map['component'] ?? '',
      intervention: map['intervention'] ?? '',
      dueDate: dueDateRaw is Timestamp ? dueDateRaw.toDate() : null,
      isAlert: map['isAlert'] ?? false,
    );
  }
}

/// One facility's contribution to a digest — the expandable breakdown a grouped notification
/// ("6 notifications from 2 facilities") reveals per facility.
class DigestFacilityGroup {
  final String facilityId;
  final String facilityName;
  final int count;
  final List<DigestTaskItem> items;

  const DigestFacilityGroup({
    required this.facilityId,
    required this.facilityName,
    required this.count,
    required this.items,
  });

  factory DigestFacilityGroup.fromMap(Map<String, dynamic> map) {
    final rawItems = map['items'] as List<dynamic>? ?? [];
    return DigestFacilityGroup(
      facilityId: map['facilityId'] ?? '',
      facilityName: map['facilityName'] ?? 'Unknown facility',
      count: map['count'] ?? 0,
      items: rawItems.map((e) => DigestTaskItem.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }
}

enum DigestKind { dueDigest, alertDigest, retrigger, custom, test }

extension DigestKindExtension on DigestKind {
  static DigestKind fromString(String? value) {
    switch (value) {
      case 'alert_digest':
        return DigestKind.alertDigest;
      case 'retrigger':
        return DigestKind.retrigger;
      case 'custom':
        return DigestKind.custom;
      case 'test':
        return DigestKind.test;
      default:
        return DigestKind.dueDigest;
    }
  }
}

/// A single push actually sent to one user — the WhatsApp-style grouped digest unit, stored at
/// `NotificationDigests/{userId}/items/{digestId}`. This is the app's one source of truth for
/// "what did this user receive, and have they read it" — see functions/index.js's
/// `checkDueNotifications`/`onCustomNotificationCreated` for what writes these.
class DigestItem {
  final String id;
  final String userId;
  final String runId;
  final DateTime createdAt;
  final DigestKind kind;
  final String title;
  final String body;
  final int totalCount;
  final int facilityCount;
  final List<DigestFacilityGroup> facilities;
  final DateTime? readAt;
  final int reTriggerCount;

  const DigestItem({
    required this.id,
    required this.userId,
    required this.runId,
    required this.createdAt,
    required this.kind,
    required this.title,
    required this.body,
    required this.totalCount,
    required this.facilityCount,
    required this.facilities,
    this.readAt,
    this.reTriggerCount = 0,
  });

  bool get isRead => readAt != null;
  bool get isUrgent => kind == DigestKind.alertDigest || facilities.any((f) => f.items.any((i) => i.isAlert));

  factory DigestItem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawFacilities = data['facilities'] as List<dynamic>? ?? [];
    return DigestItem(
      id: doc.id,
      userId: data['userId'] ?? '',
      runId: data['runId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      kind: DigestKindExtension.fromString(data['kind']),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      totalCount: data['totalCount'] ?? 0,
      facilityCount: data['facilityCount'] ?? 0,
      facilities: rawFacilities.map((e) => DigestFacilityGroup.fromMap(Map<String, dynamic>.from(e))).toList(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
      reTriggerCount: data['reTriggerCount'] ?? 0,
    );
  }
}
