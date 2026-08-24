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
  Widget build(BuildContext context) {
    final digestsAsync = ref.watch(userDigestsProvider);
    final roleAsync = ref.watch(currentUserRoleProvider);
    final canViewDeliveryLogs = roleAsync.maybeWhen(
      data: (info) => info.isDeveloper || info.roleLabel == 'Admin',
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Notifications', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
        actions: [
          if (canViewDeliveryLogs)
            IconButton(
              icon: const Icon(Icons.query_stats_rounded, color: Colors.white),
              tooltip: 'Delivery & Recipients',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationDeliveryStatsScreen())),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddCustomNotificationScreen())),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_alert_rounded, color: Colors.white),
        label: Text('New Notification', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: digestsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error loading notifications: $e', style: GoogleFonts.poppins(color: AppColors.error))),
              data: (digests) {
                final filtered = _applyFilter(digests);
                if (filtered.isEmpty) return _emptyState();

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
                    return ListView.separated(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? AppSpacing.md : AppSpacing.xl,
                        AppSpacing.md,
                        isMobile ? AppSpacing.md : AppSpacing.xl,
                        AppSpacing.xxl,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) => _digestCard(filtered[index]),
                    );
                  },
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

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _filterChip('All', _DigestFilter.all),
            const SizedBox(width: 8),
            _filterChip('Unread', _DigestFilter.unread),
            const SizedBox(width: 8),
            _filterChip('Alerts', _DigestFilter.alerts),
            const SizedBox(width: 8),
            _filterChip('Custom', _DigestFilter.custom),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, _DigestFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textPrimary)),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: BorderSide.none,
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_off_rounded, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('No notifications', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _digestCard(DigestItem digest) {
    final isUrgent = digest.isUrgent;
    final accent = isUrgent ? AppColors.error : AppColors.primary;

    return Material(
      color: digest.isRead ? AppColors.card : AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _openDigest(digest),
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
    );
  }

  void _openDigest(DigestItem digest) {
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId != null && !digest.isRead) {
      ref.read(notificationServiceProvider).markDigestRead(userId, digest.id);
    }
    Navigator.push(context, MaterialPageRoute(builder: (context) => NotificationDetailScreen(digest: digest)));
  }
}
