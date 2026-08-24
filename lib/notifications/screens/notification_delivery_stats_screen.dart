import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cmms/notifications/models/delivery_log.dart';
import 'package:cmms/notifications/models/engagement_stats.dart';
import 'package:cmms/notifications/providers/notification_providers.dart';
import 'package:cmms/theme/app_theme.dart';

enum _StatsTab { delivery, engagement }

enum _KindFilter { all, system, custom, test }

extension on _KindFilter {
  bool matches(String kind) {
    switch (this) {
      case _KindFilter.all:
        return true;
      case _KindFilter.system:
        return kind == 'due_digest' || kind == 'alert_digest' || kind == 'retrigger';
      case _KindFilter.custom:
        return kind == 'custom';
      case _KindFilter.test:
        return kind == 'test';
    }
  }
}

String _kindLabel(String kind) {
  switch (kind) {
    case 'due_digest':
      return 'Due';
    case 'alert_digest':
      return 'Alert';
    case 'retrigger':
      return 'Reminder';
    case 'custom':
      return 'Custom';
    case 'test':
      return 'Test';
    default:
      return kind;
  }
}

/// Developer/admin-only audit view: every system (due/alert/reminder), custom, and test
/// notification ever sent, with aggregate sent/failed totals up front and a per-recipient
/// success/fail breakdown per send — answers "did this actually reach who it was supposed to,
/// and if not, why" for all three notification kinds in one place. Reads
/// `NotificationDeliveryLogs`, written by every `sendNotificationInternal` call in
/// functions/index.js (checkDueNotifications, onCustomNotificationCreated, sendTestNotification).
class NotificationDeliveryStatsScreen extends ConsumerStatefulWidget {
  const NotificationDeliveryStatsScreen({super.key});

  @override
  ConsumerState<NotificationDeliveryStatsScreen> createState() => _NotificationDeliveryStatsScreenState();
}

