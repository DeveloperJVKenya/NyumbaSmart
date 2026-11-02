import 'package:cmms/display%20screens/role_assignment_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/display%20screens/facility_screen.dart';
import 'package:cmms/screens/dashboard_home_screen.dart';
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
  String? _selectedFacilityName;
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

  void _onFacilitySelected(String facilityId, String facilityName) {
    setState(() {
      _selectedFacilityId = facilityId;
      _selectedFacilityName = facilityName;
    });
    logger.i('Selected facility: $facilityName ($facilityId)');

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
    final info = ref.read(currentUserRoleProvider).value;
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
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const LoginScreen()),
      (route) => false,
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

  /// Backing all the way out of organization/facility selection with
  /// nothing left to pop to used to just push [LoginScreen] on top while
  /// the Firebase session stayed signed in — the screen looked like a
  /// logout but wasn't one, so re-entering the app (or any stale route)
  /// could bounce the user straight back to the dashboard. Sign out for
  /// real first so what's on screen matches the actual auth state.
  Future<void> _exitOrGoToLogin() async {
    if (kIsWeb) {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
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
      // While the org/facility picker is showing, route the hardware/
      // browser back gesture through the same _handleBackNavigation logic
      // the AppBar's back arrow already uses — previously the system
      // back bypassed it entirely and fell through to a default pop,
      // producing different (and less predictable) behavior from tapping
      // the visible arrow. Once a facility is selected there's nothing
      // left below this route (the auth stack is cleared on sign-in), so
      // the default pop is a no-op and safe to leave alone.
      canPop: isFacilitySelected,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation(
          isOrganizationSelectionActive: isOrganizationSelectionActive,
          isServiceProviderOrg: isServiceProviderOrg,
        );
      },
      child: ScaffoldMessenger(
        key: _messengerKey,
        child: isFacilitySelected
            ? ResponsiveScreenWrapper(
                title: currentRole == '-' ? 'Dashboard' : '$currentRole Dashboard',
                facilityId: _selectedFacilityId!,
                facilityName: _selectedFacilityName,
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
                child: DashboardHomeScreen(
                  facilityId: _selectedFacilityId!,
                  facilityName: _selectedFacilityName ?? '',
                  organization: displayOrganizationName ?? organization,
                  role: currentRole,
                ),
              )
            : _buildMainContent(isOrganizationSelectionActive, isFacilitySelectionActive, isServiceProviderOrg, organization),
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
        onBack: _exitOrGoToLogin,
      );
    }

    return FacilityScreen(
      selectedFacilityId: _selectedFacilityId,
      onFacilitySelected: _onFacilitySelected,
      isSelectionActive: isFacilitySelectionActive,
      userOrganization: isServiceProviderOrg ? _selectedOrganizationName : organization,
      isServiceProvider: isServiceProviderOrg,
      onBack: isFacilitySelectionActive
          ? () => _handleBackNavigation(
                isOrganizationSelectionActive: false,
                isServiceProviderOrg: isServiceProviderOrg,
              )
          : null,
    );
  }
}
