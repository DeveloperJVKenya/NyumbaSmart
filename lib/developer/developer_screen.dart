import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/developer/collection_detail_screen.dart';
import 'package:cmms/developer/maintenance_tasks_screen.dart';
import 'package:cmms/notifications/screens/notification_delivery_stats_screen.dart';
import 'package:cmms/notifications/screens/system_notifications_screen.dart';
import 'package:cmms/notifications/screens/test_notification_screen.dart';
import 'package:cmms/notifications/widgets/notification_bell_action.dart';
import 'package:cmms/theme/app_theme.dart';

class _NavItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final WidgetBuilder builder;

  const _NavItem({required this.icon, required this.title, this.subtitle, required this.builder});
}

class _NavGroup {
  final String title;
  final IconData icon;
  final List<_NavItem> items;

  const _NavGroup({required this.title, required this.icon, required this.items});
}

/// Developer control center: live counts of the accounts the developer manages, then every
/// developer tool grouped by purpose instead of one flat list. Redesigned to match the app's
/// current visual language (gradient app bar, AppColors/AppRadius/AppSpacing, card-based
/// sections) established by the notifications module — this screen predated both.
class DeveloperScreen extends ConsumerStatefulWidget {
  const DeveloperScreen({super.key});

  @override
  ConsumerState<DeveloperScreen> createState() => _DeveloperScreenState();
}

class _DeveloperScreenState extends ConsumerState<DeveloperScreen> {
  late Future<Map<String, int>> _countsFuture;

  @override
  void initState() {
    super.initState();
    _countsFuture = _loadCounts();
  }

  Future<Map<String, int>> _loadCounts() async {
    final firestore = FirebaseFirestore.instance;
    final results = await Future.wait([
      firestore.collection('Users').count().get(),
      firestore.collection('Admins').count().get(),
      firestore.collection('Technicians').count().get(),
      firestore.collection('Organizations').count().get(),
    ]);
    return {
      'Users': results[0].count ?? 0,
      'Admins': results[1].count ?? 0,
      'Technicians': results[2].count ?? 0,
      'Organizations': results[3].count ?? 0,
    };
  }

