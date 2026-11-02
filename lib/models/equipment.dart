import 'package:cloud_firestore/cloud_firestore.dart';

class Equipment {
  final String id;
  final String equipmentId;
  final String name;
  final String type;
  final String serialNumber;
  final String locationId; // free-text today; kept as-is so existing screens keep working
  final double purchasePrice;
  final DateTime? purchaseDate;
  final int warrantyMonths;
  final String status;
  final String notes;
  final List<Map<String, String>> attachments;
  final List<Map<String, dynamic>> maintenanceHistory;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String createdBy;

  // --- BIM link fields (all optional: existing documents and call sites are unaffected) ---

  /// IFC GlobalId (22-char GUID). The key that ties this record to a model element.
  final String? bimGlobalId;

  /// BimModel document this record was imported from.
  final String? bimModelId;

  /// Where the record came from: 'manual' | 'ifc' | 'cobie'. Null on legacy records.
  final String? bimSource;

  /// Link to a BimSpace (storey/room) document. Sits beside the legacy free-text [locationId].
  final String? spaceId;

  // COBie Type / System fields.
  final String? manufacturer;
  final String? modelNumber;
  final String? typeName;
  final String? systemName;

  /// Uniclass / OmniClass / etc. code, when the client uses one.
  final String? classification;

  // --- Lifecycle dates (imported from IFC Psets or COBie Component/Type sheets) ---

  /// Date the asset was physically installed at the facility.
  final DateTime? installationDate;

  /// Date the manufacturer warranty started (often same as installationDate).
  final DateTime? warrantyStartDate;

  /// Date the manufacturer warranty expires.
  final DateTime? warrantyEndDate;

  /// Expected service life in years from the Type specification.
  final int? expectedLifeYears;

  Equipment({
    required this.id,
    required this.equipmentId,
    required this.name,
    required this.type,
    required this.serialNumber,
    required this.locationId,
    required this.purchasePrice,
    this.purchaseDate,
    required this.warrantyMonths,
    required this.status,
    required this.notes,
    required this.attachments,
    required this.maintenanceHistory,
    this.createdAt,
    this.updatedAt,
    required this.createdBy,
    this.bimGlobalId,
    this.bimModelId,
    this.bimSource,
    this.spaceId,
    this.manufacturer,
    this.modelNumber,
    this.typeName,
    this.systemName,
    this.classification,
    this.installationDate,
    this.warrantyStartDate,
    this.warrantyEndDate,
    this.expectedLifeYears,
  });

  bool get isBimLinked => bimGlobalId != null && bimGlobalId!.isNotEmpty;

  factory Equipment.fromSnapshot(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Equipment(
      id: doc.id,
      equipmentId: data['equipmentId'] ?? '',
      name: data['name'] ?? '',
      type: data['type'] ?? '',
      serialNumber: data['serialNumber'] ?? '',
      locationId: data['locationId'] ?? '',
      purchasePrice: (data['purchasePrice'] ?? 0.0).toDouble(),
      purchaseDate: (data['purchaseDate'] as Timestamp?)?.toDate(),
      warrantyMonths: data['warrantyMonths'] ?? 0,
      status: data['status'] ?? 'Active',
      notes: data['notes'] ?? '',
      attachments: (data['attachments'] as List<dynamic>?)
          ?.map((item) => Map<String, String>.from(item as Map))
          .toList() ?? [],
      maintenanceHistory: (data['maintenanceHistory'] as List<dynamic>?)
          ?.map((item) => Map<String, dynamic>.from(item as Map))
          .toList() ?? [],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
      createdBy: data['createdBy'] ?? '',
      bimGlobalId: data['bimGlobalId'] as String?,
      bimModelId: data['bimModelId'] as String?,
      bimSource: data['bimSource'] as String?,
      spaceId: data['spaceId'] as String?,
      manufacturer: data['manufacturer'] as String?,
      modelNumber: data['modelNumber'] as String?,
      typeName: data['typeName'] as String?,
      systemName: data['systemName'] as String?,
      classification: data['classification'] as String?,
      installationDate: (data['installationDate'] as Timestamp?)?.toDate(),
      warrantyStartDate: (data['warrantyStartDate'] as Timestamp?)?.toDate(),
      warrantyEndDate: (data['warrantyEndDate'] as Timestamp?)?.toDate(),
      expectedLifeYears: data['expectedLifeYears'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'equipmentId': equipmentId,
      'name': name,
      'type': type,
      'serialNumber': serialNumber,
      'locationId': locationId,
      'purchasePrice': purchasePrice,
      'purchaseDate': purchaseDate != null ? Timestamp.fromDate(purchaseDate!) : null,
      'warrantyMonths': warrantyMonths,
      'status': status,
      'notes': notes,
      'attachments': attachments,
      'maintenanceHistory': maintenanceHistory,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'createdBy': createdBy,
      // BIM fields are only written when set, so manual records stay unchanged.
      if (bimGlobalId != null) 'bimGlobalId': bimGlobalId,
      if (bimModelId != null) 'bimModelId': bimModelId,
      if (bimSource != null) 'bimSource': bimSource,
      if (spaceId != null) 'spaceId': spaceId,
      if (manufacturer != null) 'manufacturer': manufacturer,
      if (modelNumber != null) 'modelNumber': modelNumber,
      if (typeName != null) 'typeName': typeName,
      if (systemName != null) 'systemName': systemName,
      if (classification != null) 'classification': classification,
      if (installationDate != null) 'installationDate': Timestamp.fromDate(installationDate!),
      if (warrantyStartDate != null) 'warrantyStartDate': Timestamp.fromDate(warrantyStartDate!),
      if (warrantyEndDate != null) 'warrantyEndDate': Timestamp.fromDate(warrantyEndDate!),
      if (expectedLifeYears != null) 'expectedLifeYears': expectedLifeYears,
    };
  }
}
