import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/utils/module_usage_tracker.dart';
import 'package:cmms/display_screens/locations_screen.dart';
import 'package:cmms/display_screens/schedule_maintenance_screen.dart';
import 'package:cmms/technician/preventive_maintenance_screen.dart';
import 'package:cmms/display_screens/work_order_screen.dart';
import 'package:cmms/display_screens/request_screen.dart';
import 'package:cmms/display_screens/reports_screen.dart';
import 'package:cmms/display_screens/inventory_screen.dart';
import 'package:cmms/display_screens/kpi_screen.dart';
import 'package:cmms/display_screens/billing_screen.dart';
import 'package:cmms/screens/bim/bim_models_screen.dart';

// ── Module catalogue ──────────────────────────────────────────────────────────

class _ModuleItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> roles;

  const _ModuleItem(this.title, this.subtitle, this.icon, this.color,
      {this.roles = const []});
}

const _catalogue = <_ModuleItem>[
  _ModuleItem('Work Orders', 'Manage maintenance tasks', Icons.work_rounded, Color(0xFF4C6EF5)),
  _ModuleItem('Work on Request', 'Service & repair requests', Icons.request_page_rounded, Color(0xFF12B886)),
  _ModuleItem('Preventive Maintenance', 'Scheduled PM tasks', Icons.build_circle_rounded, Color(0xFFFF6B6B)),
  _ModuleItem('Locations', 'Floors, zones & rooms', Icons.location_on_rounded, Color(0xFFFF922B)),
  _ModuleItem('Assets & BIM', 'BIM, spaces & 3D viewer', Icons.view_in_ar_rounded, Color(0xFF748FFC)),
  _ModuleItem('Reports', 'Analytics & reporting', Icons.bar_chart_rounded, Color(0xFF20C997)),
  _ModuleItem('Inventory and Parts', 'Stock & spare parts', Icons.inventory_rounded, Color(0xFFCC5DE8)),
  _ModuleItem('KPIs', 'Performance indicators', Icons.trending_up_rounded, Color(0xFF339AF0)),
  _ModuleItem('Scope of Work', 'Maintenance schedules', Icons.event_rounded, Color(0xFFE64980),
      roles: ['Admin', 'Technician']),
  _ModuleItem('Billing', 'Invoices & payments', Icons.receipt_long_rounded, Color(0xFF94D82D),
      roles: ['Admin', 'Technician']),
];

// ── Public screen ─────────────────────────────────────────────────────────────

class DashboardHomeScreen extends StatelessWidget {
  final String facilityId;
  final String facilityName;
  final String organization;
  final String role;

  const DashboardHomeScreen({
    super.key,
    required this.facilityId,
    required this.facilityName,
    required this.organization,
    required this.role,
  });

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _WelcomeBanner(
            greeting: _greeting,
            dateLabel: DateFormat('EEEE, MMMM d').format(DateTime.now()),
            facilityName: facilityName,
            organization: organization,
            role: role,
          ),
          const SizedBox(height: 28),
          _QuickAccessSection(facilityId: facilityId, role: role),
        ],
      ),
    );
  }
}

// ── Welcome banner ────────────────────────────────────────────────────────────

class _WelcomeBanner extends StatelessWidget {
  final String greeting;
  final String dateLabel;
  final String facilityName;
  final String organization;
  final String role;

