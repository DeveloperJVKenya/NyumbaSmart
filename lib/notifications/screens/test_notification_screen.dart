import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/models/delivery_log.dart';
import 'package:cmms/notifications/providers/notification_providers.dart';
import 'package:cmms/notifications/screens/notification_delivery_stats_screen.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

/// Sends a real push straight to the caller's own device(s) via the `sendTestNotification` Cloud
/// Function — the same delivery path (FCM -> system tray / background handler) real due/alert/
/// custom notifications use, so a successful test here verifies the whole pipeline end-to-end
/// regardless of whether the app is open, backgrounded, or fully closed.
class TestNotificationScreen extends ConsumerStatefulWidget {
  const TestNotificationScreen({super.key});

  @override
  ConsumerState<TestNotificationScreen> createState() => _TestNotificationScreenState();
}

class _TestNotificationScreenState extends ConsumerState<TestNotificationScreen> {
  bool _isSending = false;
  String? _resultMessage;
  bool _resultIsError = false;
  List<DeliveryRecipient>? _lastRecipients;

  @override
  Widget build(BuildContext context) {
    final roleAsync = ref.watch(currentUserRoleProvider);
    final canViewDeliveryLogs = roleAsync.maybeWhen(
      data: (info) => info.isDeveloper || info.roleLabel == 'Admin',
      orElse: () => false,
    );

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Test Notification', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
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
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.science_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sends a test push directly to your own signed-in device(s) through the same '
                    'Cloud Function delivery path as real maintenance notifications. On web, keep '
                    'this tab in the background (switch tabs) to see the OS-level push — a '
                    'foregrounded tab shows it as an in-app banner and in Notifications instead.',
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppGradientButton(
            label: _isSending ? 'Sending...' : 'Send Test Notification',
            icon: Icons.send_rounded,
            isLoading: _isSending,
            onPressed: _isSending ? null : _send,
          ),
          if (_resultMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _resultMessage!,
              style: GoogleFonts.poppins(color: _resultIsError ? AppColors.error : AppColors.success, fontWeight: FontWeight.w600),
            ),
          ],
          if (_lastRecipients != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Recipients', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            ..._lastRecipients!.map(_recipientTile),
          ],
          if (canViewDeliveryLogs) ...[
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationDeliveryStatsScreen())),
              icon: const Icon(Icons.query_stats_rounded),
              label: const Text('View All Delivery Stats & Recipients'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _recipientTile(DeliveryRecipient r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
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
              ],
            ),
          ),
          if (r.platform != null)
            Text(r.platform!, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Future<void> _send() async {
    setState(() {
      _isSending = true;
      _resultMessage = null;
      _lastRecipients = null;
    });
    try {
      final result = await ref.read(notificationServiceProvider).sendTestNotification();
      final sentCount = result['sentCount'] ?? 0;
      final rawRecipients = result['recipients'] as List<dynamic>? ?? [];
      setState(() {
        _resultIsError = sentCount == 0;
        _resultMessage = sentCount > 0
            ? 'Sent to $sentCount device${sentCount == 1 ? '' : 's'} — check your notification tray.'
            : 'No registered device found for this account (no FCM token on file).';
        _lastRecipients = rawRecipients.map((e) => DeliveryRecipient.fromMap(Map<String, dynamic>.from(e))).toList();
      });
    } catch (e) {
      setState(() {
        _resultIsError = true;
        _resultMessage = 'Error: $e';
      });
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}
