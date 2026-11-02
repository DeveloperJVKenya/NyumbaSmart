import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/models/equipment.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/services/bim/cobie_parser.dart';

class BimImportResult {
  final String modelId;
  final int spacesCreated;
  final int spacesUpdated;
  final int equipmentCreated;
  final int equipmentUpdated;
  final int jobsCreated;
  final int jobsUpdated;
  final int systemsWritten;
  final int contactsWritten;
  final int sparesWritten;

  BimImportResult({
    required this.modelId,
    required this.spacesCreated,
    required this.spacesUpdated,
    required this.equipmentCreated,
    required this.equipmentUpdated,
    required this.jobsCreated,
    required this.jobsUpdated,
    required this.systemsWritten,
    required this.contactsWritten,
    required this.sparesWritten,
  });
}

/// Writes a reviewed [CobiePreview] (from a COBie workbook or an IFC file) into Firestore:
///   facilities/{facilityId}/bimModels/{modelId}           one record per import
///   facilities/{facilityId}/spaces/{docId}                storeys + rooms
///   facilities/{facilityId}/equipment/{docId}             components
///   facilities/{facilityId}/bimSystems/{docId}            MEP systems
///   facilities/{facilityId}/bimContacts/{docId}           manufacturer/contractor contacts
///   facilities/{facilityId}/bimSpares/{docId}             spare parts
///   facilities/{facilityId}/preventive_maintenance/{docId} COBie Jobs
///
/// Re-import rules:
///  - Document ids are deterministic (see [bimDocId]), so a revised file updates the same documents.
///    IFC GlobalIds give the same id from COBie and IFC, so the two formats enrich one record.
///  - Existing documents only get the import-owned fields updated. Anything staff edited in the app
///    (status, notes, purchase price, maintenance history, attachments, a room they assigned) is left alone.
///  - Items that disappear from a newer file are NOT deleted. Removing assets should be a deliberate step.
class BimImportService {
  BimImportService({FirebaseFirestore? firestore, FirebaseStorage? storage})
      : _db = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;

  static const int _batchLimit = 400; // Firestore allows 500 writes per batch; keep headroom.

