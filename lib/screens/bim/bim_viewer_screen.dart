import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/models/equipment.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/bim_viewer/bim_viewer_host.dart';
import 'package:cmms/widgets/equipment_picker_field.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Overlay colours, shared with the legend. Anything not listed keeps the model's own colour.
class _Overlay {
  static const openWork = Color(0xFFDC2626); // has an open/in-progress work order or open request
  static const underRepair = Color(0xFFF59E0B);
  static const inactive = Color(0xFF94A3B8);
  static const active = Color(0xFF16A34A);

  static String hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

/// 3D view of a facility's IFC model. Equipment imported from that model (matched by IFC GlobalId) is
/// coloured by status, tapping an element shows its equipment record, and work can be raised from there.
class BimViewerScreen extends StatefulWidget {
  final String facilityId;

  /// A specific bimModels doc; defaults to the newest successfully imported IFC model with a stored file.
  final String? modelId;

  /// IFC GlobalId to select and zoom to once loaded (e.g. "Show in 3D" from an equipment card).
  final String? focusGlobalId;

  const BimViewerScreen({super.key, required this.facilityId, this.modelId, this.focusGlobalId});

  @override
  State<BimViewerScreen> createState() => _BimViewerScreenState();
}

class _BimViewerScreenState extends State<BimViewerScreen> {
  final Logger _logger = Logger();
  final BimViewerController _viewer = BimViewerController();

  late final DocumentReference<Map<String, dynamic>> _facility =
      FirebaseFirestore.instance.collection('facilities').doc(widget.facilityId);

  List<BimModel> _models = [];
  BimModel? _model;
  String? _error;
  bool _resolving = true;
  bool _loaded = false;
  bool _xray = false;
  double? _progress;
  String _stage = '';

  final Map<String, Equipment> _equipmentByGid = {};
  final Set<String> _openWorkEquipmentIds = {};
  final Map<String, BimSpace> _spaces = {};
  final List<StreamSubscription> _subs = [];

  Map<String, dynamic>? _selection; // last 'selected' message from the page

