const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// Set global options for all functions. 'region' must be a GCP region id, not a timezone
// (that was the bug here: 'Africa/Nairobi' broke the deploy upload URL for every function in
// this codebase). Each onSchedule() call below separately and correctly sets timeZone.
setGlobalOptions({ region: 'us-central1' });

// Send notification to multiple users (HTTPS Callable)
exports.sendSystemNotification = onCall(async (request) => { // Changed to request object
  const { data } = request; // Access data through request.data
  const context = request.auth; // Access auth through request.auth

  try {
    // Verify authentication
    if (!context) {
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }

    const {
      title, body, notificationId, targetUsers, priority = 'normal', data: notificationData = {},
    } = data;

    console.log(`Sending notification to ${targetUsers.length} users: ${title}`);

    // Get FCM tokens for target users - Process in parallel but limit concurrency
    const userTokens = [];
    const batchSize = 10; // Process users in smaller batches to avoid overwhelming Firestore

    for (let i = 0; i < targetUsers.length; i += batchSize) {
      const batch = targetUsers.slice(i, i + batchSize);
      const batchPromises = batch.map(async (userId) => {
        try {
          const userDoc = await db.collection('Users').doc(userId).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            // targetUsers is already an explicit, pre-scoped recipient list from the caller
            // (e.g. a facility's organization) — no additional organization gate belongs here;
            // it previously silently dropped every non-'JV Almacis' recipient regardless of
            // who was actually targeted.
            if (userData.fcmToken && userData.notificationsEnabled !== false) {
              return {
                userId,
                token: userData.fcmToken,
                userName: userData.name || userData.email || 'Unknown User',
              };
            }
          }
        } catch (error) {
          console.error(`Error getting token for user ${userId}:`, error);
        }
        return null;
      });

      const batchResults = await Promise.all(batchPromises);
      userTokens.push(...batchResults.filter((result) => result !== null));
    }

    if (userTokens.length === 0) {
      console.log('No valid FCM tokens found for target users');
      return { success: true, sentCount: 0, message: 'No valid recipients found' };
    }

    // FCM data payloads must be string-only key/value pairs — an array, number, or boolean
    // here (e.g. from an unvalidated client-supplied notificationData) fails validation for
    // the entire multicast send, for every recipient at once.
    const stringifiedData = Object.fromEntries(
      Object.entries({
        notificationId, priority, type: 'system', ...notificationData,
      })
        .filter(([, value]) => value !== undefined && value !== null)
        .map(([key, value]) => [key, Array.isArray(value) ? value.join(',') : String(value)]),
    );

    // Prepare FCM message
    const message = {
      notification: {
        title,
        body,
      },
      data: stringifiedData,
      android: {
        notification: {
          channelId: priority === 'urgent' ? 'maintenance_urgent' : 'maintenance_normal',
          priority: priority === 'urgent' ? 'high' : 'default',
          sound: 'default',
          vibrateTimingsMillis: priority === 'urgent' ? [0, 500, 200, 500] : [0, 200],
        },
        data: {
          click_action: 'FLUTTER_NOTIFICATION_CLICK',
        },
      },
      apns: {
        payload: {
          aps: {
            alert: {
              title,
              body,
            },
            sound: 'default',
            badge: 1,
          },
        },
      },
      webpush: {
        notification: {
          title,
          body,
          icon: '/icons/notification-icon.png',
          badge: '/icons/badge-icon.png',
          requireInteraction: priority === 'urgent',
        },
      },
    };

    // Send to all tokens in batches
    const fcmBatchSize = 500; // FCM limit
    const results = [];

    for (let i = 0; i < userTokens.length; i += fcmBatchSize) {
      const batch = userTokens.slice(i, i + fcmBatchSize);
      const tokens = batch.map((ut) => ut.token);

      try {
        const response = await messaging.sendEachForMulticast({
          ...message,
          tokens,
        });

        console.log(
          `Batch ${Math.floor(i / fcmBatchSize) + 1}: `
            + `${response.successCount}/${tokens.length} messages sent successfully`,
        );

        // Handle failed tokens
        if (response.failureCount > 0) {
          const failedTokens = [];
          response.responses.forEach((resp, idx) => {
            if (!resp.success) {
              const failedToken = batch[idx];
              failedTokens.push(failedToken);
              console.error(`Failed to send to ${failedToken.userName} (${failedToken.userId}):`, resp.error);

              // Remove invalid tokens
              if (
                resp.error
                && (resp.error.code === 'messaging/registration-token-not-registered'
                  || resp.error.code === 'messaging/invalid-registration-token')
              ) {
                db.collection('Users')
                  .doc(failedToken.userId)
                  .update({
                    fcmToken: FieldValue.delete(),
                  })
                  .catch((err) => console.error('Error removing invalid token:', err));
              }
            }
          });
        }

        results.push({
          batchIndex: Math.floor(i / fcmBatchSize) + 1,
          successCount: response.successCount,
          failureCount: response.failureCount,
          totalCount: tokens.length,
        });
      } catch (error) {
        console.error(`Error sending batch ${Math.floor(i / fcmBatchSize) + 1}:`, error);
        results.push({
          batchIndex: Math.floor(i / fcmBatchSize) + 1,
          successCount: 0,
          failureCount: tokens.length,
          totalCount: tokens.length,
          error: error.message,
        });
      }
    }

    const totalSent = results.reduce((sum, result) => sum + result.successCount, 0);
    const totalFailed = results.reduce((sum, result) => sum + result.failureCount, 0);

    // Update notification status in Firestore
    await db.collection('SystemNotifications').doc(notificationId).update({
      isTriggered: true,
      triggeredAt: FieldValue.serverTimestamp(),
      sentCount: totalSent,
      failedCount: totalFailed,
      lastSentAt: FieldValue.serverTimestamp(),
    });

    console.log(`Notification sent: ${totalSent} successful, ${totalFailed} failed`);

    return {
      success: true,
      sentCount: totalSent,
      failedCount: totalFailed,
      totalTargets: userTokens.length,
      results,
    };
  } catch (error) {
    console.error('Error in sendSystemNotification:', error);
    throw new HttpsError('internal', error.message);
  }
});

