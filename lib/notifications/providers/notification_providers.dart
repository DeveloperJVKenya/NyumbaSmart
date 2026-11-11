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

/// How many digest items to load. Incremented by the notifications screen for "load more" (#8).
class _DigestPageSizeNotifier extends Notifier<int> {
  @override
  int build() => 25;
  void loadMore() => state += 25;
}

final digestPageSizeProvider = NotifierProvider.autoDispose<_DigestPageSizeNotifier, int>(
  _DigestPageSizeNotifier.new,
);

/// The signed-in user's digest feed — the WhatsApp-style grouped notifications a user actually
/// sees, newest first. Empty when signed out. Respects [digestPageSizeProvider] for pagination.
final userDigestsProvider = StreamProvider.autoDispose<List<DigestItem>>((ref) {
  final userId = ref.watch(authStateProvider).value?.uid;
  if (userId == null) return const Stream.empty();
  final limit = ref.watch(digestPageSizeProvider);
  return ref.watch(notificationServiceProvider).watchDigests(userId, limit: limit);
});

/// Count of unread digests — drives badge counts in the app bar/drawer and the floating banner.
/// Reads the `unreadCount` integer field on `NotificationDigests/{userId}` written by the Cloud
/// Function on each digest write and decremented by the client on mark-read (#2).
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

/// Set to true while [NotificationsScreen] is the top route — suppresses the floating banner (#14).
class _NotificationsScreenActiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  // ignore: use_setters_to_change_properties
  void setActive(bool value) => state = value;
}

final isNotificationsScreenActiveProvider = NotifierProvider<_NotificationsScreenActiveNotifier, bool>(
  _NotificationsScreenActiveNotifier.new,
);

/// Developer/admin-only read/open engagement summary — see `NotificationService.fetchEngagementStats`.
final engagementStatsProvider = FutureProvider.autoDispose<EngagementStats?>((ref) {
  return ref.watch(notificationServiceProvider).fetchEngagementStats();
});

/// A facility's notification audit trail (`facilities/{facilityId}/notifications`) — used by the
/// facility-scoped notification history view.
final facilityNotificationsProvider = StreamProvider.family.autoDispose<List<FacilityNotification>, String>((ref, facilityId) {
  return ref.watch(notificationServiceProvider).watchFacilityNotifications(facilityId);
});
