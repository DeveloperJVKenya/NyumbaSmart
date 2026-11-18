const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const { VertexAI } = require('@google-cloud/vertexai');

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
        // Quiet hours: skip FCM for this user if they've set a quiet window (#23).
        if (userData.quietHoursStart && userData.quietHoursEnd) {
          const nairobiTime = new Date().toLocaleString('en-US', { timeZone: 'Africa/Nairobi' });
          const nairobiDate = new Date(nairobiTime);
          const nowMins = nairobiDate.getHours() * 60 + nairobiDate.getMinutes();
          const toMins = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
          const s = toMins(userData.quietHoursStart);
          const e = toMins(userData.quietHoursEnd);
          const inQuiet = s < e ? nowMins >= s && nowMins < e : nowMins >= s || nowMins < e;
          if (inQuiet) {
            return {
              userId, userName, token: null, platform, skipReason: 'quiet hours',
            };
          }
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

function computeNotificationDate(dueDate, daysBefore = 5) {
  return shiftOffWeekend(new Date(dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate() - daysBefore));
}

function computeAlertDate(dueDate, daysBefore = 1) {
  return shiftOffWeekend(new Date(dueDate.getFullYear(), dueDate.getMonth(), dueDate.getDate() - daysBefore));
}

function dateKey(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();
}

// Returns { pmNotifyDaysBefore, pmAlertDaysBefore } from facilitySettings/{facilityId}
// (a top-level doc), falling back to default 5-day / 1-day windows if unset (#4).
async function getFacilitySettings(facilityId) {
  try {
    const doc = await db.collection('facilitySettings').doc(facilityId).get();
    if (doc.exists) {
      const d = doc.data();
      return {
        pmNotifyDaysBefore: typeof d.pmNotifyDaysBefore === 'number' ? d.pmNotifyDaysBefore : 5,
        pmAlertDaysBefore: typeof d.pmAlertDaysBefore === 'number' ? d.pmAlertDaysBefore : 1,
      };
    }
  } catch (_) { /* fall through to defaults */ }
  return { pmNotifyDaysBefore: 5, pmAlertDaysBefore: 1 };
}

// Advances a due date forward by frequencyMonths calendar months — same logic as
// PmSchedulingService.addMonths() in lib/services/pm_scheduling_service.dart (#3).
function addMonths(date, months) {
  const d = new Date(date);
  d.setMonth(d.getMonth() + months);
  return d;
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
      // Track tasks needing a next-due-date rollover (#3).
      const nextDueRolloverDocs = [];

      for (const doc of tasksSnapshot.docs) {
        const data = doc.data();
        const dueDateTs = data.dueDate;
        const facilityRef = doc.ref.parent.parent;
        if (dueDateTs && facilityRef) {
          const facilityId = facilityRef.id;
          const dueDate = dueDateTs.toDate();
          const freqMonths = typeof data.frequencyMonths === 'number' ? data.frequencyMonths : 0;

          // #17: skip non-recurring completed tasks — they're done and won't recur.
          const isNonRecurringDone = data.status === 'completed' && freqMonths === 0;
          // #3: recurring completed tasks with a past due date need their next due date rolled forward.
          const needsRollover = data.status === 'completed' && freqMonths > 0 && dateKey(dueDate) < todayKey;

          if (!isNonRecurringDone && !needsRollover && data.status !== 'completed') {
            if (!byFacility.has(facilityId)) {
              byFacility.set(facilityId, {
                facilityRef, dueTasks: [], alertTasks: [], todayTasks: [], pendingTasksList: [],
              });
            }
            // #4: stash for per-facility window resolution below.
            byFacility.get(facilityId).pendingTasksList.push({ doc, dueDate, data });
          } else if (needsRollover) {
            nextDueRolloverDocs.push({ ref: doc.ref, dueDate, freqMonths });
          }
        }
      }

      // Resolve per-facility settings and bin tasks into due/alert/today buckets (#4, #5).
      for (const [facilityId, bucket] of byFacility) {
        const settings = await getFacilitySettings(facilityId);
        for (const { doc, dueDate, data } of bucket.pendingTasksList) {
          const dueDateKeyVal = dateKey(dueDate);
          const notificationKey = dateKey(computeNotificationDate(dueDate, settings.pmNotifyDaysBefore));
          const alertKey = dateKey(computeAlertDate(dueDate, settings.pmAlertDaysBefore));

          // Same-day bucket (#5) — guard: dueTodayNotifiedAt field.
          if (!data.dueTodayNotifiedAt && dueDateKeyVal === todayKey) {
            bucket.todayTasks.push(doc);
          } else {
            if (!data.notifiedAt && notificationKey <= todayKey) bucket.dueTasks.push(doc);
            if (!data.alertedAt && alertKey <= todayKey) bucket.alertTasks.push(doc);
          }
        }
      }

      // #3: batch-write rolled-over next due dates for recurring completed tasks.
      if (nextDueRolloverDocs.length > 0) {
        for (const rolloverChunk of chunk(nextDueRolloverDocs, 480)) {
          const rolloverBatch = db.batch();
          for (const { ref, dueDate, freqMonths } of rolloverChunk) {
            let next = addMonths(dueDate, freqMonths);
            // Advance until next is in the future.
            while (dateKey(next) <= todayKey) next = addMonths(next, freqMonths);
            rolloverBatch.update(ref, {
              dueDate: Timestamp.fromDate(next),
              status: 'pending',
              notifiedAt: null,
              alertedAt: null,
              dueTodayNotifiedAt: null,
            });
          }
          await rolloverBatch.commit();
        }
        console.log(`checkDueNotifications: rolled forward ${nextDueRolloverDocs.length} completed recurring tasks`);
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
        const hasWork = bucket.dueTasks.length > 0
          || bucket.alertTasks.length > 0
          || (bucket.todayTasks && bucket.todayTasks.length > 0);
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

        if (bucket.todayTasks && bucket.todayTasks.length > 0) {
          const rec = await recordFacilityNotification({
            facilityRef: bucket.facilityRef,
            tasks: bucket.todayTasks,
            facilityName,
            isAlert: false,
            markField: 'dueTodayNotifiedAt',
          });
          digestSourceRefs.push({ facilityId, notificationId: rec.notificationRef.id });
          items.push(...bucket.todayTasks.map((t) => rowToItem(t, false)));
        }
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

        // Build user-prefs map (already loaded above) for muted-category filtering (#24).
        const userPrefsMap = new Map(usersSnapshot.docs.map((d) => [d.id, d.data()]));

        // 240 users per batch: each user costs 2 ops (item set + parent unreadCount merge) = 480 (#2).
        for (const userIdBatch of chunk(targetUsers, 240)) {
          const digestBatch = db.batch();
          for (const userId of userIdBatch) {
            const prefs = userPrefsMap.get(userId) || {};
            const mutedCategories = Array.isArray(prefs.mutedCategories) ? prefs.mutedCategories : [];

            // #24: filter out muted categories per user.
            const userFacilities = mutedCategories.length > 0
              ? digestFacilities
                .map((f) => ({ ...f, items: f.items.filter((item) => !mutedCategories.includes(item.category)) }))
                .map((f) => ({ ...f, count: f.items.length }))
                .filter((f) => f.count > 0)
              : digestFacilities;

            const userTotalCount = userFacilities.reduce((s, f) => s + f.count, 0);
            // eslint-disable-next-line no-continue
            if (userTotalCount === 0) continue; // all tasks muted for this user

            const digestRef = db.collection('NotificationDigests').doc(userId).collection('items').doc();
            digestBatch.set(digestRef, {
              userId,
              runId,
              createdAt: FieldValue.serverTimestamp(),
              kind: anyAlert ? 'alert_digest' : 'due_digest',
              title,
              body,
              totalCount: userTotalCount,
              facilityCount: userFacilities.length,
              facilities: userFacilities,
              sourceNotificationRefs: digestSourceRefs,
              fcmSent: true,
              fcmMessageIds: [],
              deliveredAt: null,
              readAt: null,
              reTriggerCount: 0,
              lastReTriggeredAt: null,
              supersededByDigestId: null,
            });
            // #2: increment unreadCount on the parent NotificationDigests/{userId} doc.
            digestBatch.set(
              db.collection('NotificationDigests').doc(userId),
              { unreadCount: FieldValue.increment(1) },
              { merge: true },
            );
          }
          await digestBatch.commit();
        }

        // Fan-out 5-day advance notice to clients linked to each facility (#27).
        for (const facilityEntry of digestFacilities) {
          const facId = facilityEntry.facilityId;
          const clientLinksSnap = await db // eslint-disable-line no-await-in-loop
            .collection('facilities').doc(facId)
            .collection('clientLinks')
            .where('active', '==', true)
            .get();

          if (clientLinksSnap.empty) {
            // eslint-disable-next-line no-continue
            continue;
          }

          const clientUids = clientLinksSnap.docs.map((d) => d.id);
          const clientTitle = `Upcoming Maintenance at ${facilityEntry.facilityName}`;
          const topItems = facilityEntry.items.slice(0, 3).map((it) => it.component || it.intervention).join(', ');
          const clientBody = `${facilityEntry.count} task${facilityEntry.count === 1 ? '' : 's'} due: ${topItems}. `
            + 'Tap to Accept or Reschedule.';

          const clientBatch = db.batch();
          clientUids.forEach((uid) => {
            const parentRef = db.collection('NotificationDigests').doc(uid);
            const itemRef = parentRef.collection('items').doc();
            clientBatch.set(parentRef, { unreadCount: FieldValue.increment(1) }, { merge: true });
            clientBatch.set(itemRef, {
              userId: uid,
              runId,
              createdAt: FieldValue.serverTimestamp(),
              kind: 'pm_advance_client',
              title: clientTitle,
              body: clientBody,
              facilityId: facId,
              facilityName: facilityEntry.facilityName,
              items: facilityEntry.items,
              readAt: null,
              deliveredAt: null,
            });
          });
          await clientBatch.commit(); // eslint-disable-line no-await-in-loop

          // Send a per-task FCM push to each client so the notification tap
          // deep-links directly to PmScheduleResponseScreen for that task.
          const clientTokens = ( // eslint-disable-line no-await-in-loop
            await Promise.all(
              clientUids.map(async (uid) => {
                const userDoc = await db.collection('Users').doc(uid).get();
                return userDoc.exists ? userDoc.data().fcmToken || null : null;
              }),
            )
          ).filter(Boolean);

          if (clientTokens.length > 0) {
            // eslint-disable-next-line no-await-in-loop
            await Promise.all(facilityEntry.items.map((item) => {
              let plannedDate = new Date().toISOString();
              if (item.dueDate) {
                plannedDate = item.dueDate.toDate
                  ? item.dueDate.toDate().toISOString()
                  : new Date(item.dueDate).toISOString();
              }
              const equipmentName = item.component || item.intervention || 'Equipment';
              return messaging.sendEachForMulticast({
                tokens: clientTokens,
                notification: {
                  title: `Upcoming Maintenance: ${equipmentName}`,
                  body: `Scheduled maintenance on ${equipmentName}. Tap to Accept or Reschedule.`,
                },
                data: {
                  type: 'pm_advance_client',
                  facilityId: facId,
                  taskId: item.taskId,
                  equipmentName,
                  plannedDate,
                },
                android: { priority: 'normal' },
                apns: { payload: { aps: { sound: 'default' } } },
              });
            }));
          }
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
        // #2: increment unreadCount on parent doc for the retrigger digest.
        retriggerBatch.set(
          db.collection('NotificationDigests').doc(userId),
          { unreadCount: FieldValue.increment(1) },
          { merge: true },
        );
        for (const doc of staleDocs) {
          retriggerBatch.update(doc.ref, {
            reTriggerCount: FieldValue.increment(1),
            lastReTriggeredAt: FieldValue.serverTimestamp(),
            supersededByDigestId: retriggerRef.id,
          });
          // #19: also track retrigger count on the source PM tasks.
          for (const facility of (doc.data().facilities || [])) {
            for (const item of (facility.items || [])) {
              if (item.taskId) {
                // Update via the facility path derived from the digest's facilityId.
                db.collection('facilities').doc(facility.facilityId)
                  .collection('preventive_maintenance').doc(item.taskId)
                  .update({ notifyRetriggerCount: FieldValue.increment(1) })
                  .catch((e) => console.warn(
                    `notifyRetriggerCount update skipped for task ${item.taskId}: ${e.message}`,
                  ));
              }
            }
          }
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

// cleanupExpiredNotifications and onTestNotificationCreated were removed: they operated on the
// legacy SystemNotifications and CustomNotifications collections from the pre-digest architecture
// and are no longer reachable from any client path. cleanupOldDigests (below) replaces the
// former; sendTestNotification (callable, above) replaces the latter.

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
      const { facilityId, notificationId } = event.params;

      // #18: scope fan-out to users who have this facility in their `facilities` array; fall back
      // to all JV Almacis users only if no per-facility user list is recorded.
      let usersSnapshot = await db
        .collection('Users')
        .where('facilities', 'array-contains', facilityId)
        .where('notificationsEnabled', '!=', false)
        .get();
      if (usersSnapshot.empty) {
        usersSnapshot = await db
          .collection('Users')
          .where('organization', '==', 'JV Almacis')
          .where('notificationsEnabled', '!=', false)
          .get();
      }
      const targetUsers = usersSnapshot.docs.map((doc) => doc.id);
      if (targetUsers.length === 0) return;

      const facilityDoc = await db.collection('Facilities').doc(facilityId).get();
      const facilityName = facilityDoc.exists ? (facilityDoc.data().name || 'your facility') : 'your facility';
      const customRunId = `custom_${notificationId}`;

      // 240 per batch: 2 ops per user (item + parent unreadCount) = 480 max (#2).
      for (const userIdBatch of chunk(targetUsers, 240)) {
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
          // #2: increment unreadCount on parent doc.
          digestBatch.set(
            db.collection('NotificationDigests').doc(userId),
            { unreadCount: FieldValue.increment(1) },
            { merge: true },
          );
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
    const testItemRef = db.collection('NotificationDigests').doc(request.auth.uid).collection('items').doc();
    const testDigestBatch = db.batch();
    testDigestBatch.set(testItemRef, {
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
    // #2: increment unreadCount on parent doc.
    testDigestBatch.set(
      db.collection('NotificationDigests').doc(request.auth.uid),
      { unreadCount: FieldValue.increment(1) },
      { merge: true },
    );
    await testDigestBatch.commit();

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
        // #21: skip users who opted to retain their notification history indefinitely.
        // eslint-disable-next-line no-continue
        if (userDoc.data().retainDigests === true) continue;

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

// Daily aggregation of notification read/open engagement for the developer/admin "Engagement"
// stats view. Reads across every user's NotificationDigests via the Admin SDK (bypasses the
// per-user-only client rule in firestore.rules, which deliberately keeps digest content private —
// see the comment there) but writes back counts and timings only, never titles/bodies/task
// details, so that same privacy boundary holds for what developer/admin accounts can actually see.
exports.aggregateNotificationEngagement = onSchedule(
  {
    schedule: '15 3 * * *',
    timeZone: 'Africa/Nairobi',
    memory: '256MiB',
    timeoutSeconds: 300,
  },
  async () => {
    try {
      const windowDays = 30;
      const windowStart = Timestamp.fromDate(new Date(Date.now() - windowDays * 24 * 60 * 60 * 1000));
      const usersSnapshot = await db.collection('Users').where('organization', '==', 'JV Almacis').get();

      const byKind = {};
      let total = 0;
      let totalRead = 0;
      let readDelayMinutesSum = 0;

      for (const userDoc of usersSnapshot.docs) {
        const itemsSnap = await db
          .collection('NotificationDigests').doc(userDoc.id).collection('items')
          .where('createdAt', '>=', windowStart)
          .get();

        for (const itemDoc of itemsSnap.docs) {
          const data = itemDoc.data();
          const kind = data.kind || 'due_digest';
          if (!byKind[kind]) byKind[kind] = { total: 0, read: 0, readDelayMinutesSum: 0 };

          total += 1;
          byKind[kind].total += 1;

          const { createdAt, readAt } = data;
          if (readAt) {
            totalRead += 1;
            byKind[kind].read += 1;
            if (createdAt) {
              const delayMinutes = (readAt.toMillis() - createdAt.toMillis()) / 60000;
              if (delayMinutes >= 0) {
                readDelayMinutesSum += delayMinutes;
                byKind[kind].readDelayMinutesSum += delayMinutes;
              }
            }
          }
        }
      }

      const kindBreakdown = Object.entries(byKind).map(([kind, stats]) => ({
        kind,
        total: stats.total,
        read: stats.read,
        readRate: stats.total > 0 ? stats.read / stats.total : 0,
        avgMinutesToRead: stats.read > 0 ? stats.readDelayMinutesSum / stats.read : null,
      }));

      const summary = {
        windowDays,
        total,
        totalRead,
        readRate: total > 0 ? totalRead / total : 0,
        avgMinutesToRead: totalRead > 0 ? readDelayMinutesSum / totalRead : null,
        kindBreakdown,
        computedAt: FieldValue.serverTimestamp(),
      };

      const todayKey = new Date().toISOString().slice(0, 10);
      await db.collection('NotificationEngagementStats').doc(todayKey).set(summary);
      await db.collection('NotificationEngagementStats').doc('latest').set(summary);

      console.log(
        `aggregateNotificationEngagement: ${total} digests, ${totalRead} read `
        + `(${(summary.readRate * 100).toFixed(1)}%) over ${windowDays}d`,
      );
      return null;
    } catch (error) {
      console.error('Error in aggregateNotificationEngagement:', error);
      return null;
    }
  },
);

// Weekly escalation: finds overdue PM tasks (dueDate in the past, status != completed) and sends
// an escalation alert digest to JV Almacis users. Runs Monday mornings so a fresh-week inbox
// doesn't miss tasks that slipped through without being completed (#20).
exports.escalateOverdueTasks = onSchedule(
  {
    schedule: '0 7 * * 1', // Monday 07:00 Nairobi time
    timeZone: 'Africa/Nairobi',
    memory: '256MiB',
    timeoutSeconds: 300,
  },
  async () => {
    try {
      const now = new Date();
      const todayTs = Timestamp.fromDate(now);

      const tasksSnapshot = await db.collectionGroup('preventive_maintenance').get();
      const overdueFacilities = new Map();

      for (const doc of tasksSnapshot.docs) {
        const data = doc.data();
        const facilityRef = doc.ref.parent.parent;
        // eslint-disable-next-line no-continue
        if (!facilityRef || data.status === 'completed' || !data.dueDate) continue;
        // eslint-disable-next-line no-continue
        if (data.dueDate.toMillis() >= todayTs.toMillis()) continue; // not yet overdue

        const facilityId = facilityRef.id;
        if (!overdueFacilities.has(facilityId)) {
          overdueFacilities.set(facilityId, { facilityRef, tasks: [] });
        }
        overdueFacilities.get(facilityId).tasks.push(doc);
      }

      if (overdueFacilities.size === 0) {
        console.log('escalateOverdueTasks: no overdue tasks found');
        return null;
      }

      const usersSnapshot = await db
        .collection('Users')
        .where('organization', '==', 'JV Almacis')
        .where('notificationsEnabled', '!=', false)
        .get();
      const targetUsers = usersSnapshot.docs.map((u) => u.id);
      if (targetUsers.length === 0) return null;

      const escFacilities = [];
      for (const [facilityId, bucket] of overdueFacilities) {
        const facilityDoc = await db.collection('Facilities').doc(facilityId).get();
        const facilityName = facilityDoc.exists ? (facilityDoc.data().name || 'your facility') : 'your facility';
        const items = bucket.tasks.map((t) => {
          const d = t.data();
          return {
            taskId: t.id,
            category: d.category || '',
            component: d.component || '',
            intervention: d.intervention || '',
            dueDate: d.dueDate,
            isAlert: true,
          };
        });
        escFacilities.push({
          facilityId, facilityName, count: items.length, items,
        });
      }

      const totalOverdue = escFacilities.reduce((s, f) => s + f.count, 0);
      const escRunId = `escalation_${now.getTime()}`;
      const escTitle = `Escalation: ${totalOverdue} overdue task${totalOverdue === 1 ? '' : 's'}`;
      const topNames = escFacilities.slice(0, 2).map((f) => f.facilityName);
      const remaining = escFacilities.length - topNames.length;
      const escBody = remaining > 0 ? `${topNames.join(', ')} and ${remaining} more` : topNames.join(', ');

      for (const userIdBatch of chunk(targetUsers, 240)) {
        const escBatch = db.batch();
        for (const userId of userIdBatch) {
          const escRef = db.collection('NotificationDigests').doc(userId).collection('items').doc();
          escBatch.set(escRef, {
            userId,
            runId: escRunId,
            createdAt: FieldValue.serverTimestamp(),
            kind: 'alert_digest',
            title: escTitle,
            body: escBody,
            totalCount: totalOverdue,
            facilityCount: escFacilities.length,
            facilities: escFacilities,
            sourceNotificationRefs: [],
            fcmSent: true,
            fcmMessageIds: [],
            deliveredAt: null,
            readAt: null,
            reTriggerCount: 0,
            lastReTriggeredAt: null,
            supersededByDigestId: null,
          });
          escBatch.set(
            db.collection('NotificationDigests').doc(userId),
            { unreadCount: FieldValue.increment(1) },
            { merge: true },
          );
        }
        await escBatch.commit();
      }

      const escSendResult = await sendNotificationInternal(
        {
          title: escTitle,
          body: escBody,
          notificationId: null,
          priority: 'urgent',
          data: { type: 'digest', runId: escRunId },
        },
        targetUsers,
      );
      await logDelivery({
        kind: 'alert_digest', title: escTitle, body: escBody, result: escSendResult, runId: escRunId,
      });

      console.log(
        `escalateOverdueTasks: ${totalOverdue} overdue tasks across `
        + `${escFacilities.length} facilities — sent to ${targetUsers.length} users`,
      );
      return null;
    } catch (error) {
      console.error('Error in escalateOverdueTasks:', error);
      return null;
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// AI PM Analysis
// ─────────────────────────────────────────────────────────────────────────────

// Valid equipment categories: Electrical, HVAC, Mechanical, Plumbing, Safety, Structural, Furniture/Fittings

const TEMPLATE_SEED = {
  'Air Terminal': { frequencyMonths: 12, reason: 'Clean and inspect grilles/diffusers' },
  'Air Terminal Box': { frequencyMonths: 12, reason: 'Inspect, test and calibrate VAV box actuator' },
  'Boiler': { frequencyMonths: 6, reason: 'Safety valve lift test and flue gas analysis' },
  'Chiller': { frequencyMonths: 6, reason: 'Check refrigerant charge and inspect for leaks' },
  'Compressor': { frequencyMonths: 3, reason: 'Check oil level and inspect for leaks' },
  'Cooling Tower': { frequencyMonths: 3, reason: 'Clean basin and inspect fill packing' },
  'Fan': { frequencyMonths: 3, reason: 'Inspect belts, tension and alignment' },
  'Filter': { frequencyMonths: 3, reason: 'Replace or clean air filter' },
  'Pump': { frequencyMonths: 6, reason: 'Check seals, bearings and alignment' },
  'Generator': { frequencyMonths: 6, reason: 'Full load test and service' },
  'UPS': { frequencyMonths: 6, reason: 'Battery load test and inspection' },
  'Transformer': { frequencyMonths: 12, reason: 'Inspect connections and insulation' },
  'Fire Alarm Control Panel': { frequencyMonths: 6, reason: 'Full system test and sensor check' },
  'Sprinkler': { frequencyMonths: 12, reason: 'Visual inspection and flow test' },
};

async function analyzeEquipmentBatch(vertexAI, equipmentBatch) {
  const model = vertexAI.preview.getGenerativeModel({
    model: 'gemini-1.5-flash',
    generationConfig: { responseMimeType: 'application/json', temperature: 0.2 },
  });

  const seedText = Object.entries(TEMPLATE_SEED)
    .slice(0, 8)
    .map(([k, v]) => `${k}: ${v.frequencyMonths} months — ${v.reason}`)
    .join('\n');

  const equipmentList = equipmentBatch
    .map((e) => `- id: ${e.id}, name: ${e.name}, typeName: ${e.typeName}, category: ${e.category}`)
    .join('\n');

  const prompt = `You are a certified facilities maintenance engineer. For each piece of equipment below,
provide:
- frequencyMonths: maintenance interval in months (integer 1-60)
- reason: one-sentence maintenance task description IN ENGLISH
- tools: list of up to 4 specific tools/instruments required (array of strings)
- estimatedHours: estimated visit duration in hours (decimal 0.25–8)
- spares: list of up to 3 consumable spare parts or materials (array of strings)
Equipment names may be in English or Italian — recognise both languages equally.
Use industry standards (ASHRAE, BS EN, ISO 9001). Reference frequency examples:\n${seedText}\n\n
Equipment list:\n${equipmentList}\n\n
Return ONLY a JSON array, one object per equipment in the same order:
[{"id":"...", "frequencyMonths": N, "reason":"...", "tools":["t1","t2"], "estimatedHours": N, "spares":["p1"]}]`;

  const result = await model.generateContent(prompt);
  const { candidates } = result.response;
  const [firstCandidate] = candidates;
  const [firstPart] = firstCandidate.content.parts;
  return JSON.parse(firstPart.text);
}

exports.analyzeEquipmentList = onCall({ timeoutSeconds: 540, memory: '512MiB' }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Must be authenticated');
  }

  const { facilityId, equipmentIds } = request.data || {};
  if (!facilityId) {
    throw new HttpsError('invalid-argument', 'facilityId is required');
  }

  const metaRef = db.collection('facilities').doc(facilityId).collection('aiPmAnalysis').doc('_meta');

  try {
    await metaRef.set({
      status: 'running',
      triggeredAt: Timestamp.now(),
      facilityId,
      itemCount: 0,
      errorMessage: null,
    });

    const equipRef = db.collection('facilities').doc(facilityId).collection('equipment');
    let equipmentDocs;

    if (equipmentIds && equipmentIds.length > 0) {
      const idChunks = [];
      for (let i = 0; i < equipmentIds.length; i += 10) {
        idChunks.push(equipmentIds.slice(i, i + 10));
      }
      const snapshots = await Promise.all(
        idChunks.map((idChunk) => equipRef.where('__name__', 'in', idChunk).get()),
      );
      equipmentDocs = snapshots.flatMap((s) => s.docs);
    } else {
      // Only analyse equipment from currently active (ready) BIM model imports.
      // This excludes orphaned equipment left over from deleted model records.
      const bimModelsSnap = await db
        .collection('facilities')
        .doc(facilityId)
        .collection('bimModels')
        .where('status', '==', 'ready')
        .get();
      const activeBimModelIds = bimModelsSnap.docs.map((d) => d.id);

      if (activeBimModelIds.length === 0) {
        await metaRef.set(
          { status: 'done', completedAt: Timestamp.now(), itemCount: 0 },
          { merge: true },
        );
        return { itemCount: 0 };
      }

      // Firestore whereIn supports up to 30 values per query.
      const docArrays = await Promise.all(
        chunk(activeBimModelIds, 30).map((ids) => equipRef.where('bimModelId', 'in', ids).get().then((s) => s.docs)),
      );
      equipmentDocs = docArrays.flat();
    }

    const equipment = equipmentDocs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        name: d.name || '',
        typeName: d.typeName || d.type || '',
        category: d.category || 'Unknown',
      };
    });

    if (equipment.length === 0) {
      await metaRef.set({
        status: 'done',
        completedAt: Timestamp.now(),
        itemCount: 0,
      }, { merge: true });
      return { itemCount: 0 };
    }

    const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
    const vertexAI = new VertexAI({ project: projectId, location: 'us-central1' });

    const analysisRef = db.collection('facilities').doc(facilityId).collection('aiPmAnalysis');
    const batchSize = 40;
    let totalWritten = 0;

    // Prune stale analysis documents BEFORE running AI so ghost rows are
    // cleared even if the AI phase later times out.  Doing this first also
    // keeps the UI count accurate as new results stream in.
    const currentIds = new Set(equipment.map((e) => e.id));
    const preSnap = await analysisRef.get();
    const staleDocs = preSnap.docs.filter(
      (d) => d.id !== '_meta' && !currentIds.has(d.id),
    );
    console.log(
      'analyzeEquipmentList cleanup:'
      + ` equipment=${equipment.length},`
      + ` existing=${preSnap.docs.length},`
      + ` stale=${staleDocs.length}`,
    );
    for (const staleBatch of chunk(staleDocs, 500)) {
      const delBatch = db.batch();
      staleBatch.forEach((d) => delBatch.delete(d.ref));
      // eslint-disable-next-line no-await-in-loop
      await delBatch.commit();
    }
    console.log(`analyzeEquipmentList cleanup: deleted ${staleDocs.length} stale docs`);

    for (let i = 0; i < equipment.length; i += batchSize) {
      const eqChunk = equipment.slice(i, i + batchSize);
      let results;

      try {
        // eslint-disable-next-line no-await-in-loop
        results = await analyzeEquipmentBatch(vertexAI, eqChunk);
      } catch (aiErr) {
        console.warn(`AI batch ${i / batchSize} failed, using fallback:`, aiErr.message);
        results = eqChunk.map((e) => {
          const tmpl = TEMPLATE_SEED[e.typeName];
          return {
            id: e.id,
            frequencyMonths: tmpl ? tmpl.frequencyMonths : 12,
            reason: tmpl ? tmpl.reason : `Routine inspection and servicing of ${e.typeName || e.name}`,
            tools: [],
            estimatedHours: 1,
            spares: [],
          };
        });
      }

      const writeBatch = db.batch();
      results.forEach((r, idx) => {
        const eq = eqChunk[idx];
        if (!eq) return;
        const docRef = analysisRef.doc(eq.id);
        writeBatch.set(docRef, {
          facilityId,
          equipmentId: eq.id,
          equipmentName: eq.name,
          category: eq.category,
          typeName: eq.typeName,
          aiFrequencyMonths: Math.max(1, Math.min(60, Number(r.frequencyMonths) || 12)),
          aiReason: String(r.reason || '').slice(0, 300),
          aiTools: Array.isArray(r.tools) ? r.tools.slice(0, 5).map(String) : [],
          aiEstimatedHours: Math.min(8, Math.max(0.25, Number(r.estimatedHours) || 1)),
          aiSpares: Array.isArray(r.spares) ? r.spares.slice(0, 5).map(String) : [],
          editedFrequencyMonths: null,
          editedReason: null,
          editedTools: null,
          editedEstimatedHours: null,
          editedSpares: null,
          editedCategory: null,
          aiGenerated: true,
          verificationStatus: 'draft',
          verifiedBy: null,
          verifiedAt: null,
          publishedAt: null,
          createdAt: Timestamp.now(),
        }, { merge: true });
      });
      // eslint-disable-next-line no-await-in-loop
      await writeBatch.commit();
      totalWritten += eqChunk.length;
    }

    await metaRef.set(
      { status: 'done', completedAt: Timestamp.now(), itemCount: totalWritten },
      { merge: true },
    );
    return { itemCount: totalWritten };
  } catch (error) {
    console.error('analyzeEquipmentList error:', error);
    await metaRef.set(
      { status: 'failed', errorMessage: String(error.message || error), completedAt: Timestamp.now() },
      { merge: true },
    ).catch(() => {});
    throw new HttpsError('internal', `Analysis failed: ${error.message}`);
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PM Schedule Response — counter-notify admin/technician when client responds
// ─────────────────────────────────────────────────────────────────────────────

exports.onPmScheduleResponseCreated = onDocumentCreated(
  'facilities/{facilityId}/pmScheduleResponses/{taskId}',
  async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const { facilityId, taskId } = event.params;
    const data = snap.data();
    const {
      clientUid, clientAction, equipmentName, plannedDate, newDate,
    } = data;

    const newDateStr = newDate ? new Date(newDate.toDate()).toDateString() : 'a new date';
    const actionLabel = clientAction === 'accepted'
      ? 'accepted the planned date'
      : `rescheduled to ${newDateStr}`;

    const clientDoc = await db.collection('Users').doc(clientUid).get();
    const clientName = clientDoc.exists ? (clientDoc.data().name || 'Client') : 'Client';

    const title = `PM ${clientAction === 'accepted' ? 'Confirmed' : 'Rescheduled'}`;
    const body = `${clientName} ${actionLabel} for ${equipmentName} maintenance.`;

    const [adminSnap, techSnap] = await Promise.all([
      db.collection('Admins').where('facilityId', '==', facilityId).get(),
      db.collection('Technicians').where('facilityId', '==', facilityId).get(),
    ]);

    const targetUids = [
      ...adminSnap.docs.map((d) => d.id),
      ...techSnap.docs.map((d) => d.id),
    ].filter((uid, i, arr) => arr.indexOf(uid) === i);

    if (targetUids.length === 0) return null;

    const tokens = (
      await Promise.all(
        targetUids.map(async (uid) => {
          const userDoc = await db.collection('Users').doc(uid).get();
          return userDoc.exists ? userDoc.data().fcmToken : null;
        }),
      )
    ).filter(Boolean);

    const digestChunkSize = 240;
    for (let i = 0; i < targetUids.length; i += digestChunkSize) {
      const digestBatch = db.batch(); // eslint-disable-line no-await-in-loop
      const digestChunk = targetUids.slice(i, i + digestChunkSize);
      digestChunk.forEach((uid) => {
        const parentRef = db.collection('NotificationDigests').doc(uid);
        const itemRef = parentRef.collection('items').doc();
        digestBatch.set(parentRef, { unreadCount: FieldValue.increment(1) }, { merge: true });
        digestBatch.set(itemRef, {
          userId: uid,
          title,
          body,
          type: 'pm_schedule_response',
          priority: 'normal',
          data: {
            facilityId,
            taskId,
            equipmentName,
            clientAction,
            effectiveDate: (newDate || plannedDate)?.toDate().toISOString(),
          },
          createdAt: Timestamp.now(),
          readAt: null,
          deliveredAt: Timestamp.now(),
        });
      });
      await digestBatch.commit(); // eslint-disable-line no-await-in-loop
    }

    if (tokens.length > 0) {
      await messaging.sendEachForMulticast({
        tokens,
        notification: { title, body },
        data: { type: 'pm_schedule_response', facilityId, taskId },
        android: { priority: 'normal' },
        apns: { payload: { aps: { sound: 'default' } } },
      });
    }

    await snap.ref.update({ counterNotifiedAt: Timestamp.now() });
    return null;
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// PM Task Completion — write history, recalculate next due, notify client
// ─────────────────────────────────────────────────────────────────────────────

function addMonthsDate(date, months) {
  const result = new Date(date);
  result.setMonth(result.getMonth() + months);
  return result;
}

exports.onPmTaskStatusChanged = onDocumentUpdated(
  'facilities/{facilityId}/preventive_maintenance/{taskId}',
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();

    if (before.status === after.status) return null;

    const { facilityId, taskId } = event.params;
    const taskRef = event.data.after.ref;

    // ── Notify client on inProgress ──────────────────────────────────────────
    if (after.status === 'inProgress' && before.status !== 'inProgress') {
      const clientSnap = await db
        .collection('facilities').doc(facilityId).collection('clientLinks')
        .where('active', '==', true)
        .get();

      const clientUids = clientSnap.docs.map((d) => d.id);
      if (clientUids.length === 0) return null;

      const eqName = after.equipmentName || after.name || 'Equipment';
      const startTitle = 'Maintenance Started';
      const startBody = `Maintenance on ${eqName} has started.`;

      const startBatch = db.batch();
      clientUids.forEach((uid) => {
        const parentRef = db.collection('NotificationDigests').doc(uid);
        const itemRef = parentRef.collection('items').doc();
        startBatch.set(parentRef, { unreadCount: FieldValue.increment(1) }, { merge: true });
        startBatch.set(itemRef, {
          userId: uid,
          title: startTitle,
          body: startBody,
          type: 'pm_started',
          priority: 'normal',
          data: { facilityId, taskId, equipmentName: eqName },
          createdAt: Timestamp.now(),
          readAt: null,
          deliveredAt: Timestamp.now(),
        });
      });
      await startBatch.commit();

      const clientTokens = (
        await Promise.all(
          clientUids.map(async (uid) => {
            const userDoc = await db.collection('Users').doc(uid).get();
            return userDoc.exists ? userDoc.data().fcmToken : null;
          }),
        )
      ).filter(Boolean);

      if (clientTokens.length > 0) {
        await messaging.sendEachForMulticast({
          tokens: clientTokens,
          notification: { title: startTitle, body: startBody },
          data: { type: 'pm_started', facilityId, taskId },
          android: { priority: 'normal' },
          apns: { payload: { aps: { sound: 'default' } } },
        });
      }
      return null;
    }

    // ── On completion: history record + next due + notify client ─────────────
    if (after.status !== 'completed' || before.status === 'completed') return null;

    const completedAt = after.completedAt ? after.completedAt.toDate() : new Date();
    const frequencyMonths = after.frequencyMonths || 12;
    const equipmentId = after.equipmentId || after.bimGlobalId || taskId;
    const eqName = after.equipmentName || after.name || 'Equipment';

    // Determine whether this task was rescheduled by the client.
    let clientApproved = false;
    let rescheduled = false;
    let previousScheduledDate = null;
    const responseRef = db
      .collection('facilities').doc(facilityId)
      .collection('pmScheduleResponses').doc(taskId);
    const responseSnap = await responseRef.get();

    if (responseSnap.exists) {
      const rData = responseSnap.data();
      clientApproved = rData.clientAction === 'accepted' || rData.clientAction === 'rescheduled';
      rescheduled = rData.clientAction === 'rescheduled';
      previousScheduledDate = rescheduled ? (rData.plannedDate || null) : null;
    }

    const nextDueDate = addMonthsDate(completedAt, frequencyMonths);

    // Write history record.
    const historyRef = db
      .collection('facilities')
      .doc(facilityId)
      .collection('equipment')
      .doc(equipmentId)
      .collection('maintenanceHistory')
      .doc();

    const completedByUid = after.completedBy || after.assignedTo || '';
    let completedByName = 'Unknown';
    if (completedByUid) {
      const userDoc = await db.collection('Users').doc(completedByUid).get();
      if (userDoc.exists) completedByName = userDoc.data().name || completedByUid;
    }

    const historyBatch = db.batch();
    historyBatch.set(historyRef, {
      facilityId,
      equipmentId,
      taskId,
      scheduledDate: after.dueDate || Timestamp.fromDate(completedAt),
      actualDate: Timestamp.fromDate(completedAt),
      completedByUid,
      completedByName,
      notes: after.completionNotes || after.notes || '',
      clientApproved,
      rescheduled,
      previousScheduledDate,
      nextDueDate: Timestamp.fromDate(nextDueDate),
      createdAt: Timestamp.now(),
    });

    // Reset PM task for next cycle.
    historyBatch.update(taskRef, {
      dueDate: Timestamp.fromDate(nextDueDate),
      scheduledDate: after.dueDate || null,
      actualDate: Timestamp.fromDate(completedAt),
      status: 'pending',
      notifiedAt: null,
      alertedAt: null,
      dueTodayNotifiedAt: null,
    });

    await historyBatch.commit();

    // Notify client of completion.
    const clientSnap = await db
      .collection('facilities').doc(facilityId).collection('clientLinks')
      .where('active', '==', true)
      .get();

    const clientUids = clientSnap.docs.map((d) => d.id);
    if (clientUids.length === 0) return null;

    const compTitle = 'Maintenance Completed';
    const compBody = `Maintenance on ${eqName} completed. `
      + `Next scheduled: ${nextDueDate.toDateString()}.`;

    const compBatch = db.batch();
    clientUids.forEach((uid) => {
      const parentRef = db.collection('NotificationDigests').doc(uid);
      const itemRef = parentRef.collection('items').doc();
      compBatch.set(parentRef, { unreadCount: FieldValue.increment(1) }, { merge: true });
      compBatch.set(itemRef, {
        userId: uid,
        title: compTitle,
        body: compBody,
        type: 'pm_completed',
        priority: 'normal',
        data: {
          facilityId,
          taskId,
          equipmentName: eqName,
          nextDueDate: nextDueDate.toISOString(),
        },
        createdAt: Timestamp.now(),
        readAt: null,
        deliveredAt: Timestamp.now(),
      });
    });
    await compBatch.commit();

    const clientTokens = (
      await Promise.all(
        clientUids.map(async (uid) => {
          const userDoc = await db.collection('Users').doc(uid).get();
          return userDoc.exists ? userDoc.data().fcmToken : null;
        }),
      )
    ).filter(Boolean);

    if (clientTokens.length > 0) {
      await messaging.sendEachForMulticast({
        tokens: clientTokens,
        notification: { title: compTitle, body: compBody },
        data: {
          type: 'pm_completed',
          facilityId,
          taskId,
          nextDueDate: nextDueDate.toISOString(),
        },
        android: { priority: 'normal' },
        apns: { payload: { aps: { sound: 'default' } } },
      });
    }

    return null;
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// One-time backfill of legacy global Maintenance_Tasks/TaskProgress into a facility's
// facilities/{facilityId}/preventive_maintenance subcollection. See functions/migrations/
// backfillPreventiveMaintenance.js for details.
const { migrateLegacyMaintenanceData } = require('./migrations/backfillPreventiveMaintenance');

exports.migrateLegacyMaintenanceData = migrateLegacyMaintenanceData;
