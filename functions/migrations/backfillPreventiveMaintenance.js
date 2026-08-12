const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');

function mapProgressStatusToPmStatus(status) {
  switch (status) {
  case 'in_progress':
    return 'in_progress';
  case 'completed':
    return 'completed';
  default:
    return 'pending';
  }
}

async function resolveFacilityId(db, { facilityId, facilityName, organization }) {
  if (facilityId) {
    const snap = await db.collection('Facilities').doc(facilityId).get();
    if (!snap.exists) {
      throw new HttpsError('not-found', `Facility ${facilityId} not found`);
    }
    return snap.id;
  }
  if (!facilityName || !organization) {
    throw new HttpsError(
      'invalid-argument',
      'Provide either facilityId, or both facilityName and organization',
    );
  }
  const query = await db
    .collection('Facilities')
    .where('name', '==', facilityName)
    .where('organization', '==', organization)
    .limit(1)
    .get();
  if (query.empty) {
    throw new HttpsError(
      'not-found',
      `No facility named "${facilityName}" under organization "${organization}"`,
    );
  }
  return query.docs[0].id;
}

async function isCallerAuthorized(db, uid) {
  const [userDoc, developerDoc] = await Promise.all([
    db.collection('Users').doc(uid).get(),
    db.collection('Developers').doc(uid).get(),
  ]);
  if (developerDoc.exists) return true;
  return userDoc.exists && userDoc.data().role === 'Admin';
}

/**
 * One-time, idempotent backfill of the legacy global Maintenance_Tasks + TaskProgress
 * collections into a target facility's `facilities/{facilityId}/preventive_maintenance`
 * subcollection. Re-running is safe: task ids already recorded in
 * SystemSettings/migration_status.migratedTaskIds are skipped.
 *
 * Call with { dryRun: true } (or omit dryRun) to preview counts without writing.
 * Call with { dryRun: false, facilityId } or { dryRun: false, facilityName, organization }
 * to actually migrate.
 */
exports.migrateLegacyMaintenanceData = onCall(async (request) => {
  const db = getFirestore();
  const { auth, data } = request;

  if (!auth) {
    throw new HttpsError('unauthenticated', 'Must be signed in');
  }
  if (!(await isCallerAuthorized(db, auth.uid))) {
    throw new HttpsError('permission-denied', 'Only Developers/Admins can run this migration');
  }

  const dryRun = data.dryRun !== false;
  const facilityId = await resolveFacilityId(db, data);

  const manifestRef = db.collection('SystemSettings').doc('migration_status');
  const manifestSnap = await manifestRef.get();
  const migratedIds = new Set(
    manifestSnap.exists ? manifestSnap.data().migratedTaskIds || [] : [],
  );

  const [tasksSnap, progressSnap] = await Promise.all([
    db.collection('Maintenance_Tasks').get(),
    db.collection('TaskProgress').get(),
  ]);
  const progressByKey = new Map();
  progressSnap.forEach((doc) => progressByKey.set(doc.id, doc.data()));

  let migrated = 0;
  let skippedAlreadyMigrated = 0;
  let malformedSkipped = 0;
  const writes = [];

  tasksSnap.forEach((doc) => {
    const source = doc.data();
    const { category, component, intervention } = source;
    if (!category || !component || !intervention) {
      malformedSkipped += 1;
      return;
    }
    if (migratedIds.has(doc.id)) {
      skippedAlreadyMigrated += 1;
      return;
    }

    const progress = progressByKey.get(`${category}_${component}_${intervention}`);
    const now = Timestamp.now();
    const payload = {
      taskType: 'preventive_maintenance',
      facilityId,
      category,
      component,
      intervention,
      frequencyMonths: source.frequency || 0,
      dueDate: null,
      status: progress ? mapProgressStatusToPmStatus(progress.status) : 'pending',
      origin: 'legacy',
      sourceDocId: null,
      lastCompletedAt: progress && progress.completedAt ? progress.completedAt : null,
      createdBy: source.createdBy || 'migration',
      createdAt: source.createdAt || now,
      updatedAt: now,
      notes: (progress && progress.notes) || null,
      assignedTo: (progress && progress.assignedTo) || null,
    };

    if (!dryRun) {
      const targetRef = db
        .collection('facilities')
        .doc(facilityId)
        .collection('preventive_maintenance')
        .doc(doc.id);
      writes.push(targetRef.set(payload));
      migratedIds.add(doc.id);
    }
    migrated += 1;
  });

  if (!dryRun) {
    await Promise.all(writes);
    await manifestRef.set(
      {
        migratedTaskIds: Array.from(migratedIds),
        lastMigratedFacilityId: facilityId,
        lastRunAt: Timestamp.now(),
      },
      { merge: true },
    );
  }

  return {
    dryRun,
    facilityId,
    totalSourceTasks: tasksSnap.size,
    migrated,
    skippedAlreadyMigrated,
    malformedSkipped,
  };
});
