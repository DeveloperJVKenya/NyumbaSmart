import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cmms/services/geocoding_service.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

/// Coordinates + resolved address the user confirmed in the picker.
class LocationPickResult {
  final double latitude;
  final double longitude;
  final String? address;

  const LocationPickResult({required this.latitude, required this.longitude, this.address});
}

/// Kenya-centered default so a first-time picker (no existing coordinates)
/// opens somewhere useful rather than the middle of the ocean — matches the
/// Kenya geocoding bias used elsewhere in this app (GeocodingService).
const LatLng _kenyaDefault = LatLng(-1.2921, 36.8219);

/// Interactive tap/drag-to-place-pin map for capturing a facility's
/// location, shared by the facility creation form and the Locations
/// screen's "Edit Location" action. Falls back to address-only entry on
/// platforms `google_maps_flutter` doesn't support (see
/// [AppPlatform.mapsSupported]).
class LocationPickerMap extends StatefulWidget {
  final double? initialLatitude;
  final double? initialLongitude;
  final String? initialAddress;

  const LocationPickerMap({super.key, this.initialLatitude, this.initialLongitude, this.initialAddress});

  /// Opens the picker as a full-screen dialog route and returns the
  /// confirmed result, or null if the user cancelled.
  static Future<LocationPickResult?> show(
    BuildContext context, {
    double? initialLatitude,
    double? initialLongitude,
    String? initialAddress,
  }) {
    return Navigator.of(context).push<LocationPickResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => LocationPickerMap(
          initialLatitude: initialLatitude,
          initialLongitude: initialLongitude,
          initialAddress: initialAddress,
        ),
      ),
    );
  }

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  final GeocodingService _geocodingService = GeocodingService();
  final TextEditingController _searchController = TextEditingController();

  LatLng? _picked;
  String? _resolvedAddress;
  bool _resolving = false;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _picked = LatLng(widget.initialLatitude!, widget.initialLongitude!);
    }
    _resolvedAddress = widget.initialAddress;
    if (widget.initialAddress != null) _searchController.text = widget.initialAddress!;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _selectPoint(LatLng point) async {
    setState(() {
      _picked = point;
      _resolving = true;
    });
    final address = await _geocodingService.reverseGeocode(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      _resolvedAddress = address;
      _resolving = false;
    });
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    setState(() => _searching = true);
    final coords = await _geocodingService.geocode(query);
    if (!mounted) return;
    setState(() => _searching = false);
    if (coords == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not find that location', style: GoogleFonts.poppins())),
      );
      return;
    }
    await _selectPoint(LatLng(coords.latitude, coords.longitude));
  }

  void _confirm() {
    final point = _picked;
    if (point == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pick a location first', style: GoogleFonts.poppins())),
      );
      return;
    }
    Navigator.of(context).pop(
      LocationPickResult(latitude: point.latitude, longitude: point.longitude, address: _resolvedAddress),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Location'),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
        actions: [
          TextButton(
            onPressed: _confirm,
            child: const Text('Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: AppPlatform.mapsSupported ? _buildMapBody() : _buildDesktopBody(),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: (_) => _searchAddress(),
              decoration: InputDecoration(
                hintText: 'Search for an address...',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  borderSide: BorderSide(color: AppColors.textSecondary.withValues(alpha: 0.25)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _searching ? null : _searchAddress,
              style: ElevatedButton.styleFrom(shape: const CircleBorder(), padding: EdgeInsets.zero, minimumSize: const Size(48, 48)),
              child: _searching
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.arrow_forward_rounded),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapBody() {
    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: GoogleMap(
            initialCameraPosition: CameraPosition(target: _picked ?? _kenyaDefault, zoom: _picked != null ? 15 : 6),
            onTap: _selectPoint,
            markers: _picked == null
                ? {}
                : {
                    Marker(
                      markerId: const MarkerId('picked_location'),
                      position: _picked!,
                      draggable: true,
                      onDragEnd: _selectPoint,
                    ),
                  },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: true,
            mapToolbarEnabled: false,
          ),
        ),
        _buildResolvedAddressBar(),
      ],
    );
  }

  Widget _buildResolvedAddressBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          const Icon(Icons.place_rounded, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: _resolving
                ? Text('Resolving address...', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13))
                : Text(
                    _resolvedAddress ?? (_picked == null ? 'Tap the map or search to place a pin' : 'Location selected'),
                    style: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textPrimary),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopBody() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            child: Row(
              children: [
                const Icon(Icons.desktop_windows_rounded, color: AppColors.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'An interactive map isn\'t available on this platform. Search for an address to resolve its coordinates instead.',
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _searchController,
                  label: 'Address',
                  icon: Icons.search_rounded,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 54,
                child: ElevatedButton(
                  onPressed: _searching ? null : _searchAddress,
                  // Local override: the theme's default minimumSize is
                  // Size(double.infinity, 54), which inside this Row's
                  // non-flexible slot (next to an Expanded sibling) asks
                  // for infinite width and breaks layout. Content-hugging
                  // with generous padding instead.
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 54), padding: const EdgeInsets.symmetric(horizontal: 24)),
                  child: _searching
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Find'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_picked != null)
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resolved location', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  Text(_resolvedAddress ?? '${_picked!.latitude}, ${_picked!.longitude}', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