  List<_NavGroup> get _groups => [
        _NavGroup(
          title: 'User Management',
          icon: Icons.people_alt_rounded,
          items: [
            _NavItem(
              icon: Icons.business_rounded,
              title: 'Organizations',
              subtitle: 'Manage system organizations',
              builder: (_) => const CollectionDetailScreen(
                collectionName: 'Organizations',
                fields: ['name', 'description', 'createdAt', 'isActive'],
                hasActions: true,
              ),
            ),
            _NavItem(
              icon: Icons.admin_panel_settings_rounded,
              title: 'Admins',
              builder: (_) => const CollectionDetailScreen(
                collectionName: 'Admins',
                fields: ['username', 'email', 'organization', 'createdAt', 'isDisabled'],
                hasActions: true,
              ),
            ),
            _NavItem(
              icon: Icons.group_rounded,
              title: 'Users',
              builder: (_) => const CollectionDetailScreen(
                collectionName: 'Users',
                fields: ['username', 'email', 'role', 'organization', 'createdAt'],
                hasActions: true,
              ),
            ),
            _NavItem(
              icon: Icons.build_rounded,
              title: 'Technicians',
              builder: (_) => const CollectionDetailScreen(
                collectionName: 'Technicians',
                fields: ['username', 'email', 'organization', 'createdAt', 'isDisabled'],
                hasActions: true,
              ),
            ),
            _NavItem(
              icon: Icons.developer_mode_rounded,
              title: 'Developers',
              builder: (_) => const CollectionDetailScreen(
                collectionName: 'Developers',
                fields: ['username', 'email', 'organization', 'createdAt'],
                hasActions: true,
              ),
            ),
            _NavItem(
              icon: Icons.history_rounded,
              title: 'Admin Actions',
              subtitle: 'Audit trail of admin/developer actions',
              builder: (_) => const CollectionDetailScreen(
                collectionName: 'admin_logs',
                fields: ['action', 'timestamp', 'performedBy'],
                hasActions: true,
              ),
            ),
          ],
        ),
        _NavGroup(
          title: 'Maintenance Data',
          icon: Icons.construction_rounded,
          items: [
            _NavItem(
              icon: Icons.fact_check_rounded,
              title: 'Update Maintenance Tasks',
              subtitle: 'Master preventive-maintenance task catalog',
              builder: (_) => const MaintenanceTasksScreen(),
            ),
          ],
        ),
        _NavGroup(
          title: 'Notifications & System Tools',
          icon: Icons.settings_suggest_rounded,
          items: [
            _NavItem(
              icon: Icons.notifications_active_rounded,
              title: 'Regenerate Maintenance Schedule',
              subtitle: 'Recompute PM schedules from a chosen start date',
              builder: (_) => const SystemNotificationsScreen(),
            ),
            _NavItem(
              icon: Icons.science_rounded,
              title: 'Test Notifications',
              subtitle: 'Verify delivery — open, background, and closed app',
              builder: (_) => const TestNotificationScreen(),
            ),
            _NavItem(
              icon: Icons.query_stats_rounded,
              title: 'Delivery & Engagement Analytics',
              subtitle: 'Who received each notification, and read/open rates',
              builder: (_) => const NotificationDeliveryStatsScreen(),
            ),
          ],
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Developer Dashboard', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
        actions: const [NotificationBellAction()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
          final padding = isMobile ? AppSpacing.md : AppSpacing.xl;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(padding, AppSpacing.md, padding, AppSpacing.xxl),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _countsRow(),
                    const SizedBox(height: AppSpacing.lg),
                    if (isMobile)
                      Column(children: _groups.map(_groupCard).toList())
                    else
                      _twoColumnGroups(),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _twoColumnGroups() {
    // Simple left/right split (not a strict masonry) — keeps groups readable top-to-bottom
    // within each column instead of interleaving unrelated sections.
    final left = <_NavGroup>[];
    final right = <_NavGroup>[];
    for (var i = 0; i < _groups.length; i++) {
      (i.isEven ? left : right).add(_groups[i]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(children: left.map(_groupCard).toList())),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Column(children: right.map(_groupCard).toList())),
      ],
    );
  }

  Widget _countsRow() {
    return FutureBuilder<Map<String, int>>(
      future: _countsFuture,
      builder: (context, snapshot) {
        final counts = snapshot.data;
        final tiles = [
          _statTile('Users', counts?['Users'], AppColors.primary, Icons.group_rounded),
          _statTile('Admins', counts?['Admins'], AppColors.accent, Icons.admin_panel_settings_rounded),
          _statTile('Technicians', counts?['Technicians'], AppColors.success, Icons.build_rounded),
          _statTile('Organizations', counts?['Organizations'], AppColors.primaryDark, Icons.business_rounded),
        ];
        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
            if (isMobile) {
              return Column(
                children: [
                  Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 8), Expanded(child: tiles[1])]),
                  const SizedBox(height: 8),
                  Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 8), Expanded(child: tiles[3])]),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: tiles[0]),
                const SizedBox(width: 10),
                Expanded(child: tiles[1]),
                const SizedBox(width: 10),
                Expanded(child: tiles[2]),
                const SizedBox(width: 10),
                Expanded(child: tiles[3]),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statTile(String label, int? value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          value == null
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              : Text('$value', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _groupCard(_NavGroup group) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                Icon(group.icon, color: AppColors.primary, size: 18),
                const SizedBox(width: 8),
                Text(group.title, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1),
          ...group.items.map(_navTile),
        ],
      ),
    );
  }

  Widget _navTile(_NavItem item) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
        child: Icon(item.icon, color: AppColors.primary, size: 20),
      ),
      title: Text(item.title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: item.subtitle == null
          ? null
          : Text(item.subtitle!, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: item.builder)),
    );
  }
}
