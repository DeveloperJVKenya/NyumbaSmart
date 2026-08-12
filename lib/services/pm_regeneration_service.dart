import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/services/pm_scheduling_service.dart';

/// Bulk/per-facility regeneration of `facilities/{facilityId}/preventive_maintenance` due dates.
///
/// Shared by the Scope of Work screen's single-facility "replace document" flow and the System
/// Notifications screen's "Regenerate Notifications" bulk action — both need the exact same
/// behavior: re-anchor every task's due date to a real maintenance start date, walking forward on
/// each task's own frequency until landing on a date that isn't in the past, so a fresh
/// regeneration never retroactively marks anything overdue.
class PmRegenerationService {
  const PmRegenerationService._();

  /// Regenerates due dates for every task at `facilities/{facilityId}/preventive_maintenance`,
  /// anchored to [startDate]. Returns the number of tasks updated.
  static Future<int> regenerateFacilitySchedule({
    required String facilityId,
    required DateTime startDate,
  }) async {
    final tasksRef = FirebaseFirestore.instance
        .collection('facilities')
        .doc(facilityId)
        .collection('preventive_maintenance');
    final tasksSnapshot = await tasksRef.get();
    final now = DateTime.now();
    var updated = 0;

    for (final taskDoc in tasksSnapshot.docs) {
      final frequencyMonths = taskDoc.data()['frequencyMonths'] as int?;
      if (frequencyMonths == null || frequencyMonths <= 0) continue;

      final newDueDate = PmSchedulingService.nextOccurrenceFromAnchor(
        anchor: startDate,
        frequencyMonths: frequencyMonths,
        notBefore: now,
      );

      await taskDoc.reference.update({
        'dueDate': Timestamp.fromDate(newDueDate),
        'notifiedAt': FieldValue.delete(),
        'alertedAt': FieldValue.delete(),
        'updatedAt': Timestamp.fromDate(now),
      });
      updated += 1;
    }

    return updated;
  }

  /// Regenerates every facility's schedule in one pass. A facility whose Scope of Work document
  /// already recorded its own maintenance start date keeps using that date; [fallbackStartDate]
  /// is only used for facilities that haven't recorded one yet.
  static Future<int> regenerateAllFacilities({required DateTime fallbackStartDate}) async {
    final firestore = FirebaseFirestore.instance;
    final facilitiesSnapshot = await firestore.collection('Facilities').get();
    var totalUpdated = 0;

    for (final facilityDoc in facilitiesSnapshot.docs) {
      final facilityId = facilityDoc.id;

      final sowDoc = await firestore
          .collection('facilities')
          .doc(facilityId)
          .collection('scope_of_work_documents')
          .doc('current')
          .get();
      final storedStartDate = sowDoc.data()?['startDate'];
      final startDate = storedStartDate is Timestamp ? storedStartDate.toDate() : fallbackStartDate;

      totalUpdated += await regenerateFacilitySchedule(facilityId: facilityId, startDate: startDate);
    }

    return totalUpdated;
  }
}
