import 'package:cmms/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/display%20screens/locations_screen.dart';
import 'package:cmms/display%20screens/building_survey_screen.dart';
import 'package:cmms/display%20screens/documentations_screen.dart';
import 'package:cmms/display%20screens/drawings_screen.dart';
import 'package:cmms/display%20screens/schedule_maintenance_screen.dart';
import 'package:cmms/technician/preventive_maintenance_screen.dart';
import 'package:cmms/display%20screens/reports_screen.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
import 'package:cmms/display%20screens/price_list_screen.dart';
import 'package:cmms/display%20screens/billing_screen.dart';
import 'package:cmms/display%20screens/equipment_supplied_screen.dart';
import 'package:cmms/display%20screens/inventory_screen.dart';
import 'package:cmms/display%20screens/vendor_screen.dart';
import 'package:cmms/display%20screens/kpi_screen.dart';
import 'package:cmms/display%20screens/report_screen.dart';
import 'package:cmms/screens/bim/bim_models_screen.dart';
import 'package:cmms/screens/bim/bim_viewer_screen.dart';
import 'package:cmms/screens/bim/spaces_screen.dart';
import 'package:cmms/screens/settings_screen.dart';
import 'package:cmms/developer/developer_screen.dart';
import 'package:cmms/notifications/widgets/notification_bell_action.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/models/user_model.dart';
import 'package:cmms/theme/app_theme.dart';

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
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final VoidCallback? onFacilityReset;

  const ResponsiveScreenWrapper({
    super.key,
    required this.title,
    required this.child,
    required this.facilityId,
    this.currentRole,
    this.organization,
    this.selectedOrganizationName,
    this.actions,
    this.floatingActionButton,
    this.onFacilityReset,
  });

  @override
  ConsumerState<ResponsiveScreenWrapper> createState() => _ResponsiveScreenWrapperState();
}

