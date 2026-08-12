import 'package:cloud_firestore/cloud_firestore.dart';

enum PmTaskOrigin { ocr, manual, legacy }

extension PmTaskOriginExtension on PmTaskOrigin {
  String get value => toString().split('.').last;

  static PmTaskOrigin fromString(String? value) {
    switch (value) {
      case 'ocr':
        return PmTaskOrigin.ocr;
      case 'legacy':
        return PmTaskOrigin.legacy;
      default:
        return PmTaskOrigin.manual;
    }
  }
}

enum PmTaskStatus { pending, due, inProgress, completed, overdue }

extension PmTaskStatusExtension on PmTaskStatus {
  String get value {
    switch (this) {
      case PmTaskStatus.pending:
        return 'pending';
      case PmTaskStatus.due:
        return 'due';
      case PmTaskStatus.inProgress:
        return 'in_progress';
      case PmTaskStatus.completed:
        return 'completed';
      case PmTaskStatus.overdue:
        return 'overdue';
    }
  }

  String get displayName {
    switch (this) {
      case PmTaskStatus.pending:
        return 'Pending';
      case PmTaskStatus.due:
        return 'Due';
      case PmTaskStatus.inProgress:
        return 'In Progress';
      case PmTaskStatus.completed:
        return 'Completed';
      case PmTaskStatus.overdue:
        return 'Overdue';
    }
  }

  static PmTaskStatus fromString(String? value) {
    switch (value) {
      case 'due':
        return PmTaskStatus.due;
      case 'in_progress':
        return PmTaskStatus.inProgress;
      case 'completed':
        return PmTaskStatus.completed;
      case 'overdue':
        return PmTaskStatus.overdue;
      default:
        return PmTaskStatus.pending;
    }
  }
}

/// A single preventive maintenance activity scheduled for a facility, stored at
/// `facilities/{facilityId}/preventive_maintenance/{taskId}`. Populated either by
/// OCR/parsing from an uploaded scope-of-work document, by manual entry, or by
/// backfill from the legacy global `Maintenance_Tasks`/`TaskProgress` collections.
class PreventiveMaintenanceTask {
  final String id;
  final String facilityId;
  final String category;
  final String component;
  final String intervention;
  final int frequencyMonths;
  final DateTime? dueDate;
  final PmTaskStatus status;
  final PmTaskOrigin origin;
  final String? sourceDocId;
  final DateTime? lastCompletedAt;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;
  final String? assignedTo;

  PreventiveMaintenanceTask({
    required this.id,
    required this.facilityId,
    required this.category,
    required this.component,
    required this.intervention,
    required this.frequencyMonths,
    this.dueDate,
    this.status = PmTaskStatus.pending,
    this.origin = PmTaskOrigin.manual,
    this.sourceDocId,
    this.lastCompletedAt,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.notes,
    this.assignedTo,
  });

  Map<String, dynamic> toMap() {
    return {
      'taskType': 'preventive_maintenance',
      'facilityId': facilityId,
      'category': category,
      'component': component,
      'intervention': intervention,
      'frequencyMonths': frequencyMonths,
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'status': status.value,
      'origin': origin.value,
      'sourceDocId': sourceDocId,
      'lastCompletedAt': lastCompletedAt != null ? Timestamp.fromDate(lastCompletedAt!) : null,
      'createdBy': createdBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'notes': notes,
      'assignedTo': assignedTo,
    };
  }

  factory PreventiveMaintenanceTask.fromFirestore(DocumentSnapshot doc, String facilityId) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PreventiveMaintenanceTask(
      id: doc.id,
      facilityId: data['facilityId'] ?? facilityId,
      category: data['category'] ?? '',
      component: data['component'] ?? '',
      intervention: data['intervention'] ?? '',
      frequencyMonths: data['frequencyMonths'] ?? 0,
      dueDate: data['dueDate'] != null ? (data['dueDate'] as Timestamp).toDate() : null,
      status: PmTaskStatusExtension.fromString(data['status']),
      origin: PmTaskOriginExtension.fromString(data['origin']),
      sourceDocId: data['sourceDocId'],
      lastCompletedAt:
          data['lastCompletedAt'] != null ? (data['lastCompletedAt'] as Timestamp).toDate() : null,
      createdBy: data['createdBy'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.now(),
      notes: data['notes'],
      assignedTo: data['assignedTo'],
    );
  }

  PreventiveMaintenanceTask copyWith({
    String? category,
    String? component,
    String? intervention,
    int? frequencyMonths,
    DateTime? dueDate,
    PmTaskStatus? status,
    DateTime? lastCompletedAt,
    DateTime? updatedAt,
    String? notes,
    String? assignedTo,
  }) {
    return PreventiveMaintenanceTask(
      id: id,
      facilityId: facilityId,
      category: category ?? this.category,
      component: component ?? this.component,
      intervention: intervention ?? this.intervention,
      frequencyMonths: frequencyMonths ?? this.frequencyMonths,
      dueDate: dueDate ?? this.dueDate,
      status: status ?? this.status,
      origin: origin,
      sourceDocId: sourceDocId,
      lastCompletedAt: lastCompletedAt ?? this.lastCompletedAt,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      notes: notes ?? this.notes,
      assignedTo: assignedTo ?? this.assignedTo,
    );
  }
}