  Future<BimImportResult> commit({
    required String facilityId,
    required String fileName,
    required int? sizeBytes,
    required CobiePreview preview,
    required String userId,
    BimSourceType sourceType = BimSourceType.cobie,
    String? schemaVersion,
    String? siteName,
    Uint8List? sourceBytes,
    void Function(String stage, double fraction)? onProgress,
  }) async {
    final facility = _db.collection('facilities').doc(facilityId);
    final models = facility.collection('bimModels');
    final bimSource = sourceType.name; // 'cobie' | 'ifc', stored on equipment as bimSource

    final previous = await models.count().get();
    final modelRef = models.doc();
    final now = DateTime.now();

    // Upload first: if it fails nothing has been written yet, so the user can simply retry.
    var storagePath = '';
    if (sourceBytes != null) {
      final ext = fileName.contains('.') ? fileName.split('.').last.toLowerCase() : sourceType.name;
      storagePath = 'facilities/$facilityId/bim/${modelRef.id}/source.$ext';
      onProgress?.call('Uploading file to storage', 0.05);
      await _storage.ref(storagePath).putData(
            sourceBytes,
            SettableMetadata(
              contentType: ext == 'xlsx'
                  ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                  : 'application/octet-stream',
              customMetadata: {'originalName': fileName, 'uploadedBy': userId, 'facilityId': facilityId},
            ),
          );
      onProgress?.call('Uploading file to storage', 0.15);
    }

    onProgress?.call('Creating model record', 0.17);
    await modelRef.set(BimModel(
      id: modelRef.id,
      facilityId: facilityId,
      fileName: fileName,
      storagePath: storagePath,
      sourceType: sourceType,
      schemaVersion: schemaVersion,
      siteName: siteName,
      revision: (previous.count ?? 0) + 1,
      status: BimImportStatus.processing,
      sizeBytes: sizeBytes,
      uploadedBy: userId,
      uploadedAt: now,
    ).toMap());

    try {
      final writer = _BatchWriter(_db, _batchLimit);

      // ---- Spaces ----
      onProgress?.call('Analyzing existing records', 0.20);
      final existingSpaces = (await facility.collection('spaces').get()).docs.map((d) => d.id).toSet();
      final storeyIdByName = <String, String>{
        for (final s in preview.spaces.where((s) => s.isStorey)) s.name.toLowerCase(): s.docId,
      };

      onProgress?.call('Writing spaces (${preview.spaces.length})', 0.23);
      var spacesCreated = 0;
      var spacesUpdated = 0;
      for (final s in preview.spaces) {
        final ref = facility.collection('spaces').doc(s.docId);
        final parentId = s.isStorey ? null : (s.parentDocId ?? storeyIdByName[(s.floorName ?? '').toLowerCase()]);

        if (existingSpaces.contains(s.docId)) {
          await writer.update(ref, {
            'name': s.name,
            'description': s.description,
            'parentId': parentId,
            'elevation': s.elevation,
            'bimGlobalId': s.globalId,
            'bimModelId': modelRef.id,
            if (s.grossArea != null) 'grossArea': s.grossArea,
            if (s.usageType != null) 'usageType': s.usageType,
          });
          spacesUpdated++;
        } else {
          await writer.set(
            ref,
            BimSpace(
              id: s.docId,
              facilityId: facilityId,
              kind: s.isStorey ? BimSpaceKind.storey : BimSpaceKind.space,
              name: s.name,
              description: s.description,
              parentId: parentId,
              elevation: s.elevation,
              bimGlobalId: s.globalId,
              bimModelId: modelRef.id,
              createdAt: now,
              grossArea: s.grossArea,
              usageType: s.usageType,
            ).toMap(),
          );
          spacesCreated++;
        }
      }

      // ---- Equipment ----
      onProgress?.call('Writing equipment (${preview.equipment.length})', 0.40);
      final existingEquipment = (await facility
              .collection('equipment')
              .where('bimSource', whereIn: ['cobie', 'ifc'])
              .get())
          .docs
          .map((d) => d.id)
          .toSet();
      final spaceIdByName = <String, String>{
        for (final s in preview.spaces.where((s) => !s.isStorey)) s.name.toLowerCase(): s.docId,
      };

      var equipmentCreated = 0;
      var equipmentUpdated = 0;
      var equipIdx = 0;
      for (final e in preview.equipment) {
        equipIdx++;
        if (equipIdx == 1 || equipIdx % 200 == 0) {
          onProgress?.call(
            'Writing equipment ($equipIdx / ${preview.equipment.length})',
            0.42 + 0.33 * equipIdx / preview.equipment.length,
          );
        }
        final ref = facility.collection('equipment').doc(e.docId);
        final spaceId = e.spaceDocId ?? (e.spaceName == null ? null : spaceIdByName[e.spaceName!.toLowerCase()]);

        if (existingEquipment.contains(e.docId)) {
          final update = <String, dynamic>{
            'name': e.name,
            'type': e.type,
            'manufacturer': e.manufacturer,
            'modelNumber': e.modelNumber,
            'typeName': e.typeName.isEmpty ? null : e.typeName,
            'systemName': e.systemName,
            'classification': e.classification,
            'bimGlobalId': e.globalId,
            'bimModelId': modelRef.id,
            'bimSource': bimSource,
            'updatedAt': Timestamp.fromDate(now),
            'spaceId': ?spaceId,
            if (e.serialNumber.isNotEmpty) 'serialNumber': e.serialNumber,
            if (e.installationDate != null) 'installationDate': Timestamp.fromDate(e.installationDate!),
            if (e.warrantyStart != null) 'warrantyStartDate': Timestamp.fromDate(e.warrantyStart!),
            if (e.warrantyEnd != null) 'warrantyEndDate': Timestamp.fromDate(e.warrantyEnd!),
            if (e.expectedLifeYears != null) 'expectedLifeYears': e.expectedLifeYears,
          };
          await writer.update(ref, update);
          equipmentUpdated++;
        } else {
          await writer.set(
            ref,
            Equipment(
              id: e.docId,
              equipmentId: e.equipmentId,
              name: e.name,
              type: e.type,
              serialNumber: e.serialNumber,
              locationId: e.spaceName ?? '',
              purchasePrice: 0.0,
              warrantyMonths: e.warrantyMonths,
              status: 'Active',
              notes: e.notes,
              attachments: [],
              maintenanceHistory: [
                {
                  'action': 'Imported from ${sourceType == BimSourceType.ifc ? 'IFC' : 'COBie'}',
                  'timestamp': Timestamp.fromDate(now),
                  'notes': fileName,
                  'userId': userId,
                }
              ],
              createdAt: now,
              updatedAt: now,
              createdBy: userId,
              bimGlobalId: e.globalId,
              bimModelId: modelRef.id,
              bimSource: bimSource,
              spaceId: spaceId,
              manufacturer: e.manufacturer,
              modelNumber: e.modelNumber,
              typeName: e.typeName.isEmpty ? null : e.typeName,
              systemName: e.systemName,
              classification: e.classification,
              installationDate: e.installationDate,
              warrantyStartDate: e.warrantyStart,
              warrantyEndDate: e.warrantyEnd,
              expectedLifeYears: e.expectedLifeYears,
            ).toMap(),
          );
          equipmentCreated++;
        }
      }

      // ---- MEP Systems ----
      var systemsWritten = 0;
      if (preview.systems.isNotEmpty) {
        onProgress?.call('Writing MEP systems (${preview.systems.length})', 0.78);
        final existingSystems = (await facility.collection('bimSystems').get()).docs.map((d) => d.id).toSet();
        for (final sys in preview.systems) {
          final ref = facility.collection('bimSystems').doc(sys.docId);
          if (existingSystems.contains(sys.docId)) {
            await writer.update(ref, {
              'name': sys.name,
              if (sys.category != null) 'category': sys.category,
              'equipmentIds': sys.equipmentDocIds,
              'bimModelId': modelRef.id,
            });
          } else {
            await writer.set(
              ref,
              BimSystem(
                id: sys.docId,
                facilityId: facilityId,
                name: sys.name,
                category: sys.category,
                equipmentIds: sys.equipmentDocIds,
                bimModelId: modelRef.id,
                createdAt: now,
              ).toMap(),
            );
          }
          systemsWritten++;
        }
      }

      // ---- Contacts ----
      var contactsWritten = 0;
      if (preview.contacts.isNotEmpty) {
        onProgress?.call('Writing contacts (${preview.contacts.length})', 0.84);
        final existingContacts = (await facility.collection('bimContacts').get()).docs.map((d) => d.id).toSet();
        for (final c in preview.contacts) {
          final ref = facility.collection('bimContacts').doc(c.docId);
          if (existingContacts.contains(c.docId)) {
            await writer.update(ref, {
              'name': c.name,
              if (c.company != null) 'company': c.company,
              if (c.email != null) 'email': c.email,
              if (c.phone != null) 'phone': c.phone,
              if (c.category != null) 'category': c.category,
              if (c.description != null) 'description': c.description,
              'bimModelId': modelRef.id,
            });
          } else {
            await writer.set(
              ref,
              BimContact(
                id: c.docId,
                facilityId: facilityId,
                name: c.name,
                company: c.company,
                email: c.email,
                phone: c.phone,
                category: c.category,
                description: c.description,
                bimModelId: modelRef.id,
                createdAt: now,
              ).toMap(),
            );
          }
          contactsWritten++;
        }
      }

      // ---- Spares ----
      var sparesWritten = 0;
      if (preview.spares.isNotEmpty) {
        onProgress?.call('Writing spare parts (${preview.spares.length})', 0.90);
        final existingSpares = (await facility.collection('bimSpares').get()).docs.map((d) => d.id).toSet();
        for (final sp in preview.spares) {
          final ref = facility.collection('bimSpares').doc(sp.docId);
          if (existingSpares.contains(sp.docId)) {
            await writer.update(ref, {
              'name': sp.name,
              if (sp.typeName != null) 'typeName': sp.typeName,
              if (sp.category != null) 'category': sp.category,
              if (sp.partNumber != null) 'partNumber': sp.partNumber,
              if (sp.supplier != null) 'supplier': sp.supplier,
              if (sp.description != null) 'description': sp.description,
              if (sp.setNumber != null) 'setNumber': sp.setNumber,
              'bimModelId': modelRef.id,
            });
          } else {
            await writer.set(
              ref,
              BimSpare(
                id: sp.docId,
                facilityId: facilityId,
                name: sp.name,
                typeName: sp.typeName,
                category: sp.category,
                partNumber: sp.partNumber,
                supplier: sp.supplier,
                description: sp.description,
                setNumber: sp.setNumber,
                bimModelId: modelRef.id,
                createdAt: now,
              ).toMap(),
            );
          }
          sparesWritten++;
        }
      }

      // ---- Preventive maintenance tasks (COBie Jobs) ----
      var jobsCreated = 0;
      var jobsUpdated = 0;
      if (preview.jobs.isNotEmpty) {
        onProgress?.call('Writing maintenance jobs (${preview.jobs.length})', 0.94);
        final pmCol = facility.collection('preventive_maintenance');
        final existingJobs = (await pmCol.where('origin', isEqualTo: PmTaskOrigin.excel.value).get())
            .docs
            .map((d) => d.id)
            .toSet();

        for (final j in preview.jobs) {
          final ref = pmCol.doc(j.docId);
          if (existingJobs.contains(j.docId)) {
            await writer.update(ref, {
              'category': j.category,
              'component': j.component,
              'intervention': j.intervention,
              'frequencyMonths': j.frequencyMonths,
              'bimModelId': modelRef.id,
              'updatedAt': Timestamp.fromDate(now),
            });
            jobsUpdated++;
          } else {
            await writer.set(
              ref,
              {
                ...PreventiveMaintenanceTask(
                  id: j.docId,
                  facilityId: facilityId,
                  category: j.category,
                  component: j.component,
                  intervention: j.intervention,
                  frequencyMonths: j.frequencyMonths,
                  status: PmTaskStatus.pending,
                  origin: PmTaskOrigin.excel,
                  createdBy: userId,
                  createdAt: now,
                  updatedAt: now,
                  notes: j.notes,
                ).toMap(),
                'bimModelId': modelRef.id,
              },
            );
            jobsCreated++;
          }
        }
      }

      onProgress?.call('Finalizing', 0.97);
      await writer.flush();

      await modelRef.update({
        'status': BimImportStatus.ready.name,
        'spaceCount': preview.spaces.length,
        'equipmentCount': preview.equipment.length,
        'jobCount': preview.jobs.length,
        'systemCount': preview.systems.length,
        'contactCount': preview.contacts.length,
        'sparesCount': preview.spares.length,
        'processedAt': Timestamp.fromDate(DateTime.now()),
      });

      onProgress?.call('Complete', 1.0);
      return BimImportResult(
        modelId: modelRef.id,
        spacesCreated: spacesCreated,
        spacesUpdated: spacesUpdated,
        equipmentCreated: equipmentCreated,
        equipmentUpdated: equipmentUpdated,
        jobsCreated: jobsCreated,
        jobsUpdated: jobsUpdated,
        systemsWritten: systemsWritten,
        contactsWritten: contactsWritten,
        sparesWritten: sparesWritten,
      );
    } catch (e) {
      await modelRef.update({
        'status': BimImportStatus.failed.name,
        'errorMessage': e.toString(),
      });
      rethrow;
    }
  }
}

/// Collects writes and commits them in chunks under Firestore's 500-write batch limit.
class _BatchWriter {
  _BatchWriter(this._db, this._limit) : _batch = _db.batch();

  final FirebaseFirestore _db;
  final int _limit;
  WriteBatch _batch;
  int _count = 0;

  Future<void> set(DocumentReference ref, Map<String, dynamic> data) async {
    _batch.set(ref, data);
    await _tick();
  }

  Future<void> update(DocumentReference ref, Map<String, dynamic> data) async {
    _batch.update(ref, data);
    await _tick();
  }

  Future<void> _tick() async {
    _count++;
    if (_count >= _limit) await flush();
  }

  Future<void> flush() async {
    if (_count == 0) return;
    await _batch.commit();
    _batch = _db.batch();
    _count = 0;
  }
}
