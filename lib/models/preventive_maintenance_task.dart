import 'package:cloud_firestore/cloud_firestore.dart';

enum PmTaskOrigin { ocr, excel, manual, legacy, bim }

extension PmTaskOriginExtension on PmTaskOrigin {
  String get value => name;

  static PmTaskOrigin fromString(String? value) => switch (value) {
        'ocr' => PmTaskOrigin.ocr,
        'excel' => PmTaskOrigin.excel,
        'legacy' => PmTaskOrigin.legacy,
        'bim' => PmTaskOrigin.bim,
        _ => PmTaskOrigin.manual,
      };
}

enum PmTaskStatus { pending, due, inProgress, completed, overdue }

extension PmTaskStatusExtension on PmTaskStatus {
  String get value => switch (this) {
        PmTaskStatus.inProgress => 'in_progress',
        _ => name,
      };

  String get displayName => switch (this) {
        PmTaskStatus.pending => 'Pending',
        PmTaskStatus.due => 'Due',
        PmTaskStatus.inProgress => 'In Progress',
        PmTaskStatus.completed => 'Completed',
        PmTaskStatus.overdue => 'Overdue',
      };

  static PmTaskStatus fromString(String? value) => switch (value) {
        'due' => PmTaskStatus.due,
        'in_progress' => PmTaskStatus.inProgress,
        'completed' => PmTaskStatus.completed,
        'overdue' => PmTaskStatus.overdue,
        _ => PmTaskStatus.pending,
      };
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

  /// Firestore doc ID of the [Equipment] record this task was generated from.
  /// Set when [origin] == [PmTaskOrigin.bim]; null for all other origins.
  final String? equipmentId;

  /// Denormalised equipment name, stored so the task card can show it without
  /// a secondary Firestore read.
  final String? equipmentName;

  final List<String> toolsRequired;
  final double estimatedHours;
  final List<String> spares;

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
    this.equipmentId,
    this.equipmentName,
    this.toolsRequired = const [],
    this.estimatedHours = 0,
    this.spares = const [],
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
      if (equipmentId != null) 'equipmentId': equipmentId,
      if (equipmentName != null) 'equipmentName': equipmentName,
      if (toolsRequired.isNotEmpty) 'toolsRequired': toolsRequired,
      if (estimatedHours > 0) 'estimatedHours': estimatedHours,
      if (spares.isNotEmpty) 'spares': spares,
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
      equipmentId: data['equipmentId'] as String?,
      equipmentName: data['equipmentName'] as String?,
      toolsRequired: (data['toolsRequired'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      estimatedHours: (data['estimatedHours'] as num?)?.toDouble() ?? 0,
      spares: (data['spares'] as List?)?.map((e) => e.toString()).toList() ?? const [],
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
    String? equipmentId,
    String? equipmentName,
    List<String>? toolsRequired,
    double? estimatedHours,
    List<String>? spares,
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
      equipmentId: equipmentId ?? this.equipmentId,
      equipmentName: equipmentName ?? this.equipmentName,
      toolsRequired: toolsRequired ?? this.toolsRequired,
      estimatedHours: estimatedHours ?? this.estimatedHours,
      spares: spares ?? this.spares,
    );
  }
}
