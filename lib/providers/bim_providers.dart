import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cmms/models/bim_model.dart';

/// All BIM models for a facility, newest-first.
/// Shared by BimModelsScreen (import history) and any screen that needs to
/// know what models are loaded for a facility.
final bimModelsProvider = StreamProvider.autoDispose
    .family<List<BimModel>, String>((ref, facilityId) => FirebaseFirestore
        .instance
        .collection('facilities')
        .doc(facilityId)
        .collection('bimModels')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(BimModel.fromSnapshot).toList()));

/// Total equipment count summed from active (ready) BIM models.
/// Matches what each model card shows and is used by PreventiveMaintenanceScreen
/// to detect stale AI analysis results when the equipment list changes.
final bimEquipmentCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, facilityId) => FirebaseFirestore.instance
        .collection('facilities')
        .doc(facilityId)
        .collection('bimModels')
        .where('status', isEqualTo: 'ready')
        .snapshots()
        .map((s) => s.docs.fold<int>(
              0,
              (acc, d) => acc + ((d.data()['equipmentCount'] as int?) ?? 0))));

/// Spaces snapshot for the BIM overview card (floors + rooms count).
final bimSpacesSnapshotProvider = StreamProvider.autoDispose
    .family<QuerySnapshot<Map<String, dynamic>>, String>((ref, facilityId) =>
        FirebaseFirestore.instance
            .collection('facilities')
            .doc(facilityId)
            .collection('spaces')
            .snapshots());

/// Live count of BIM-linked equipment in the equipment collection.
/// Reflects the true Firestore document count (goes to 0 after cascade delete).
final bimActualEquipmentCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, facilityId) => FirebaseFirestore.instance
        .collection('facilities')
        .doc(facilityId)
        .collection('equipment')
        .where('bimSource', whereIn: ['cobie', 'ifc'])
        .snapshots()
        .map((s) => s.docs.length));

/// Live count of BIM systems for the overview card.
final bimSystemsCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, facilityId) => FirebaseFirestore.instance
        .collection('facilities')
        .doc(facilityId)
        .collection('bimSystems')
        .snapshots()
        .map((s) => s.docs.length));

/// Live count of BIM contacts for the overview card.
final bimContactsCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, facilityId) => FirebaseFirestore.instance
        .collection('facilities')
        .doc(facilityId)
        .collection('bimContacts')
        .snapshots()
        .map((s) => s.docs.length));

/// Live count of BIM spares for the overview card.
final bimSparesCountProvider = StreamProvider.autoDispose
    .family<int, String>((ref, facilityId) => FirebaseFirestore.instance
        .collection('facilities')
        .doc(facilityId)
        .collection('bimSpares')
        .snapshots()
        .map((s) => s.docs.length));
