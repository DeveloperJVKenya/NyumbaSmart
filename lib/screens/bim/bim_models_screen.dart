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
import 'package:cmms/screens/bim/bim_import_screen.dart';
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

  /// An import that has said "processing" this long was interrupted (app closed, connection lost).
  static const Duration _staleAfter = Duration(minutes: 30);

  void _openImport() => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => BimImportScreen(facilityId: widget.facilityId)),
      );

  @override
  Widget build(BuildContext context) {
    final canManage = canManageBim(ref.watch(currentUserRoleProvider).value);
    return ResponsiveScreenWrapper(
      title: 'BIM Models',
      facilityId: widget.facilityId,
      currentRole: 'User',
      organization: '-',
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
              return Column(children: [for (final m in models) _buildModelCard(m)]);
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
              builder: (context, eqSnap) {
                final spaces = spaceSnap.data?.docs ?? const [];
                final floors = spaces.where((d) => d.data()['kind'] == BimSpaceKind.storey.name).length;
                final rooms = spaces.length - floors;
                final linked = eqSnap.data?.docs.length;
                String v(int? n) => (spaceSnap.hasData && n != null) ? '$n' : '…';
                return Wrap(spacing: 12, runSpacing: 12, children: [
                  _tappable(BimStat(icon: Icons.layers_rounded, label: 'Floors', value: v(floors)), _openSpaces),
                  _tappable(BimStat(icon: Icons.meeting_room_rounded, label: 'Rooms', value: v(rooms)), _openSpaces),
                  _tappable(
                    BimStat(icon: Icons.precision_manufacturing_rounded, label: 'BIM-linked equipment', value: v(linked)),
                    _openEquipment,
                  ),
                ]);
              },
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

  Widget _buildModelCard(BimModel m) {
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
                BimPill(label: statusLabel, color: statusColor, icon: statusIcon),
              ],
            ),
            if (m.status == BimImportStatus.ready) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 4, children: [
                _count(Icons.meeting_room_outlined, '${m.spaceCount ?? 0} floors & rooms'),
                _count(Icons.precision_manufacturing_outlined, '${m.equipmentCount ?? 0} equipment'),
                if (!isIfc) _count(Icons.event_repeat_rounded, '${m.jobCount ?? 0} maintenance jobs'),
              ]),
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
            if (m.storagePath.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 4, children: [
                  if (isIfc && m.status == BimImportStatus.ready)
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => BimViewerScreen(facilityId: widget.facilityId, modelId: m.id),
                      )),
                      icon: const Icon(Icons.threed_rotation_rounded, size: 18),
                      label: Text('Open 3D view', style: GoogleFonts.poppins(fontSize: 13)),
                    ),
                  TextButton.icon(
                    onPressed: () => _download(m),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: Text('Download original', style: GoogleFonts.poppins(fontSize: 13)),
                  ),
                ]),
              ),
            ],
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
