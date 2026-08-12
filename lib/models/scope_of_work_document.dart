import 'package:cloud_firestore/cloud_firestore.dart';

enum ScopeOfWorkSourceType { excel, pdf }

extension ScopeOfWorkSourceTypeExtension on ScopeOfWorkSourceType {
  String get value => this == ScopeOfWorkSourceType.excel ? 'excel' : 'pdf';

  static ScopeOfWorkSourceType fromString(String? value) =>
      value == 'pdf' ? ScopeOfWorkSourceType.pdf : ScopeOfWorkSourceType.excel;

  static ScopeOfWorkSourceType? fromFileName(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) return ScopeOfWorkSourceType.excel;
    if (lower.endsWith('.pdf')) return ScopeOfWorkSourceType.pdf;
    return null;
  }
}

enum ScopeOfWorkParseStatus { pending, parsed, confirmed, failed }

extension ScopeOfWorkParseStatusExtension on ScopeOfWorkParseStatus {
  String get value => toString().split('.').last;

  static ScopeOfWorkParseStatus fromString(String? value) {
    switch (value) {
      case 'parsed':
        return ScopeOfWorkParseStatus.parsed;
      case 'confirmed':
        return ScopeOfWorkParseStatus.confirmed;
      case 'failed':
        return ScopeOfWorkParseStatus.failed;
      default:
        return ScopeOfWorkParseStatus.pending;
    }
  }
}

/// An uploaded scope-of-work document for a facility, stored at
/// `facilities/{facilityId}/scope_of_work_documents/{docId}`. Excel uploads are parsed
/// directly; PDF uploads go through OCR. Either way, extracted activity rows land in the
/// `parsed_rows` subcollection for user review before becoming live PreventiveMaintenanceTasks.
class ScopeOfWorkDocument {
  final String id;
  final String facilityId;
  final String title;
  final String? category;
  final String fileName;
  final String downloadUrl;
  final DateTime uploadedAt;
  final String uploadedBy;
  final ScopeOfWorkSourceType sourceType;
  final ScopeOfWorkParseStatus parseStatus;
  final DateTime? startDate;
  final String? parseError;

  ScopeOfWorkDocument({
    required this.id,
    required this.facilityId,
    required this.title,
    this.category,
    required this.fileName,
    required this.downloadUrl,
    required this.uploadedAt,
    required this.uploadedBy,
    required this.sourceType,
    this.parseStatus = ScopeOfWorkParseStatus.pending,
    this.startDate,
    this.parseError,
  });

  Map<String, dynamic> toMap() {
    return {
      'facilityId': facilityId,
      'title': title,
      'category': category,
      'fileName': fileName,
      'downloadUrl': downloadUrl,
      'uploadedAt': Timestamp.fromDate(uploadedAt),
      'uploadedBy': uploadedBy,
      'sourceType': sourceType.value,
      'parseStatus': parseStatus.value,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'parseError': parseError,
    };
  }

  factory ScopeOfWorkDocument.fromFirestore(DocumentSnapshot doc, String facilityId) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ScopeOfWorkDocument(
      id: doc.id,
      facilityId: data['facilityId'] ?? facilityId,
      title: data['title'] ?? data['fileName'] ?? '',
      category: data['category'],
      fileName: data['fileName'] ?? '',
      downloadUrl: data['downloadUrl'] ?? '',
      uploadedAt: data['uploadedAt'] != null
          ? (data['uploadedAt'] as Timestamp).toDate()
          : DateTime.now(),
      uploadedBy: data['uploadedBy'] ?? '',
      sourceType: ScopeOfWorkSourceTypeExtension.fromString(data['sourceType']),
      parseStatus: ScopeOfWorkParseStatusExtension.fromString(data['parseStatus']),
      startDate: data['startDate'] != null ? (data['startDate'] as Timestamp).toDate() : null,
      parseError: data['parseError'],
    );
  }

  ScopeOfWorkDocument copyWith({
    ScopeOfWorkParseStatus? parseStatus,
    DateTime? startDate,
    String? parseError,
  }) {
    return ScopeOfWorkDocument(
      id: id,
      facilityId: facilityId,
      title: title,
      category: category,
      fileName: fileName,
      downloadUrl: downloadUrl,
      uploadedAt: uploadedAt,
      uploadedBy: uploadedBy,
      sourceType: sourceType,
      parseStatus: parseStatus ?? this.parseStatus,
      startDate: startDate ?? this.startDate,
      parseError: parseError ?? this.parseError,
    );
  }
}

/// A single candidate activity row extracted from a scope-of-work document, pending user
/// review, stored at `facilities/{facilityId}/scope_of_work_documents/{docId}/parsed_rows/{rowId}`.
class ScopeOfWorkParsedRow {
  final String id;
  final Map<String, dynamic> rawRow;
  final String? mappedCategory;
  final String? mappedComponent;
  final String? mappedIntervention;
  final int? mappedFrequencyMonths;
  final double confidence;
  final bool needsReview;
  final bool accepted;

  ScopeOfWorkParsedRow({
    required this.id,
    required this.rawRow,
    this.mappedCategory,
    this.mappedComponent,
    this.mappedIntervention,
    this.mappedFrequencyMonths,
    this.confidence = 0.0,
    this.needsReview = true,
    this.accepted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'rawRow': rawRow,
      'mappedCategory': mappedCategory,
      'mappedComponent': mappedComponent,
      'mappedIntervention': mappedIntervention,
      'mappedFrequencyMonths': mappedFrequencyMonths,
      'confidence': confidence,
      'needsReview': needsReview,
      'accepted': accepted,
    };
  }

  factory ScopeOfWorkParsedRow.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return ScopeOfWorkParsedRow(
      id: doc.id,
      rawRow: Map<String, dynamic>.from(data['rawRow'] ?? {}),
      mappedCategory: data['mappedCategory'],
      mappedComponent: data['mappedComponent'],
      mappedIntervention: data['mappedIntervention'],
      mappedFrequencyMonths: data['mappedFrequencyMonths'],
      confidence: (data['confidence'] ?? 0.0).toDouble(),
      needsReview: data['needsReview'] ?? true,
      accepted: data['accepted'] ?? false,
    );
  }

  ScopeOfWorkParsedRow copyWith({
    String? mappedCategory,
    String? mappedComponent,
    String? mappedIntervention,
    int? mappedFrequencyMonths,
    bool? accepted,
  }) {
    return ScopeOfWorkParsedRow(
      id: id,
      rawRow: rawRow,
      mappedCategory: mappedCategory ?? this.mappedCategory,
      mappedComponent: mappedComponent ?? this.mappedComponent,
      mappedIntervention: mappedIntervention ?? this.mappedIntervention,
      mappedFrequencyMonths: mappedFrequencyMonths ?? this.mappedFrequencyMonths,
      confidence: confidence,
      needsReview: needsReview,
      accepted: accepted ?? this.accepted,
    );
  }
}
