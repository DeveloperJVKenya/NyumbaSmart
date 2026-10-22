import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/models/equipment.dart';

/// The bits of an equipment record a work order or request keeps a copy of.
class EquipmentRef {
  final String id;
  final String name;
  final String? spaceId;

  const EquipmentRef({required this.id, required this.name, this.spaceId});

  factory EquipmentRef.fromEquipment(Equipment e) => EquipmentRef(id: e.id, name: e.name, spaceId: e.spaceId);
}

CollectionReference<Map<String, dynamic>> _equipmentCol(String facilityId) =>
    FirebaseFirestore.instance.collection('facilities').doc(facilityId).collection('equipment');

/// Appends a line to an equipment record's maintenance history (e.g. "Work order completed").
/// Best effort: a failure is logged, never shown, so it can't block the work order/request itself.
Future<void> appendEquipmentHistory({
  required String facilityId,
  required String equipmentId,
  required String action,
  String notes = '',
  required String userId,
}) async {
  try {
    await _equipmentCol(facilityId).doc(equipmentId).update({
      'maintenanceHistory': FieldValue.arrayUnion([
        {'action': action, 'timestamp': Timestamp.now(), 'notes': notes, 'userId': userId},
      ]),
      'updatedAt': Timestamp.now(),
    });
  } catch (e) {
    Logger().w('Could not add history to equipment $equipmentId: $e');
  }
}

/// Read-only form field that opens a searchable equipment list for the facility.
class EquipmentPickerField extends StatelessWidget {
  const EquipmentPickerField({
    super.key,
    required this.facilityId,
    required this.value,
    required this.onChanged,
    this.fontSize = 14,
    this.label = 'Equipment (optional)',
  });

  final String facilityId;
  final EquipmentRef? value;
  final ValueChanged<EquipmentRef?> onChanged;
  final double fontSize;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final picked = await showEquipmentPicker(context, facilityId);
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: InputDecoration(
          labelText: label,
          hintText: 'Tap to choose the asset this is about',
          hintStyle: GoogleFonts.poppins(color: Colors.grey),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          labelStyle: GoogleFonts.poppins(color: Colors.grey[600]),
          prefixIcon: Icon(Icons.precision_manufacturing_outlined, color: Colors.blueGrey[600]),
          suffixIcon: value == null
              ? Icon(Icons.search, color: Colors.blueGrey[600])
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: () => onChanged(null),
                ),
        ),
        child: value == null
            ? null
            : Text(value!.name, style: GoogleFonts.poppins(fontSize: fontSize), overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Bottom sheet listing the facility's equipment with search by name, type, room, serial or tag.
Future<EquipmentRef?> showEquipmentPicker(BuildContext context, String facilityId) {
  return showModalBottomSheet<EquipmentRef>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _EquipmentPickerSheet(facilityId: facilityId),
  );
}

class _EquipmentPickerSheet extends StatefulWidget {
  const _EquipmentPickerSheet({required this.facilityId});
  final String facilityId;

  @override
  State<_EquipmentPickerSheet> createState() => _EquipmentPickerSheetState();
}

class _EquipmentPickerSheetState extends State<_EquipmentPickerSheet> {
  late final Future<(List<Equipment>, Map<String, BimSpace>)> _data = _load();
  String _query = '';

  Future<(List<Equipment>, Map<String, BimSpace>)> _load() async {
    final facility = FirebaseFirestore.instance.collection('facilities').doc(widget.facilityId);
    final results = await Future.wait([facility.collection('equipment').get(), facility.collection('spaces').get()]);
    final equipment = results[0].docs.map(Equipment.fromSnapshot).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final spaces = {for (final d in results[1].docs) d.id: BimSpace.fromSnapshot(d)};
    return (equipment, spaces);
  }

  String _where(Equipment e, Map<String, BimSpace> spaces) {
    final space = spaces[e.spaceId];
    if (space == null) return e.locationId;
    final floor = spaces[space.parentId];
    return floor == null ? space.name : '${space.name} · ${floor.name}';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, controller) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Search name, type, room, serial or tag',
                  hintStyle: GoogleFonts.poppins(fontSize: 13),
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<(List<Equipment>, Map<String, BimSpace>)>(
                future: _data,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text('Could not load equipment: ${snap.error}', style: GoogleFonts.poppins()),
                    );
                  }
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final (equipment, spaces) = snap.data!;
                  final items = equipment.where((e) {
                    if (_query.isEmpty) return true;
                    return [e.name, e.type, e.serialNumber, e.equipmentId, _where(e, spaces), e.typeName ?? '']
                        .any((s) => s.toLowerCase().contains(_query));
                  }).toList();
                  if (equipment.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('No equipment recorded for this facility yet.',
                            textAlign: TextAlign.center, style: GoogleFonts.poppins(color: Colors.grey[600])),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: controller,
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = items[i];
                      final where = _where(e, spaces);
                      return ListTile(
                        leading: Icon(
                          e.isBimLinked ? Icons.view_in_ar_outlined : Icons.precision_manufacturing_outlined,
                          color: Colors.blueGrey[600],
                        ),
                        title: Text(e.name, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
                        subtitle: Text(
                          [e.type, if (where.isNotEmpty) where, e.status].join('  •  '),
                          style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600]),
                        ),
                        onTap: () => Navigator.of(context).pop(EquipmentRef.fromEquipment(e)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
