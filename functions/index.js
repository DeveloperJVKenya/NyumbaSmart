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

// Helper function to send notifications (internal use)
async function sendNotificationInternal(notificationData, targetUsers) {
  const {
    title, body, notificationId, priority = 'normal', data: extraData = {},
  } = notificationData;

  console.log(`Sending notification to ${targetUsers.length} users: ${title}`);

  // Get FCM tokens for target users
  const userTokens = [];
  const batchSize = 10;

  for (let i = 0; i < targetUsers.length; i += batchSize) {
    const batch = targetUsers.slice(i, i + batchSize);
    const batchPromises = batch.map(async (userId) => {
      try {
        const userDoc = await db.collection('Users').doc(userId).get();
        if (userDoc.exists) {
          const userData = userDoc.data();
          // Same as sendSystemNotification: trust the caller's already-scoped targetUsers
          // list instead of re-filtering to a single hardcoded organization.
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

      if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            const failedToken = batch[idx];
            console.error(`Failed to send to ${failedToken.userName} (${failedToken.userId}):`, resp.error);
            if (
              resp.error
              && (resp.error.code === 'messaging/registration-token-not-registered'
                || resp.error.code === 'messaging/invalid-registration-token')
            ) {
              db.collection('Users')
                .doc(failedToken.userId)
                .update({ fcmToken: FieldValue.delete() })
                .catch((err) => console.error('Error removing invalid token:', err));
            }
          }
        });
      }
    } catch (error) {
      console.error(`Error sending batch ${Math.floor(i / fcmBatchSize) + 1}:`, error);
      totalFailed += tokens.length;
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
    totalTargets: userTokens.length,
  };
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

// Sends the due/alert notification for one facility's batch of tasks: writes a summary doc to
// facilities/{facilityId}/notifications, pushes FCM to the contractor (JV Almacis), and marks
// each task's [markField] so this same due/alert cycle isn't re-sent on the next cron tick.
async function notifyFacilityTasks({
  facilityRef, tasks, targetUsers, facilityName, isAlert, markField,
}) {
  const title = isAlert ? `Maintenance Alert — ${facilityName}` : `Maintenance Due — ${facilityName}`;
  const body = isAlert
    ? `${tasks.length} maintenance ${tasks.length === 1 ? 'task is' : 'tasks are'} due very soon at ${facilityName}`
    : `${tasks.length} maintenance ${tasks.length === 1 ? 'task needs' : 'tasks need'} attention at ${facilityName}`;

  const notificationRef = await facilityRef.collection('notifications').add({
    title,
    body,
    taskIds: tasks.map((t) => t.id),
    isAlert,
    createdAt: FieldValue.serverTimestamp(),
    readByUsers: [],
  });

  const result = await sendNotificationInternal(
    {
      title,
      body,
      notificationId: null,
      priority: isAlert ? 'urgent' : 'normal',
      data: { type: 'facility_pm', facilityId: facilityRef.id, notificationId: notificationRef.id },
    },
    targetUsers,
  );

  await notificationRef.update({
    sentCount: result.sentCount,
    failedCount: result.failedCount,
  });

  const batch = db.batch();
  for (const taskDoc of tasks) {
    batch.update(taskDoc.ref, { [markField]: FieldValue.serverTimestamp() });
  }
  await batch.commit();
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
    schedule: '0 9,11 * * *',
    timeZone: 'Africa/Nairobi',
    memory: '256MiB',
    timeoutSeconds: 120,
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

      let facilitiesNotified = 0;
      for (const [facilityId, bucket] of byFacility) {
        const hasWork = bucket.dueTasks.length > 0 || bucket.alertTasks.length > 0;
        if (hasWork && targetUsers.length > 0) {
          const facilityDoc = await db.collection('Facilities').doc(facilityId).get();
          const facilityName = facilityDoc.exists ? (facilityDoc.data().name || 'your facility') : 'your facility';

          if (bucket.dueTasks.length > 0) {
            await notifyFacilityTasks({
              facilityRef: bucket.facilityRef,
              tasks: bucket.dueTasks,
              targetUsers,
              facilityName,
              isAlert: false,
              markField: 'notifiedAt',
            });
          }
          if (bucket.alertTasks.length > 0) {
            await notifyFacilityTasks({
              facilityRef: bucket.facilityRef,
              tasks: bucket.alertTasks,
              targetUsers,
              facilityName,
              isAlert: true,
              markField: 'alertedAt',
            });
          }
          facilitiesNotified += 1;
        }
      }

      console.log(`checkDueNotifications complete: ${facilitiesNotified} facilities notified`);
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

// One-time backfill of legacy global Maintenance_Tasks/TaskProgress into a facility's
// facilities/{facilityId}/preventive_maintenance subcollection. See functions/migrations/
// backfillPreventiveMaintenance.js for details.
const { migrateLegacyMaintenanceData } = require('./migrations/backfillPreventiveMaintenance');

exports.migrateLegacyMaintenanceData = migrateLegacyMaintenanceData;
