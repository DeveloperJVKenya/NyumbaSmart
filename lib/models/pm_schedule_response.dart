import 'package:cloud_firestore/cloud_firestore.dart';

enum PmClientAction { pending, accepted, rescheduled }

extension PmClientActionX on PmClientAction {
  String get value => name;
  static PmClientAction fromString(String? v) {
    switch (v) {
      case 'accepted':
        return PmClientAction.accepted;
      case 'rescheduled':
        return PmClientAction.rescheduled;
      default:
        return PmClientAction.pending;
    }
  }
}

/// Client's response to a 5-day-advance PM notification.
/// Stored at `facilities/{facilityId}/pmScheduleResponses/{taskId}`.
class PmScheduleResponse {
  final String id; // == taskId
  final String facilityId;
  final String clientUid;
  final String taskId;
  final String equipmentName;
  final DateTime plannedDate;
  final PmClientAction clientAction;
  final DateTime? newDate; // set when rescheduled
  final DateTime? respondedAt;
  final DateTime? counterNotifiedAt;

  const PmScheduleResponse({
    required this.id,
    required this.facilityId,
    required this.clientUid,
    required this.taskId,
    required this.equipmentName,
    required this.plannedDate,
    this.clientAction = PmClientAction.pending,
    this.newDate,
    this.respondedAt,
    this.counterNotifiedAt,
  });

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'clientUid': clientUid,
        'taskId': taskId,
        'equipmentName': equipmentName,
        'plannedDate': Timestamp.fromDate(plannedDate),
        'clientAction': clientAction.value,
        'newDate': newDate != null ? Timestamp.fromDate(newDate!) : null,
        'respondedAt': respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
        'counterNotifiedAt': counterNotifiedAt != null ? Timestamp.fromDate(counterNotifiedAt!) : null,
      };

  factory PmScheduleResponse.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PmScheduleResponse(
      id: doc.id,
      facilityId: d['facilityId'] as String? ?? '',
      clientUid: d['clientUid'] as String? ?? '',
      taskId: d['taskId'] as String? ?? doc.id,
      equipmentName: d['equipmentName'] as String? ?? '',
      plannedDate: (d['plannedDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      clientAction: PmClientActionX.fromString(d['clientAction'] as String?),
      newDate: (d['newDate'] as Timestamp?)?.toDate(),
      respondedAt: (d['respondedAt'] as Timestamp?)?.toDate(),
      counterNotifiedAt: (d['counterNotifiedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// The effective working date — rescheduled date overrides the planned date.
  DateTime get effectiveDate => newDate ?? plannedDate;
}
