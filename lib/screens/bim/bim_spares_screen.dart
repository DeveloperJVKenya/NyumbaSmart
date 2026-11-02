import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Browse spare parts imported from COBie Spare/Resource sheet
/// (facilities/{fId}/bimSpares), grouped by equipment type name.
class BimSparesScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const BimSparesScreen({super.key, required this.facilityId});

  @override
  ConsumerState<BimSparesScreen> createState() => _BimSparesScreenState();
}

class _BimSparesScreenState extends ConsumerState<BimSparesScreen> {
  final Logger _logger = Logger();
  String _filter = '';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sparesStream = FirebaseFirestore.instance
      .collection('facilities')
      .doc(widget.facilityId)
      .collection('bimSpares')
      .orderBy('name')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    return ResponsiveScreenWrapper(
      title: 'Spare Parts',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? '-',
      organization: roleInfo?.organization ?? '-',
      child: BimPage(
        children: [
          _buildSearch(),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sparesStream,
            builder: (context, snap) {
              if (snap.hasError) {
                _logger.e('bimSpares load failed', error: snap.error);
                return AppErrorBanner(message: 'Could not load spare parts: ${snap.error}');
              }
              if (!snap.hasData) return const AppSkeletonList(count: 4);
              final all = snap.data!.docs.map(BimSpare.fromSnapshot).toList();
              if (all.isEmpty) return _buildEmpty();
              final filtered = _filter.isEmpty
                  ? all
                  : all
                      .where((s) =>
                          s.name.toLowerCase().contains(_filter) ||
                          (s.typeName?.toLowerCase().contains(_filter) ?? false) ||
                          (s.partNumber?.toLowerCase().contains(_filter) ?? false) ||
                          (s.supplier?.toLowerCase().contains(_filter) ?? false))
                      .toList();
              if (filtered.isEmpty) {
                return Center(
                    child: Text('No spare parts match "$_filter"',
                        style: GoogleFonts.poppins(color: AppColors.textSecondary)));
              }

              // Group by typeName (the equipment type this spare belongs to).
              final grouped = <String, List<BimSpare>>{};
              for (final s in filtered) {
                final key = s.typeName ?? 'Unassigned';
                grouped.putIfAbsent(key, () => []).add(s);
              }
              final types = grouped.keys.toList()..sort();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${filtered.length} spare part${filtered.length == 1 ? '' : 's'}',
                      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: AppSpacing.sm),
                  for (final typeName in types) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 6),
                      child: Row(children: [
                        const Icon(Icons.precision_manufacturing_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(typeName,
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.textPrimary)),
                        ),
                        Text('${grouped[typeName]!.length} part${grouped[typeName]!.length == 1 ? '' : 's'}',
                            style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                      ]),
                    ),
                    for (final s in grouped[typeName]!) _buildSpareCard(s),
                  ],
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
        hintText: 'Search spares…',
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
        const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.primaryLight),
        const SizedBox(height: 12),
        Text('No spare parts found',
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'Spare parts are imported from the COBie Spare or Resource sheet and linked to equipment types.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
      ]),
    );
  }

  Widget _buildSpareCard(BimSpare s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppColors.surfaceAlt,
              child: const Icon(Icons.build_circle_outlined, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.name,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  if (s.description != null)
                    Text(s.description!,
                        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    if (s.partNumber != null) _pill('P/N  ${s.partNumber!}', copyable: s.partNumber),
                    if (s.supplier != null) _pill(s.supplier!),
                    if (s.category != null) _pill(s.category!),
                    if (s.setNumber != null) _pill('Set ${s.setNumber}'),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String label, {String? copyable}) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: copyable == null
          ? null
          : () {
              Clipboard.setData(ClipboardData(text: copyable));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied: $copyable', style: GoogleFonts.poppins())),
              );
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textPrimary)),
          if (copyable != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.copy_outlined, size: 12, color: AppColors.textSecondary),
          ],
        ]),
      ),
    );
  }
}
