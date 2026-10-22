import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/display%20screens/equipment_supplied_screen.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/screens/bim/spaces_screen.dart';
import 'package:cmms/services/bim/bim_import_service.dart';
import 'package:cmms/services/bim/cobie_parser.dart';
import 'package:cmms/services/bim/cobie_workbook_reader.dart';
import 'package:cmms/services/bim/ifc_parser.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Top-level so `compute()` can run it off the UI isolate (on web it runs inline).
CobiePreview _parseCobieBytes(Uint8List bytes) => CobieParser.parse(CobieWorkbookReader.read(bytes));

/// Parsing happens on the device, so very large models are refused rather than exhausting memory.
/// Typical MEP models are 20–150 MB; a federated whole-campus model can be far larger.
const int _maxIfcBytes = 300 * 1024 * 1024;
const int _maxXlsxBytes = 60 * 1024 * 1024;

/// Pick a COBie .xlsx or an IFC .ifc -> review what will be created and any warnings -> confirm.
/// Nothing is written to Firestore until the user taps the import button.
class BimImportScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const BimImportScreen({super.key, required this.facilityId});

  @override
  ConsumerState<BimImportScreen> createState() => _BimImportScreenState();
}

class _BimImportScreenState extends ConsumerState<BimImportScreen> {
  final Logger _logger = Logger();
  final BimImportService _service = BimImportService();

  bool _parsing = false;
  bool _importing = false;
  bool _keepOriginal = true;

  String? _fileName;
  Uint8List? _bytes;
  BimSourceType? _sourceType;
  String? _schemaVersion;
  String? _buildingName;
  CobiePreview? _preview;
  final Set<String> _excludedTypes = {};

