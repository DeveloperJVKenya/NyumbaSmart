import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore: facilities/{facilityId}/bimModels/{modelId}
/// Storage:   `facilities/{facilityId}/bim/{modelId}/source.<ext>`
///            facilities/{facilityId}/bim/{modelId}/derived/   (glTF/XKT, later steps)
///
/// One document per uploaded file/revision. Equipment and spaces point back here via bimModelId.
enum BimSourceType { ifc, cobie }

enum BimImportStatus { uploaded, processing, ready, failed }

class BimModel {
  final String id;
  final String facilityId;
  final String fileName;
  final String storagePath;
  final BimSourceType sourceType;

  /// 'IFC2X3' | 'IFC4' | 'IFC4X3' for IFC files; null for COBie spreadsheets.
  final String? schemaVersion;

  /// Increments per upload for the same facility, so re-imports are traceable.
  final int revision;
  final BimImportStatus status;
  final String? errorMessage;
  final int? sizeBytes;

  // Filled in by the importer once it finishes.
  final int? spaceCount;
  final int? equipmentCount;
  final int? jobCount; // COBie Jobs imported as preventive maintenance tasks
  final String? derivedGeometryPath; // later: .glb / .xkt for the viewer

  final String uploadedBy;
  final DateTime uploadedAt;
  final DateTime? processedAt;

  BimModel({
    required this.id,
    required this.facilityId,
    required this.fileName,
    required this.storagePath,
    required this.sourceType,
    this.schemaVersion,
    required this.revision,
    required this.status,
    this.errorMessage,
    this.sizeBytes,
    this.spaceCount,
    this.equipmentCount,
    this.jobCount,
    this.derivedGeometryPath,
    required this.uploadedBy,
    required this.uploadedAt,
    this.processedAt,
  });

  factory BimModel.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BimModel(
      id: doc.id,
      facilityId: data['facilityId'] ?? '',
      fileName: data['fileName'] ?? '',
      storagePath: data['storagePath'] ?? '',
      sourceType: BimSourceType.values.firstWhere(
        (e) => e.name == data['sourceType'],
        orElse: () => BimSourceType.ifc,
      ),
      schemaVersion: data['schemaVersion'] as String?,
      revision: data['revision'] ?? 1,
      status: BimImportStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => BimImportStatus.uploaded,
      ),
      errorMessage: data['errorMessage'] as String?,
      sizeBytes: data['sizeBytes'] as int?,
      spaceCount: data['spaceCount'] as int?,
      equipmentCount: data['equipmentCount'] as int?,
      jobCount: data['jobCount'] as int?,
      derivedGeometryPath: data['derivedGeometryPath'] as String?,
      uploadedBy: data['uploadedBy'] ?? '',
      uploadedAt: (data['uploadedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      processedAt: (data['processedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'fileName': fileName,
        'storagePath': storagePath,
        'sourceType': sourceType.name,
        if (schemaVersion != null) 'schemaVersion': schemaVersion,
        'revision': revision,
        'status': status.name,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (spaceCount != null) 'spaceCount': spaceCount,
        if (equipmentCount != null) 'equipmentCount': equipmentCount,
        if (jobCount != null) 'jobCount': jobCount,
        if (derivedGeometryPath != null) 'derivedGeometryPath': derivedGeometryPath,
        'uploadedBy': uploadedBy,
        'uploadedAt': Timestamp.fromDate(uploadedAt),
        if (processedAt != null) 'processedAt': Timestamp.fromDate(processedAt!),
      };
}

/// Firestore: facilities/{facilityId}/spaces/{spaceId}
///
/// Storeys and rooms. Maps to IFC IfcBuildingStorey / IfcSpace and to the COBie Floor / Space sheets.
/// Equipment.spaceId points here. [parentId] links a room to its storey.
enum BimSpaceKind { storey, space }

class BimSpace {
  final String id;
  final String facilityId;
  final BimSpaceKind kind;
  final String name; // COBie Floor/Space "Name" (the code people recognise)
  final String? description;
  final String? parentId; // storey for a space; null for a storey
  final double? elevation; // storeys only
  final String? bimGlobalId; // IFC GlobalId; null for COBie-only imports
  final String? bimModelId;
  final DateTime createdAt;

  BimSpace({
    required this.id,
    required this.facilityId,
    required this.kind,
    required this.name,
    this.description,
    this.parentId,
    this.elevation,
    this.bimGlobalId,
    this.bimModelId,
    required this.createdAt,
  });

  factory BimSpace.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BimSpace(
      id: doc.id,
      facilityId: data['facilityId'] ?? '',
      kind: BimSpaceKind.values.firstWhere(
        (e) => e.name == data['kind'],
        orElse: () => BimSpaceKind.space,
      ),
      name: data['name'] ?? '',
      description: data['description'] as String?,
      parentId: data['parentId'] as String?,
      elevation: (data['elevation'] as num?)?.toDouble(),
      bimGlobalId: data['bimGlobalId'] as String?,
      bimModelId: data['bimModelId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'kind': kind.name,
        'name': name,
        if (description != null) 'description': description,
        if (parentId != null) 'parentId': parentId,
        if (elevation != null) 'elevation': elevation,
        if (bimGlobalId != null) 'bimGlobalId': bimGlobalId,
        if (bimModelId != null) 'bimModelId': bimModelId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
