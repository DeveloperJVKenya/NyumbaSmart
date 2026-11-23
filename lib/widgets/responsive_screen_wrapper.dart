import 'package:cmms/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/display_screens/locations_screen.dart';
import 'package:cmms/display_screens/building_survey_screen.dart';
import 'package:cmms/display_screens/documentations_screen.dart';
import 'package:cmms/display_screens/drawings_screen.dart';
import 'package:cmms/display_screens/schedule_maintenance_screen.dart';
import 'package:cmms/technician/preventive_maintenance_screen.dart';
import 'package:cmms/display_screens/reports_screen.dart';
import 'package:cmms/display_screens/request_screen.dart';
import 'package:cmms/display_screens/work_order_screen.dart';
import 'package:cmms/display_screens/price_list_screen.dart';
import 'package:cmms/display_screens/billing_screen.dart';
import 'package:cmms/display_screens/equipment_supplied_screen.dart';
import 'package:cmms/display_screens/inventory_screen.dart';
import 'package:cmms/display_screens/vendor_screen.dart';
import 'package:cmms/display_screens/kpi_screen.dart';
import 'package:cmms/display_screens/report_screen.dart';
import 'package:cmms/screens/bim/bim_models_screen.dart';
import 'package:cmms/screens/bim/bim_viewer_screen.dart';
import 'package:cmms/screens/bim/spaces_screen.dart';
import 'package:cmms/screens/settings_screen.dart';
import 'package:cmms/developer/developer_screen.dart';
import 'package:cmms/notifications/widgets/notification_bell_action.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/models/user_model.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/utils/module_usage_tracker.dart';

// Persists sidebar scroll position across screen navigations so the user
// never loses their scroll context when moving between routes.
// A plain ValueNotifier (file-level singleton) is sufficient — no Riverpod
// provider needed since this state is app-wide and never streamed.
// Reset to 0 on sign-out so the next session starts at the top.
final sidebarScrollOffset = ValueNotifier<double>(0.0);

/// Dashboard shell (AppBar + drawer/sidebar/rail + content). Role and
/// organization are sourced live from [currentUserRoleProvider] instead of
/// this widget's own retry-fetch (previously `_fetchUserRoleWithRetry`),
/// which duplicated the same Admins/Developers/Technicians/Users cascade
/// already centralized in lib/providers/auth_providers.dart.
class ResponsiveScreenWrapper extends ConsumerStatefulWidget {
  final String title;
  final Widget child;
  final String facilityId;
  final String? currentRole;
  final String? organization;
  final String? selectedOrganizationName;
  final String? facilityName;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final VoidCallback? onFacilityReset;
  final Widget? bottomBar;

  const ResponsiveScreenWrapper({
    super.key,
    required this.title,
    required this.child,
    required this.facilityId,
    this.currentRole,
    this.organization,
    this.selectedOrganizationName,
    this.facilityName,
    this.actions,
    this.floatingActionButton,
    this.onFacilityReset,
    this.bottomBar,
  });

  @override
  ConsumerState<ResponsiveScreenWrapper> createState() => _ResponsiveScreenWrapperState();
}

