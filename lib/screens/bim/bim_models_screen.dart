import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/display%20screens/equipment_supplied_screen.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/bim/bim_contacts_screen.dart';
import 'package:cmms/screens/bim/bim_import_screen.dart';
import 'package:cmms/screens/bim/bim_spares_screen.dart';
import 'package:cmms/screens/bim/bim_systems_screen.dart';
import 'package:cmms/screens/bim/bim_viewer_screen.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/screens/bim/spaces_screen.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Register of every BIM import for a facility (facilities/{facilityId}/bimModels), newest first.
/// Entry point of the "Assets & BIM" menu section.
class BimModelsScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const BimModelsScreen({super.key, required this.facilityId});

  @override
  ConsumerState<BimModelsScreen> createState() => _BimModelsScreenState();
}

class _BimModelsScreenState extends ConsumerState<BimModelsScreen> {
  final Logger _logger = Logger();

  late final DocumentReference<Map<String, dynamic>> _facility =
      FirebaseFirestore.instance.collection('facilities').doc(widget.facilityId);
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _modelsStream =
      _facility.collection('bimModels').orderBy('uploadedAt', descending: true).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _spacesStream = _facility.collection('spaces').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _linkedEquipmentStream =
      _facility.collection('equipment').where('bimSource', whereIn: ['cobie', 'ifc']).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _systemsStream =
      _facility.collection('bimSystems').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _contactsStream =
      _facility.collection('bimContacts').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sparesStream =
      _facility.collection('bimSpares').snapshots();

  /// An import that has said "processing" this long was interrupted (app closed, connection lost).
  static const Duration _staleAfter = Duration(minutes: 30);

