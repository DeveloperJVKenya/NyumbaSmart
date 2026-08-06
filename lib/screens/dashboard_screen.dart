import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/screens/organization_selection_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:logger/logger.dart';
import 'package:cmms/authentication/login_screen.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// First screen shown after a successful login/registration. Role and
/// organization are no longer fetched/listened to here directly — they
/// come live from [currentUserRoleProvider] (see
/// lib/providers/auth_providers.dart), which replaces the 4 manually
/// managed Firestore listeners this screen used to own. Only the user's
/// in-session facility/organization *selection* remains local state.
class DashboardScreen extends ConsumerStatefulWidget {
  final String facilityId;
  final String role;

  const DashboardScreen({super.key, required this.facilityId, required this.role});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends ConsumerState<DashboardScreen> {
  final logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String? _selectedFacilityId;
  String? _selectedOrganizationId;
  String? _selectedOrganizationName;

  @override
  void initState() {
    super.initState();
    _selectedFacilityId = widget.facilityId.isNotEmpty ? widget.facilityId : null;
  }

  void _onOrganizationSelected(String organizationId, String organizationName) {
    setState(() {
      _selectedOrganizationId = organizationId;
      _selectedOrganizationName = organizationName;
    });
    logger.i('Selected organization: $organizationName (ID: $organizationId)');
  }

  void _onFacilitySelected(String facilityId) {
    setState(() => _selectedFacilityId = facilityId);
    logger.i('Selected facility: $facilityId');

    final screenWidth = MediaQuery.of(context).size.width;
    if (AppBreakpoints.isMobile(screenWidth)) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted && _scaffoldKey.currentState != null && !_scaffoldKey.currentState!.isDrawerOpen) {
          _scaffoldKey.currentState!.openDrawer();
        }
      });
    }
  }

  void _refreshFacilitiesView() {
    final info = ref.read(currentUserRoleProvider).valueOrNull;
    setState(() {
      _selectedFacilityId = null;
      if (info != null && info.isServiceProviderOrg) {
        _selectedOrganizationId = null;
        _selectedOrganizationName = null;
      }
    });
    _messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          (info?.isClient ?? false) ? 'Facilities refreshed' : 'Selection refreshed',
          style: GoogleFonts.poppins(),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.primaryDark,
      ),
    );
  }

  Future<void> _redirectToLogin(String message) async {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
    );
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins())),
    );
  }

  void _handleBackNavigation({required bool isOrganizationSelectionActive, required bool isServiceProviderOrg}) {
    if (isOrganizationSelectionActive) {
      _exitOrGoToLogin();
    } else if (_selectedFacilityId == null && isServiceProviderOrg && _selectedOrganizationId != null) {
      setState(() {
        _selectedOrganizationId = null;
        _selectedOrganizationName = null;
      });
    } else if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      _exitOrGoToLogin();
    }
  }

  void _exitOrGoToLogin() {
    if (kIsWeb) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);
    if (authAsync.hasValue && authAsync.value == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _redirectToLogin('No user logged in'));
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    }

    final roleAsync = ref.watch(currentUserRoleProvider);

    return roleAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary))),
      error: (e, st) {
        logger.e('Error resolving role: $e');
        return Scaffold(
          body: Center(
            child: Text('Something went wrong loading your account.', style: GoogleFonts.poppins()),
          ),
        );
      },
      data: (info) => _buildWithRole(info),
    );
  }

  Widget _buildWithRole(UserRoleInfo info) {
    final currentRole = info.roleLabel;
    final organization = info.organization;
    final isServiceProviderOrg = info.isServiceProviderOrg;

    final isOrganizationSelectionActive = isServiceProviderOrg && _selectedOrganizationId == null;
    final isFacilitySelectionActive = isServiceProviderOrg
        ? (_selectedOrganizationId != null && _selectedFacilityId == null)
        : (_selectedFacilityId == null);
    final displayOrganizationName = isServiceProviderOrg ? _selectedOrganizationName : organization;
    final isFacilitySelected = _selectedFacilityId != null && _selectedFacilityId!.isNotEmpty;

    return PopScope(
      canPop: true,
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: isFacilitySelected
            ? ResponsiveScreenWrapper(
                title: currentRole == '-' ? 'Dashboard' : '$currentRole Dashboard',
                facilityId: _selectedFacilityId!,
                currentRole: currentRole,
                organization: organization,
                selectedOrganizationName: displayOrganizationName,
                onFacilityReset: _refreshFacilitiesView,
                actions: [
                  if (currentRole == 'Admin')
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: IconButton(
                        icon: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RoleAssignmentScreen()),
                          );
                        },
                        tooltip: 'Assign Technician Role',
                      ),
                    ),
                ],
                child: _buildMainContent(isOrganizationSelectionActive, isFacilitySelectionActive, isServiceProviderOrg, organization),
              )
            : Scaffold(
                key: _scaffoldKey,
                appBar: AppBar(
                  title: Text(
                    isOrganizationSelectionActive ? 'Select Organization' : 'Select Facility',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 22),
                  ),
                  flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 26),
                    onPressed: () => _handleBackNavigation(
                      isOrganizationSelectionActive: isOrganizationSelectionActive,
                      isServiceProviderOrg: isServiceProviderOrg,
                    ),
                    tooltip: 'Back',
                  ),
                ),
                body: DecoratedBox(
                  decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
                  child: _buildMainContent(isOrganizationSelectionActive, isFacilitySelectionActive, isServiceProviderOrg, organization),
                ),
              ),
      ),
    );
  }

  Widget _buildMainContent(
    bool isOrganizationSelectionActive,
    bool isFacilitySelectionActive,
    bool isServiceProviderOrg,
    String organization,
  ) {
    if (isOrganizationSelectionActive) {
      return OrganizationSelectionScreen(
        onOrganizationSelected: _onOrganizationSelected,
      );
    }

    return FacilityScreen(
      selectedFacilityId: _selectedFacilityId,
      onFacilitySelected: _onFacilitySelected,
      isSelectionActive: isFacilitySelectionActive,
      userOrganization: isServiceProviderOrg ? _selectedOrganizationName : organization,
      isServiceProvider: isServiceProviderOrg,
    );
  }
}
