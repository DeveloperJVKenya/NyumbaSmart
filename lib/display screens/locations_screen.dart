import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/models/facility.dart';
import 'package:cmms/services/geocoding_service.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

/// `google_maps_flutter` only ships Android/iOS/Web implementations — no
/// desktop (Windows/macOS/Linux) backend exists. Rather than let the plugin
/// fail unpredictably there, the screen deliberately checks this and shows
/// an address-details + "open externally" fallback on unsupported platforms.
/// `defaultTargetPlatform` reflects the host OS even on web, so the `kIsWeb`
/// check must come first.
bool get _mapsSupportedOnThisPlatform =>
    kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS;

class LocationsScreen extends StatefulWidget {
  final String facilityId;

  const LocationsScreen({super.key, required this.facilityId});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
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

  Future<void> _openDirections() async {
    if (_facility == null) return;
    try {
      final destination = _facilityLatLng != null
          ? '${_facilityLatLng!.latitude},${_facilityLatLng!.longitude}'
          : Uri.encodeComponent(_facility!.location);
      final origin = _currentPosition != null ? '${_currentPosition!.latitude},${_currentPosition!.longitude}/' : '';
      final url = Uri.parse('https://www.google.com/maps/dir/$origin$destination');
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

  Future<void> _openInMaps() async {
    if (_facility == null) return;
    final query = _facilityLatLng != null
        ? '${_facilityLatLng!.latitude},${_facilityLatLng!.longitude}'
        : Uri.encodeComponent(_facility!.location);
    final url = Uri.parse('https://www.google.com/maps/search/?api=1&query=$query');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar('Could not open Google Maps');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Facility Location',
      facilityId: '',
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
            if (_mapsSupportedOnThisPlatform) _buildMapPanel() else _buildDesktopFallback(),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(child: AppGradientButton(label: 'Get Directions', icon: Icons.directions_rounded, onPressed: _openDirections)),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openInMaps,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open in Maps'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary, side: const BorderSide(color: AppColors.primary)),
                  ),
                ),
              ],
            ),
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
              'An interactive map isn\'t available on this platform yet — use "Open in Maps" or "Get Directions" below.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
