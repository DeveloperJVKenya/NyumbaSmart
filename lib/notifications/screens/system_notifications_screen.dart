import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cmms/notifications/screens/notifications_screen.dart';
import 'package:cmms/services/pm_regeneration_service.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

/// Auto-notification settings: regenerates every facility's preventive-maintenance schedule from
/// a chosen start date (the same logic the Scope of Work screen uses on a per-facility upload —
/// see [PmRegenerationService]). Due/alert detection and delivery themselves are entirely
/// server-side (the hourly `checkDueNotifications` Cloud Function) — this screen no longer lists
/// or manages individual notifications, since that's now the unified feed in
/// [NotificationsScreen].
class SystemNotificationsScreen extends StatefulWidget {
  const SystemNotificationsScreen({super.key});

  @override
  State<SystemNotificationsScreen> createState() => _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState extends State<SystemNotificationsScreen> {
  bool _isRegenerating = false;
  DateTime _startDate = DateTime(DateTime.now().year, 1, 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('System Notifications', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_rounded, color: Colors.white),
            tooltip: 'View notifications',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen())),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 10))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(gradient: AppColors.primaryGradient, borderRadius: BorderRadius.circular(AppRadius.md)),
                            child: const Icon(Icons.event_repeat_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text('Regenerate Maintenance Schedule', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Recomputes every facility\'s task due dates from the chosen start date, walking each '
                        'task forward on its own frequency until it lands on a date that isn\'t in the past. '
                        'Due/alert notifications themselves are generated automatically every hour by the server '
                        '— this only affects when tasks are next due.',
                        style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _pickStartDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                              const SizedBox(width: 10),
                              Text('Fallback start date: ${DateFormat('MMMM dd, yyyy').format(_startDate)}', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      AppGradientButton(
                        label: _isRegenerating ? 'Regenerating...' : 'Regenerate All Facilities',
                        icon: Icons.refresh_rounded,
                        isLoading: _isRegenerating,
                        onPressed: _isRegenerating ? null : _regenerate,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _regenerate() async {
    setState(() => _isRegenerating = true);
    try {
      final count = await PmRegenerationService.regenerateAllFacilities(fallbackStartDate: _startDate);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count task${count == 1 ? '' : 's'} rescheduled', style: GoogleFonts.poppins()), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error regenerating schedule: $e', style: GoogleFonts.poppins()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isRegenerating = false);
    }
  }
}
