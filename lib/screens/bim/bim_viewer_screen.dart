import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/display%20screens/request_screen.dart';
import 'package:cmms/display%20screens/work_order_screen.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/models/equipment.dart';
import 'package:cmms/providers/auth_providers.dart';
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
class BimViewerScreen extends ConsumerStatefulWidget {
  final String facilityId;

  /// A specific bimModels doc; defaults to the newest successfully imported IFC model with a stored file.
  final String? modelId;

  /// IFC GlobalId to select and zoom to once loaded (e.g. "Show in 3D" from an equipment card).
  final String? focusGlobalId;

  const BimViewerScreen({super.key, required this.facilityId, this.modelId, this.focusGlobalId});

  @override
  ConsumerState<BimViewerScreen> createState() => _BimViewerScreenState();
}

class _BimViewerScreenState extends ConsumerState<BimViewerScreen> {
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
  bool _showSpaces = false;
  double? _progress;
  String _stage = '';

  final Map<String, Equipment> _equipmentByGid = {};
  final Set<String> _openWorkEquipmentIds = {};
  final Map<String, BimSpace> _spaces = {};
  final List<StreamSubscription> _subs = [];

  String? _isolatedStoreyGid; // null = show all floors

  /// Storey list received from the viewer after a model loads.
  List<({String globalId, String name})> _viewerStoreys = [];

  Map<String, dynamic>? _selection;
  String? _dataError;

  // --- Interactive tool modes ---
  bool _measureMode   = false;
  String? _measureResult;      // e.g. "12.35 m / 40.52 ft"
  bool _annotateMode  = false;
  bool _transformMode = false;

  // Annotation items loaded from Firestore, sent to viewer whenever it loads.
  final List<Map<String, dynamic>> _annotationItems = [];

