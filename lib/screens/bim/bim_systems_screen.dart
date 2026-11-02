import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Browse MEP systems imported from IFC or COBie (facilities/{fId}/bimSystems).
class BimSystemsScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const BimSystemsScreen({super.key, required this.facilityId});

  @override
  ConsumerState<BimSystemsScreen> createState() => _BimSystemsScreenState();
}

class _BimSystemsScreenState extends ConsumerState<BimSystemsScreen> {
  final Logger _logger = Logger();
  String _filter = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _systemsStream = FirebaseFirestore.instance
      .collection('facilities')
      .doc(widget.facilityId)
      .collection('bimSystems')
      .orderBy('name')
      .snapshots();

  // Lazy fetch: expand one system at a time to show its equipment names.
  final Map<String, List<String>> _expandedNames = {};

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    return ResponsiveScreenWrapper(
      title: 'MEP Systems',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? '-',
      organization: roleInfo?.organization ?? '-',
      child: BimPage(
        children: [
          _buildSearch(),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _systemsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                _logger.e('bimSystems load failed', error: snap.error);
                return AppErrorBanner(message: 'Could not load systems: ${snap.error}');
              }
              if (!snap.hasData) return const AppSkeletonList(count: 4);
              final all = snap.data!.docs.map(BimSystem.fromSnapshot).toList();
              if (all.isEmpty) return _buildEmpty();
              final filtered = _filter.isEmpty
                  ? all
                  : all
                      .where((s) =>
                          s.name.toLowerCase().contains(_filter) ||
                          (s.category?.toLowerCase().contains(_filter) ?? false))
                      .toList();
              if (filtered.isEmpty) {
                return Center(
                    child: Text('No systems match "$_filter"',
                        style: GoogleFonts.poppins(color: AppColors.textSecondary)));
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${filtered.length} system${filtered.length == 1 ? '' : 's'}',
                      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  for (final sys in filtered) _buildSystemCard(sys),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search systems…',
        prefixIcon: const Icon(Icons.search_rounded),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: AppColors.surfaceAlt,
      ),
      style: GoogleFonts.poppins(fontSize: 14),
      onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
    );
  }

  Widget _buildEmpty() {
    return AppCard(
      child: Column(children: [
        const Icon(Icons.account_tree_outlined, size: 48, color: AppColors.primaryLight),
        const SizedBox(height: 12),
        Text('No MEP systems found',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Systems are imported from IFC IfcSystem/IfcDistributionSystem entities or from the COBie System sheet.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
      ]),
    );
  }

  Widget _buildSystemCard(BimSystem sys) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: AppColors.surfaceAlt,
              child: const Icon(Icons.account_tree_rounded, color: AppColors.primary, size: 20),
            ),
            title: Text(sys.name,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Row(children: [
              if (sys.category != null) ...[
                BimPill(label: sys.category!, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Text('${sys.equipmentIds.length} equipment',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ]),
            onExpansionChanged: (expanded) {
              if (expanded && !_expandedNames.containsKey(sys.id)) {
                _loadEquipmentNames(sys);
              }
            },
            children: [
              if (sys.equipmentIds.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('No equipment assigned.',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                )
              else if (_expandedNames.containsKey(sys.id))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final name in _expandedNames[sys.id]!)
                        Chip(
                          label: Text(name, style: GoogleFonts.poppins(fontSize: 12)),
                          backgroundColor: AppColors.surfaceAlt,
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadEquipmentNames(BimSystem sys) async {
    if (sys.equipmentIds.isEmpty) {
      setState(() => _expandedNames[sys.id] = []);
      return;
    }
    try {
      // Fetch in batches of 30 (Firestore whereIn limit).
      final names = <String>[];
      final ids = sys.equipmentIds;
      for (var i = 0; i < ids.length; i += 30) {
        final batch = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
        final snap = await FirebaseFirestore.instance
            .collection('facilities')
            .doc(widget.facilityId)
            .collection('equipment')
            .where(FieldPath.documentId, whereIn: batch)
            .get();
        names.addAll(snap.docs.map((d) => d.data()['name'] as String? ?? d.id));
      }
      names.sort();
      if (!mounted) return;
      setState(() => _expandedNames[sys.id] = names);
    } catch (e) {
      _logger.e('equipment names load failed', error: e);
      if (!mounted) return;
      setState(() => _expandedNames[sys.id] = sys.equipmentIds);
    }
  }
}