class _ResponsiveScreenWrapperState extends ConsumerState<ResponsiveScreenWrapper> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Static so the Building Information submenu stays expanded across
  // rebuilds/navigations, matching the previous behavior.
  static bool _isBuildingInfoExpanded = false;
  static bool _isAssetsBimExpanded = false;

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

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          appBarTitle,
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: isMobile ? 18 : 20),
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
      floatingActionButton: widget.floatingActionButton,
    );
  }

  Widget _buildDrawer(String role, String organization, bool isDeveloper, bool isClient, bool isMobile) {
    return Drawer(
      backgroundColor: AppColors.card,
      child: Column(
        children: [
          _buildAppIcon(role, organization, isDeveloper, isClient, isMobile),
          const Divider(height: 1),
          Expanded(child: ListView(children: _buildMenuItems(role, organization, isMobile))),
        ],
      ),
    );
  }

  Widget _buildSidebar(String role, String organization, bool isDeveloper, bool isClient, bool isMobile) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        border: Border(right: BorderSide(color: Color(0x14000000))),
      ),
      child: Column(
        children: [
          _buildAppIcon(role, organization, isDeveloper, isClient, isMobile),
          const Divider(height: 1),
          Expanded(child: ListView(children: _buildMenuItems(role, organization, isMobile))),
        ],
      ),
    );
  }

  Widget _buildAppIcon(String role, String organization, bool isDeveloper, bool isClient, bool isMobile) {
    return GestureDetector(
      onTap: isDeveloper ? () => _handleDeveloperIconTap(isMobile) : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        width: double.infinity,
        child: Center(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: Image.asset('assets/icons/icon.png', width: 52, height: 52),
                  ),
                  if (isDeveloper)
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
                        child: Text('DEV', style: GoogleFonts.poppins(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                role == '-' ? 'Pending Approval' : role,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontSize: 15),
              ),
              if (isDeveloper) ...[
                const SizedBox(height: 2),
                Text('Tap for Developer Tools', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 10, fontStyle: FontStyle.italic)),
              ],
              if (organization != '-') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Text(
                    isClient ? organization : 'Managing: ${widget.selectedOrganizationName ?? organization}',
                    style: GoogleFonts.poppins(color: AppColors.primaryDark, fontSize: 11, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<String> _getMenuItemsForRole(String role, String organization) {
    final Map<String, List<String>> jvAlmacisMenus = {
      'Admin': [
        'Facilities', 'Locations', 'Building Information', 'Assets & BIM', 'Scope of Work',
        'Preventive Maintenance', 'Reports', 'Work on Request', 'Work Orders',
        'Price Lists', 'Billing', 'Inventory and Parts', 'Vendors', 'KPIs', 'Report', 'Settings',
      ],
      'Technician': [
        'Facilities', 'Locations', 'Building Information', 'Assets & BIM', 'Preventive Maintenance',
        'Scope of Work', 'Reports', 'Work on Request', 'Work Orders', 'Billing',
        'Inventory and Parts', 'Vendors', 'KPIs',
        'Report', 'Settings',
      ],
    };

    final Map<String, List<String>> clientOrganizationMenus = {
      'Admin': [
        'Facilities', 'Locations', 'Building Information', 'Assets & BIM', 'Scope of Work',
        'Preventive Maintenance', 'Reports', 'Work on Request', 'Work Orders',
        'Price Lists', 'Billing', 'Inventory and Parts', 'Vendors', 'KPIs', 'Report', 'Settings',
      ],
      'Technician': [
        'Facilities', 'Locations', 'Building Information', 'Assets & BIM', 'Preventive Maintenance',
        'Scope of Work', 'Reports', 'Work on Request', 'Work Orders', 'Billing',
        'Inventory and Parts', 'Vendors', 'KPIs',
        'Report', 'Settings',
      ],
    };

    final List<String> userMenus = ['Facilities', 'Settings'];

    if (role == 'User' || organization == '-') {
      return userMenus;
    } else if (organization == 'JV Almacis') {
      return jvAlmacisMenus[role] ?? userMenus;
    } else {
      return clientOrganizationMenus[role] ?? userMenus;
    }
  }

  List<Widget> _buildMenuItems(String role, String organization, bool isMobile) {
    final menuStructure = [
      {'title': 'Facilities', 'icon': Icons.business_rounded, 'isSubItem': false},
      {'title': 'Locations', 'icon': Icons.location_on_rounded, 'isSubItem': false},
      {'title': 'Building Information', 'icon': Icons.info_rounded, 'isSubItem': false, 'isParent': true},
      {'title': 'Assets & BIM', 'icon': Icons.view_in_ar_rounded, 'isSubItem': false, 'isParent': true},
      {'title': 'Scope of Work', 'icon': Icons.event_rounded, 'isSubItem': false},
      {'title': 'Preventive Maintenance', 'icon': Icons.build_circle_rounded, 'isSubItem': false},
      {'title': 'Reports', 'icon': Icons.bar_chart_rounded, 'isSubItem': false},
      {'title': 'Work on Request', 'icon': Icons.request_page_rounded, 'isSubItem': false},
      {'title': 'Work Orders', 'icon': Icons.work_rounded, 'isSubItem': false},
      {'title': 'Price Lists', 'icon': Icons.attach_money_rounded, 'isSubItem': false},
      {'title': 'Billing', 'icon': Icons.receipt_long_rounded, 'isSubItem': false},
      {'title': 'Equipment Supplied', 'icon': Icons.construction_rounded, 'isSubItem': false},
      {'title': 'Inventory and Parts', 'icon': Icons.inventory_rounded, 'isSubItem': false},
      {'title': 'Vendors', 'icon': Icons.store_rounded, 'isSubItem': false},
      {'title': 'KPIs', 'icon': Icons.trending_up_rounded, 'isSubItem': false},
      {'title': 'Report', 'icon': Icons.bar_chart_rounded, 'isSubItem': false},
      {'title': 'Settings', 'icon': Icons.settings_rounded, 'isSubItem': false},
    ];

    final buildingInfoSubItems = [
      {'title': 'Building Survey', 'icon': Icons.account_balance_rounded},
      {'title': 'Documentations', 'icon': Icons.description_rounded},
      {'title': 'Drawings', 'icon': Icons.brush_rounded},
    ];

    final assetsBimSubItems = [
      {'title': 'BIM Models', 'icon': Icons.view_in_ar_outlined},
      {'title': '3D Viewer', 'icon': Icons.threed_rotation_rounded},
      {'title': 'Floors & Rooms', 'icon': Icons.meeting_room_rounded},
      {'title': 'Equipment Supplied', 'icon': Icons.construction_rounded},
    ];

    final allowedItems = _getMenuItemsForRole(role, organization);
    final List<Widget> menuWidgets = [];

    for (var menuItem in menuStructure) {
      final itemTitle = menuItem['title'] as String;
      if (!allowedItems.contains(itemTitle)) continue;
      final icon = menuItem['icon'] as IconData;
      final isParent = menuItem['isParent'] as bool? ?? false;

      if (isParent && (itemTitle == 'Building Information' || itemTitle == 'Assets & BIM')) {
        final isBim = itemTitle == 'Assets & BIM';
        final expanded = isBim ? _isAssetsBimExpanded : _isBuildingInfoExpanded;
        menuWidgets.add(_menuTile(
          icon: icon,
          title: itemTitle,
          trailing: Icon(
            expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: AppColors.textSecondary,
          ),
          onTap: () => setState(() {
            if (isBim) {
              _isAssetsBimExpanded = !_isAssetsBimExpanded;
            } else {
              _isBuildingInfoExpanded = !_isBuildingInfoExpanded;
            }
          }),
        ));

        if (expanded) {
          for (var subItem in isBim ? assetsBimSubItems : buildingInfoSubItems) {
            final subTitle = subItem['title'] as String;
            final subIcon = subItem['icon'] as IconData;
            menuWidgets.add(_menuTile(
              icon: subIcon,
              title: subTitle,
              indent: true,
              onTap: () => _handleSubMenuNavigation(subTitle, isMobile),
            ));
          }
        }
      } else if (!isParent) {
        if (!['Building Survey', 'Documentations', 'Drawings'].contains(itemTitle)) {
          menuWidgets.add(_menuTile(
            icon: icon,
            title: itemTitle,
            onTap: () => _handleMenuNavigation(itemTitle, isMobile),
          ));
        }
      }
    }

    return menuWidgets;
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Widget? trailing,
    bool indent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.only(left: indent ? 32 : 12, right: 12, top: 12, bottom: 12),
            child: Row(
              children: [
                Icon(icon, color: indent ? AppColors.textSecondary : AppColors.primary, size: indent ? 19 : 22),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.poppins(
                      fontSize: indent ? 13.5 : 14.5,
                      color: indent ? AppColors.textSecondary : AppColors.textPrimary,
                      fontWeight: indent ? FontWeight.w400 : FontWeight.w500,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSubMenuNavigation(String title, bool isMobile) {
    if (isMobile) Navigator.pop(context);

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

    if (title == 'Facilities') {
      widget.onFacilityReset?.call();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const DashboardScreen(facilityId: '', role: 'User')),
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
