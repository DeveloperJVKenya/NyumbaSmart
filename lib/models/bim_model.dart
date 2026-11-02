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

  /// Site name from IfcSite or COBie Facility sheet.
  final String? siteName;

  /// Increments per upload for the same facility, so re-imports are traceable.
  final int revision;
  final BimImportStatus status;
  final String? errorMessage;
  final int? sizeBytes;

  // Filled in by the importer once it finishes.
  final int? spaceCount;
  final int? equipmentCount;
  final int? jobCount; // COBie Jobs imported as preventive maintenance tasks
  final int? systemCount;
  final int? contactCount;
  final int? sparesCount;
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
    this.siteName,
    required this.revision,
    required this.status,
    this.errorMessage,
    this.sizeBytes,
    this.spaceCount,
    this.equipmentCount,
    this.jobCount,
    this.systemCount,
    this.contactCount,
    this.sparesCount,
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
      siteName: data['siteName'] as String?,
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
      systemCount: data['systemCount'] as int?,
      contactCount: data['contactCount'] as int?,
      sparesCount: data['sparesCount'] as int?,
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
        if (siteName != null) 'siteName': siteName,
        'revision': revision,
        'status': status.name,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (spaceCount != null) 'spaceCount': spaceCount,
        if (equipmentCount != null) 'equipmentCount': equipmentCount,
        if (jobCount != null) 'jobCount': jobCount,
        if (systemCount != null) 'systemCount': systemCount,
        if (contactCount != null) 'contactCount': contactCount,
        if (sparesCount != null) 'sparesCount': sparesCount,
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

  /// Gross floor area in m² (from Qto_SpaceBaseQuantities or COBie Space.GrossArea).
  final double? grossArea;

  /// Space usage type (IFC IfcSpace.PredefinedType or COBie Space.UsageType).
  final String? usageType;

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
    this.grossArea,
    this.usageType,
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
      grossArea: (data['grossArea'] as num?)?.toDouble(),
      usageType: data['usageType'] as String?,
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
        if (grossArea != null) 'grossArea': grossArea,
        if (usageType != null) 'usageType': usageType,
      };
}

/// Firestore: facilities/{facilityId}/bimSystems/{systemId}
///
/// An MEP system (HVAC loop, electrical circuit, plumbing ring main, etc.).
/// Equipment assigned to the system has a matching [systemName] field.
class BimSystem {
  final String id;
  final String facilityId;
  final String name;

  /// IFC PredefinedType or COBie System.Category.
  final String? category;

  /// Doc ids of equipment documents in this system.
  final List<String> equipmentIds;
  final String? bimModelId;
  final DateTime createdAt;

  BimSystem({
    required this.id,
    required this.facilityId,
    required this.name,
    this.category,
    required this.equipmentIds,
    this.bimModelId,
    required this.createdAt,
  });

  factory BimSystem.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BimSystem(
      id: doc.id,
      facilityId: data['facilityId'] ?? '',
      name: data['name'] ?? '',
      category: data['category'] as String?,
      equipmentIds: (data['equipmentIds'] as List<dynamic>?)?.cast<String>() ?? const [],
      bimModelId: data['bimModelId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'name': name,
        if (category != null) 'category': category,
        'equipmentIds': equipmentIds,
        if (bimModelId != null) 'bimModelId': bimModelId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

/// Firestore: facilities/{facilityId}/bimContacts/{contactId}
///
/// Manufacturer, installer, contractor or emergency contact imported from COBie Contact sheet.
class BimContact {
  final String id;
  final String facilityId;
  final String name;
  final String? company;
  final String? email;
  final String? phone;

  /// Category: Manufacturer, Installer, Contractor, Operator, Supplier, etc.
  final String? category;
  final String? description;
  final String? bimModelId;
  final DateTime createdAt;

  BimContact({
    required this.id,
    required this.facilityId,
    required this.name,
    this.company,
    this.email,
    this.phone,
    this.category,
    this.description,
    this.bimModelId,
    required this.createdAt,
  });

  factory BimContact.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BimContact(
      id: doc.id,
      facilityId: data['facilityId'] ?? '',
      name: data['name'] ?? '',
      company: data['company'] as String?,
      email: data['email'] as String?,
      phone: data['phone'] as String?,
      category: data['category'] as String?,
      description: data['description'] as String?,
      bimModelId: data['bimModelId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'name': name,
        if (company != null) 'company': company,
        if (email != null) 'email': email,
        if (phone != null) 'phone': phone,
        if (category != null) 'category': category,
        if (description != null) 'description': description,
        if (bimModelId != null) 'bimModelId': bimModelId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

/// Firestore: facilities/{facilityId}/bimSpares/{spareId}
///
/// Spare part or resource from COBie Spare/Resource sheet.
class BimSpare {
  final String id;
  final String facilityId;
  final String name;

  /// COBie TypeName — links this spare to the equipment type it services.
  final String? typeName;
  final String? category;
  final String? partNumber;
  final String? supplier;
  final String? description;
  final int? setNumber;
  final String? bimModelId;
  final DateTime createdAt;

  BimSpare({
    required this.id,
    required this.facilityId,
    required this.name,
    this.typeName,
    this.category,
    this.partNumber,
    this.supplier,
    this.description,
    this.setNumber,
    this.bimModelId,
    required this.createdAt,
  });

  factory BimSpare.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return BimSpare(
      id: doc.id,
      facilityId: data['facilityId'] ?? '',
      name: data['name'] ?? '',
      typeName: data['typeName'] as String?,
      category: data['category'] as String?,
      partNumber: data['partNumber'] as String?,
      supplier: data['supplier'] as String?,
      description: data['description'] as String?,
      setNumber: data['setNumber'] as int?,
      bimModelId: data['bimModelId'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'facilityId': facilityId,
        'name': name,
        if (typeName != null) 'typeName': typeName,
        if (category != null) 'category': category,
        if (partNumber != null) 'partNumber': partNumber,
        if (supplier != null) 'supplier': supplier,
        if (description != null) 'description': description,
        if (setNumber != null) 'setNumber': setNumber,
        if (bimModelId != null) 'bimModelId': bimModelId,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
