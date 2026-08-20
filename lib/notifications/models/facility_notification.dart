import 'package:cloud_firestore/cloud_firestore.dart';

/// An immutable audit record at `facilities/{facilityId}/notifications/{notificationId}` — either
/// system-generated (from a due/alert preventive-maintenance scan) or a manually authored custom
/// notification. Per-user delivery/read state lives separately in `NotificationDigests`; this is
/// purely the facility-level history of what was sent.
class FacilityNotification {
  final String id;
  final String facilityId;
  final String type; // 'system' | 'custom'
  final String category; // 'due' | 'alert' | 'manual'
  final String title;
  final String body;
  final List<String> taskIds;
  final bool isAlert;
  final String priority; // 'normal' | 'urgent'
  final DateTime createdAt;
  final String? createdBy;
  final int sentCount;
  final int failedCount;

  const FacilityNotification({
    required this.id,
    required this.facilityId,
    required this.type,
    required this.category,
    required this.title,
    required this.body,
    required this.taskIds,
    required this.isAlert,
    required this.priority,
    required this.createdAt,
    this.createdBy,
    this.sentCount = 0,
    this.failedCount = 0,
  });

  factory FacilityNotification.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, String facilityId) {
    final data = doc.data() ?? {};
    return FacilityNotification(
      id: doc.id,
      facilityId: data['facilityId'] ?? facilityId,
      type: data['type'] ?? 'system',
      category: data['category'] ?? (data['isAlert'] == true ? 'alert' : 'due'),
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      taskIds: List<String>.from(data['taskIds'] ?? const []),
      isAlert: data['isAlert'] ?? false,
      priority: data['priority'] ?? (data['isAlert'] == true ? 'urgent' : 'normal'),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'],
      sentCount: data['sentCount'] ?? 0,
      failedCount: data['failedCount'] ?? 0,
    );
  }

  Map<String, dynamic> toCreateMap() {
    return {
      'facilityId': facilityId,
      'type': type,
      'category': category,
      'title': title,
      'body': body,
      'taskIds': taskIds,
      'isAlert': isAlert,
      'priority': priority,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': createdBy,
      'sentCount': 0,
      'failedCount': 0,
      'digestId': null,
    };
  }
}
