import 'package:cloud_firestore/cloud_firestore.dart';

/// One recipient's outcome within a [DeliveryLog] — whether the push actually reached that
/// account's device, or why it didn't (no token on file, disabled, stale token, FCM error).
class DeliveryRecipient {
  final String userId;
  final String userName;
  final String? platform;
  final bool success;
  final String? error;

  const DeliveryRecipient({
    required this.userId,
    required this.userName,
    this.platform,
    required this.success,
    this.error,
  });

  factory DeliveryRecipient.fromMap(Map<String, dynamic> map) {
    return DeliveryRecipient(
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? 'Unknown User',
      platform: map['platform'],
      success: map['success'] ?? false,
      error: map['error'],
    );
  }
}

/// A single notification send-run's delivery audit record — `NotificationDeliveryLogs/{logId}`,
/// developer/admin-only. Answers "which accounts/devices actually received this?" for both test
/// pushes and real system/custom notifications, which the digest docs alone don't show (a digest
/// only exists for users it was written for, with no record of who was skipped or why).
class DeliveryLog {
  final String id;
  final String kind;
  final String title;
  final String body;
  final String runId;
  final DateTime createdAt;
  final int totalTargets;
  final int sentCount;
  final int failedCount;
  final List<DeliveryRecipient> recipients;

  const DeliveryLog({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.runId,
    required this.createdAt,
    required this.totalTargets,
    required this.sentCount,
    required this.failedCount,
    required this.recipients,
  });

  factory DeliveryLog.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final rawRecipients = data['recipients'] as List<dynamic>? ?? [];
    return DeliveryLog(
      id: doc.id,
      kind: data['kind'] ?? '',
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      runId: data['runId'] ?? '',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalTargets: data['totalTargets'] ?? 0,
      sentCount: data['sentCount'] ?? 0,
      failedCount: data['failedCount'] ?? 0,
      recipients: rawRecipients.map((e) => DeliveryRecipient.fromMap(Map<String, dynamic>.from(e))).toList(),
    );
  }
}
