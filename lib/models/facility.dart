import 'package:cloud_firestore/cloud_firestore.dart';

class Facility {
  final String id;
  final String name;
  final String location;
  final String? address;
  final String organization;
  final DateTime createdAt;
  final String createdBy;
  final double? latitude;
  final double? longitude;

  Facility({
    required this.id,
    required this.name,
    required this.location,
    this.address,
    required this.organization,
    required this.createdAt,
    required this.createdBy,
    this.latitude,
    this.longitude,
  });

  bool get hasCoordinates => latitude != null && longitude != null;

  factory Facility.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final geoLocation = data['geoLocation'];
    return Facility(
      id: doc.id,
      name: data['name'] ?? '',
      location: data['location'] ?? '',
      address: data['address'],
      organization: data['organization'] ?? 'Embassy',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      latitude: geoLocation is GeoPoint ? geoLocation.latitude : null,
      longitude: geoLocation is GeoPoint ? geoLocation.longitude : null,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'location': location,
      'address': address,
      'organization': organization,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      if (hasCoordinates) 'geoLocation': GeoPoint(latitude!, longitude!),
    };
  }

  Facility copyWithCoordinates(double latitude, double longitude) {
    return Facility(
      id: id,
      name: name,
      location: location,
      address: address,
      organization: organization,
      createdAt: createdAt,
      createdBy: createdBy,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
