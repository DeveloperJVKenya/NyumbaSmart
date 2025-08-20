import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/models/facility.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class LocationsScreen extends StatefulWidget {
  final String facilityId;

  const LocationsScreen({super.key, required this.facilityId});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  Facility? _facility; // Store the selected facility
  bool _isLoading = true; // Loading state

  @override
  void initState() {
    super.initState();
    _fetchFacilityDetails(); // Fetch facility details on initialization
  }

  /// Fetch facility details from Firestore
  Future<void> _fetchFacilityDetails() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('Facilities')
          .doc(widget.facilityId)
          .get();

      if (doc.exists) {
        setState(() {
          _facility = Facility.fromFirestore(doc);
          _isLoading = false; // Set loading to false once data is fetched
        });
      } else {
        _logger.e('Facility not found');
        _showSnackBar('Facility not found');
      }
    } catch (e) {
      _logger.e('Error fetching facility details: $e');
      _showSnackBar('Error fetching facility details: $e');
    }
  }

  /// Shows a snackbar with the given message
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins())),
      );
    }
  }

  /// Opens Google Maps with directions from the current location to the facility
  Future<void> _openDirections() async {
    if (_facility == null) return;
    try {
      // Request location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Location permissions are permanently denied');
        return;
      }

      // Get current position
      final Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );

      // Create Google Maps directions URL using the facility's location name
      final String googleMapsUrl = 
          'https://www.google.com/maps/dir/${position.latitude},${position.longitude}/${Uri.encodeComponent(_facility!.location)}';

      final Uri url = Uri.parse(googleMapsUrl);
      
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
        _logger.i('Opened directions to ${_facility!.name} at ${_facility!.location}');
      } else {
        _showSnackBar('Could not open Google Maps');
      }
    } catch (e) {
      _logger.e('Error opening directions: $e');
      _showSnackBar('Error getting directions: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Facility Location',
      facilityId: '',
      child: _isLoading ? _buildLoadingIndicator() : _buildFacilityDetails(),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Center(child: CircularProgressIndicator());
  }

  Widget _buildFacilityDetails() {
    if (_facility == null) {
      return Center(child: Text('Facility details not available', style: GoogleFonts.poppins()));
    }

    return Center( // Center the entire content
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center( // Center the title
                child: Text(
                  _facility!.name,
                  style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(FontAwesomeIcons.locationDot, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    'Location:',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey[700]),
                  ),
                  const SizedBox(width: 8),
                  Expanded( // Use Expanded to fill available space
                    child: Text(
                      _facility!.location,
                      style: GoogleFonts.poppins(fontSize: 16),
                      overflow: TextOverflow.ellipsis, // Handle overflow
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(FontAwesomeIcons.building, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    'Organization:',
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey[700]),
                  ),
                  const SizedBox(width: 8),
                  Expanded( // Use Expanded to fill available space
                    child: Text(
                      _facility!.organization, // Assuming organization is a field in Facility
                      style: GoogleFonts.poppins(fontSize: 16),
                      overflow: TextOverflow.ellipsis, // Handle overflow
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _openDirections,
                icon: const Icon(Icons.directions),
                label: Text('Get Directions', style: GoogleFonts.poppins()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal, // Change button color
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  // Open Google Maps with the facility's location
                  final String googleMapsUrl = 
                      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(_facility!.location)}';
                  launchUrl(Uri.parse(googleMapsUrl), mode: LaunchMode.externalApplication);
                },
                icon: const Icon(Icons.map),
                label: Text('View on Map', style: GoogleFonts.poppins()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, // Change button color
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