  BimImportResult? _result;
  String? _error;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _result = null;
      _preview = null;
      _bytes = null;
      _excludedTypes.clear();
    });

    try {
      // Mobile pickers filter by MIME/UTI and have none registered for .ifc, so a custom filter there
      // would grey the file out. Let the user pick any file and validate the extension below.
      final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
      final file = await FilePicker.pickFile(
        type: mobile ? FileType.any : FileType.custom,
        allowedExtensions: mobile ? null : const ['xlsx', 'ifc'],
      );
      if (file == null) return;

      final ext = (file.extension ?? '').toLowerCase();
      if (ext != 'xlsx' && ext != 'ifc') {
        throw const FormatException(
            'Choose a COBie spreadsheet (.xlsx) or an IFC model (.ifc). Legacy .xls, .ifczip and .rvt files are not supported; '
            'export IFC from the authoring tool (Revit: File → Export → IFC).');
      }
      final isIfc = ext == 'ifc';
      final size = await file.length();
      if (size > (isIfc ? _maxIfcBytes : _maxXlsxBytes)) {
        throw FormatException(
            'This file is ${formatBytes(size)}. The limit for in-app import is ${formatBytes(isIfc ? _maxIfcBytes : _maxXlsxBytes)}. '
            '${isIfc ? 'Ask for the MEP model on its own, or a COBie export, which is much smaller.' : ''}');
      }

      setState(() => _parsing = true);
      final bytes = await file.readAsBytes();

      CobiePreview preview;
      String? schema;
      String? building;
      if (isIfc) {
        final result = await compute(parseIfcBytes, bytes);
        preview = result.preview;
        schema = result.schemaVersion;
        building = result.buildingName;
      } else {
        preview = await compute(_parseCobieBytes, bytes);
      }
      _logger.i('BIM parsed ($ext): ${preview.spaces.length} spaces, ${preview.equipment.length} equipment, '
          '${preview.jobs.length} jobs, ${preview.warnings.length} warnings');

      if (!mounted) return;
      setState(() {
        _fileName = file.name;
        _bytes = bytes;
        _sourceType = isIfc ? BimSourceType.ifc : BimSourceType.cobie;
        _schemaVersion = schema;
        _buildingName = building;
        _preview = preview;
        _parsing = false;
      });
    } catch (e, st) {
      _logger.e('BIM parse failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = e is FormatException ? e.message : 'Could not read this file: $e';
        _parsing = false;
      });
    }
  }

  CobiePreview _filtered(CobiePreview p) => _excludedTypes.isEmpty
      ? p
      : CobiePreview(
          spaces: p.spaces,
          equipment: p.equipment.where((e) => !_excludedTypes.contains(e.type)).toList(),
          jobs: p.jobs,
          warnings: p.warnings,
        );

  Future<void> _confirmImport() async {
    final preview = _preview;
    final user = FirebaseAuth.instance.currentUser;
    if (preview == null || user == null) return;

    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await _service.commit(
        facilityId: widget.facilityId,
        fileName: _fileName ?? 'model',
        sizeBytes: _bytes?.length,
        preview: _filtered(preview),
        userId: user.uid,
        sourceType: _sourceType ?? BimSourceType.cobie,
        schemaVersion: _schemaVersion,
        sourceBytes: _keepOriginal ? _bytes : null,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _preview = null;
        _bytes = null;
        _importing = false;
      });
    } on FirebaseException catch (e) {
      _logger.e('BIM import failed', error: e);
      if (!mounted) return;
      setState(() {
        _error = e.code == 'permission-denied' || e.code == 'unauthorized'
            ? 'You do not have permission to import BIM data for this facility.'
            : 'Import failed: ${e.message ?? e.code}';
        _importing = false;
      });
    } catch (e, st) {
      _logger.e('BIM import failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = 'Import failed: $e';
        _importing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Import BIM Data',
      facilityId: widget.facilityId,
      currentRole: 'User',
      organization: '-',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final role = ref.watch(currentUserRoleProvider);
    if (role.isLoading && !role.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!canManageBim(role.value)) {
      return const BimPage(children: [
        BimNotice(
          message: 'Only administrators and developers can import BIM data. '
              'You can still browse imported models, spaces and equipment.',
          icon: Icons.lock_outline,
        ),
      ]);
    }

    return BimPage(
      maxWidth: 860,
      children: [
        _buildIntro(),
        const SizedBox(height: AppSpacing.md),
        if (_parsing) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text('Reading the file. Large IFC models can take a minute…', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_error != null) ...[
          AppErrorBanner(message: _error!),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_preview != null) _buildPreview(_preview!),
        if (_result != null) _buildResult(_result!),
      ],
    );
  }

  Widget _buildIntro() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.view_in_ar_rounded, color: AppColors.primary),
            const SizedBox(width: 10),
            Text('Bring in building data',
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 10),
          Text(
            'Import floors, rooms and equipment from a COBie spreadsheet (.xlsx) or an IFC model (.ifc). '
            'COBie files can also carry maintenance jobs. You will see a summary first, and nothing is saved until you confirm.\n\n'
            'Re-importing a revised file updates the same records: it never deletes anything, and it leaves your own edits '
            '(status, notes, price, history, a room you assigned) alone. COBie and IFC files of the same building that share '
            'IFC GlobalIds update one record rather than creating two.',
            style: GoogleFonts.poppins(fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 260,
              child: AppGradientButton(
                label: _preview == null ? 'Choose file (.xlsx or .ifc)' : 'Choose a different file',
                icon: Icons.upload_file_rounded,
                isLoading: _parsing,
                onPressed: (_parsing || _importing) ? null : _pickFile,
              ),
            ),
            Text('IFC up to ${formatBytes(_maxIfcBytes)} · COBie up to ${formatBytes(_maxXlsxBytes)}',
                style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ],
      ),
    );
  }

  Widget _buildPreview(CobiePreview p) {
    final included = _filtered(p);
    final typeCounts = <String, int>{};
    for (final e in p.equipment) {
      typeCounts[e.type] = (typeCounts[e.type] ?? 0) + 1;
    }
    final types = typeCounts.keys.toList()..sort();
    final isIfc = _sourceType == BimSourceType.ifc;
    final storeys = p.spaces.where((s) => s.isStorey).toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isIfc ? Icons.view_in_ar_rounded : Icons.table_chart_rounded, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_fileName ?? 'File',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              BimPill(label: isIfc ? (_schemaVersion ?? 'IFC') : 'COBie', color: AppColors.primary),
            ],
          ),
          if (_buildingName != null) ...[
            const SizedBox(height: 4),
            Text('Building: $_buildingName', style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary)),
          ],
          Text(formatBytes(_bytes?.length), style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: 12, runSpacing: 12, children: [
            BimStat(icon: Icons.layers_rounded, label: 'Floors', value: '${p.storeyCount}'),
            BimStat(icon: Icons.meeting_room_rounded, label: 'Rooms', value: '${p.roomCount}'),
            BimStat(icon: Icons.precision_manufacturing_rounded, label: 'Equipment', value: '${included.equipment.length}'),
            if (!isIfc) BimStat(icon: Icons.event_repeat_rounded, label: 'Maintenance jobs', value: '${p.jobs.length}'),
          ]),
          if (storeys.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Floors', style: _labelStyle),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in storeys.take(30))
                Chip(
                  label: Text(s.elevation == null ? s.name : '${s.name}  (${s.elevation!.toStringAsFixed(2)} m)',
                      style: GoogleFonts.poppins(fontSize: 12)),
                  backgroundColor: AppColors.surfaceAlt,
                  side: BorderSide.none,
                ),
              if (storeys.length > 30) Text('+${storeys.length - 30} more', style: _hintStyle),
            ]),
          ],
          if (types.length > 1) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Equipment to include', style: _labelStyle),
            Text('Untick categories you do not maintain (for example light fittings or outlets).', style: _hintStyle),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in types.take(60))
                FilterChip(
                  label: Text('$t (${typeCounts[t]})', style: GoogleFonts.poppins(fontSize: 12)),
                  selected: !_excludedTypes.contains(t),
                  onSelected: _importing
                      ? null
                      : (on) => setState(() => on ? _excludedTypes.remove(t) : _excludedTypes.add(t)),
                  selectedColor: AppColors.surfaceAlt,
                  checkmarkColor: AppColors.primary,
                ),
            ]),
          ],
          if (p.warnings.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                title: Text('${p.warnings.length} warning${p.warnings.length == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(color: AppColors.warning, fontWeight: FontWeight.w600)),
                children: [
                  for (final w in p.warnings.take(50))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.chevron_right, size: 18, color: AppColors.warning),
                      title: Text(w, style: GoogleFonts.poppins(fontSize: 12)),
                    ),
                  if (p.warnings.length > 50) Text('…and ${p.warnings.length - 50} more', style: _hintStyle),
                ],
              ),
            ),
          ],
          if (included.equipment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('First ${included.equipment.take(8).length} of ${included.equipment.length} equipment records',
                style: _hintStyle),
            for (final e in included.equipment.take(8))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.precision_manufacturing_outlined, size: 20, color: AppColors.textSecondary),
                title: Text(e.name, style: GoogleFonts.poppins(fontSize: 13)),
                subtitle: Text(
                  [
                    e.type,
                    if (e.typeName.isNotEmpty && e.typeName != e.type) e.typeName,
                    if (e.spaceName != null) e.spaceName!,
                    if (e.manufacturer != null) e.manufacturer!,
                  ].join('  •  '),
                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _keepOriginal,
            onChanged: _importing ? null : (v) => setState(() => _keepOriginal = v ?? true),
            title: Text('Keep a copy of the original file with this import', style: GoogleFonts.poppins(fontSize: 13)),
            subtitle: Text('Stored privately for this facility; downloadable from BIM Models.', style: _hintStyle),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (p.isEmpty)
            AppErrorBanner(
              message: isIfc
                  ? 'No floors, rooms or equipment were found in this IFC file.'
                  : 'No Floor, Space, Component or Job rows were found. Check that this is a COBie workbook.',
            )
          else
            AppGradientButton(
              label: _importing ? 'Importing…' : 'Import into this facility',
              icon: Icons.check_rounded,
              isLoading: _importing,
              onPressed: _importing ? null : _confirmImport,
            ),
        ],
      ),
    );
  }

  TextStyle get _labelStyle => GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
  TextStyle get _hintStyle => GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary);

  Widget _buildResult(BimImportResult r) {
    Widget line(String label, int created, int updated) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('$label: $created new, $updated updated', style: GoogleFonts.poppins(fontSize: 13)),
        );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success),
            const SizedBox(width: 8),
            Text('Import complete', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
          ]),
          const SizedBox(height: 10),
          line('Floors and rooms', r.spacesCreated, r.spacesUpdated),
          line('Equipment', r.equipmentCreated, r.equipmentUpdated),
          if (r.jobsCreated + r.jobsUpdated > 0) ...[
            line('Maintenance jobs', r.jobsCreated, r.jobsUpdated),
            Text('Imported jobs have no due date yet. Set one in Preventive Maintenance to start scheduling them.',
                style: _hintStyle),
          ],
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => EquipmentSuppliedScreen(facilityId: widget.facilityId)),
              ),
              icon: const Icon(Icons.precision_manufacturing_outlined),
              label: Text('View equipment', style: GoogleFonts.poppins()),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => SpacesScreen(facilityId: widget.facilityId)),
              ),
              icon: const Icon(Icons.meeting_room_outlined),
              label: Text('View floors & rooms', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('Done', style: GoogleFonts.poppins()),
            ),
          ]),
        ],
      ),
    );
  }
}
