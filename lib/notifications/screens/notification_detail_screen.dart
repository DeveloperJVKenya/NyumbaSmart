import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cmms/notifications/models/digest_item.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:cmms/theme/app_theme.dart';

/// Full detail view for one digest — the per-facility, per-task breakdown behind a grouped
/// notification like "6 notifications from 2 facilities". Replaces the previous separate
/// System/Custom detail screens, which each only ever showed a single flat notification with no
/// facility breakdown at all.
class NotificationDetailScreen extends StatelessWidget {
  final DigestItem digest;

  const NotificationDetailScreen({super.key, required this.digest});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Notification', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryCard(),
                const SizedBox(height: AppSpacing.lg),
                if (digest.facilities.isNotEmpty) ...[
                  Text('Facilities', style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: AppSpacing.sm),
                  ...digest.facilities.map((f) => _facilityCard(context, f)),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _summaryCard() {
    final isUrgent = digest.isUrgent;
    final accent = isUrgent ? AppColors.error : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                child: Icon(isUrgent ? Icons.warning_rounded : Icons.notifications_active_rounded, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(digest.title, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(digest.body, style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          Text(
            DateFormat('MMMM dd, yyyy · h:mm a').format(digest.createdAt),
            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: 0.8)),
          ),
          if (digest.readAt != null) ...[
            const SizedBox(height: 4),
            Text('Read ${DateFormat('MMM dd, h:mm a').format(digest.readAt!)}', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.success)),
          ],
        ],
      ),
    );
  }

  Widget _facilityCard(BuildContext context, DigestFacilityGroup facility) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.apartment_rounded, color: AppColors.primary),
            title: Text(facility.facilityName, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            subtitle: Text('${facility.count} task${facility.count == 1 ? '' : 's'}', style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary)),
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DashboardScreen(facilityId: facility.facilityId, role: ''))),
              child: Text('Open', style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.w600)),
            ),
          ),
          if (facility.items.isNotEmpty) const Divider(height: 1),
          ...facility.items.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(item.isAlert ? Icons.priority_high_rounded : Icons.build_rounded, size: 16, color: item.isAlert ? AppColors.error : AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${item.category} — ${item.component}', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        Text(item.intervention, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
