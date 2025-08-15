const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { setGlobalOptions } = require('firebase-functions/v2');

initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// Set global options for all functions
setGlobalOptions({ region: 'Africa/Nairobi' });

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
            if (
              userData.fcmToken
              && userData.notificationsEnabled !== false
              && userData.organization === 'JV Almacis'
            ) {
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

    // Prepare FCM message
    const message = {
      notification: {
        title,
        body,
      },
      data: {
        notificationId,
        priority,
        type: 'system',
        ...notificationData,
      },
      android: {
        notification: {
          channelId: priority === 'urgent' ? 'maintenance_urgent' : 'maintenance_normal',
          priority: priority === 'urgent' ? 'high' : 'default',
          sound: 'default',
          vibrationPattern: priority === 'urgent' ? [0, 500, 200, 500] : [0, 200],
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
        const response = await messaging.sendMulticast({
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
          if (userData.fcmToken && userData.notificationsEnabled !== false
            && userData.organization === 'JV Almacis') {
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

  // Prepare FCM message
  const message = {
    notification: {
      title,
      body,
    },
    data: {
      notificationId,
      priority,
      type: 'system',
      ...extraData,
    },
    android: {
      notification: {
        channelId: priority === 'urgent' ? 'maintenance_urgent' : 'maintenance_normal',
        priority: priority === 'urgent' ? 'high' : 'default',
        sound: 'default',
        vibrationPattern: priority === 'urgent' ? [0, 500, 200, 500] : [0, 200],
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
      const response = await messaging.sendMulticast({
        ...message,
        tokens,
      });

      totalSent += response.successCount;
      totalFailed += response.failureCount;

      console.log(
        `Batch ${Math.floor(i / fcmBatchSize) + 1}: `
          + `${response.successCount}/${tokens.length} messages sent successfully`,
      );
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

// Scheduled function to check for due notifications
exports.checkDueNotifications = onSchedule(
  {
    schedule: '0 9,11 * * *',
    timeZone: 'Africa/Nairobi',
    memory: '256MiB',
    timeoutSeconds: 60,
  },
  async () => {
    try {
      console.log('Checking for due notifications...');
      const now = new Date();
      const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());

      // Get due notifications that haven't been triggered
      const dueNotificationsSnapshot = await db
        .collection('SystemNotifications')
        .where('notificationDate', '<=', Timestamp.fromDate(today))
        .where('isTriggered', '==', false)
        .where('isActive', '==', true)
        .get();

      console.log(`Found ${dueNotificationsSnapshot.docs.length} due notifications`);

      for (const doc of dueNotificationsSnapshot.docs) {
        const notification = doc.data();

        // Get all users from JV Almacis organization
        const usersSnapshot = await db
          .collection('Users')
          .where('organization', '==', 'JV Almacis')
          .where('notificationsEnabled', '!=', false)
          .get();

        const targetUsers = usersSnapshot.docs.map((userDoc) => userDoc.id);

        if (targetUsers.length > 0) {
          // Send notification using internal helper function
          await sendNotificationInternal(
            {
              title: notification.title,
              body: notification.body,
              notificationId: doc.id,
              priority: notification.priority || 'normal',
              data: {
                type: 'system',
                categories: notification.categories || [],
                taskCount: notification.taskCount || 0,
              },
            },
            targetUsers,
          );
        }
      }

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
