import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

/// Work orders and requests that name this equipment (Work_Orders / Work_Requests with
/// facilityId + equipmentId). Equality-only filters, so no composite index is needed.
/// Only built when the equipment card is expanded, so a long list doesn't cost reads per row.
class EquipmentActivitySection extends StatelessWidget {
  const EquipmentActivitySection({
    super.key,
    required this.facilityId,
    required this.equipmentId,
    this.fontSize = 14,
  });

  final String facilityId;
  final String equipmentId;
  final double fontSize;

  Stream<QuerySnapshot<Map<String, dynamic>>> _query(String collection) => FirebaseFirestore.instance
      .collection(collection)
      .where('facilityId', isEqualTo: facilityId)
      .where('equipmentId', isEqualTo: equipmentId)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _query('Work_Orders'),
      builder: (context, woSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query('Work_Requests'),
        builder: (context, reqSnap) {
          if (woSnap.hasError || reqSnap.hasError) {
            return Text('Could not load related work: ${woSnap.error ?? reqSnap.error}',
                style: GoogleFonts.poppins(fontSize: fontSize - 3, color: Colors.red[700]));
          }
          if (!woSnap.hasData || !reqSnap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            );
          }
          final items = [
            for (final d in woSnap.data!.docs) _Item.from(d.data(), isWorkOrder: true),
            for (final d in reqSnap.data!.docs) _Item.from(d.data(), isWorkOrder: false),
          ]..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          final open = items.where((i) => i.isOpen).length;

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  items.isEmpty ? 'Work orders & requests: none yet' : 'Work orders & requests ($open open of ${items.length})',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w500, color: Colors.blueGrey[700], fontSize: fontSize - 2),
                ),
                const SizedBox(height: 4),
                for (final i in items.take(6))
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(i.isWorkOrder ? Icons.build_outlined : Icons.report_problem_outlined,
                          size: 16, color: i.isOpen ? Colors.orange[700] : Colors.green[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(i.title, style: GoogleFonts.poppins(fontSize: fontSize - 3), overflow: TextOverflow.ellipsis),
                      ),
                      Text(
                        [i.status, if (i.createdAt != null) DateFormat.yMMMd().format(i.createdAt!)].join(' · '),
                        style: GoogleFonts.poppins(fontSize: fontSize - 4, color: Colors.grey[600]),
                      ),
                    ]),
                  ),
                if (items.length > 6)
                  Text('…and ${items.length - 6} more in Work Orders / Work on Request',
                      style: GoogleFonts.poppins(fontSize: fontSize - 4, color: Colors.grey[600])),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Item {
  _Item(this.title, this.status, this.createdAt, this.isWorkOrder);

  final String title;
  final String status;
  final DateTime? createdAt;
  final bool isWorkOrder;

  bool get isOpen => isWorkOrder ? status != 'Completed' : status == 'Open' || status == 'In Progress';

  factory _Item.from(Map<String, dynamic> d, {required bool isWorkOrder}) => _Item(
        (d['title'] as String?)?.trim().isNotEmpty == true ? d['title'] as String : 'Untitled',
        (d['status'] as String?) ?? 'Open',
        (d['createdAt'] as Timestamp?)?.toDate(),
        isWorkOrder,
      );
}