  // --- In-panel equipment edit state ---
  bool _editingEquipment = false;
  String? _editStatus;
  String? _editSpaceId;
  final TextEditingController _editNotesCtrl = TextEditingController();
  bool _savingEdit = false;

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
      if (mounted) setState(() => _dataError = null);
      _pushColors();
    }, onError: (e) {
      _logger.w('Equipment unavailable: $e');
      if (mounted) setState(() => _dataError = 'Could not load equipment overlay data: $e');
    }));
    _subs.add(_facility.collection('spaces').snapshots().listen((snap) {
      _spaces
        ..clear()
        ..addEntries(snap.docs.map((d) => MapEntry(d.id, BimSpace.fromSnapshot(d))));
      if (mounted) setState(() => _dataError = null);
    }, onError: (e) {
      _logger.w('Spaces unavailable: $e');
      if (mounted) setState(() => _dataError = 'Could not load spaces data: $e');
    }));
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

    // Annotation pins — sent to the viewer whenever it finishes loading.
    _subs.add(_facility.collection('bimAnnotations').snapshots().listen((snap) {
      final items = snap.docs.map((d) {
        final data = d.data();
        final pos = data['worldPosition'] as Map<String, dynamic>?;
        return <String, dynamic>{
          'id': d.id,
          'x': (pos?['x'] as num?)?.toDouble() ?? 0.0,
          'y': (pos?['y'] as num?)?.toDouble() ?? 0.0,
          'z': (pos?['z'] as num?)?.toDouble() ?? 0.0,
          'text': data['text'] as String? ?? '',
        };
      }).toList();
      _annotationItems
        ..clear()
        ..addAll(items);
      if (_loaded) _viewer.send({'type': 'annotations', 'items': items});
    }, onError: (e) => _logger.w('Annotations unavailable: $e')));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _editNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveModel() async {
    _logger.i('BIM resolve — facilityId=${widget.facilityId} modelId=${widget.modelId}');
    try {
      final snap = await _facility.collection('bimModels').where('sourceType', isEqualTo: BimSourceType.ifc.name).get();
      _logger.i('BIM models fetched: ${snap.docs.length} total');
      final models = snap.docs
          .map(BimModel.fromSnapshot)
          .where((m) => m.status == BimImportStatus.ready && m.storagePath.isNotEmpty)
          .toList()
        ..sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
      _logger.i('BIM ready models: ${models.length}');
      for (final m in models) {
        _logger.i('  → ${m.fileName} (${m.id})');
      }
      final model = widget.modelId == null
          ? (models.isEmpty ? null : models.first)
          : models.where((m) => m.id == widget.modelId).firstOrNull ?? (models.isEmpty ? null : models.first);
      _logger.i('BIM selected model: ${model?.id ?? "none"}');
      if (!mounted) return;
      setState(() {
        _models = models;
        _resolving = false;
      });
      if (model != null) await _open(model);
    } catch (e) {
      _logger.e('BIM could not fetch model list', error: e);
      if (mounted) {
        setState(() {
          _resolving = false;
          _error = 'Could not load the model list: $e';
        });
      }
    }
  }

  Future<void> _open(BimModel model) async {
    _logger.i('BIM opening model: ${model.fileName} (${model.id})');
    setState(() {
      _model = model;
      _loaded = false;
      _error = null;
      _selection = null;
      _progress = 0;
      _stage = 'Preparing…';
      _isolatedStoreyGid = null;
      _showSpaces = false;
      _equipmentByGid.clear();
      _spaces.clear();
      _viewerStoreys = [];
    });
    try {
      final url = await FirebaseStorage.instance.ref(model.storagePath).getDownloadURL();
      _logger.i('BIM download URL obtained');
      // Load any saved position overrides so the viewer can apply them as the model renders.
      final overridesSnap = await _facility.collection('bimElementOverrides').get();
      final overrides = <String, dynamic>{
        for (final doc in overridesSnap.docs)
          doc.id: {
            'dx': (doc.data()['dx'] as num?)?.toDouble() ?? 0.0,
            'dy': (doc.data()['dy'] as num?)?.toDouble() ?? 0.0,
            'dz': (doc.data()['dz'] as num?)?.toDouble() ?? 0.0,
          },
      };
      _logger.i('BIM sending load (overrides=${overrides.length}, colors=${_colors().length})');
      _viewer.send({
        'type': 'load',
        'url': url,
        'select': widget.focusGlobalId,
        'colors': _colors(),
        if (overrides.isNotEmpty) 'overrides': overrides,
      });
    } catch (e) {
      _logger.e('BIM could not get model URL', error: e);
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
        _logger.i('BIM model loaded — storeys=${(msg['storeys'] as List?)?.length ?? 0}');
        final rawStoreys = (msg['storeys'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        setState(() {
          _loaded = true;
          _progress = null;
          _viewerStoreys = [
            for (final s in rawStoreys)
              (globalId: s['globalId'] as String, name: s['name'] as String? ?? s['globalId'] as String),
          ];
        });
        _viewer.send({'type': 'colors', 'colors': _colors()});
        if (_xray) _viewer.send({'type': 'xray', 'on': true});
        // Push any annotations that arrived before the model finished loading.
        if (_annotationItems.isNotEmpty) {
          _viewer.send({'type': 'annotations', 'items': _annotationItems});
        }
      case 'selected':
        setState(() {
          _selection = msg['globalId'] == null ? null : msg;
          // Reset edit mode whenever the selection changes.
          _editingEquipment = false;
        });
      case 'error':
        final errMsg = msg['message'] as String? ?? 'The viewer reported an error.';
        _logger.e('BIM viewer error: $errMsg');
        setState(() { _error = errMsg; _progress = null; });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Could not display the 3D model. Please try again.'),
              action: SnackBarAction(label: 'Dismiss', onPressed: () {}),
            ),
          );
        }
      case 'measurement':
        if (msg['state'] == 'firstPoint') {
          setState(() => _measureResult = 'Tap second point…');
        } else {
          setState(() => _measureResult = msg['distanceText'] as String?);
        }
      case 'annotateAt':
        _showAnnotateDialog(
          x: (msg['x'] as num).toDouble(),
          y: (msg['y'] as num).toDouble(),
          z: (msg['z'] as num).toDouble(),
        );
      case 'transformed':
        _saveTransformOverride(
          globalId: msg['globalId'] as String,
          dx: (msg['dx'] as num).toDouble(),
          dy: (msg['dy'] as num).toDouble(),
          dz: (msg['dz'] as num).toDouble(),
        );
      case 'modeExited':
        setState(() {
          _measureMode  = false;
          _annotateMode = false;
          _transformMode = false;
          _measureResult = null;
        });
    }
  }

  Future<void> _showAnnotateDialog({required double x, required double y, required double z}) async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Annotation', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Describe this location…',
            border: const OutlineInputBorder(),
            hintStyle: GoogleFonts.poppins(fontSize: 13),
          ),
          style: GoogleFonts.poppins(fontSize: 13),
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Save', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (text == null || text.isEmpty) return;
    try {
      await _facility.collection('bimAnnotations').add({
        'text': text,
        'worldPosition': {'x': x, 'y': y, 'z': z},
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      });
    } catch (e) {
      _logger.w('Could not save annotation: $e');
    }
  }

  Future<void> _saveTransformOverride({
    required String globalId,
    required double dx,
    required double dy,
    required double dz,
  }) async {
    try {
      await _facility.collection('bimElementOverrides').doc(globalId).set({
        'dx': dx,
        'dy': dy,
        'dz': dz,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
      });
    } catch (e) {
      _logger.w('Could not save transform override: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    return ResponsiveScreenWrapper(
      title: '3D Viewer',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? '-',
      organization: roleInfo?.organization ?? '-',
      actions: [
        if (_model != null && bimViewerSupported && _loaded) ...[
          // Floor isolation dropdown
          _buildFloorSelector(),
          // Measure distance
          IconButton(
            tooltip: _measureMode ? 'Exit measure mode' : 'Measure distance',
            icon: Icon(Icons.straighten_rounded,
                color: _measureMode ? Colors.yellowAccent : Colors.white),
            onPressed: () {
              final on = !_measureMode;
              setState(() {
                _measureMode = on;
                if (!on) _measureResult = null;
              });
              _viewer.send({'type': 'measure', 'on': on});
            },
          ),
          // Place annotation
          IconButton(
            tooltip: _annotateMode ? 'Exit annotation mode' : 'Add location annotation',
            icon: Icon(Icons.push_pin_rounded,
                color: _annotateMode ? Colors.yellowAccent : Colors.white),
            onPressed: () {
              final on = !_annotateMode;
              setState(() => _annotateMode = on);
              _viewer.send({'type': 'annotate', 'on': on});
            },
          ),
          // Reposition element (admin/developer only)
          if (canManageBim(roleInfo))
            IconButton(
              tooltip: _transformMode ? 'Exit reposition mode' : 'Reposition selected element',
              icon: Icon(Icons.open_with_rounded,
                  color: _transformMode ? Colors.yellowAccent : Colors.white),
              onPressed: () {
                final on = !_transformMode;
                setState(() => _transformMode = on);
                _viewer.send({'type': 'transform', 'on': on});
              },
            ),
          // Spaces toggle
          IconButton(
            tooltip: _showSpaces ? 'Hide space boundaries' : 'Show space boundaries',
            icon: Icon(_showSpaces ? Icons.meeting_room_rounded : Icons.meeting_room_outlined,
                color: Colors.white),
            onPressed: () {
              setState(() => _showSpaces = !_showSpaces);
              _viewer.send({'type': 'showSpaces', 'on': _showSpaces});
            },
          ),
          IconButton(
            tooltip: _xray ? 'Show walls normally' : 'X-ray: see equipment through walls',
            icon: Icon(_xray ? Icons.visibility_rounded : Icons.layers_clear_rounded,
                color: Colors.white),
            onPressed: () {
              setState(() => _xray = !_xray);
              _viewer.send({'type': 'xray', 'on': _xray});
            },
          ),
          IconButton(
            tooltip: 'Reset view',
            icon: const Icon(Icons.center_focus_strong_rounded, color: Colors.white),
            onPressed: () {
              setState(() {
                _selection = null;
                _isolatedStoreyGid = null;
                _measureMode = false;
                _annotateMode = false;
                _transformMode = false;
                _measureResult = null;
              });
              _viewer.send({'type': 'reset'});
            },
          ),
        ],
        if (_models.isNotEmpty)
          PopupMenuButton<BimModel>(
            tooltip: _models.length == 1
                ? 'Current model: ${_model?.fileName ?? ''}'
                : 'Switch model (${_models.length} available)',
            icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white),
            onSelected: _open,
            itemBuilder: (_) => [
              for (final m in _models)
                CheckedPopupMenuItem(
                  value: m,
                  checked: m.id == _model?.id,
                  child: Text('${m.fileName}  ·  rev ${m.revision}  ·  ${DateFormat.yMMMd().format(m.uploadedAt)}',
                      style: GoogleFonts.poppins(fontSize: 13)),
                ),
            ],
          ),
      ],
      child: _buildBody(),
    );
  }

  Widget _buildFloorSelector() {
    if (_viewerStoreys.isEmpty) return const SizedBox.shrink();
    // Ensure the isolated value is still valid for the currently loaded model.
    final validGid = _viewerStoreys.any((s) => s.globalId == _isolatedStoreyGid)
        ? _isolatedStoreyGid
        : null;
    return Theme(
      data: Theme.of(context).copyWith(canvasColor: const Color(0xFF1E293B)),
      child: DropdownButton<String?>(
        value: validGid,
        hint: Text('All floors', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
        style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        dropdownColor: const Color(0xFF1E293B),
        underline: const SizedBox.shrink(),
        icon: const Icon(Icons.layers_rounded, color: Colors.white70),
        onChanged: (gid) {
          setState(() => _isolatedStoreyGid = gid);
          _viewer.send({'type': 'isolate', 'storeyGlobalId': gid});
        },
        items: [
          DropdownMenuItem<String?>(
            value: null,
            child: Text('All floors', style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
          ),
          for (final s in _viewerStoreys)
            DropdownMenuItem<String?>(
              value: s.globalId,
              child: Text(s.name, style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
            ),
        ],
      ),
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
        if (_dataError != null && _error == null)
          Positioned(left: 16, right: 16, top: 16, child: AppErrorBanner(message: _dataError!)),
        if (_loaded) Positioned(left: 12, top: 12, child: _buildLegend()),
        if (_measureResult != null)
          Positioned(
            left: 0, right: 0, bottom: 20,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_measureResult!,
                    style: GoogleFonts.poppins(fontSize: 14, color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        if (panel != null)
          isWide
              ? Positioned(right: 16, top: 16, bottom: 16, width: 360, child: panel)
              : Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.55,
                    ),
                    child: panel,
                  ),
                ),
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
    final roleInfo = ref.read(currentUserRoleProvider).value;
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
              // Header row
              Row(children: [
                Icon(equipment == null ? Icons.view_in_ar_outlined : Icons.precision_manufacturing_rounded,
                    color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(equipment?.name ?? (sel['name'] as String?) ?? ifcType,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.textPrimary)),
                ),
                if (_editingEquipment)
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Cancel edit',
                    onPressed: () => setState(() => _editingEquipment = false),
                  )
                else
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
              ] else if (_editingEquipment) ...[
                _buildEquipmentEditForm(equipment),
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
                if (equipment.notes.isNotEmpty) detail('Notes', equipment.notes),
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
                  if (canManageBim(roleInfo))
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: Text('Edit', style: GoogleFonts.poppins(fontSize: 13)),
                      onPressed: () => setState(() {
                        _editingEquipment = true;
                        _editStatus = equipment.status;
                        _editSpaceId = equipment.spaceId;
                        _editNotesCtrl.text = equipment.notes;
                      }),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEquipmentEditForm(Equipment equipment) {
    const statuses = ['Active', 'Under Repair', 'Inactive', 'Decommissioned'];
    // Rooms (spaces with a parent) sorted by name
    final rooms = _spaces.values
        .where((s) => s.kind == BimSpaceKind.space)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Edit Equipment', style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600,
            color: AppColors.textPrimary)),
        const SizedBox(height: 10),
        // Status
        DropdownButtonFormField<String>(
          initialValue: _editStatus,
          decoration: InputDecoration(
            labelText: 'Status',
            labelStyle: GoogleFonts.poppins(fontSize: 12),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
          items: [
            for (final s in statuses)
              DropdownMenuItem(value: s, child: Text(s, style: GoogleFonts.poppins(fontSize: 13))),
          ],
          onChanged: (v) => setState(() => _editStatus = v),
        ),
        const SizedBox(height: 10),
        // Room reassignment
        DropdownButtonFormField<String?>(
          initialValue: rooms.any((r) => r.id == _editSpaceId) ? _editSpaceId : null,
          decoration: InputDecoration(
            labelText: 'Room / Space',
            labelStyle: GoogleFonts.poppins(fontSize: 12),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('— Unassigned —', style: GoogleFonts.poppins(fontSize: 13,
                  color: AppColors.textSecondary)),
            ),
            for (final r in rooms)
              DropdownMenuItem<String?>(
                value: r.id,
                child: Text(r.name, style: GoogleFonts.poppins(fontSize: 13)),
              ),
          ],
          onChanged: (v) => setState(() => _editSpaceId = v),
        ),
        const SizedBox(height: 10),
        // Notes
        TextField(
          controller: _editNotesCtrl,
          decoration: InputDecoration(
            labelText: 'Notes',
            labelStyle: GoogleFonts.poppins(fontSize: 12),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          style: GoogleFonts.poppins(fontSize: 13),
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _savingEdit ? null : () => setState(() => _editingEquipment = false),
              child: Text('Cancel', style: GoogleFonts.poppins(fontSize: 13)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: _savingEdit ? null : () => _saveEquipmentEdit(equipment),
              child: _savingEdit
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('Save', style: GoogleFonts.poppins(fontSize: 13)),
            ),
          ),
        ]),
      ],
    );
  }

  Future<void> _saveEquipmentEdit(Equipment equipment) async {
    setState(() => _savingEdit = true);
    try {
      await _facility.collection('equipment').doc(equipment.id).update({
        'status': _editStatus ?? equipment.status,
        'notes': _editNotesCtrl.text.trim(),
        if (_editSpaceId != null) 'spaceId': _editSpaceId,
        if (_editSpaceId == null && equipment.spaceId != null) 'spaceId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _editingEquipment = false);
    } catch (e) {
      _logger.w('Could not save equipment edit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e', style: GoogleFonts.poppins(fontSize: 13))),
        );
      }
    } finally {
      if (mounted) setState(() => _savingEdit = false);
    }
  }

  Color _statusColor(Equipment e) => switch (e.status.toLowerCase()) {
        'under repair' => _Overlay.underRepair,
        'inactive' || 'decommissioned' => _Overlay.inactive,
        _ => _Overlay.active,
      };
}
