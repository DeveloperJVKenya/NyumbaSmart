import 'package:cloud_firestore/cloud_firestore.dart';

/// Links a client user to a facility.
/// Stored at `facilities/{facilityId}/clientLinks/{uid}`.
class ClientFacilityLink {
  final String uid;
  final String facilityId;
  final DateTime linkedAt;
  final bool active;
  final String? linkedByUid;

  const ClientFacilityLink({
    required this.uid,
    required this.facilityId,
    required this.linkedAt,
    this.active = true,
    this.linkedByUid,
  });

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'facilityId': facilityId,
        'linkedAt': Timestamp.fromDate(linkedAt),
        'active': active,
        'linkedByUid': linkedByUid,
      };

  factory ClientFacilityLink.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return ClientFacilityLink(
      uid: doc.id,
      facilityId: d['facilityId'] as String? ?? '',
      linkedAt: (d['linkedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      active: d['active'] as bool? ?? true,
      linkedByUid: d['linkedByUid'] as String?,
    );
  }
}