class _ResponsiveScreenWrapperState extends ConsumerState<ResponsiveScreenWrapper> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final ScrollController _sidebarScrollCtrl;
  final GlobalKey _activeItemKey = GlobalKey();

  static bool _isBuildingInfoExpanded = false;
  static bool _isAssetsBimExpanded = false;

  @override
  void initState() {
    super.initState();
    if (_buildingInfoSubTitles.contains(widget.title)) _isBuildingInfoExpanded = true;
    if (_assetsBimSubTitles.contains(widget.title)) _isAssetsBimExpanded = true;
    _sidebarScrollCtrl = ScrollController(
      initialScrollOffset: sidebarScrollOffset.value,
    );
    _sidebarScrollCtrl.addListener(_persistSidebarScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToActiveItem());
  }

  void _persistSidebarScroll() {
    if (_sidebarScrollCtrl.hasClients) {
      sidebarScrollOffset.value = _sidebarScrollCtrl.offset;
    }
  }

  void _scrollToActiveItem() {
    if (!mounted) return;
    final ctx = _activeItemKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.1,
    );
  }

  @override
  void dispose() {
    _sidebarScrollCtrl
      ..removeListener(_persistSidebarScroll)
      ..dispose();
    super.dispose();
  }

  static const Map<String, Color> _itemColors = {
    'Facilities': Color(0xFF4C6EF5),
    'Locations': Color(0xFFFF922B),
    'Building Information': Color(0xFF339AF0),
    'Scope of Work': Color(0xFFE64980),
    'Preventive Maintenance': Color(0xFFFF6B6B),
    'Work on Request': Color(0xFF12B886),
    'Work Orders': Color(0xFF4C6EF5),
    'Reports': Color(0xFF20C997),
    'Assets & BIM': Color(0xFF748FFC),
    'Inventory and Parts': Color(0xFFCC5DE8),
    'Vendors': Color(0xFFFF922B),
    'Price Lists': Color(0xFF94D82D),
    'Billing': Color(0xFF94D82D),
    'KPIs': Color(0xFF339AF0),
    'Report': Color(0xFF20C997),
    'Settings': Color(0xFF868E96),
    // Sub-items
    'Building Survey': Color(0xFF74C0FC),
    'Documentations': Color(0xFF74C0FC),
    'Drawings': Color(0xFF74C0FC),
    'BIM Models': Color(0xFF9775FA),
    '3D Viewer': Color(0xFF9775FA),
    'Floors & Rooms': Color(0xFF9775FA),
    'Equipment Supplied': Color(0xFF9775FA),
  };

  static const _buildingInfoSubTitles = ['Building Survey', 'Documentations', 'Drawings'];
  static const _assetsBimSubTitles = ['BIM Models', '3D Viewer', 'Floors & Rooms', 'Equipment Supplied'];

  void _handleDeveloperIconTap(bool isMobile) async {
    _logger.i('App icon clicked by developer, navigating to DeveloperScreen');
    try {
      if (isMobile && _scaffoldKey.currentState?.isDrawerOpen == true) {
        Navigator.pop(context);
        await Future.delayed(const Duration(milliseconds: 200));
      }
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const DeveloperScreen()),
        );
      }
    } catch (e) {
      _logger.e('Error navigating to DeveloperScreen: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error opening developer screen: $e', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value ??
        UserRoleInfo(
          role: UserRoleX.fromString(widget.currentRole),
          organization: widget.organization ?? '-',
        );

    final currentRole = roleInfo.roleLabel;
    final organization = roleInfo.organization;
    final isDeveloper = roleInfo.isDeveloper;
    final isClient = roleInfo.isClient;

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = AppBreakpoints.isMobile(screenWidth);
    final String appBarTitle = organization == '-' ? 'Dashboard' : widget.title;
    final String orgContext = widget.selectedOrganizationName ??
        (organization != '-' ? organization : '');
    final String orgSubtitle = orgContext.isNotEmpty
        ? '${currentRole == '-' ? 'Dashboard' : currentRole} · $orgContext'
        : (currentRole != '-' ? currentRole : '');

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        toolbarHeight: 62,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.facilityName ?? appBarTitle,
              style: GoogleFonts.plusJakartaSans(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: isMobile ? 16 : 17,
                letterSpacing: -0.2,
              ),
            ),
            if (orgSubtitle.isNotEmpty)
              Text(
                orgSubtitle,
                style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 11,
                ),
              ),
          ],
        ),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
        // The hamburger/drawer menu is a mobile-only pattern now — tablet
        // and desktop both get the permanent side panel instead, since
        // that's the width where content (e.g. the facilities grid) is
        // already laid out in more than a single column.
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
        actions: [const NotificationBellAction(), ...?widget.actions],
      ),
      drawer: isMobile ? _buildDrawer(currentRole, organization, isDeveloper, isClient, isMobile) : null,
      body: Row(
        children: [
          if (!isMobile) _buildSidebar(currentRole, organization, isDeveloper, isClient, isMobile),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: widget.bottomBar,
      floatingActionButton: widget.floatingActionButton,
    );
  }

  Widget _buildDrawer(String role, String organization, bool isDeveloper, bool isClient, bool isMobile) {
    return Drawer(
      backgroundColor: context.panelColor,
      child: Column(
        children: [
          _buildSidebarHeader(role, organization, isDeveloper, isClient, isMobile),
          Divider(height: 1, color: context.dividerColor),
          Expanded(child: ListView(
            controller: _sidebarScrollCtrl,
            children: _buildMenuItems(role, organization, isMobile),
          )),
        ],
      ),
    );
  }

  Widget _buildSidebar(String role, String organization, bool isDeveloper, bool isClient, bool isMobile) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: context.panelColor,
        border: Border(right: BorderSide(color: context.dividerColor)),
      ),
      child: Column(
        children: [
          _buildSidebarHeader(role, organization, isDeveloper, isClient, isMobile),
          Divider(height: 1, color: context.dividerColor),
          Expanded(child: ListView(
            controller: _sidebarScrollCtrl,
            children: _buildMenuItems(role, organization, isMobile),
          )),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(String role, String organization, bool isDeveloper, bool isClient, bool isMobile) {
    final orgDisplay = isClient
        ? organization
        : (widget.selectedOrganizationName ?? organization);

    return GestureDetector(
      onTap: isDeveloper ? () => _handleDeveloperIconTap(isMobile) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(gradient: AppColors.primaryGradient),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App brand row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Image.asset('assets/icons/icon.png', width: 28, height: 28),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'NyumbaSmart',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        isDeveloper ? 'Developer Mode ↗' : 'CMMS Platform',
                        style: GoogleFonts.poppins(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDeveloper)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('DEV', style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Facility + context card (frosted on gradient)
            Container(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.17),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_city_rounded, size: 12, color: Colors.white.withValues(alpha: 0.85)),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          widget.facilityName ?? (orgDisplay != '-' ? orgDisplay : 'Dashboard'),
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (orgDisplay != '-') ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.corporate_fare_rounded, size: 11, color: Colors.white.withValues(alpha: 0.65)),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            orgDisplay,
                            style: GoogleFonts.poppins(fontSize: 11, color: Colors.white.withValues(alpha: 0.75)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      role == '-' ? 'Pending Approval' : role,
                      style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getMenuItemsForRole(String role, String organization) {
    const roleMenus = <String, List<String>>{
      'Admin': [
        'Facilities', 'Locations', 'Building Information', 'Assets & BIM', 'Scope of Work',
        'Preventive Maintenance', 'Reports', 'Work on Request', 'Work Orders',
        'Price Lists', 'Billing', 'Inventory and Parts', 'Vendors', 'KPIs', 'Report', 'Settings',
      ],
      'Technician': [
        'Facilities', 'Locations', 'Building Information', 'Assets & BIM', 'Preventive Maintenance',
        'Scope of Work', 'Reports', 'Work on Request', 'Work Orders', 'Billing',
        'Inventory and Parts', 'Vendors', 'KPIs', 'Report', 'Settings',
      ],
    };

    const userMenus = ['Facilities', 'Settings'];

    if (role == 'User' || organization == '-') return userMenus;
    return roleMenus[role] ?? userMenus;
  }

  List<Widget> _buildMenuItems(String role, String organization, bool isMobile) {
    final allowedItems = _getMenuItemsForRole(role, organization);
    final List<Widget> w = [];

    const buildingInfoSubs = [
      {'title': 'Building Survey', 'icon': Icons.account_balance_rounded},
      {'title': 'Documentations', 'icon': Icons.description_rounded},
      {'title': 'Drawings', 'icon': Icons.brush_rounded},
    ];
    const assetsBimSubs = [
      {'title': 'BIM Models', 'icon': Icons.view_in_ar_outlined},
      {'title': '3D Viewer', 'icon': Icons.threed_rotation_rounded},
      {'title': 'Floors & Rooms', 'icon': Icons.meeting_room_rounded},
      {'title': 'Equipment Supplied', 'icon': Icons.construction_rounded},
    ];

    // ── CORE ──────────────────────────────────────────────────────────────
    final coreItems = <Map<String, Object>>[
      {'title': 'Facilities', 'icon': Icons.business_rounded},
      {'title': 'Locations', 'icon': Icons.location_on_rounded},
    ].where((i) => allowedItems.contains(i['title'])).toList();
    if (coreItems.isNotEmpty) {
      w.add(_menuSectionHeader('Core'));
      for (final i in coreItems) {
        final t = i['title'] as String;
        final active = t == widget.title;
        w.add(_menuTile(
          icon: i['icon'] as IconData, title: t,
          onTap: () => _handleMenuNavigation(t, isMobile),
          isActive: active, itemKey: active ? _activeItemKey : null,
        ));
      }
    }

    // ── OPERATIONS ────────────────────────────────────────────────────────
    final opsItems = <Map<String, Object>>[
      {'title': 'Building Information', 'icon': Icons.info_rounded, 'isParent': true},
      {'title': 'Scope of Work', 'icon': Icons.event_rounded},
      {'title': 'Preventive Maintenance', 'icon': Icons.build_circle_rounded},
      {'title': 'Work on Request', 'icon': Icons.request_page_rounded},
      {'title': 'Work Orders', 'icon': Icons.work_rounded},
      {'title': 'Reports', 'icon': Icons.bar_chart_rounded},
    ].where((i) => allowedItems.contains(i['title'])).toList();
    if (opsItems.isNotEmpty) {
      w.add(_menuSectionHeader('Operations'));
      for (final i in opsItems) {
        final title = i['title'] as String;
        final icon = i['icon'] as IconData;
        if (i['isParent'] == true) {
          final subActive = _buildingInfoSubTitles.contains(widget.title);
          final parentActive = title == widget.title || subActive;
          w.add(_menuTile(
            icon: icon, title: title,
            trailing: Icon(_isBuildingInfoExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: const Color(0xFF9CA3AF)),
            onTap: () => setState(() => _isBuildingInfoExpanded = !_isBuildingInfoExpanded),
            isActive: parentActive,
            itemKey: parentActive && !subActive ? _activeItemKey : null,
          ));
          if (_isBuildingInfoExpanded) {
            for (final s in buildingInfoSubs) {
              final st = s['title'] as String;
              final sa = st == widget.title;
              w.add(_menuTile(
                icon: s['icon'] as IconData, title: st, indent: true,
                onTap: () => _handleSubMenuNavigation(st, isMobile),
                isActive: sa, itemKey: sa ? _activeItemKey : null,
              ));
            }
          }
        } else {
          final active = title == widget.title;
          w.add(_menuTile(
            icon: icon, title: title,
            onTap: () => _handleMenuNavigation(title, isMobile),
            isActive: active, itemKey: active ? _activeItemKey : null,
          ));
        }
      }
    }

    // ── ASSETS ────────────────────────────────────────────────────────────
    final assetItems = <Map<String, Object>>[
      {'title': 'Assets & BIM', 'icon': Icons.view_in_ar_rounded, 'isParent': true},
      {'title': 'Inventory and Parts', 'icon': Icons.inventory_rounded},
      {'title': 'Vendors', 'icon': Icons.store_rounded},
    ].where((i) => allowedItems.contains(i['title'])).toList();
    if (assetItems.isNotEmpty) {
      w.add(_menuSectionHeader('Assets'));
      for (final i in assetItems) {
        final title = i['title'] as String;
        final icon = i['icon'] as IconData;
        if (i['isParent'] == true) {
          final subActive = _assetsBimSubTitles.contains(widget.title);
          final parentActive = title == widget.title || subActive;
          w.add(_menuTile(
            icon: icon, title: title,
            trailing: Icon(_isAssetsBimExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 16, color: const Color(0xFF9CA3AF)),
            onTap: () => setState(() => _isAssetsBimExpanded = !_isAssetsBimExpanded),
            isActive: parentActive,
            itemKey: parentActive && !subActive ? _activeItemKey : null,
          ));
          if (_isAssetsBimExpanded) {
            for (final s in assetsBimSubs) {
              final st = s['title'] as String;
              final sa = st == widget.title;
              w.add(_menuTile(
                icon: s['icon'] as IconData, title: st, indent: true,
                onTap: () => _handleSubMenuNavigation(st, isMobile),
                isActive: sa, itemKey: sa ? _activeItemKey : null,
              ));
            }
          }
        } else {
          final active = title == widget.title;
          w.add(_menuTile(
            icon: icon, title: title,
            onTap: () => _handleMenuNavigation(title, isMobile),
            isActive: active, itemKey: active ? _activeItemKey : null,
          ));
        }
      }
    }

    // ── FINANCIAL ─────────────────────────────────────────────────────────
    final finItems = <Map<String, Object>>[
      {'title': 'Price Lists', 'icon': Icons.attach_money_rounded},
      {'title': 'Billing', 'icon': Icons.receipt_long_rounded},
      {'title': 'KPIs', 'icon': Icons.trending_up_rounded},
      {'title': 'Report', 'icon': Icons.analytics_rounded},
    ].where((i) => allowedItems.contains(i['title'])).toList();
    if (finItems.isNotEmpty) {
      w.add(_menuSectionHeader('Financial'));
      for (final i in finItems) {
        final t = i['title'] as String;
        final active = t == widget.title;
        w.add(_menuTile(
          icon: i['icon'] as IconData, title: t,
          onTap: () => _handleMenuNavigation(t, isMobile),
          isActive: active, itemKey: active ? _activeItemKey : null,
        ));
      }
    }

    // ── SYSTEM ────────────────────────────────────────────────────────────
    if (allowedItems.contains('Settings')) {
      w.add(const SizedBox(height: 4));
      w.add(Divider(height: 1, indent: 16, endIndent: 16, color: context.dividerColor));
      final settingsActive = 'Settings' == widget.title;
      w.add(_menuTile(
        icon: Icons.settings_rounded, title: 'Settings',
        onTap: () => _handleMenuNavigation('Settings', isMobile),
        isActive: settingsActive, itemKey: settingsActive ? _activeItemKey : null,
      ));
    }

    w.add(const SizedBox(height: 16));
    return w;
  }

  Widget _menuSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 3),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.poppins(fontSize: 10.5, fontWeight: FontWeight.w600, color: context.textSecondary.withValues(alpha: 0.7), letterSpacing: 0.9),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
    bool indent = false,
    Color? iconColor,
    bool isActive = false,
    Key? itemKey,
  }) {
    final effectiveColor = iconColor ?? _itemColors[title] ?? AppColors.primary;
    return _SidebarTile(
      key: itemKey,
      icon: icon,
      title: title,
      onTap: onTap,
      trailing: trailing,
      indent: indent,
      effectiveColor: effectiveColor,
      isActive: isActive,
    );
  }

  void _handleSubMenuNavigation(String title, bool isMobile) {
    if (isMobile) Navigator.pop(context);
    ModuleUsageTracker.track(title, facilityId: widget.facilityId);

    if (widget.facilityId.isEmpty && !['Settings'].contains(title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a facility first.', style: GoogleFonts.poppins())),
      );
      return;
    }

    final screenMap = {
      'Building Survey': () => BuildingSurveyScreen(facilityId: widget.facilityId, selectedSubSection: ''),
      'Documentations': () => DocumentationsScreen(facilityId: widget.facilityId),
      'Drawings': () => DrawingsScreen(facilityId: widget.facilityId),
      'BIM Models': () => BimModelsScreen(facilityId: widget.facilityId),
      '3D Viewer': () => BimViewerScreen(facilityId: widget.facilityId),
      'Floors & Rooms': () => SpacesScreen(facilityId: widget.facilityId),
      'Equipment Supplied': () => EquipmentSuppliedScreen(facilityId: widget.facilityId),
    };

    final screenBuilder = screenMap[title];
    if (screenBuilder != null) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => screenBuilder()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title feature not found', style: GoogleFonts.poppins())),
      );
    }
  }

  void _handleMenuNavigation(String title, bool isMobile) {
    if (isMobile) Navigator.pop(context);
    if (title != 'Facilities' && title != 'Settings') {
      ModuleUsageTracker.track(title, facilityId: widget.facilityId);
    }

    if (title == 'Facilities') {
      widget.onFacilityReset?.call();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen(facilityId: '')),
        (route) => false,
      );
      return;
    }

    if (widget.facilityId.isEmpty && !['Settings'].contains(title)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a facility first.', style: GoogleFonts.poppins())),
      );
      return;
    }

    final screenMap = {
      'Locations': () => LocationsScreen(facilityId: widget.facilityId),
      'Scope of Work': () => ScheduleMaintenanceScreen(facilityId: widget.facilityId),
      'Preventive Maintenance': () => PreventiveMaintenanceScreen(facilityId: widget.facilityId),
      'Reports': () => ReportsScreen(facilityId: widget.facilityId),
      'Work on Request': () => RequestScreen(facilityId: widget.facilityId),
      'Work Orders': () => WorkOrderScreen(facilityId: widget.facilityId),
      'Price Lists': () => PriceListScreen(facilityId: widget.facilityId),
      'Billing': () => BillingScreen(facilityId: widget.facilityId),
      'Equipment Supplied': () => EquipmentSuppliedScreen(facilityId: widget.facilityId),
      'Inventory and Parts': () => InventoryScreen(facilityId: widget.facilityId),
      'Vendors': () => VendorScreen(facilityId: widget.facilityId),
      'KPIs': () => KpiScreen(facilityId: widget.facilityId),
      'Report': () => ReportScreen(facilityId: widget.facilityId),
      'Settings': () => SettingsScreen(facilityId: widget.facilityId),
    };

    final screenBuilder = screenMap[title];
    if (screenBuilder != null) {
      Navigator.push(context, MaterialPageRoute(builder: (context) => screenBuilder()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title feature not found', style: GoogleFonts.poppins())),
      );
    }
  }
}

