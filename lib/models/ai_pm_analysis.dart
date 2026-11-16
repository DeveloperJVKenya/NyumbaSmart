import 'package:cloud_firestore/cloud_firestore.dart';

enum AiPmVerificationStatus { draft, verified, published }

extension AiPmVerificationStatusX on AiPmVerificationStatus {
  String get value => name;
  static AiPmVerificationStatus fromString(String? v) {
    switch (v) {
      case 'verified':
        return AiPmVerificationStatus.verified;
      case 'published':
        return AiPmVerificationStatus.published;
      default:
        return AiPmVerificationStatus.draft;
    }
  }
}

/// One AI-generated PM analysis row for a single piece of equipment.
/// Stored at `facilities/{facilityId}/aiPmAnalysis/{itemId}`.
class AiPmAnalysisItem {
  final String id;
  final String facilityId;
  final String equipmentId;
  final String equipmentName;
  final String category;
  final String typeName;

  /// AI-generated values (immutable after creation).
  final int aiFrequencyMonths;
  final String aiReason;
  final List<String> aiTools;
  final double aiEstimatedHours;
  final List<String> aiSpares;

  /// Staff-edited overrides — null means use the AI value.
  final int? editedFrequencyMonths;
  final String? editedReason;
  final List<String>? editedTools;
  final double? editedEstimatedHours;
  final List<String>? editedSpares;
  final String? editedCategory;

  final bool aiGenerated;
  final AiPmVerificationStatus verificationStatus;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final DateTime? publishedAt;
  final DateTime createdAt;

  /// True when a user has manually excluded this equipment from PM scheduling.
  final bool excluded;

  AiPmAnalysisItem({
    required this.id,
    required this.facilityId,
    required this.equipmentId,
    required this.equipmentName,
    required this.category,
    required this.typeName,
    required this.aiFrequencyMonths,
    required this.aiReason,
    this.aiTools = const [],
    this.aiEstimatedHours = 1.0,
    this.aiSpares = const [],
    this.editedFrequencyMonths,
    this.editedReason,
    this.editedTools,
    this.editedEstimatedHours,
    this.editedSpares,
    this.editedCategory,
    this.aiGenerated = true,
    this.verificationStatus = AiPmVerificationStatus.draft,
    this.verifiedBy,
    this.verifiedAt,
    this.publishedAt,
    required this.createdAt,
    this.excluded = false,
  });

