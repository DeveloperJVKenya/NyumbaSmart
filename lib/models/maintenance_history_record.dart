import 'package:cloud_firestore/cloud_firestore.dart';

/// One completed maintenance action for a piece of equipment.
/// Stored at `facilities/{facilityId}/equipment/{equipmentId}/maintenanceHistory/{historyId}`.
/// Immutable after creation.
class MaintenanceHistoryRecord {
  final String id;
  final String facilityId;
  final String equipmentId;
  final String taskId;
  final DateTime scheduledDate;
  final DateTime actualDate;
  final String completedByUid;
  final String completedByName;
  final String notes;
  final bool clientApproved;
  final bool rescheduled;
  final DateTime? previousScheduledDate;
  final DateTime nextDueDate;
  final DateTime createdAt;

  const MaintenanceHistoryRecord({
    required this.id,
    required this.facilityId,
    required this.equipmentId,
    required this.taskId,
    required this.scheduledDate,
    required this.actualDate,
    required this.completedByUid,
    required this.completedByName,
    this.notes = '',
    this.clientApproved = false,
    this.rescheduled = false,
    this.previousScheduledDate,
    required this.nextDueDate,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'equipmentId': equipmentId,
        'taskId': taskId,
        'scheduledDate': Timestamp.fromDate(scheduledDate),
        'actualDate': Timestamp.fromDate(actualDate),
        'completedByUid': completedByUid,
        'completedByName': completedByName,
        'notes': notes,
        'clientApproved': clientApproved,
        'rescheduled': rescheduled,
        'previousScheduledDate': previousScheduledDate != null
            ? Timestamp.fromDate(previousScheduledDate!)
            : null,
        'nextDueDate': Timestamp.fromDate(nextDueDate),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory MaintenanceHistoryRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return MaintenanceHistoryRecord(
      id: doc.id,
      facilityId: d['facilityId'] as String? ?? '',
      equipmentId: d['equipmentId'] as String? ?? '',
      taskId: d['taskId'] as String? ?? '',
      scheduledDate: (d['scheduledDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      actualDate: (d['actualDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      completedByUid: d['completedByUid'] as String? ?? '',
      completedByName: d['completedByName'] as String? ?? '',
      notes: d['notes'] as String? ?? '',
      clientApproved: d['clientApproved'] as bool? ?? false,
      rescheduled: d['rescheduled'] as bool? ?? false,
      previousScheduledDate: (d['previousScheduledDate'] as Timestamp?)?.toDate(),
      nextDueDate: (d['nextDueDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}
