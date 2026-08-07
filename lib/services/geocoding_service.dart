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

  Future<GeoCoordinates?> geocode(String query) async {
    if (query.trim().isEmpty) return null;
    try {
      final results = await locationFromAddress('$query, Kenya');
      if (results.isEmpty) return null;
      return GeoCoordinates(results.first.latitude, results.first.longitude);
    } catch (e) {
      _logger.w('Geocoding failed for "$query": $e');
      return null;
    }
  }
}