  int get frequencyMonths => editedFrequencyMonths ?? aiFrequencyMonths;
  String get reason => editedReason ?? aiReason;
  List<String> get tools => editedTools ?? aiTools;
  double get estimatedHours => editedEstimatedHours ?? aiEstimatedHours;
  List<String> get spares => editedSpares ?? aiSpares;
  String get effectiveCategory => editedCategory ?? category;

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'equipmentId': equipmentId,
        'equipmentName': equipmentName,
        'category': category,
        'typeName': typeName,
        'aiFrequencyMonths': aiFrequencyMonths,
        'aiReason': aiReason,
        'aiTools': aiTools,
        'aiEstimatedHours': aiEstimatedHours,
        'aiSpares': aiSpares,
        'editedFrequencyMonths': editedFrequencyMonths,
        'editedReason': editedReason,
        'editedTools': editedTools,
        'editedEstimatedHours': editedEstimatedHours,
        'editedSpares': editedSpares,
        'editedCategory': editedCategory,
        'aiGenerated': aiGenerated,
        'excluded': excluded,
        'verificationStatus': verificationStatus.value,
        'verifiedBy': verifiedBy,
        'verifiedAt': verifiedAt != null ? Timestamp.fromDate(verifiedAt!) : null,
        'publishedAt': publishedAt != null ? Timestamp.fromDate(publishedAt!) : null,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  factory AiPmAnalysisItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    List<String> strings(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    return AiPmAnalysisItem(
      id: doc.id,
      facilityId: d['facilityId'] as String? ?? '',
      equipmentId: d['equipmentId'] as String? ?? '',
      equipmentName: d['equipmentName'] as String? ?? '',
      category: d['category'] as String? ?? 'Unknown',
      typeName: d['typeName'] as String? ?? '',
      aiFrequencyMonths: (d['aiFrequencyMonths'] as num?)?.toInt() ?? 12,
      aiReason: d['aiReason'] as String? ?? '',
      aiTools: strings(d['aiTools']),
      aiEstimatedHours: (d['aiEstimatedHours'] as num?)?.toDouble() ?? 1.0,
      aiSpares: strings(d['aiSpares']),
      editedFrequencyMonths: (d['editedFrequencyMonths'] as num?)?.toInt(),
      editedReason: d['editedReason'] as String?,
      editedTools: d['editedTools'] != null ? strings(d['editedTools']) : null,
      editedEstimatedHours: (d['editedEstimatedHours'] as num?)?.toDouble(),
      editedSpares: d['editedSpares'] != null ? strings(d['editedSpares']) : null,
      editedCategory: d['editedCategory'] as String?,
      aiGenerated: d['aiGenerated'] as bool? ?? true,
      excluded: d['excluded'] as bool? ?? false,
      verificationStatus: AiPmVerificationStatusX.fromString(d['verificationStatus'] as String?),
      verifiedBy: d['verifiedBy'] as String?,
      verifiedAt: (d['verifiedAt'] as Timestamp?)?.toDate(),
      publishedAt: (d['publishedAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  AiPmAnalysisItem copyWith({
    int? editedFrequencyMonths,
    String? editedReason,
    List<String>? editedTools,
    double? editedEstimatedHours,
    List<String>? editedSpares,
    String? editedCategory,
    AiPmVerificationStatus? verificationStatus,
    String? verifiedBy,
    DateTime? verifiedAt,
    DateTime? publishedAt,
    bool? excluded,
  }) {
    return AiPmAnalysisItem(
      id: id,
      facilityId: facilityId,
      equipmentId: equipmentId,
      equipmentName: equipmentName,
      category: category,
      typeName: typeName,
      aiFrequencyMonths: aiFrequencyMonths,
      aiReason: aiReason,
      aiTools: aiTools,
      aiEstimatedHours: aiEstimatedHours,
      aiSpares: aiSpares,
      editedFrequencyMonths: editedFrequencyMonths ?? this.editedFrequencyMonths,
      editedReason: editedReason ?? this.editedReason,
      editedTools: editedTools ?? this.editedTools,
      editedEstimatedHours: editedEstimatedHours ?? this.editedEstimatedHours,
      editedSpares: editedSpares ?? this.editedSpares,
      editedCategory: editedCategory ?? this.editedCategory,
      aiGenerated: aiGenerated,
      excluded: excluded ?? this.excluded,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      verifiedAt: verifiedAt ?? this.verifiedAt,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt,
    );
  }
}

enum AiAnalysisStatus { idle, running, done, failed }

extension AiAnalysisStatusX on AiAnalysisStatus {
  String get value => name;
  static AiAnalysisStatus fromString(String? v) {
    switch (v) {
      case 'running':
        return AiAnalysisStatus.running;
      case 'done':
        return AiAnalysisStatus.done;
      case 'failed':
        return AiAnalysisStatus.failed;
      default:
        return AiAnalysisStatus.idle;
    }
  }
}

/// Meta-document at `facilities/{facilityId}/aiPmAnalysis/_meta`.
class AiPmAnalysisMeta {
  final AiAnalysisStatus status;
  final DateTime? triggeredAt;
  final DateTime? completedAt;
  final String? errorMessage;
  final int itemCount;
  final String facilityId;
  final String? publishedSowId;

  const AiPmAnalysisMeta({
    required this.status,
    this.triggeredAt,
    this.completedAt,
    this.errorMessage,
    this.itemCount = 0,
    required this.facilityId,
    this.publishedSowId,
  });

  Map<String, dynamic> toMap() => {
        'status': status.value,
        'triggeredAt': triggeredAt != null ? Timestamp.fromDate(triggeredAt!) : null,
        'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
        'errorMessage': errorMessage,
        'itemCount': itemCount,
        'facilityId': facilityId,
        'publishedSowId': publishedSowId,
      };

  factory AiPmAnalysisMeta.fromMap(Map<String, dynamic> d, String facilityId) {
    return AiPmAnalysisMeta(
      status: AiAnalysisStatusX.fromString(d['status'] as String?),
      triggeredAt: (d['triggeredAt'] as Timestamp?)?.toDate(),
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
      errorMessage: d['errorMessage'] as String?,
      itemCount: (d['itemCount'] as num?)?.toInt() ?? 0,
      facilityId: d['facilityId'] as String? ?? facilityId,
      publishedSowId: d['publishedSowId'] as String?,
    );
  }
}