// Helper function to send notifications (internal use). Returns per-recipient results
// (not just aggregate counts) so callers can persist/display exactly which accounts and
// devices did or didn't receive a given send — including *why* a recipient was skipped
// (no token on file, notifications disabled, stale token, etc.), which the old aggregate-only
// return value threw away.
async function sendNotificationInternal(notificationData, targetUsers) {
  const {
    title, body, notificationId, priority = 'normal', data: extraData = {},
  } = notificationData;

  console.log(`Sending notification to ${targetUsers.length} users: ${title}`);

  // Look up every target user's token/eligibility (not just the ones that pan out) so we can
  // report a reason for every recipient, not only the successful ones.
  const recipientChecks = [];
  const batchSize = 10;

  for (let i = 0; i < targetUsers.length; i += batchSize) {
    const batch = targetUsers.slice(i, i + batchSize);
    const batchPromises = batch.map(async (userId) => {
      try {
        const userDoc = await db.collection('Users').doc(userId).get();
        if (!userDoc.exists) {
          return {
            userId, userName: 'Unknown User', token: null, platform: null, skipReason: 'user not found',
          };
        }
        const userData = userDoc.data();
        const userName = userData.name || userData.email || 'Unknown User';
        const platform = userData.platform || null;
        if (!userData.fcmToken) {
          return {
            userId, userName, token: null, platform, skipReason: 'no FCM token on file',
          };
        }
        if (userData.notificationsEnabled === false) {
          return {
            userId, userName, token: null, platform, skipReason: 'notifications disabled',
          };
        }
        return {
          userId, userName, token: userData.fcmToken, platform, skipReason: null,
        };
      } catch (error) {
        console.error(`Error getting token for user ${userId}:`, error);
        return {
          userId, userName: 'Unknown User', token: null, platform: null, skipReason: error.message,
        };
      }
    });

    recipientChecks.push(...await Promise.all(batchPromises));
  }

  const userTokens = recipientChecks.filter((r) => r.token);
  const recipients = recipientChecks.map((r) => ({
    userId: r.userId,
    userName: r.userName,
    platform: r.platform,
    success: false,
    error: r.skipReason,
  }));
  const recipientByUserId = new Map(recipients.map((r) => [r.userId, r]));

  if (userTokens.length === 0) {
    console.log('No valid FCM tokens found for target users');
    return {
      success: true, sentCount: 0, failedCount: 0, totalTargets: targetUsers.length, recipients,
    };
  }

  // FCM data payloads must be string-only key/value pairs — an array, number, or boolean here
  // fails validation for the entire multicast send (every recipient, not just that field),
  // which is exactly what silently zeroed out delivery for checkDueNotifications before this
  // guard existed. Coercing defensively here means no future caller can reintroduce that bug.
  const stringifiedData = Object.fromEntries(
    Object.entries({
      notificationId, priority, type: 'system', ...extraData,
    })
      .filter(([, value]) => value !== undefined && value !== null)
      .map(([key, value]) => [key, Array.isArray(value) ? value.join(',') : String(value)]),
  );

  // Prepare FCM message
  const message = {
    notification: {
      title,
      body,
    },
    data: stringifiedData,
    android: {
      notification: {
        channelId: priority === 'urgent' ? 'maintenance_urgent' : 'maintenance_normal',
        priority: priority === 'urgent' ? 'high' : 'default',
        sound: 'default',
        vibrateTimingsMillis: priority === 'urgent' ? [0, 500, 200, 500] : [0, 200],
      },
      data: {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
    apns: {
      payload: {
        aps: {
          alert: {
            title,
            body,
          },
          sound: 'default',
          badge: 1,
        },
      },
    },
  };

  // Send notifications
  const fcmBatchSize = 500;
  let totalSent = 0;
  let totalFailed = 0;

  for (let i = 0; i < userTokens.length; i += fcmBatchSize) {
    const batch = userTokens.slice(i, i + fcmBatchSize);
    const tokens = batch.map((ut) => ut.token);

    try {
      const response = await messaging.sendEachForMulticast({
        ...message,
        tokens,
      });

      totalSent += response.successCount;
      totalFailed += response.failureCount;

      console.log(
        `Batch ${Math.floor(i / fcmBatchSize) + 1}: `
          + `${response.successCount}/${tokens.length} messages sent successfully`,
      );

      response.responses.forEach((resp, idx) => {
        const sentTo = batch[idx];
        const rec = recipientByUserId.get(sentTo.userId);
        if (resp.success) {
          if (rec) rec.success = true;
          return;
        }
        console.error(`Failed to send to ${sentTo.userName} (${sentTo.userId}):`, resp.error);
        if (rec) rec.error = resp.error ? resp.error.message : 'unknown error';
        if (
          resp.error
          && (resp.error.code === 'messaging/registration-token-not-registered'
            || resp.error.code === 'messaging/invalid-registration-token')
        ) {
          db.collection('Users')
            .doc(sentTo.userId)
            .update({ fcmToken: FieldValue.delete() })
            .catch((err) => console.error('Error removing invalid token:', err));
        }
      });
    } catch (error) {
      console.error(`Error sending batch ${Math.floor(i / fcmBatchSize) + 1}:`, error);
      totalFailed += tokens.length;
      batch.forEach((sentTo) => {
        const rec = recipientByUserId.get(sentTo.userId);
        if (rec) rec.error = error.message;
      });
    }
  }

  // Update notification status
  if (notificationId) {
    await db.collection('SystemNotifications').doc(notificationId).update({
      isTriggered: true,
      triggeredAt: FieldValue.serverTimestamp(),
      sentCount: totalSent,
      failedCount: totalFailed,
      lastSentAt: FieldValue.serverTimestamp(),
    });
  }

  return {
    success: true,
    sentCount: totalSent,
    failedCount: totalFailed,
    totalTargets: targetUsers.length,
    recipients,
  };
}

// Persists a per-recipient delivery record so a developer/admin can see exactly which accounts
// and devices received (or were skipped/failed for) a given system or test notification —
// aggregate sentCount/failedCount alone don't answer "did *my* account get it".
async function logDelivery({
  kind, title, body, result, runId,
}) {
  try {
    await db.collection('NotificationDeliveryLogs').add({
      kind,
      title,
      body,
      runId,
      createdAt: FieldValue.serverTimestamp(),
      totalTargets: result.totalTargets,
      sentCount: result.sentCount,
      failedCount: result.failedCount,
      recipients: result.recipients,
    });
  } catch (error) {
    console.error('Error logging notification delivery:', error);
  }
}

// Calendar-accurate date helpers mirroring the notification/alert math in
// lib/services/pm_scheduling_service.dart — kept in sync deliberately (not imported, since this
// runs in a separate Node runtime); dueDate itself is already computed and stored client-side by
// PmSchedulingService, so this only needs to derive the notify/alert window from it.
function shiftOffWeekend(date) {
  const day = date.getDay(); // 0 = Sunday, 6 = Saturday
  if (day === 6) return new Date(date.getFullYear(), date.getMonth(), date.getDate() - 1);
  if (day === 0) return new Date(date.getFullYear(), date.getMonth(), date.getDate() - 2);
  return date;
}

function computeNotificationDate(dueDate) {
  return shiftOffWeekend(new Date(dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate() - 5));
}

function computeAlertDate(dueDate) {
  return shiftOffWeekend(new Date(dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate() - 1));
}

function dateKey(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

// Splits an array into fixed-size chunks — used to stay under Firestore's 500-op batch limit
// when writing one digest doc per target user.
function chunk(array, size) {
  const chunks = [];
  for (let i = 0; i < array.length; i += size) chunks.push(array.slice(i, i + size));
  return chunks;
}

// Writes the immutable audit record for one facility's batch of due/alert tasks to
// facilities/{facilityId}/notifications, and marks each task's [markField] so this same
// due/alert cycle isn't re-sent on the next cron tick. No FCM send here — delivery is handled
// once, as a single cross-facility digest per user, by the caller (checkDueNotifications).
async function recordFacilityNotification({
  facilityRef, tasks, facilityName, isAlert, markField,
}) {
  const title = isAlert ? `Maintenance Alert — ${facilityName}` : `Maintenance Due — ${facilityName}`;
  const body = isAlert
    ? `${tasks.length} maintenance ${tasks.length === 1 ? 'task is' : 'tasks are'} due very soon at ${facilityName}`
    : `${tasks.length} maintenance ${tasks.length === 1 ? 'task needs' : 'tasks need'} attention at ${facilityName}`;

  const notificationRef = await facilityRef.collection('notifications').add({
    facilityId: facilityRef.id,
    type: 'system',
    category: isAlert ? 'alert' : 'due',
    title,
    body,
    taskIds: tasks.map((t) => t.id),
    isAlert,
    priority: isAlert ? 'urgent' : 'normal',
    createdAt: FieldValue.serverTimestamp(),
    createdBy: null,
    sentCount: 0,
    failedCount: 0,
    digestId: null,
  });

  const batch = db.batch();
  for (const taskDoc of tasks) {
    batch.update(taskDoc.ref, { [markField]: FieldValue.serverTimestamp() });
  }
  await batch.commit();

  return { notificationRef, title, body };
}

// Scheduled function to check for due/alert preventive-maintenance tasks across every facility's
// facilities/{facilityId}/preventive_maintenance subcollection — replaces the legacy global
// Maintenance_Tasks -> SystemNotifications pipeline, which used crude single-occurrence date math
// with no real per-facility maintenance start date and no protection against marking distant-past
// dates overdue after a fresh regeneration. `dueDate` on each task is already calendar-anchored by
// PmSchedulingService (client-side regeneration), so this function only derives the notification/
// alert window from it and tracks per-task dedup via `notifiedAt`/`alertedAt`.
exports.checkDueNotifications = onSchedule(
  {
    schedule: '0 * * * *',
    timeZone: 'Africa/Nairobi',
    memory: '256MiB',
    timeoutSeconds: 180,
  },
  async () => {
    try {
      console.log('Checking facility-scoped preventive maintenance due/alert notifications...');
      const now = new Date();
      const todayKey = dateKey(now);

      // No server-side filters here (deliberately) — collection-group queries need an explicit
      // per-field index once you add where()/orderBy(), while a bare scan across the group works
      // out of the box. Task volume here is small enough that filtering in-process is simpler and
      // avoids provisioning a new collection-group index just for this.
      const tasksSnapshot = await db.collectionGroup('preventive_maintenance').get();
      console.log(`Scanning ${tasksSnapshot.docs.length} preventive_maintenance tasks across all facilities`);

      const byFacility = new Map();

      for (const doc of tasksSnapshot.docs) {
        const data = doc.data();
        const dueDateTs = data.dueDate;
        const facilityRef = doc.ref.parent.parent;

        if (data.status !== 'completed' && dueDateTs && facilityRef) {
          const facilityId = facilityRef.id;
          if (!byFacility.has(facilityId)) {
            byFacility.set(facilityId, { facilityRef, dueTasks: [], alertTasks: [] });
          }
          const bucket = byFacility.get(facilityId);

          const dueDate = dueDateTs.toDate();
          const notificationKey = dateKey(computeNotificationDate(dueDate));
          const alertKey = dateKey(computeAlertDate(dueDate));

          if (!data.notifiedAt && notificationKey <= todayKey) {
            bucket.dueTasks.push(doc);
          }
          if (!data.alertedAt && alertKey <= todayKey) {
            bucket.alertTasks.push(doc);
          }
        }
      }

      // JV Almacis is the contractor who performs on-site maintenance for every client
      // facility — they're the intended recipient, not the client organizations themselves.
      const usersSnapshot = await db
        .collection('Users')
        .where('organization', '==', 'JV Almacis')
        .where('notificationsEnabled', '!=', false)
        .get();
      const targetUsers = usersSnapshot.docs.map((userDoc) => userDoc.id);

      // Phase 1: record each facility's due/alert work as an immutable audit doc, and roll every
      // facility's items into ONE cross-facility digest structure — every target user currently
      // shares the same JV-Almacis-wide scope, so the digest content is identical for all of them
      // this run, but it's still written per-user (not once) so future per-user facility scoping
      // is a pure data-shape change, not a rearchitecture.
      const digestFacilities = [];
      const digestSourceRefs = [];
      let anyAlert = false;

      for (const [facilityId, bucket] of byFacility) {
        const hasWork = bucket.dueTasks.length > 0 || bucket.alertTasks.length > 0;
        if (!hasWork) {
          // eslint-disable-next-line no-continue
          continue;
        }

        const facilityDoc = await db.collection('Facilities').doc(facilityId).get();
        const facilityName = facilityDoc.exists ? (facilityDoc.data().name || 'your facility') : 'your facility';
        const items = [];

        const rowToItem = (t, isAlert) => {
          const d = t.data();
          return {
            taskId: t.id,
            category: d.category || '',
            component: d.component || '',
            intervention: d.intervention || '',
            dueDate: d.dueDate,
            isAlert,
          };
        };

        if (bucket.dueTasks.length > 0) {
          const rec = await recordFacilityNotification({
            facilityRef: bucket.facilityRef,
            tasks: bucket.dueTasks,
            facilityName,
            isAlert: false,
            markField: 'notifiedAt',
          });
          digestSourceRefs.push({ facilityId, notificationId: rec.notificationRef.id });
          items.push(...bucket.dueTasks.map((t) => rowToItem(t, false)));
        }
        if (bucket.alertTasks.length > 0) {
          anyAlert = true;
          const rec = await recordFacilityNotification({
            facilityRef: bucket.facilityRef,
            tasks: bucket.alertTasks,
            facilityName,
            isAlert: true,
            markField: 'alertedAt',
          });
          digestSourceRefs.push({ facilityId, notificationId: rec.notificationRef.id });
          items.push(...bucket.alertTasks.map((t) => rowToItem(t, true)));
        }

        digestFacilities.push({
          facilityId, facilityName, count: items.length, items,
        });
      }

      const totalCount = digestFacilities.reduce((sum, f) => sum + f.count, 0);
      const facilityCount = digestFacilities.length;

      if (totalCount > 0 && targetUsers.length > 0) {
        const notifWord = totalCount === 1 ? '' : 's';
        const facilityWord = facilityCount === 1 ? 'y' : 'ies';
        const title = `${totalCount} notification${notifWord} from ${facilityCount} facilit${facilityWord}`;
        const topNames = digestFacilities.slice(0, 2).map((f) => f.facilityName);
        const remaining = facilityCount - topNames.length;
        const body = remaining > 0 ? `${topNames.join(', ')} and ${remaining} more` : topNames.join(', ');
        const runId = `run_${now.getTime()}`;

        for (const userIdBatch of chunk(targetUsers, 450)) {
          const digestBatch = db.batch();
          for (const userId of userIdBatch) {
            const digestRef = db.collection('NotificationDigests').doc(userId).collection('items').doc();
            digestBatch.set(digestRef, {
              userId,
              runId,
              createdAt: FieldValue.serverTimestamp(),
              kind: anyAlert ? 'alert_digest' : 'due_digest',
              title,
              body,
              totalCount,
              facilityCount,
              facilities: digestFacilities,
              sourceNotificationRefs: digestSourceRefs,
              fcmSent: true,
              fcmMessageIds: [],
              deliveredAt: null,
              readAt: null,
              reTriggerCount: 0,
              lastReTriggeredAt: null,
              supersededByDigestId: null,
            });
          }
          await digestBatch.commit();
        }

        // One multicast for the whole run — content is uniform across recipients today (see
        // comment above), so a single send covers every target user's device(s). `runId` rides
        // along in the data payload so each recipient's device can ack receipt back onto its own
        // NotificationDigests doc (which shares this same runId) — see markDelivered() client-side.
        const digestSendResult = await sendNotificationInternal(
          {
            title,
            body,
            notificationId: null,
            priority: anyAlert ? 'urgent' : 'normal',
            data: { type: 'digest', runId },
          },
          targetUsers,
        );
        await logDelivery({
          kind: anyAlert ? 'alert_digest' : 'due_digest', title, body, result: digestSendResult, runId,
        });
        console.log(`checkDueNotifications: digest sent to ${targetUsers.length} users — ${title}`);
      } else {
        console.log('checkDueNotifications: nothing due this run, no digest sent');
      }

      // Phase 2: re-trigger any digest a user still hasn't opened 4+ hours after it was sent —
      // capped at 3 re-triggers per original digest, and combined per-user into one push each
      // (not one push per stale digest) so a user who ignored several runs still gets a single
      // reminder, not a flood.
      const fourHoursAgo = new Date(now.getTime() - 4 * 60 * 60 * 1000);
      const RETRIGGER_CAP = 3;
      let usersRetriggered = 0;

      for (const userId of targetUsers) {
        // Filtered to reTriggerCount < RETRIGGER_CAP in-process rather than in the query itself —
        // Firestore doesn't support inequality filters on two different fields in one query
        // without a purpose-built composite index, and this keeps the query index-free.
        const staleSnap = await db
          .collection('NotificationDigests').doc(userId).collection('items')
          .where('readAt', '==', null)
          .where('createdAt', '<=', Timestamp.fromDate(fourHoursAgo))
          .orderBy('createdAt', 'desc')
          .limit(20)
          .get();

        const staleDocs = staleSnap.docs.filter((d) => (d.data().reTriggerCount || 0) < RETRIGGER_CAP);

        const mergedFacilitiesMap = new Map();
        let mergedTotal = 0;
        for (const doc of staleDocs) {
          const d = doc.data();
          mergedTotal += d.totalCount || 0;
          for (const f of (d.facilities || [])) {
            const existingEntry = mergedFacilitiesMap.get(f.facilityId);
            if (existingEntry) {
              existingEntry.count += f.count;
              existingEntry.items = existingEntry.items.concat(f.items || []);
            } else {
              mergedFacilitiesMap.set(f.facilityId, { ...f, items: [...(f.items || [])] });
            }
          }
        }

        if (staleDocs.length === 0 || mergedTotal === 0) {
          // eslint-disable-next-line no-continue
          continue;
        }

        const mergedFacilities = Array.from(mergedFacilitiesMap.values());
        const mergedFacilityCount = mergedFacilities.length;
        const mergedNotifWord = mergedTotal === 1 ? '' : 's';
        const mergedFacilityWord = mergedFacilityCount === 1 ? 'y' : 'ies';
        const retriggerTitle = `Reminder: ${mergedTotal} notification${mergedNotifWord} still unread`;
        const retriggerBody = `From ${mergedFacilityCount} facilit${mergedFacilityWord} — tap to review`;

        const retriggerRunId = `retrigger_${now.getTime()}_${userId}`;
        const retriggerRef = db.collection('NotificationDigests').doc(userId).collection('items').doc();
        const retriggerBatch = db.batch();
        retriggerBatch.set(retriggerRef, {
          userId,
          runId: retriggerRunId,
          createdAt: FieldValue.serverTimestamp(),
          kind: 'retrigger',
          title: retriggerTitle,
          body: retriggerBody,
          totalCount: mergedTotal,
          facilityCount: mergedFacilityCount,
          facilities: mergedFacilities,
          sourceNotificationRefs: [],
          fcmSent: true,
          fcmMessageIds: [],
          deliveredAt: null,
          readAt: null,
          reTriggerCount: 0,
          lastReTriggeredAt: null,
          supersededByDigestId: null,
        });
        for (const doc of staleDocs) {
          retriggerBatch.update(doc.ref, {
            reTriggerCount: FieldValue.increment(1),
            lastReTriggeredAt: FieldValue.serverTimestamp(),
            supersededByDigestId: retriggerRef.id,
          });
        }
        await retriggerBatch.commit();

        const retriggerSendResult = await sendNotificationInternal(
          {
            title: retriggerTitle,
            body: retriggerBody,
            notificationId: null,
            priority: 'normal',
            data: { type: 'digest', runId: retriggerRunId },
          },
          [userId],
        );
        await logDelivery({
          kind: 'retrigger',
          title: retriggerTitle,
          body: retriggerBody,
          result: retriggerSendResult,
          runId: retriggerRunId,
        });
        usersRetriggered += 1;
      }

      console.log(`checkDueNotifications complete: digest=${totalCount > 0}, usersRetriggered=${usersRetriggered}`);
      return null;
    } catch (error) {
      console.error('Error in checkDueNotifications:', error);
      return null;
    }
  },
);

// Clean up expired notifications
exports.cleanupExpiredNotifications = onSchedule(
  {
    schedule: '0 2 * * *',
    timeZone: 'Africa/Nairobi',
    memory: '256MiB',
    timeoutSeconds: 60,
  },
  async () => {
    try {
      console.log('Cleaning up expired notifications...');
      const now = new Date();

      const expiredNotificationsSnapshot = await db
        .collection('SystemNotifications')
        .where('expiryDate', '<', Timestamp.fromDate(now))
        .where('type', '==', 'custom')
        .get();

      const batch = db.batch();
      expiredNotificationsSnapshot.docs.forEach((doc) => {
        batch.delete(doc.ref);
      });

      await batch.commit();

      console.log(`Cleaned up ${expiredNotificationsSnapshot.docs.length} expired notifications`);
      return null;
    } catch (error) {
      console.error('Error in cleanupExpiredNotifications:', error);
      return null;
    }
  },
);

// Immediately sends a real FCM push the instant a test notification (CustomNotifications
// docs with type=='test') is created — a client-only timer/listener can never deliver to a
// backgrounded or fully-closed app, since Dart timers stop running once the app process isn't
// alive. A server-triggered FCM push is what actually wakes a closed app via the OS.
exports.onTestNotificationCreated = onDocumentCreated('CustomNotifications/{notificationId}', async (event) => {
  const snapshot = event.data;
  if (!snapshot) return;
  const notification = snapshot.data();
  if (notification.type !== 'test') return;

  try {
    const usersSnapshot = await db
      .collection('Users')
      .where('organization', '==', notification.organization)
      .where('notificationsEnabled', '!=', false)
      .get();

    const userTokens = usersSnapshot.docs
      .map((doc) => doc.data())
      .filter((userData) => !!userData.fcmToken)
      .map((userData) => userData.fcmToken);

    if (userTokens.length === 0) {
      console.log(
        `No FCM tokens found for test notification ${event.params.notificationId} `
        + `(org: ${notification.organization})`,
      );
      await snapshot.ref.update({
        isTriggered: true,
        status: 'failed',
        lastError: 'No recipients with an FCM token',
        lastErrorAt: FieldValue.serverTimestamp(),
      });
      return;
    }

    const response = await messaging.sendEachForMulticast({
      tokens: userTokens,
      notification: { title: notification.title, body: notification.body },
      data: { notificationId: event.params.notificationId, type: 'test' },
      android: { notification: { channelId: 'maintenance_normal', sound: 'default' } },
      apns: { payload: { aps: { alert: { title: notification.title, body: notification.body }, sound: 'default' } } },
    });

    await snapshot.ref.update({
      isTriggered: true,
      triggeredAt: FieldValue.serverTimestamp(),
      status: 'triggered',
      sentCount: response.successCount,
      failedCount: response.failureCount,
      lastSentAt: FieldValue.serverTimestamp(),
    });

    console.log(
      `Test notification ${event.params.notificationId} sent: `
      + `${response.successCount}/${userTokens.length} delivered`,
    );
  } catch (error) {
    console.error(`Error sending test notification ${event.params.notificationId}:`, error);
    await snapshot.ref.update({
      status: 'failed',
      lastError: error.message,
      lastErrorAt: FieldValue.serverTimestamp(),
    });
  }
});

// Fans out a facility-scoped custom notification (facilities/{facilityId}/notifications doc
// with type=='custom') to every JV Almacis contractor user's digest and sends FCM immediately —
// unlike due/alert digests, a custom notification is a deliberate, human-authored single
// message, so it delivers right away instead of waiting for the next hourly digest run.
exports.onCustomNotificationCreated = onDocumentCreated(
  'facilities/{facilityId}/notifications/{notificationId}',
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    const notification = snapshot.data();
    if (notification.type !== 'custom') return;

    try {
      const usersSnapshot = await db
        .collection('Users')
        .where('organization', '==', 'JV Almacis')
        .where('notificationsEnabled', '!=', false)
        .get();
      const targetUsers = usersSnapshot.docs.map((doc) => doc.id);
      if (targetUsers.length === 0) return;

      const { facilityId, notificationId } = event.params;
      const facilityDoc = await db.collection('Facilities').doc(facilityId).get();
      const facilityName = facilityDoc.exists ? (facilityDoc.data().name || 'your facility') : 'your facility';
      const customRunId = `custom_${notificationId}`;

      for (const userIdBatch of chunk(targetUsers, 450)) {
        const digestBatch = db.batch();
        for (const userId of userIdBatch) {
          const digestRef = db.collection('NotificationDigests').doc(userId).collection('items').doc();
          digestBatch.set(digestRef, {
            userId,
            runId: customRunId,
            createdAt: FieldValue.serverTimestamp(),
            kind: 'custom',
            title: notification.title,
            body: notification.body,
            totalCount: 1,
            facilityCount: 1,
            facilities: [{
              facilityId, facilityName, count: 1, items: [],
            }],
            sourceNotificationRefs: [{ facilityId, notificationId }],
            fcmSent: true,
            fcmMessageIds: [],
            deliveredAt: null,
            readAt: null,
            reTriggerCount: 0,
            lastReTriggeredAt: null,
            supersededByDigestId: null,
          });
        }
        await digestBatch.commit();
      }

      const result = await sendNotificationInternal(
        {
          title: notification.title,
          body: notification.body,
          notificationId: null,
          priority: notification.priority || 'normal',
          data: { type: 'digest', facilityId, runId: customRunId },
        },
        targetUsers,
      );
      await logDelivery({
        kind: 'custom', title: notification.title, body: notification.body, result, runId: customRunId,
      });

      await snapshot.ref.update({ sentCount: result.sentCount, failedCount: result.failedCount });
    } catch (error) {
      console.error(`Error fanning out custom notification ${event.params.notificationId}:`, error);
    }
  },
);

// Sends a test push directly to the calling user's own device(s). Replaces the old client-side
// direct-FCM-HTTP path, which bundled a Firebase service-account JSON inside the app — a real
// credential-exposure risk (a decompiled app leaks push-send credentials for the whole project).
// No persistent Firestore doc is needed; this purely verifies delivery end-to-end.
exports.sendTestNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be authenticated');
  }

  const title = 'Test Notification';
  const body = 'This is a test notification from the CMMS system.';
  const testRunId = `test_${Date.now()}_${request.auth.uid}`;

  try {
    const result = await sendNotificationInternal(
      {
        title, body, notificationId: null, priority: 'normal', data: { type: 'test', runId: testRunId },
      },
      [request.auth.uid],
    );
    await logDelivery({
      kind: 'test', title, body, result, runId: testRunId,
    });

    // Also write a digest item for the caller, same as every other notification kind — this is
    // what makes the test push actually visible in-app (floating banner / notifications screen /
    // tray grouping) rather than relying solely on the OS push, which a foregrounded web tab
    // never auto-displays (Chrome/web only auto-shows a notification for *background* pushes;
    // a page that's open and focused only gets the onMessage JS event, which this app previously
    // no-op'd on web).
    await db.collection('NotificationDigests').doc(request.auth.uid).collection('items').add({
      userId: request.auth.uid,
      runId: testRunId,
      createdAt: FieldValue.serverTimestamp(),
      kind: 'test',
      title,
      body,
      totalCount: 1,
      facilityCount: 0,
      facilities: [],
      sourceNotificationRefs: [],
      fcmSent: result.sentCount > 0,
      fcmMessageIds: [],
      deliveredAt: null,
      readAt: null,
      reTriggerCount: 0,
      lastReTriggeredAt: null,
      supersededByDigestId: null,
    });

    return result;
  } catch (error) {
    console.error('Error sending test notification:', error);
    throw new HttpsError('internal', error.message);
  }
});

