import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/models/facility.dart';
import 'package:cmms/models/user_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/services/geocoding_service.dart';
import 'package:cmms/widgets/location_picker_map.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class LocationsScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const LocationsScreen({super.key, required this.facilityId});

  @override
  ConsumerState<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends ConsumerState<LocationsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final GeocodingService _geocodingService = GeocodingService();

  Facility? _facility;
  LatLng? _facilityLatLng;
  Position? _currentPosition;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadFacility();
  }

  Future<void> _loadFacility() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('Facilities').doc(widget.facilityId).get();
      if (!doc.exists) {
        setState(() {
          _loadError = 'Facility not found';
          _isLoading = false;
        });
        return;
      }

      final facility = Facility.fromFirestore(doc);
      LatLng? latLng;

      if (facility.hasCoordinates) {
        latLng = LatLng(facility.latitude!, facility.longitude!);
      } else {
        // Facility was saved before geocoding existed (or geocoding failed
        // at save time) — resolve it now and self-heal Firestore so future
        // loads skip this round trip.
        final coords = await _geocodingService.geocode(
          (facility.address != null && facility.address!.isNotEmpty) ? facility.address! : facility.location,
        );
        if (coords != null) {
          latLng = LatLng(coords.latitude, coords.longitude);
          FirebaseFirestore.instance
              .collection('Facilities')
              .doc(widget.facilityId)
              .update({'geoLocation': GeoPoint(coords.latitude, coords.longitude)})
              .then((_) => _logger.i('Self-healed geoLocation for ${widget.facilityId}'))
              .catchError((e) => _logger.e('Failed to self-heal geoLocation: $e'));
        }
      }

      _getCurrentPosition();

      if (mounted) {
        setState(() {
          _facility = facility;
          _facilityLatLng = latLng;
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Error loading facility: $e');
      if (mounted) {
        setState(() {
          _loadError = 'Error loading facility: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _getCurrentPosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      );
      if (mounted) setState(() => _currentPosition = position);
    } catch (e) {
      _logger.w('Could not get current position: $e');
    }
  }

  /// A resolvable text fallback when there are no coordinates: prefer the
  /// full street address over the short "Location" label (e.g. "Nairobi CBD
  /// Office"), since Maps can't geocode a made-up nickname.
  String? get _fallbackDestinationText {
    final facility = _facility;
    if (facility == null) return null;
    if (facility.address != null && facility.address!.isNotEmpty) return facility.address;
    if (facility.location.isNotEmpty) return facility.location;
    return null;
  }

  Future<void> _openDirections() async {
    if (_facility == null) return;
    try {
      final destination = _facilityLatLng != null
          ? '${_facilityLatLng!.latitude},${_facilityLatLng!.longitude}'
          : _fallbackDestinationText;
      if (destination == null) {
        _showSnackBar('No location details available for directions');
        return;
      }
      // Built via Uri.https' queryParameters (not raw string concatenation)
      // so the destination/origin are always correctly encoded and placed
      // in the documented `/maps/dir/?api=1&...` query form — the previous
      // version spliced coordinates/text directly into the path, which
      // produced a broken or origin-less URL whenever the current position
      // was unavailable.
      final url = Uri.https('www.google.com', '/maps/dir/', {
        'api': '1',
        'destination': destination,
        'travelmode': 'driving',
        if (_currentPosition != null) 'origin': '${_currentPosition!.latitude},${_currentPosition!.longitude}',
      });
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar('Could not open Google Maps');
      }
    } catch (e) {
      _logger.e('Error opening directions: $e');
      _showSnackBar('Error getting directions: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
    }
  }

  /// Only Developers (fixing legacy/mis-geocoded facilities) or Admins
  /// belonging to the JV Almacis service-provider org (the contractor side
  /// that manages client facilities day to day) may correct a location.
  bool _canEditLocation(UserRoleInfo? roleInfo) {
    if (roleInfo == null) return false;
    return roleInfo.isDeveloper || (roleInfo.role == UserRole.admin && roleInfo.isServiceProviderOrg);
  }

  Future<void> _editLocation() async {
    final facility = _facility;
    if (facility == null) return;

    final result = await LocationPickerMap.show(
      context,
      initialLatitude: _facilityLatLng?.latitude,
      initialLongitude: _facilityLatLng?.longitude,
      initialAddress: facility.address,
    );
    if (result == null || !mounted) return;

    try {
      // Every confirmed pick is authoritative: the short "Location" label
      // is always resynced from the freshly-picked point, not just when it
      // was blank, so what's shown here (and fed into Get Directions) never
      // drifts from the coordinates actually selected on the map.
      final newLocation = result.address != null && result.address!.isNotEmpty
          ? result.address!.split(',').first.trim()
          : facility.location;

      await FirebaseFirestore.instance.collection('Facilities').doc(widget.facilityId).update({
        'geoLocation': GeoPoint(result.latitude, result.longitude),
        if (result.address != null && result.address!.isNotEmpty) 'address': result.address,
        if (newLocation != facility.location) 'location': newLocation,
      });
      if (!mounted) return;
      setState(() {
        _facilityLatLng = LatLng(result.latitude, result.longitude);
        _facility = Facility(
          id: facility.id,
          name: facility.name,
          location: newLocation,
          address: result.address ?? facility.address,
          organization: facility.organization,
          createdAt: facility.createdAt,
          createdBy: facility.createdBy,
          latitude: result.latitude,
          longitude: result.longitude,
        );
      });
      _showSnackBar('Location updated');
    } catch (e) {
      _logger.e('Error updating location: $e');
      _showSnackBar('Error updating location: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).valueOrNull;
    final canEdit = _canEditLocation(roleInfo);

    return ResponsiveScreenWrapper(
      title: 'Facility Location',
      // Was hardcoded to '' — the sidebar's "select a facility first" guard
      // (_handleSubMenuNavigation in responsive_screen_wrapper.dart) reads
      // this exact value, so switching menus from within Locations always
      // looked like no facility was selected even though one was.
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? 'User',
      organization: roleInfo?.organization ?? '-',
      floatingActionButton: canEdit && !_isLoading && _loadError == null
          ? FloatingActionButton.extended(
              onPressed: _editLocation,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.edit_location_alt_rounded, color: Colors.white),
              label: Text('Edit Location', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
            )
          : null,
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: _isLoading
            ? const Padding(padding: EdgeInsets.all(20), child: AppSkeletonList(count: 3, itemHeight: 140))
            : _loadError != null
                ? _buildError(_loadError!)
                : _buildContent(),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(message, style: GoogleFonts.poppins(color: AppColors.textSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final facility = _facility;
    if (facility == null) return _buildError('Facility details not available');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              facility.name,
              style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow(Icons.location_on_rounded, 'Location', facility.location),
                  if (facility.address != null && facility.address!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _detailRow(Icons.home_rounded, 'Address', facility.address!),
                  ],
                  const SizedBox(height: 10),
                  _detailRow(Icons.business_rounded, 'Organization', facility.organization),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (AppPlatform.mapsSupported) _buildMapPanel() else _buildDesktopFallback(),
            const SizedBox(height: AppSpacing.lg),
            Center(child: AppGradientButton(label: 'Get Directions', icon: Icons.directions_rounded, onPressed: _openDirections)),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 10),
        SizedBox(
          width: 96,
          child: Text(label, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary))),
      ],
    );
  }

  Widget _buildMapPanel() {
    final markers = <Marker>{
      if (_currentPosition != null)
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      if (_facilityLatLng != null)
        Marker(
          markerId: const MarkerId('facility_location'),
          position: _facilityLatLng!,
          infoWindow: InfoWindow(title: _facility!.name, snippet: _facility!.location),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
    };

    if (_facilityLatLng == null) {
      return AppCard(
        child: Column(
          children: [
            const Icon(Icons.location_off_rounded, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 8),
            Text(
              'Could not resolve a map location for this address.',
              style: GoogleFonts.poppins(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 320,
        child: GoogleMap(
          initialCameraPosition: CameraPosition(target: _facilityLatLng!, zoom: 13),
          markers: markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          zoomControlsEnabled: true,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }

  Widget _buildDesktopFallback() {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.desktop_windows_rounded, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'An interactive map isn\'t available on this platform yet — use "Get Directions" below.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