  const _WelcomeBanner({
    required this.greeting,
    required this.dateLabel,
    required this.facilityName,
    required this.organization,
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.4,
                        )),
                    const SizedBox(height: 3),
                    Text(dateLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 12.5,
                            color: Colors.white.withValues(alpha: 0.72))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Text(
                  role == '-' ? 'Pending' : role,
                  style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_city_rounded, size: 16, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(facilityName,
                          style: GoogleFonts.poppins(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                          overflow: TextOverflow.ellipsis),
                      if (organization.isNotEmpty && organization != '-')
                        Text(organization,
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.72)),
                            overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Icon(Icons.verified_rounded,
                    size: 15, color: Colors.white.withValues(alpha: 0.55)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick access (frequency-tracked) ─────────────────────────────────────────

class _QuickAccessSection extends StatefulWidget {
  final String facilityId;
  final String role;

  const _QuickAccessSection({required this.facilityId, required this.role});

  @override
  State<_QuickAccessSection> createState() => _QuickAccessSectionState();
}

class _QuickAccessSectionState extends State<_QuickAccessSection> {
  late Future<List<String>> _topFuture;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final allowed = _catalogue
        .where((m) => m.roles.isEmpty || m.roles.contains(widget.role))
        .map((m) => m.title)
        .toList();
    _topFuture = ModuleUsageTracker.getTop(4, facilityId: widget.facilityId, allowedNames: allowed);
  }

  Future<void> _open(BuildContext context, String title) async {
    await ModuleUsageTracker.track(title, facilityId: widget.facilityId);
    final id = widget.facilityId;
    final screenMap = <String, Widget Function()>{
      'Work Orders': () => WorkOrderScreen(facilityId: id),
      'Work on Request': () => RequestScreen(facilityId: id),
      'Preventive Maintenance': () => PreventiveMaintenanceScreen(facilityId: id),
      'Locations': () => LocationsScreen(facilityId: id),
      'Assets & BIM': () => BimModelsScreen(facilityId: id),
      'Reports': () => ReportsScreen(facilityId: id),
      'Inventory and Parts': () => InventoryScreen(facilityId: id),
      'KPIs': () => KpiScreen(facilityId: id),
      'Scope of Work': () => ScheduleMaintenanceScreen(facilityId: id),
      'Billing': () => BillingScreen(facilityId: id),
    };
    final builder = screenMap[title];
    if (builder != null && context.mounted) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => builder()));
      // Refresh after returning so the list reflects the new usage count
      if (mounted) setState(_reload);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _topFuture,
      builder: (context, snapshot) {
        final topNames =
            snapshot.data ?? ModuleUsageTracker.defaultModuleNames;
        final isDefault = snapshot.data == null ||
            snapshot.data!
                .every((n) => ModuleUsageTracker.defaultModuleNames.contains(n));

        final modules = topNames
            .map((n) =>
                _catalogue.firstWhere((m) => m.title == n,
                    orElse: () => _catalogue.first))
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Quick Access',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                      letterSpacing: -0.2,
                    )),
                const Spacer(),
                Text(
                  isDefault ? 'Default picks' : 'Based on usage',
                  style: GoogleFonts.poppins(
                      fontSize: 11.5,
                      color: context.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isDefault
                  ? 'Your top 4 will appear here as you use the app'
                  : 'Your 4 most-opened modules',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: context.textSecondary),
            ),
            const SizedBox(height: 14),
            if (snapshot.connectionState == ConnectionState.waiting &&
                snapshot.data == null)
              _buildSkeleton()
            else
              _buildGrid(context, modules),
          ],
        );
      },
    );
  }

  Widget _buildSkeleton() {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 600 ? 4 : 2;
      final cardWidth = (constraints.maxWidth - (cols - 1) * 14) / cols;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: List.generate(
          4,
          (_) => Container(
            width: cardWidth,
            height: 110,
            decoration: BoxDecoration(
              color: context.surfaceAltColor,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildGrid(BuildContext context, List<_ModuleItem> modules) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = constraints.maxWidth > 600 ? 4 : 2;
      final cardWidth = (constraints.maxWidth - (cols - 1) * 14) / cols;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children: [
          for (var i = 0; i < modules.length; i++)
            SizedBox(
              width: cardWidth,
              child: _ModuleCard(
                module: modules[i],
                onTap: () => _open(context, modules[i].title),
              ),
            ),
        ],
      );
    });
  }
}

// ── Module card ───────────────────────────────────────────────────────────────

class _ModuleCard extends StatefulWidget {
  final _ModuleItem module;
  final VoidCallback onTap;

  const _ModuleCard({required this.module, required this.onTap});

  @override
  State<_ModuleCard> createState() => _ModuleCardState();
}

class _ModuleCardState extends State<_ModuleCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            color: _hovered
                ? m.color.withValues(alpha: 0.1)
                : context.cardColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: _hovered
                  ? m.color.withValues(alpha: 0.4)
                  : context.dividerColor,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                        color: m.color.withValues(alpha: 0.14),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ]
                : [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: m.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(m.icon, color: m.color, size: 21),
              ),
              const SizedBox(height: 10),
              Text(m.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(m.subtitle,
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: context.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
