import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/models/equipment.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/services/pm_scheduling_service.dart';
import 'package:cmms/services/pm_template_library.dart';

/// One entry in the `pm_review_queue` subcollection — an equipment item whose
/// [typeName] had no known PM template, queued for the facility manager to
/// either accept (creating a custom PM task) or dismiss permanently.
class PmReviewItem {
  final String id; // == equipmentId (Firestore doc ID of the Equipment record)
  final String equipmentId;
  final String equipmentName;
  final String equipmentType; // typeName, e.g. 'Flow Terminal'
  final String equipmentCategory; // type, e.g. 'Mechanical'
  final String? bimGlobalId;
  final String status; // 'pending' | 'accepted' | 'dismissed'
  final DateTime createdAt;

  const PmReviewItem({
    required this.id,
    required this.equipmentId,
    required this.equipmentName,
    required this.equipmentType,
    required this.equipmentCategory,
    this.bimGlobalId,
    required this.status,
    required this.createdAt,
  });

  factory PmReviewItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PmReviewItem(
      id: doc.id,
      equipmentId: d['equipmentId'] as String? ?? doc.id,
      equipmentName: d['equipmentName'] as String? ?? '',
      equipmentType: d['equipmentType'] as String? ?? '',
      equipmentCategory: d['equipmentCategory'] as String? ?? '',
      bimGlobalId: d['bimGlobalId'] as String?,
      status: d['status'] as String? ?? 'pending',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'equipmentId': equipmentId,
        'equipmentName': equipmentName,
        'equipmentType': equipmentType,
        'equipmentCategory': equipmentCategory,
        if (bimGlobalId != null) 'bimGlobalId': bimGlobalId,
        'status': status,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

class PmGenerationResult {
  final int created;
  final int skipped; // already had tasks — not re-processed
  final int queued; // newly added to review queue
  final int alreadyQueued; // already in review queue — not duplicated

  const PmGenerationResult({
    required this.created,
    required this.skipped,
    required this.queued,
    required this.alreadyQueued,
  });

  int get total => created + skipped + queued + alreadyQueued;

  @override
  String toString() =>
      'Created $created tasks, skipped $skipped (already scheduled), '
      'queued $queued for review, $alreadyQueued already in review queue.';
}

class PmGenerationService {
  PmGenerationService._();

  static final _db = FirebaseFirestore.instance;

  /// Reads all BIM-linked equipment for [facilityId] and:
  /// - If the equipment's [typeName] has a known template → creates PM tasks
  ///   (one per template entry) unless that equipment already has tasks.
  /// - If [typeName] is unknown → adds to `pm_review_queue` for the user
  ///   to review, unless it was already queued or dismissed.
  ///
  /// Uses [userId] as `createdBy` on new PM task documents.
  static Future<PmGenerationResult> generate({
    required String facilityId,
    required String userId,
  }) async {
    final facility = _db.collection('facilities').doc(facilityId);

    // ── 1. Load all BIM-linked equipment ───────────────────────────────────
    // Use `bimSource` (equality whereIn) rather than `bimGlobalId isNull:false`
    // (a not-equal range query that can silently return 0 results without an
    // explicit index on the subcollection).
    final equipSnap = await facility
        .collection('equipment')
        .where('bimSource', whereIn: ['ifc', 'cobie'])
        .get();

    final allEquipment = equipSnap.docs
        .map(Equipment.fromSnapshot)
        .where((e) => e.bimGlobalId != null && e.bimGlobalId!.isNotEmpty)
        .toList();

    if (allEquipment.isEmpty) {
      return const PmGenerationResult(
          created: 0, skipped: 0, queued: 0, alreadyQueued: 0);
    }

    // ── 2. Find equipment that already has PM tasks (by equipmentId) ───────
    final pmSnap = await facility.collection('preventive_maintenance').get();
    final alreadyScheduledEquipmentIds = <String>{};
    for (final doc in pmSnap.docs) {
      final eid = doc.data()['equipmentId'] as String?;
      if (eid != null) alreadyScheduledEquipmentIds.add(eid);
    }

    // ── 3. Find items already in the review queue ──────────────────────────
    final reviewSnap = await facility.collection('pm_review_queue').get();
    final alreadyInQueue = <String>{
      for (final doc in reviewSnap.docs) doc.id,
    };

    // ── 4. Process each piece of equipment ────────────────────────────────
    final batch = _db.batch();
    int created = 0, skipped = 0, queued = 0, alreadyQueued = 0;
    final now = DateTime.now();

    for (final equipment in allEquipment) {
      final templates = PmTemplateLibrary.templatesFor(equipment.typeName);

      if (templates != null) {
        // Known type — generate PM tasks.
        if (alreadyScheduledEquipmentIds.contains(equipment.id)) {
          skipped++;
          continue;
        }
        for (final tpl in templates) {
          final dueDate = PmSchedulingService.nextUpcomingOccurrence(
            from: now,
            frequencyMonths: tpl.frequencyMonths,
          );
          final ref = facility.collection('preventive_maintenance').doc();
          batch.set(
            ref,
            PreventiveMaintenanceTask(
              id: ref.id,
              facilityId: facilityId,
              category: equipment.type, // e.g. 'HVAC', 'Electrical'
              component: equipment.name,
              intervention: tpl.intervention,
              frequencyMonths: tpl.frequencyMonths,
              dueDate: dueDate,
              status: PmTaskStatus.pending,
              origin: PmTaskOrigin.bim,
              lastCompletedAt: null,
              createdBy: userId,
              createdAt: now,
              updatedAt: now,
              equipmentId: equipment.id,
              equipmentName: equipment.name,
            ).toMap(),
          );
          created++;
        }
        // Mark so subsequent templates for the same equipment don't
        // also get the "already scheduled" skip.
        alreadyScheduledEquipmentIds.add(equipment.id);
      } else {
        // Unknown type — queue for review (unless already there).
        if (alreadyInQueue.contains(equipment.id)) {
          alreadyQueued++;
          continue;
        }
        // Only queue equipment whose typeName is non-trivially unknown
        // (skip entirely null/empty typeName — those are data quality issues).
        final typeName = equipment.typeName;
        if (typeName == null || typeName.isEmpty) continue;

        final ref =
            facility.collection('pm_review_queue').doc(equipment.id);
        batch.set(
          ref,
          PmReviewItem(
            id: equipment.id,
            equipmentId: equipment.id,
            equipmentName: equipment.name,
            equipmentType: typeName,
            equipmentCategory: equipment.type,
            bimGlobalId: equipment.bimGlobalId,
            status: 'pending',
            createdAt: now,
          ).toMap(),
        );
        alreadyInQueue.add(equipment.id);
        queued++;
      }
    }

    await batch.commit();

    return PmGenerationResult(
      created: created,
      skipped: skipped,
      queued: queued,
      alreadyQueued: alreadyQueued,
    );
  }

  /// Accept a review-queue item: creates one PM task from the user-supplied
  /// details and marks the queue item as accepted.
  static Future<void> acceptReviewItem({
    required String facilityId,
    required String userId,
    required PmReviewItem item,
    required String category,
    required String intervention,
    required int frequencyMonths,
    String? assignedTo,
    String? notes,
  }) async {
    final facility = _db.collection('facilities').doc(facilityId);
    final now = DateTime.now();
    final dueDate = PmSchedulingService.nextUpcomingOccurrence(
      from: now,
      frequencyMonths: frequencyMonths,
    );

    final batch = _db.batch();

    final taskRef = facility.collection('preventive_maintenance').doc();
    batch.set(
      taskRef,
      PreventiveMaintenanceTask(
        id: taskRef.id,
        facilityId: facilityId,
        category: category,
        component: item.equipmentName,
        intervention: intervention,
        frequencyMonths: frequencyMonths,
        dueDate: dueDate,
        status: PmTaskStatus.pending,
        origin: PmTaskOrigin.bim,
        lastCompletedAt: null,
        createdBy: userId,
        createdAt: now,
        updatedAt: now,
        notes: notes,
        assignedTo: assignedTo,
        equipmentId: item.equipmentId,
        equipmentName: item.equipmentName,
      ).toMap(),
    );

    batch.update(
      facility.collection('pm_review_queue').doc(item.id),
      {'status': 'accepted', 'updatedAt': Timestamp.fromDate(now)},
    );

    await batch.commit();
  }

  /// Dismiss a review-queue item — the equipment won't be queued again on
  /// subsequent generation runs because [generate] checks for existing entries.
  static Future<void> dismissReviewItem({
    required String facilityId,
    required String itemId,
  }) async {
    await _db
        .collection('facilities')
        .doc(facilityId)
        .collection('pm_review_queue')
        .doc(itemId)
        .update({
      'status': 'dismissed',
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Stream of pending review-queue items for [facilityId].
  static Stream<List<PmReviewItem>> reviewQueueStream(String facilityId) {
    return _db
        .collection('facilities')
        .doc(facilityId)
        .collection('pm_review_queue')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) =>
            snap.docs.map(PmReviewItem.fromFirestore).toList());
  }
}