class _NotificationDeliveryStatsScreenState extends ConsumerState<NotificationDeliveryStatsScreen> {
  _StatsTab _tab = _StatsTab.delivery;
  _KindFilter _filter = _KindFilter.all;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Notification Analytics', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
            child: _tabBar(),
          ),
          Expanded(child: _tab == _StatsTab.delivery ? _deliveryView() : _engagementView()),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Row(
      children: [
        _tabChip('Delivery', _StatsTab.delivery),
        const SizedBox(width: 8),
        _tabChip('Engagement', _StatsTab.engagement),
      ],
    );
  }

  Widget _tabChip(String label, _StatsTab value) {
    final selected = _tab == value;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? Colors.white : AppColors.textPrimary)),
      selected: selected,
      onSelected: (_) => setState(() => _tab = value),
      selectedColor: AppColors.primary,
      backgroundColor: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      side: BorderSide.none,
    );
  }

  Widget _deliveryView() {
    return StreamBuilder<List<DeliveryLog>>(
      stream: ref.read(notificationServiceProvider).watchRecentDeliveryLogs(limit: 100),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading delivery logs: ${snapshot.error}', style: GoogleFonts.poppins(color: AppColors.error)));
        }
        final logs = snapshot.data ?? [];
        final filtered = logs.where((l) => _filter.matches(l.kind)).toList();

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _summaryRow(logs),
            const SizedBox(height: AppSpacing.md),
            _filterBar(),
            const SizedBox(height: AppSpacing.md),
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text('No sends yet for this filter.', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
                ),
              )
            else
              ...filtered.map(_logCard),
          ],
        );
      },
    );
  }

  Widget _engagementView() {
    final statsAsync = ref.watch(engagementStatsProvider);
    return statsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error loading engagement stats: $e', style: GoogleFonts.poppins(color: AppColors.error))),
      data: (stats) {
        if (stats == null) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No engagement data yet — the daily aggregation runs each night and will populate here after its first run.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text(
              'Last ${stats.windowDays} days${stats.computedAt != null ? ' · updated ${DateFormat('MMM dd, h:mm a').format(stats.computedAt!)}' : ''}',
              style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(child: _statTile('Sent', '${stats.total}', AppColors.primary, Icons.mark_email_unread_rounded)),
                const SizedBox(width: 8),
                Expanded(child: _statTile('Read rate', '${(stats.readRate * 100).toStringAsFixed(0)}%', AppColors.success, Icons.visibility_rounded)),
                const SizedBox(width: 8),
                Expanded(
                  child: _statTile(
                    'Avg time to read',
                    stats.avgMinutesToRead == null ? '—' : _formatMinutes(stats.avgMinutesToRead!),
                    AppColors.accent,
                    Icons.timer_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('By notification type', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            ...stats.kindBreakdown.map(_engagementKindCard),
          ],
        );
      },
    );
  }

  Widget _engagementKindCard(EngagementKindStat stat) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(_kindLabel(stat.kind), style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          Text(
            '${stat.read}/${stat.total} read (${(stat.readRate * 100).toStringAsFixed(0)}%)',
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (stat.avgMinutesToRead != null) ...[
            const SizedBox(width: 10),
            Text(_formatMinutes(stat.avgMinutesToRead!), style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
          ],
        ],
      ),
    );
  }

  String _formatMinutes(double minutes) {
    if (minutes < 60) return '${minutes.round()}m';
    final hours = minutes / 60;
    if (hours < 24) return '${hours.toStringAsFixed(1)}h';
    return '${(hours / 24).toStringAsFixed(1)}d';
  }

  Widget _summaryRow(List<DeliveryLog> logs) {
    final totalSent = logs.fold<int>(0, (sum, l) => sum + l.sentCount);
    final totalFailed = logs.fold<int>(0, (sum, l) => sum + l.failedCount);
    final totalRuns = logs.length;

    return Row(
      children: [
        Expanded(child: _statTile('Sends', '$totalRuns', AppColors.primary, Icons.campaign_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _statTile('Delivered', '$totalSent', AppColors.success, Icons.check_circle_rounded)),
        const SizedBox(width: 8),
        Expanded(child: _statTile('Failed', '$totalFailed', AppColors.error, Icons.error_rounded)),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _filterBar() {
    return Row(
      children: [
        _filterChip('All', _KindFilter.all),
        const SizedBox(width: 8),
        _filterChip('System', _KindFilter.system),
        const SizedBox(width: 8),
        _filterChip('Custom', _KindFilter.custom),
        const SizedBox(width: 8),
        _filterChip('Test', _KindFilter.test),
      ],
    );
  }

  Widget _filterChip(String label, _KindFilter value) {
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

  Widget _logCard(DeliveryLog log) {
    final hasFailures = log.failedCount > 0;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: (hasFailures ? AppColors.error : AppColors.textSecondary).withValues(alpha: 0.15)),
        ),
        child: ExpansionTile(
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: (hasFailures ? AppColors.error : AppColors.success).withValues(alpha: 0.12),
            child: Text(
              _kindLabel(log.kind).characters.first,
              style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.bold, color: hasFailures ? AppColors.error : AppColors.success),
            ),
          ),
          title: Text(log.title, style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          subtitle: Text(
            '${_kindLabel(log.kind)} · ${DateFormat('MMM dd, h:mm a').format(log.createdAt)} · '
            '${log.sentCount}/${log.totalTargets} delivered'
            '${hasFailures ? ' · ${log.failedCount} failed' : ''}',
            style: GoogleFonts.poppins(fontSize: 11.5, color: hasFailures ? AppColors.error : AppColors.textSecondary),
          ),
          children: log.recipients.isEmpty
              ? [Padding(padding: const EdgeInsets.all(12), child: Text('No recipients recorded.', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)))]
              : log.recipients.map((r) => _recipientTile(r, log.runId)).toList(),
        ),
      ),
    );
  }

  Widget _recipientTile(DeliveryRecipient r, String runId) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: (r.success ? AppColors.success : AppColors.error).withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(r.success ? Icons.check_circle_rounded : Icons.error_rounded, size: 16, color: r.success ? AppColors.success : AppColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.userName, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (!r.success && r.error != null)
                  Text(r.error!, style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.error)),
                if (r.success && runId.isNotEmpty) _receiptBadge(runId, r.userId),
              ],
            ),
          ),
          if (r.platform != null)
            Text(r.platform!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  /// FCM accepting a push for delivery isn't the same as the device actually getting it — a
  /// closed/offline device can sit queued for a while. This resolves that gap by checking the
  /// receipt the device itself writes back the moment it actually receives the push (see
  /// NotificationService.markDelivered).
  Widget _receiptBadge(String runId, String userId) {
    return FutureBuilder<DateTime?>(
      future: ref.read(notificationServiceProvider).fetchDeliveryReceipt(runId: runId, userId: userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Text('Checking device receipt…', style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.textSecondary));
        }
        final deliveredAt = snapshot.data;
        if (deliveredAt == null) {
          return Text(
            'Sent — not yet confirmed on device',
            style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
          );
        }
        return Text(
          'Confirmed received ${DateFormat('MMM dd, h:mm a').format(deliveredAt)}',
          style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.success, fontWeight: FontWeight.w600),
        );
      },
    );
  }
}
