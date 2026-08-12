import 'package:geocoding/geocoding.dart';
import 'package:logger/logger.dart';

/// Simple lat/lng pair — avoids pulling `google_maps_flutter`'s `LatLng`
/// into non-map screens/services that only need coordinates.
class GeoCoordinates {
  final double latitude;
  final double longitude;
  const GeoCoordinates(this.latitude, this.longitude);
}

/// Thin wrapper around package:geocoding shared by the facility form
/// (geocode on save) and the Locations screen (lazy geocode + self-heal
/// for facilities saved before this feature existed).
///
/// Facilities in this app are predominantly Kenya-based (JV Almacis /
/// embassy clients), so queries are biased with a ", Kenya" suffix to
/// disambiguate short local place names — this is a deliberate product
/// choice, not a hardcoded assumption to "fix" later.
class GeocodingService {
  GeocodingService({Logger? logger}) : _logger = logger ?? Logger(printer: PrettyPrinter());

  final Logger _logger;
  final Geocoding _geocoding = Geocoding();

  Future<GeoCoordinates?> geocode(String query) async {
    if (query.trim().isEmpty) return null;
    try {
      final results = await _geocoding.locationFromAddress('$query, Kenya');
      if (results.isEmpty) return null;
      return GeoCoordinates(results.first.latitude, results.first.longitude);
    } catch (e) {
      _logger.w('Geocoding failed for "$query": $e');
      return null;
    }
  }

  /// Coordinates → human-readable address, used by the map picker to show
  /// what a dropped/dragged pin resolves to.
  Future<String?> reverseGeocode(double latitude, double longitude) async {
    try {
      final placemarks = await _geocoding.placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      final parts = [p.street, p.subLocality, p.locality, p.administrativeArea, p.country]
          .where((part) => part != null && part.trim().isNotEmpty)
          .toList();
      return parts.isEmpty ? null : parts.join(', ');
    } catch (e) {
      _logger.w('Reverse geocoding failed for ($latitude, $longitude): $e');
      return null;
    }
  }
}