  @override
  void initState() {
    super.initState();
    _resolveModel();
    _subs.add(_facility.collection('equipment').snapshots().listen((snap) {
      _equipmentByGid
        ..clear()
        ..addEntries(snap.docs
            .map(Equipment.fromSnapshot)
            .where((e) => e.isBimLinked)
            .map((e) => MapEntry(e.bimGlobalId!, e)));
      _pushColors();
    }, onError: (e) => _logger.w('Equipment unavailable: $e')));
    _subs.add(_facility.collection('spaces').snapshots().listen((snap) {
      _spaces
        ..clear()
        ..addEntries(snap.docs.map((d) => MapEntry(d.id, BimSpace.fromSnapshot(d))));
      if (mounted) setState(() {});
    }, onError: (e) => _logger.w('Spaces unavailable: $e')));
    // Open work: work orders not completed, and requests not closed, that name an equipment record.
    final openWorkOrders = FirebaseFirestore.instance
        .collection('Work_Orders')
        .where('facilityId', isEqualTo: widget.facilityId)
        .snapshots();
    final openRequests = FirebaseFirestore.instance
        .collection('Work_Requests')
        .where('facilityId', isEqualTo: widget.facilityId)
        .snapshots();
    Set<String> woIds = {}, reqIds = {};
    void merge() {
      _openWorkEquipmentIds
        ..clear()
        ..addAll(woIds)
        ..addAll(reqIds);
      _pushColors();
    }

    _subs.add(openWorkOrders.listen((snap) {
      woIds = {
        for (final d in snap.docs)
          if (d.data()['equipmentId'] != null && d.data()['status'] != 'Completed') d.data()['equipmentId'] as String,
      };
      merge();
    }, onError: (e) => _logger.w('Work orders unavailable: $e')));
    _subs.add(openRequests.listen((snap) {
      reqIds = {
        for (final d in snap.docs)
          if (d.data()['equipmentId'] != null && d.data()['status'] == 'Open') d.data()['equipmentId'] as String,
      };
      merge();
    }, onError: (e) => _logger.w('Requests unavailable: $e')));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _resolveModel() async {
    try {
      final snap = await _facility.collection('bimModels').where('sourceType', isEqualTo: BimSourceType.ifc.name).get();
      final models = snap.docs
          .map(BimModel.fromSnapshot)
          .where((m) => m.status == BimImportStatus.ready && m.storagePath.isNotEmpty)
          .toList()
        ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
      final model = widget.modelId == null
          ? (models.isEmpty ? null : models.first)
          : models.where((m) => m.id == widget.modelId).firstOrNull ?? (models.isEmpty ? null : models.first);
      if (!mounted) return;
      setState(() {
        _models = models;
        _resolving = false;
      });
      if (model != null) await _open(model);
    } catch (e) {
      _logger.e('Could not find IFC models', error: e);
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'Could not load the model list: $e';
        });
      }
    }
  }

  Future<void> _open(BimModel model) async {
    setState(() {
      _model = model;
      _loaded = false;
      _error = null;
      _selection = null;
      _progress = 0;
      _stage = 'Preparing…';
    });
    try {
      final url = await FirebaseStorage.instance.ref(model.storagePath).getDownloadURL();
      _viewer.send({'type': 'load', 'url': url, 'select': widget.focusGlobalId, 'colors': _colors()});
    } catch (e) {
      _logger.e('Could not get model URL', error: e);
      if (mounted) setState(() => _error = 'Could not open ${model.fileName}: $e');
    }
  }

  Map<String, String> _colors() {
    final out = <String, String>{};
    _equipmentByGid.forEach((gid, e) {
      final Color c;
      if (_openWorkEquipmentIds.contains(e.id)) {
        c = _Overlay.openWork;
      } else {
        switch (e.status.toLowerCase()) {
          case 'under repair':
            c = _Overlay.underRepair;
          case 'inactive':
          case 'decommissioned':
            c = _Overlay.inactive;
          default:
            c = _Overlay.active;
        }
      }
      out[gid] = _Overlay.hex(c);
    });
    return out;
  }

  void _pushColors() {
    if (_loaded) _viewer.send({'type': 'colors', 'colors': _colors()});
    if (mounted) setState(() {});
  }

  void _onMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'progress':
        final f = (msg['fraction'] as num?)?.toDouble() ?? 0;
        final download = msg['stage'] == 'download';
        setState(() {
          _progress = download ? f * 0.5 : 0.5 + f * 0.5;
          _stage = download ? 'Downloading model' : 'Building 3D view';
        });
      case 'loaded':
        setState(() {
          _loaded = true;
          _progress = null;
        });
        _viewer.send({'type': 'colors', 'colors': _colors()});
        if (_xray) _viewer.send({'type': 'xray', 'on': true});
      case 'selected':
        setState(() => _selection = msg['globalId'] == null ? null : msg);
      case 'error':
        setState(() {
          _error = msg['message'] as String? ?? 'The viewer reported an error.';
          _progress = null;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: '3D Viewer',
      facilityId: widget.facilityId,
      currentRole: 'User',
      organization: '-',
      actions: [
        if (_model != null && bimViewerSupported) ...[
          IconButton(
            tooltip: _xray ? 'Show walls normally' : 'X-ray: see equipment through walls',
            icon: Icon(_xray ? Icons.visibility_rounded : Icons.layers_clear_rounded, color: Colors.white),
            onPressed: () {
              setState(() => _xray = !_xray);
              _viewer.send({'type': 'xray', 'on': _xray});
            },
          ),
          IconButton(
            tooltip: 'Reset view',
            icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
            onPressed: () {
              setState(() => _selection = null);
              _viewer.send({'type': 'reset'});
            },
          ),
        ],
        if (_models.length > 1)
          PopupMenuButton<BimModel>(
            tooltip: 'Choose model',
            icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
            onSelected: _open,
            itemBuilder: (_) => [
              for (final m in _models)
                CheckedPopupMenuItem(
                  value: m,
                  checked: m.id == _model?.id,
                  child: Text('${m.fileName}  (rev ${m.revision}, ${DateFormat.yMMMd().format(m.uploadedAt)})',
                      style: GoogleFonts.poppins(fontSize: 13)),
                ),
            ],
          ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_resolving) return const Center(child: CircularProgressIndicator());
    if (_models.isEmpty) {
      return const BimPage(children: [
        BimNotice(
          message: 'No IFC model is available for this facility yet. Import an IFC file in BIM Models '
              '(keep "Keep a copy of the original file" ticked) and it will open here.',
          icon: Icons.view_in_ar_outlined,
        ),
      ]);
    }
    if (!bimViewerSupported) return _buildUnsupported();

    final isWide = MediaQuery.of(context).size.width >= AppBreakpoints.tablet;
    final panel = _selection == null ? null : _buildSelectionPanel(_selection!);

    return Stack(
      children: [
        Positioned.fill(child: BimViewerHost(controller: _viewer, onMessage: _onMessage)),
        if (_progress != null && _error == null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Column(children: [
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              Container(
                width: double.infinity,
                color: AppColors.surfaceAlt.withValues(alpha: 0.9),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Text('$_stage…  ${_model?.fileName ?? ''}',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ]),
          ),
        if (_error != null)
          Positioned(left: 16, right: 16, top: 16, child: AppErrorBanner(message: _error!)),
        if (_loaded) Positioned(left: 12, top: 12, child: _buildLegend()),
        if (panel != null)
          isWide
              ? Positioned(right: 16, top: 16, bottom: 16, width: 360, child: panel)
              : Positioned(left: 12, right: 12, bottom: 12, child: panel),
      ],
    );
  }

  Widget _buildUnsupported() {
    return BimPage(children: [
      const BimNotice(
        message: 'The 3D viewer runs in the web app and on Android, iOS and macOS. On this device you can '
            'download the model and open it in an IFC viewer, or use the web app.',
        icon: Icons.desktop_windows_outlined,
      ),
      const SizedBox(height: AppSpacing.md),
      if (_models.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: Text('Download ${_models.first.fileName}', style: GoogleFonts.poppins()),
            onPressed: () async {
              final url = await FirebaseStorage.instance.ref(_models.first.storagePath).getDownloadURL();
              await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
          ),
        ),
    ]);
  }

  Widget _buildLegend() {
    Widget row(Color c, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textPrimary)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${_equipmentByGid.length} linked equipment',
            style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        row(_Overlay.openWork, 'Open work'),
        row(_Overlay.underRepair, 'Under repair'),
        row(_Overlay.active, 'Active'),
        row(_Overlay.inactive, 'Inactive / decommissioned'),
      ]),
    );
  }

  Widget _buildSelectionPanel(Map<String, dynamic> sel) {
    final gid = sel['globalId'] as String;
    final equipment = _equipmentByGid[gid];
    final space = equipment == null ? null : _spaces[equipment.spaceId];
    final floor = space == null ? null : _spaces[space.parentId];
    final ifcType = (sel['ifcType'] as String? ?? '').replaceFirst(RegExp('^Ifc'), '');

    Widget detail(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                width: 96,
                child: Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ),
              Expanded(child: Text(value, style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textPrimary))),
            ]),
          );

    return Material(
      color: Colors.transparent,
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(equipment == null ? Icons.view_in_ar_outlined : Icons.precision_manufacturing_rounded,
                    color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(equipment?.name ?? (sel['name'] as String?) ?? ifcType,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() => _selection = null);
                    _viewer.send({'type': 'select', 'globalId': null});
                  },
                ),
              ]),
              const SizedBox(height: 6),
              if (equipment == null) ...[
                detail('IFC type', ifcType),
                const SizedBox(height: 6),
                Text('This element is not in the equipment register. Only maintainable equipment is imported.',
                    style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
              ] else ...[
                Wrap(spacing: 6, runSpacing: 4, children: [
                  BimPill(label: equipment.status, color: _statusColor(equipment)),
                  if (_openWorkEquipmentIds.contains(equipment.id))
                    const BimPill(label: 'Open work', color: _Overlay.openWork, icon: Icons.build_circle_outlined),
                ]),
                const SizedBox(height: 8),
                detail('Type', [equipment.type, if (equipment.typeName != null) equipment.typeName!].join(' · ')),
                detail('Location', [if (space != null) space.name, if (floor != null) floor.name].join(' · ')),
                detail('Manufacturer', equipment.manufacturer),
                detail('Model', equipment.modelNumber),
                detail('Serial', equipment.serialNumber),
                detail('System', equipment.systemName),
                detail('Tag / ID', equipment.equipmentId),
                if (equipment.maintenanceHistory.isNotEmpty)
                  detail('Last activity', equipment.maintenanceHistory.last['action']?.toString()),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    icon: const Icon(Icons.build_rounded, size: 18),
                    label: Text('New work order', style: GoogleFonts.poppins(fontSize: 13)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => WorkOrderScreen(
                        facilityId: widget.facilityId,
                        initialEquipment: EquipmentRef.fromEquipment(equipment),
                      ),
                    )),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.report_problem_outlined, size: 18),
                    label: Text('Report a problem', style: GoogleFonts.poppins(fontSize: 13)),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => RequestScreen(
                        facilityId: widget.facilityId,
                        initialEquipment: EquipmentRef.fromEquipment(equipment),
                      ),
                    )),
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(Equipment e) => switch (e.status.toLowerCase()) {
        'under repair' => _Overlay.underRepair,
        'inactive' || 'decommissioned' => _Overlay.inactive,
        _ => _Overlay.active,
      };
}