  void _openImport() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BimImportScreen(facilityId: widget.facilityId)),
      );

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    final canManage = canManageBim(roleInfo);
    return ResponsiveScreenWrapper(
      title: 'BIM Models',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? '-',
      organization: roleInfo?.organization ?? '-',
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _openImport,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.upload_file_rounded, color: Colors.white),
              label: Text('Import COBie / IFC', style: GoogleFonts.poppins(color: Colors.white)),
            )
          : null,
      child: BimPage(
        children: [
          _buildOverview(),
          const SizedBox(height: AppSpacing.lg),
          Text('Import history',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _modelsStream,
            builder: (context, snap) {
              if (snap.hasError) {
                _logger.e('bimModels load failed', error: snap.error);
                return AppErrorBanner(message: 'Could not load BIM models: ${snap.error}');
              }
              if (!snap.hasData) return const AppSkeletonList(count: 2);
              final models = snap.data!.docs.map(BimModel.fromSnapshot).toList();
              if (models.isEmpty) return _buildEmpty(canManage);
              return Column(children: [for (final m in models) _buildModelCard(m, canManage)]);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildOverview() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.view_in_ar_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Building model data',
                  style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Floors, rooms and equipment imported from COBie spreadsheets and IFC models. Imported equipment is '
            'linked to its model element by IFC GlobalId and to the room it sits in.',
            style: GoogleFonts.poppins(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _spacesStream,
            builder: (context, spaceSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _linkedEquipmentStream,
              builder: (context, eqSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _systemsStream,
                builder: (context, sysSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _contactsStream,
                  builder: (context, cntSnap) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _sparesStream,
                    builder: (context, sprSnap) {
                      final spaces = spaceSnap.data?.docs ?? const [];
                      final floors = spaces.where((d) => d.data()['kind'] == BimSpaceKind.storey.name).length;
                      final rooms = spaces.length - floors;
                      final linked = eqSnap.data?.docs.length;
                      final sysCount = sysSnap.data?.docs.length;
                      final cntCount = cntSnap.data?.docs.length;
                      final sprCount = sprSnap.data?.docs.length;
                      String v(int? n, bool loaded) => loaded ? '${n ?? 0}' : '…';
                      return Wrap(spacing: 12, runSpacing: 12, children: [
                        _tappable(BimStat(icon: Icons.layers_rounded, label: 'Floors', value: v(floors, spaceSnap.hasData)), _openSpaces),
                        _tappable(BimStat(icon: Icons.meeting_room_rounded, label: 'Rooms', value: v(rooms, spaceSnap.hasData)), _openSpaces),
                        _tappable(
                          BimStat(icon: Icons.precision_manufacturing_rounded, label: 'BIM equipment', value: v(linked, eqSnap.hasData)),
                          _openEquipment,
                        ),
                        if (sysSnap.hasData && (sysCount ?? 0) > 0)
                          _tappable(BimStat(icon: Icons.account_tree_rounded, label: 'Systems', value: '$sysCount'), _openSystems),
                        if (cntSnap.hasData && (cntCount ?? 0) > 0)
                          _tappable(BimStat(icon: Icons.contacts_rounded, label: 'Contacts', value: '$cntCount'), _openContacts),
                        if (sprSnap.hasData && (sprCount ?? 0) > 0)
                          _tappable(BimStat(icon: Icons.inventory_2_rounded, label: 'Spares', value: '$sprCount'), _openSpares),
                      ]);
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tappable(Widget child, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: child,
      );

  void _openSpaces() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SpacesScreen(facilityId: widget.facilityId)),
      );

  void _openEquipment() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EquipmentSuppliedScreen(facilityId: widget.facilityId)),
      );

  void _openSystems() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BimSystemsScreen(facilityId: widget.facilityId)),
      );

  void _openContacts() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BimContactsScreen(facilityId: widget.facilityId)),
      );

  void _openSpares() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BimSparesScreen(facilityId: widget.facilityId)),
      );

  Widget _buildEmpty(bool canManage) {
    return AppCard(
      child: Column(children: [
        const Icon(Icons.view_in_ar_outlined, size: 56, color: AppColors.primaryLight),
        const SizedBox(height: 12),
        Text('No BIM data imported yet',
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text(
          canManage
              ? 'Ask the contractor or design team for a COBie handover spreadsheet (.xlsx) or an IFC export (.ifc) of the building.'
              : 'An administrator can import COBie or IFC files for this facility.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (canManage) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: 260,
            child: AppGradientButton(label: 'Import COBie / IFC', icon: Icons.upload_file_rounded, onPressed: _openImport),
          ),
        ],
      ]),
    );
  }

  /// Extracts the discipline code from IFC filenames like CF01-XX-M3-EE-EN0001-00.ifc → 'EE'
  String? _disciplineCode(String fileName) {
    final parts = fileName.split('.').first.split('-');
    return parts.length >= 4 ? parts[3].toUpperCase() : null;
  }

  static const _disciplineLabels = <String, (String, Color)>{
    'AR': ('Architecture', Color(0xFF2563EB)),
    'EE': ('Electrical', Color(0xFFD97706)),
    'ME': ('Mechanical', Color(0xFF0D9488)),
    'ST': ('Structural', Color(0xFF7C3AED)),
    'FP': ('Fire Protection', Color(0xFFDC2626)),
    'DR': ('Drawings', Color(0xFF6B7280)),
  };

  List<Widget> _viewabilityHints(BimModel m) {
    final hints = <Widget>[];
    if (m.status != BimImportStatus.ready) return hints;
    final isIfc = m.sourceType == BimSourceType.ifc;
    final disc = _disciplineCode(m.fileName);

    if (!isIfc) {
      hints.add(const BimNotice(
        icon: Icons.info_outline,
        color: AppColors.primary,
        message: 'COBie spreadsheets contain asset data only — no 3D geometry. '
            'Import a matching IFC file to enable 3D viewing.',
      ));
      return hints;
    }

    if (m.storagePath.isEmpty) {
      hints.add(const BimNotice(
        icon: Icons.warning_amber_rounded,
        color: AppColors.warning,
        message: 'The source file was not stored during this import so 3D viewing is unavailable. '
            'Re-import with "Keep original file" enabled to fix this.',
      ));
    }

    if ((m.spaceCount ?? 0) == 0) {
      hints.add(const BimNotice(
        icon: Icons.meeting_room_outlined,
        color: AppColors.warning,
        message: 'No floor spaces (IfcSpace) were found in this file. Equipment will be linked to floors only, '
            'not individual rooms. Re-export from Revit with "Export rooms/spaces" enabled to include room-level data.',
      ));
    }

    if (disc == 'EE') {
      hints.add(const BimNotice(
        icon: Icons.lightbulb_outline_rounded,
        color: AppColors.primary,
        message: 'Electrical models show conduits, panels and detection devices only — not the building shell. '
            'Open the Architecture (AR) model from this list to see the full building structure.',
      ));
    } else if (disc == 'ME') {
      hints.add(const BimNotice(
        icon: Icons.air_rounded,
        color: AppColors.primary,
        message: 'Mechanical models show HVAC ducts, pipework and plant — not the building shell. '
            'Open the Architecture (AR) model from this list to see the full building structure.',
      ));
    } else if (disc == 'ST') {
      hints.add(const BimNotice(
        icon: Icons.foundation_rounded,
        color: AppColors.primary,
        message: 'Structural models show beams, columns and slabs — the architectural finishes and rooms '
            'are in the Architecture (AR) model.',
      ));
    }

    return hints;
  }

  Widget _buildModelCard(BimModel m, bool canManage) {
    final interrupted =
        m.status == BimImportStatus.processing && DateTime.now().difference(m.uploadedAt) > _staleAfter;
    final (statusLabel, statusColor, statusIcon) = switch (m.status) {
      BimImportStatus.ready => ('Imported', AppColors.success, Icons.check_circle_rounded),
      BimImportStatus.failed => ('Failed', AppColors.error, Icons.error_rounded),
      BimImportStatus.processing when interrupted => ('Interrupted', AppColors.warning, Icons.warning_amber_rounded),
      BimImportStatus.processing => ('Importing…', AppColors.primary, Icons.sync_rounded),
      BimImportStatus.uploaded => ('Uploaded', AppColors.textSecondary, Icons.cloud_done_rounded),
    };
    final isIfc = m.sourceType == BimSourceType.ifc;
    final disc = _disciplineCode(m.fileName);
    final discInfo = disc != null ? _disciplineLabels[disc] : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.surfaceAlt,
                  child: Icon(isIfc ? Icons.view_in_ar_rounded : Icons.table_chart_rounded, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.fileName,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        [
                          'Revision ${m.revision}',
                          isIfc ? (m.schemaVersion ?? 'IFC') : 'COBie',
                          formatBytes(m.sizeBytes),
                          DateFormat.yMMMd().add_jm().format(m.uploadedAt),
                        ].join('  ·  '),
                        style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    BimPill(label: statusLabel, color: statusColor, icon: statusIcon),
                    if (discInfo != null) ...[
                      const SizedBox(height: 4),
                      BimPill(label: discInfo.$1, color: discInfo.$2),
                    ],
                  ],
                ),
              ],
            ),
            if (m.status == BimImportStatus.ready) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _count(Icons.meeting_room_outlined, '${m.spaceCount ?? 0} floors & rooms'),
                _count(Icons.precision_manufacturing_outlined, '${m.equipmentCount ?? 0} equipment'),
                if (!isIfc) _count(Icons.event_repeat_rounded, '${m.jobCount ?? 0} jobs'),
                if ((m.systemCount ?? 0) > 0)
                  _count(Icons.account_tree_rounded, '${m.systemCount} systems'),
                if ((m.contactCount ?? 0) > 0)
                  _count(Icons.contacts_rounded, '${m.contactCount} contacts'),
                if ((m.sparesCount ?? 0) > 0)
                  _count(Icons.inventory_2_rounded, '${m.sparesCount} spares'),
              ]),
              ...[ for (final h in _viewabilityHints(m)) ...[const SizedBox(height: 8), h] ],
            ],
            if (m.status == BimImportStatus.failed && m.errorMessage != null) ...[
              const SizedBox(height: 10),
              AppErrorBanner(message: m.errorMessage!),
            ],
            if (interrupted) ...[
              const SizedBox(height: 10),
              const BimNotice(
                message: 'This import did not finish (the app was closed or the connection dropped). '
                    'Records written before it stopped are kept. Import the same file again to complete it.',
                color: AppColors.warning,
                icon: Icons.warning_amber_rounded,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Wrap(spacing: 4, children: [
                  if (isIfc && m.status == BimImportStatus.ready)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BimViewerScreen(facilityId: widget.facilityId, modelId: m.id),
                      )),
                      icon: const Icon(Icons.threed_rotation_rounded, size: 18),
                      label: Text('Open 3D view', style: GoogleFonts.poppins(fontSize: 13)),
                    ),
                  if (m.storagePath.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => _download(m),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text('Download original', style: GoogleFonts.poppins(fontSize: 13)),
                    ),
                ]),
                if (canManage)
                  IconButton(
                    tooltip: 'Delete this import record',
                    icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                    onPressed: () => _deleteModel(m),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _count(IconData icon, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textPrimary)),
      ]);

  Future<void> _deleteModel(BimModel m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${m.fileName}"?', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'This removes the import record${m.storagePath.isNotEmpty ? ' and the stored file' : ''}. '
          'Spaces and equipment already written by this import are kept.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (m.storagePath.isNotEmpty) {
        await FirebaseStorage.instance.ref(m.storagePath).delete();
      }
      await _facility.collection('bimModels').doc(m.id).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted ${m.fileName}', style: GoogleFonts.poppins())),
      );
    } catch (e) {
      _logger.e('BIM model delete failed', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e', style: GoogleFonts.poppins())),
      );
    }
  }

  Future<void> _download(BimModel m) async {
    try {
      final url = await FirebaseStorage.instance.ref(m.storagePath).getDownloadURL();
      final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      if (!ok) throw 'No app could open the link';
    } catch (e) {
      _logger.e('BIM download failed', error: e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not download ${m.fileName}: $e', style: GoogleFonts.poppins())),
      );
    }
  }
}