// ── Sidebar tile with full colored hover state ────────────────────────────────

class _SidebarTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool indent;
  final Color effectiveColor;
  final bool isActive;

  const _SidebarTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.trailing,
    this.indent = false,
    required this.effectiveColor,
    this.isActive = false,
  });

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.effectiveColor;
    final isIndent = widget.indent;
    final isActive = widget.isActive;
    final highlight = isActive || _hovered;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              color: highlight
                  ? c.withValues(alpha: isIndent ? 0.08 : (isActive ? 0.12 : 0.09))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border(
                left: BorderSide(
                  color: highlight ? c : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            padding: EdgeInsets.only(
              left: isIndent ? (highlight ? 33 : 36) : (highlight ? 9 : 12),
              right: 12,
              top: 10,
              bottom: 10,
            ),
            child: Row(
              children: [
                Icon(widget.icon,
                    color: highlight ? c : c.withValues(alpha: isIndent ? 0.75 : 0.85),
                    size: isIndent ? 18 : 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.title,
                    style: GoogleFonts.poppins(
                      fontSize: isIndent ? 13 : 13.5,
                      color: highlight
                          ? c
                          : (isIndent ? const Color(0xFF6B7280) : context.textPrimary),
                      fontWeight: highlight ? FontWeight.w600 : (isIndent ? FontWeight.w400 : FontWeight.w500),
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