// Replaces cleanupExpiredNotifications for the consolidated pipeline: deletes NotificationDigests
// items older than 90 days. facilities/{id}/notifications audit docs are intentionally left
// alone — they're the maintenance history record, not a delivery queue, so they don't expire.
exports.cleanupOldDigests = onSchedule(
  {
    schedule: '30 2 * * *',
    timeZone: 'Africa/Nairobi',
    memory: '256MiB',
    timeoutSeconds: 120,
  },
  async () => {
    try {
      const cutoff = Timestamp.fromDate(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000));
      const usersSnapshot = await db.collection('Users').where('organization', '==', 'JV Almacis').get();

      let deleted = 0;
      for (const userDoc of usersSnapshot.docs) {
        const oldSnap = await db
          .collection('NotificationDigests').doc(userDoc.id).collection('items')
          .where('createdAt', '<', cutoff)
          .limit(400)
          .get();
        if (!oldSnap.empty) {
          const batch = db.batch();
          oldSnap.docs.forEach((doc) => batch.delete(doc.ref));
          await batch.commit();
          deleted += oldSnap.docs.length;
        }
      }

      const oldLogsSnap = await db
        .collection('NotificationDeliveryLogs')
        .where('createdAt', '<', cutoff)
        .limit(400)
        .get();
      if (!oldLogsSnap.empty) {
        const logsBatch = db.batch();
        oldLogsSnap.docs.forEach((doc) => logsBatch.delete(doc.ref));
        await logsBatch.commit();
      }

      console.log(
        `cleanupOldDigests: deleted ${deleted} digest items and ${oldLogsSnap.size} `
        + 'delivery logs older than 90 days',
      );
      return null;
    } catch (error) {
      console.error('Error in cleanupOldDigests:', error);
      return null;
    }
  },
);

// One-time backfill of legacy global Maintenance_Tasks/TaskProgress into a facility's
// facilities/{facilityId}/preventive_maintenance subcollection. See functions/migrations/
// backfillPreventiveMaintenance.js for details.
const { migrateLegacyMaintenanceData } = require('./migrations/backfillPreventiveMaintenance');

exports.migrateLegacyMaintenanceData = migrateLegacyMaintenanceData;
