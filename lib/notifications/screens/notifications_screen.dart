import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cmms/notifications/models/digest_item.dart';
import 'package:cmms/notifications/providers/notification_providers.dart';
import 'package:cmms/notifications/screens/add_custom_notification_screen.dart';
import 'package:cmms/notifications/screens/notification_delivery_stats_screen.dart';
import 'package:cmms/notifications/screens/notification_detail_screen.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';

enum _DigestFilter { all, unread, alerts, custom }

/// The unified notification feed — every digest a user has received (due, alert, re-trigger,
/// custom), newest first. Replaces the previous System/Custom tabbed screens: both kinds now
/// live in the same `NotificationDigests` stream, distinguished by [DigestKind] instead of by
/// being separate collections.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _DigestFilter _filter = _DigestFilter.all;

  @override
  void initState() {
    super.initState();
    // Suppress the floating banner while this screen is open (#14).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(isNotificationsScreenActiveProvider.notifier).setActive(true);
    });
  }

  @override
  void dispose() {
    ref.read(isNotificationsScreenActiveProvider.notifier).setActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final digestsAsync = ref.watch(userDigestsProvider);
    final roleAsync = ref.watch(currentUserRoleProvider);
    final canViewDeliveryLogs = roleAsync.maybeWhen(
      data: (info) => info.isDeveloper || info.roleLabel == 'Admin',
      orElse: () => false,
    );
    final canCreateNotification = roleAsync.maybeWhen(
      data: (info) => info.isDeveloper || info.roleLabel == 'Admin' || info.roleLabel == 'Technician',
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Notifications', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final hasUnread = ref.watch(userDigestsProvider).maybeWhen(
                data: (list) => list.any((d) => !d.isRead),
                orElse: () => false,
              );
              if (!hasUnread) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.done_all_rounded, color: Colors.white),
                tooltip: 'Mark all as read',
                onPressed: () {
                  final userId = ref.read(authStateProvider).value?.uid;
                  if (userId != null) ref.read(notificationServiceProvider).markAllDigestsRead(userId);
                },
              );
            },
          ),
          // Clear read digests (#10)
          Consumer(
            builder: (context, ref, _) {
              final hasRead = ref.watch(userDigestsProvider).maybeWhen(
                data: (list) => list.any((d) => d.isRead),
                orElse: () => false,
              );
              if (!hasRead) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white70),
                tooltip: 'Clear read notifications',
                onPressed: () => _confirmClearRead(),
              );
            },
          ),
          if (canViewDeliveryLogs)
            IconButton(
              icon: const Icon(Icons.query_stats_rounded, color: Colors.white),
              tooltip: 'Delivery & Recipients',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationDeliveryStatsScreen())),
            ),
        ],
      ),
      floatingActionButton: canCreateNotification
          ? FloatingActionButton.extended(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddCustomNotificationScreen())),
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
              label: Text('New Notification', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
            )
          : null,
      body: Column(
        children: [
          _buildFilterBar(digestsAsync.value ?? []),
          Expanded(
            child: digestsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error loading notifications: $e', style: GoogleFonts.poppins(color: AppColors.error))),
              data: (digests) {
                final filtered = _applyFilter(digests);

                return RefreshIndicator(
                  // Pull-to-refresh forces a provider rebuild (#7).
                  onRefresh: () async => ref.invalidate(userDigestsProvider),
                  color: AppColors.primary,
                  child: filtered.isEmpty
                      ? _emptyState(digests)
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
                            return ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.fromLTRB(
                                isMobile ? AppSpacing.md : AppSpacing.xl,
                                AppSpacing.md,
                                isMobile ? AppSpacing.md : AppSpacing.xl,
                                AppSpacing.xxl,
                              ),
                              itemCount: filtered.length + 1,
                              itemBuilder: (context, index) {
                                if (index == filtered.length) {
                                  return _loadMoreFooter(digests.length);
                                }
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                                  child: _digestCard(filtered[index]),
                                );
                              },
                            );
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<DigestItem> _applyFilter(List<DigestItem> digests) {
    switch (_filter) {
      case _DigestFilter.unread:
        return digests.where((d) => !d.isRead).toList();
      case _DigestFilter.alerts:
        return digests.where((d) => d.isUrgent).toList();
      case _DigestFilter.custom:
        return digests.where((d) => d.kind == DigestKind.custom).toList();
      case _DigestFilter.all:
        return digests;
    }
  }

  // Filter bar with item counts per category (#12).
  Widget _buildFilterBar(List<DigestItem> allDigests) {
    final unreadCount = allDigests.where((d) => !d.isRead).length;
    final alertCount = allDigests.where((d) => d.isUrgent).length;
    final customCount = allDigests.where((d) => d.kind == DigestKind.custom).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('All', allDigests.length, _DigestFilter.all),
            const SizedBox(width: 8),
            _filterChip('Unread', unreadCount, _DigestFilter.unread),
            const SizedBox(width: 8),
            _filterChip('Alerts', alertCount, _DigestFilter.alerts),
            const SizedBox(width: 8),
            _filterChip('Custom', customCount, _DigestFilter.custom),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, int count, _DigestFilter value) {
    final selected = _filter == value;
    final displayLabel = count > 0 ? '$label ($count)' : label;
    return ChoiceChip(
      label: Text(displayLabel, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textPrimary)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: BorderSide.none,
    );
  }

  Widget _emptyState(List<DigestItem> allDigests) {
    final hasItemsButFiltered = allDigests.isNotEmpty;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.notifications_off_rounded, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  hasItemsButFiltered ? 'No notifications match this filter' : 'No notifications',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                ),
                if (hasItemsButFiltered) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => _filter = _DigestFilter.all),
                    child: Text('Show all', style: GoogleFonts.poppins(color: AppColors.primary)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Load-more footer for pagination (#8).
  Widget _loadMoreFooter(int loadedCount) {
    final pageSize = ref.watch(digestPageSizeProvider);
    final atLimit = loadedCount >= pageSize;
    if (!atLimit) return const SizedBox(height: AppSpacing.xl);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: () => ref.read(digestPageSizeProvider.notifier).loadMore(),
          icon: const Icon(Icons.expand_more_rounded),
          label: Text('Load more', style: GoogleFonts.poppins()),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
          ),
        ),
      ),
    );
  }

  Widget _digestCard(DigestItem digest) {
    final isUrgent = digest.isUrgent;
    final accent = isUrgent ? AppColors.error : AppColors.primary;

    // Swipe right → mark read; swipe left → delete (#9, #10).
    return Dismissible(
      key: ValueKey(digest.id),
      background: _swipeBackground(
        color: AppColors.success,
        icon: Icons.mark_email_read_rounded,
        alignment: Alignment.centerLeft,
      ),
      secondaryBackground: _swipeBackground(
        color: AppColors.error,
        icon: Icons.delete_outline_rounded,
        alignment: Alignment.centerRight,
      ),
      confirmDismiss: (direction) async {
        final userId = ref.read(authStateProvider).value?.uid;
        if (userId == null) return false;
        if (direction == DismissDirection.startToEnd) {
          // Swipe right → mark read (don't actually dismiss the tile).
          if (!digest.isRead) {
            await ref.read(notificationServiceProvider).markDigestRead(userId, digest.id);
          }
          return false; // keep the tile; the stream will update it
        } else {
          // Swipe left → confirm delete.
          return await _confirmDeleteDigest(digest);
        }
      },
      onDismissed: (_) {
        final userId = ref.read(authStateProvider).value?.uid;
        if (userId != null) {
          ref.read(notificationServiceProvider).deleteDigest(
            userId,
            digest.id,
            wasUnread: !digest.isRead,
          );
        }
      },
      child: Material(
        color: digest.isRead ? AppColors.card : AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () => _openDigest(digest),
          onLongPress: () => _showDigestOptions(digest),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: accent.withValues(alpha: digest.isRead ? 0.1 : 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(
                    digest.kind == DigestKind.test
                        ? Icons.science_rounded
                        : digest.kind == DigestKind.custom
                            ? Icons.campaign_rounded
                            : (isUrgent ? Icons.warning_rounded : Icons.build_circle_rounded),
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(digest.title, style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: digest.isRead ? FontWeight.w500 : FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: Text(digest.kind.label, style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: accent)),
                      ),
                      const SizedBox(height: 5),
                      Text(digest.body, style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Text(DateFormat('MMM dd, yyyy · h:mm a').format(digest.createdAt), style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.8))),
                    ],
                  ),
                ),
                if (!digest.isRead)
                  Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground({required Color color, required IconData icon, required Alignment alignment}) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Icon(icon, color: color),
    );
  }

  // Long-press overflow menu for a single digest (#10).
  void _showDigestOptions(DigestItem digest) {
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(digest.isRead ? Icons.mark_email_unread_rounded : Icons.mark_email_read_rounded, color: AppColors.primary),
              title: Text(digest.isRead ? 'Mark as unread' : 'Mark as read', style: GoogleFonts.poppins()),
              onTap: () {
                Navigator.pop(ctx);
                if (digest.isRead) {
                  ref.read(notificationServiceProvider).markDigestUnread(userId, digest.id);
                } else {
                  ref.read(notificationServiceProvider).markDigestRead(userId, digest.id);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              title: Text('Delete', style: GoogleFonts.poppins(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await _confirmDeleteDigest(digest);
                if (confirmed) {
                  if (mounted) {
                    ref.read(notificationServiceProvider).deleteDigest(userId, digest.id, wasUnread: !digest.isRead);
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteDigest(DigestItem digest) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete notification?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('This cannot be undone.', style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: GoogleFonts.poppins())),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: GoogleFonts.poppins(color: AppColors.error)),
          ),
        ],
      ),
    ) ?? false;
  }

  void _confirmClearRead() {
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Clear read notifications?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('All read notifications will be permanently deleted.', style: GoogleFonts.poppins()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.poppins())),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final count = await ref.read(notificationServiceProvider).clearReadDigests(userId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Cleared $count notification${count == 1 ? '' : 's'}', style: GoogleFonts.poppins())),
                );
              }
            },
            child: Text('Clear', style: GoogleFonts.poppins(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  void _openDigest(DigestItem digest) {
    final userId = ref.read(authStateProvider).value?.uid;
    DigestItem displayed = digest;
    if (userId != null && !digest.isRead) {
      ref.read(notificationServiceProvider).markDigestRead(userId, digest.id);
      displayed = digest.copyWith(readAt: DateTime.now());
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => NotificationDetailScreen(digest: displayed)));
  }
}
