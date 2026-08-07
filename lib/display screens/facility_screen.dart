import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/facility.dart';
import 'package:cmms/services/geocoding_service.dart';
import 'package:cmms/widgets/location_picker_map.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class FacilityScreen extends StatefulWidget {
  final String? selectedFacilityId;
  final void Function(String) onFacilitySelected;
  final bool isSelectionActive;
  final String? userOrganization; // User's organization for filtering
  final bool isServiceProvider; // Whether user is a service provider

  const FacilityScreen({
    super.key,
    required this.selectedFacilityId,
    required this.onFacilitySelected,
    required this.isSelectionActive,
    this.userOrganization,
    this.isServiceProvider = false,
  });

  @override
  FacilityScreenState createState() => FacilityScreenState();
}

class FacilityScreenState extends State<FacilityScreen> {
  final Logger logger = Logger(printer: PrettyPrinter());
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ScrollController _scrollController = ScrollController();
  bool _isAddingFacility = false;
  LocationPickResult? _pickedLocation;

  late Stream<QuerySnapshot<Map<String, dynamic>>> _facilitiesStream;

  @override
  void initState() {
    super.initState();
    _facilitiesStream = _buildFacilitiesStream();
  }

  @override
  void didUpdateWidget(covariant FacilityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild (re-attach) the Firestore listener when the org filter
    // actually changes — not on every parent rebuild.
    if (oldWidget.userOrganization != widget.userOrganization) {
      _facilitiesStream = _buildFacilitiesStream();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _addressController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Check if user is new (no role/organization assigned)
  bool get _isNewUser => widget.userOrganization == '-' || widget.userOrganization == null;

  // Get user's organization for facility creation
  Future<String> _getUserOrganization() async {
    if (widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-') {
      return widget.userOrganization!;
    }

    // Fallback: get organization from user data
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Embassy'; // Default fallback

    try {
      // Check Technicians collection first
      final technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(user.uid)
          .get();

      if (technicianDoc.exists) {
        return technicianDoc.data()?['organization'] ?? 'Embassy';
      }

      // Check Users collection
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      if (userDoc.exists) {
        return userDoc.data()?['organization'] ?? 'Embassy';
      }
    } catch (e) {
      logger.e('Error getting user organization: $e');
    }

    return 'Embassy'; // Default fallback
  }

  Future<void> _addFacility() async {
    if (_formKey.currentState!.validate()) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Please log in to add a facility', style: GoogleFonts.poppins())),
          );
          return;
        }

        // Get organization for the facility
        final organizationForFacility = await _getUserOrganization();
        logger.i('Creating facility with organization: $organizationForFacility');

        final locationText = _locationController.text.trim();
        final addressText = _pickedLocation?.address ?? _addressController.text.trim();

        // Prefer the map-picker's confirmed coordinates. Only fall back to
        // blind geocoding-from-text if the user skipped the picker
        // entirely, so the form still works without forcing map use.
        final coordinates = _pickedLocation != null
            ? GeoCoordinates(_pickedLocation!.latitude, _pickedLocation!.longitude)
            : await GeocodingService().geocode(addressText.isNotEmpty ? addressText : locationText);

        final facility = Facility(
          id: '',
          name: _nameController.text.trim(),
          location: locationText,
          address: addressText.isNotEmpty ? addressText : null,
          organization: organizationForFacility, // Include organization
          createdAt: DateTime.now(),
          createdBy: user.uid,
          latitude: coordinates?.latitude,
          longitude: coordinates?.longitude,
        );

        final ref = await FirebaseFirestore.instance.collection('Facilities').add(facility.toFirestore());
        widget.onFacilitySelected(ref.id);
        _nameController.clear();
        _locationController.clear();
        _addressController.clear();
        setState(() {
          _isAddingFacility = false;
          _pickedLocation = null;
        });
        logger.i('Facility added: ${ref.id} with organization: $organizationForFacility');
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Facility added successfully', style: GoogleFonts.poppins())),
          );
        }
      } catch (e) {
        logger.e('Error adding facility: $e');
        if (mounted) {
          _messengerKey.currentState?.showSnackBar(
            SnackBar(content: Text('Error adding facility: $e', style: GoogleFonts.poppins())),
          );
        }
      }
    }
  }

  void _cancelAddingFacility() {
    setState(() {
      _isAddingFacility = false;
      _pickedLocation = null;
    });
    _nameController.clear();
    _locationController.clear();
    _addressController.clear();
  }

  Future<void> _pickLocation() async {
    final result = await LocationPickerMap.show(
      context,
      initialLatitude: _pickedLocation?.latitude,
      initialLongitude: _pickedLocation?.longitude,
      initialAddress: _pickedLocation?.address ?? _addressController.text.trim(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickedLocation = result;
      if (result.address != null && result.address!.isNotEmpty) {
        _addressController.text = result.address!;
      }
    });
  }

  // Build query based on user type and organization
  Stream<QuerySnapshot<Map<String, dynamic>>> _buildFacilitiesStream() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('Facilities');

    // Filter by organization if user is not a service provider or if specific organization is selected
    if (widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-') {
      query = query.where('organization', isEqualTo: widget.userOrganization);
      logger.i('Filtering facilities by organization: ${widget.userOrganization}');
    }

    // Order by createdAt descending
    query = query.orderBy('createdAt', descending: true);

    return query.snapshots();
  }

  Widget _buildAddFacilityForm() {
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = screenHeight - keyboardHeight - kToolbarHeight - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: availableHeight,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 100.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: _cancelAddingFacility,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: AppColors.textPrimary,
                  ),
                  Text(
                    'Add New Facility',
                    style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-') ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Organization', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      const SizedBox(height: 4),
                      Text(widget.userOrganization!, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              AppTextField(controller: _nameController, label: 'Facility Name *', icon: Icons.business_rounded, validator: (value) => value!.isEmpty ? 'Enter facility name' : null),
              const SizedBox(height: 16),
              AppTextField(controller: _locationController, label: 'Location', icon: Icons.location_on_rounded),
              const SizedBox(height: 16),
              Text('Address', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (_pickedLocation != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.place_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _addressController.text.isNotEmpty
                              ? _addressController.text
                              : '${_pickedLocation!.latitude}, ${_pickedLocation!.longitude}',
                          style: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textPrimary),
                        ),
                      ),
                      TextButton(onPressed: _pickLocation, child: const Text('Change')),
                    ],
                  ),
                )
              else
                OutlinedButton.icon(
                  onPressed: _pickLocation,
                  icon: const Icon(Icons.map_rounded, size: 18),
                  label: const Text('Pick Location on Map'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _cancelAddingFacility,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.35)),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: AppGradientButton(label: 'Add Facility', onPressed: _addFacility)),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFacilitiesList(bool isMobile) {
    return StreamBuilder<QuerySnapshot>(
      stream: _facilitiesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const AppSkeletonList(count: 5, itemHeight: 128);
        }

        if (snapshot.hasError) {
          logger.e('Firestore error: ${snapshot.error}');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
                const SizedBox(height: 16),
                Text('Error loading facilities', style: GoogleFonts.poppins(fontSize: 16, color: AppColors.error, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('${snapshot.error}', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13), textAlign: TextAlign.center),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.business_rounded, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                const SizedBox(height: 16),
                Text(
                  widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-'
                      ? 'No facilities found for ${widget.userOrganization}'
                      : 'No facilities added yet',
                  style: GoogleFonts.poppins(fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text('Tap the + button to add a new facility', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary.withValues(alpha: 0.8)), textAlign: TextAlign.center),
              ],
            ),
          );
        }

        final facilities = docs.map((doc) => Facility.fromFirestore(doc)).toList();
        logger.i('Fetched ${facilities.length} facilities from Firestore for organization: ${widget.userOrganization ?? 'all'}');

        return GridView.builder(
          padding: const EdgeInsets.only(bottom: 88),
          gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: isMobile ? 5000 : 420,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            mainAxisExtent: 152,
          ),
          itemCount: facilities.length,
          itemBuilder: (context, index) {
            final facility = facilities[index];
            final isSelected = facility.id == widget.selectedFacilityId;
            final isInteractable = widget.isSelectionActive || isSelected;
            return _FacilityCard(
              facility: facility,
              isSelected: isSelected,
              isInteractable: isInteractable,
              onTap: isInteractable
                  ? () {
                      widget.onFacilitySelected(facility.id);
                      logger.i('Selected facility: ${facility.name}, ID: ${facility.id}, Organization: ${facility.organization}');
                    }
                  : null,
            );
          },
        );
      },
    );
  }

  // Method to check user role and refresh the screen
  Future<void> _checkUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      logger.w('No user logged in');
      return;
    }

    try {
      logger.i('Refreshing user role and organization for user: ${user.uid}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
                const SizedBox(width: 16),
                Text('Checking for role updates...', style: GoogleFonts.poppins()),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.primaryDark,
          ),
        );
      }

      if (mounted) setState(() {});
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Screen refreshed! If your role was updated, the interface will change automatically.', style: GoogleFonts.poppins()),
            duration: const Duration(seconds: 3),
            backgroundColor: AppColors.success,
          ),
        );
      }

      logger.i('User role refresh completed');
    } catch (e) {
      logger.e('Error refreshing user role: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing screen: $e', style: GoogleFonts.poppins()), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _buildNewUserMessage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom - kToolbarHeight - 32,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(gradient: AppColors.primaryGradient, shape: BoxShape.circle),
              child: const Icon(Icons.waving_hand_rounded, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text('Welcome to NyumbaSmart', style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('The ultimate system for your maintenance success!', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            AppCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text('Getting Started', style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Text(
                    'To access all features tailored for you, please reach out to your system administrator for role assignment.',
                    style: GoogleFonts.poppins(fontSize: 14.5, color: AppColors.textSecondary, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The interface will update automatically once your role is assigned. If it doesn\'t update, use the refresh button below.',
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary.withValues(alpha: 0.85), height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 220,
              child: AppGradientButton(label: 'Refresh Screen', icon: Icons.refresh_rounded, onPressed: _checkUserRole),
            ),
            const SizedBox(height: 24),
            Text('Need help? Contact your system administrator.', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = AppBreakpoints.isMobile(screenWidth);
    final isDesktop = AppBreakpoints.isDesktop(screenWidth);
    final contentWidth = isDesktop ? screenWidth * 0.7 : screenWidth;

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Center(
              child: SizedBox(
                width: contentWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_isAddingFacility && !_isNewUser) ...[
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isServiceProvider && widget.userOrganization != null ? '${widget.userOrganization} Facilities' : 'Your Facilities',
                              style: GoogleFonts.poppins(fontSize: isMobile ? 20 : 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 6),
                            Text('Select a facility to manage its maintenance tasks', style: GoogleFonts.poppins(fontSize: isMobile ? 13 : 15, color: AppColors.textSecondary)),
                            if (widget.userOrganization != null && widget.userOrganization!.isNotEmpty && widget.userOrganization != '-') ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadius.pill)),
                                child: Text('Organization: ${widget.userOrganization}', style: GoogleFonts.poppins(fontSize: isMobile ? 11.5 : 13, color: AppColors.primaryDark, fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    Expanded(
                      child: _isAddingFacility
                          ? _buildAddFacilityForm()
                          : _isNewUser
                              ? _buildNewUserMessage()
                              : Padding(padding: const EdgeInsets.symmetric(horizontal: 20.0), child: _buildFacilitiesList(isMobile)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        floatingActionButton: _isAddingFacility || _isNewUser
            ? null
            : FloatingActionButton.extended(
                onPressed: () => setState(() => _isAddingFacility = true),
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: Text('Add Facility', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
      ),
    );
  }
}

class _FacilityCard extends StatelessWidget {
  final Facility facility;
  final bool isSelected;
  final bool isInteractable;
  final VoidCallback? onTap;

  const _FacilityCard({required this.facility, required this.isSelected, required this.isInteractable, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = isSelected ? Colors.white : (isInteractable ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6));
    final fgMuted = isSelected ? Colors.white.withValues(alpha: 0.85) : (isInteractable ? AppColors.textSecondary : AppColors.textSecondary.withValues(alpha: 0.5));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : (isInteractable ? AppColors.card : AppColors.surfaceAlt.withValues(alpha: 0.6)),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: isSelected
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))]
                : [BoxShadow(color: AppColors.primary.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(facility.name, style: GoogleFonts.poppins(fontSize: 16.5, fontWeight: FontWeight.bold, color: fg), overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withValues(alpha: 0.2) : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(facility.organization, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w500, color: isSelected ? Colors.white.withValues(alpha: 0.9) : AppColors.primaryDark)),
                  ),
                ],
              ),
              if (facility.location.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded, size: 15, color: fgMuted),
                    const SizedBox(width: 4),
                    Expanded(child: Text(facility.location, style: GoogleFonts.poppins(fontSize: 13, color: fgMuted), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
              if (facility.address != null && facility.address!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.home_rounded, size: 15, color: fgMuted),
                    const SizedBox(width: 4),
                    Expanded(child: Text(facility.address!, style: GoogleFonts.poppins(fontSize: 12, color: fgMuted), overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ],
              const Spacer(),
              Text('Added: ${facility.createdAt.toLocal().toString().split(' ')[0]}', style: GoogleFonts.poppins(fontSize: 11, color: fgMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
