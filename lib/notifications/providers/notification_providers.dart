import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cmms/notifications/models/digest_item.dart';
import 'package:cmms/notifications/models/engagement_stats.dart';
import 'package:cmms/notifications/models/facility_notification.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/providers/auth_providers.dart';

/// Riverpod home for the consolidated notifications pipeline. Plain `Provider`/`StreamProvider`
/// declarations to match `lib/providers/auth_providers.dart`'s existing style — this repo has no
/// `riverpod_generator`/`@riverpod` codegen anywhere, so introducing one here would be a second,
/// inconsistent DI convention for a single-provider-file codebase.

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

/// The signed-in user's digest feed — the WhatsApp-style grouped notifications a user actually
/// sees, newest first. Empty when signed out.
final userDigestsProvider = StreamProvider.autoDispose<List<DigestItem>>((ref) {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return const Stream.empty();
  return ref.watch(notificationServiceProvider).watchDigests(userId);
});

/// Count of unread digests — drives badge counts in the app bar/drawer and the floating banner.
final unreadDigestCountProvider = StreamProvider.autoDispose<int>((ref) {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return Stream.value(0);
  return ref.watch(notificationServiceProvider).watchUnreadCount(userId);
});

/// The most recent unread digest, if any — what the floating banner shows.
final latestUnreadDigestProvider = Provider.autoDispose<DigestItem?>((ref) {
  final digests = ref.watch(userDigestsProvider).value ?? const [];
  for (final digest in digests) {
    if (!digest.isRead) return digest;
  }
  return null;
});

/// Developer/admin-only read/open engagement summary — see `NotificationService.fetchEngagementStats`.
final engagementStatsProvider = FutureProvider.autoDispose<EngagementStats?>((ref) {
  return ref.watch(notificationServiceProvider).fetchEngagementStats();
});

/// A facility's notification audit trail (`facilities/{facilityId}/notifications`) — used by the
/// facility-scoped notification history view.
final facilityNotificationsProvider = StreamProvider.family.autoDispose<List<FacilityNotification>, String>((ref, facilityId) {
  return ref.watch(notificationServiceProvider).watchFacilityNotifications(facilityId);
});
