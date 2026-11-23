import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:cmms/display_screens/equipment_supplied_screen.dart';
import 'package:cmms/models/bim_model.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/bim/bim_widgets.dart';
import 'package:cmms/screens/bim/spaces_screen.dart';
import 'package:cmms/screens/pm/ai_pm_analysis_screen.dart';
import 'package:cmms/services/bim/bim_import_service.dart';
import 'package:cmms/services/bim/bim_translation_service.dart';
import 'package:cmms/services/bim/italian_bim_glossary.dart';
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

  bool _picking = false;
  bool _parsing = false;
  bool _importing = false;
  bool _keepOriginal = true;
  bool _translateEnabled = false;
  String _parseStage = '';

  String? _fileName;
  Uint8List? _bytes;
  BimSourceType? _sourceType;
  String? _schemaVersion;
  String? _buildingName;
  String? _siteName;
  CobiePreview? _preview;
  final Set<String> _excludedTypes = {};

  BimImportResult? _result;
  String? _error;
  String _importStage = '';
  double _importFraction = 0.0;

  Future<void> _pickFile() async {
    _logger.i('BIM pick: user tapped "Choose file"');
    setState(() {
      _error = null;
      _result = null;
      _preview = null;
      _bytes = null;
      _excludedTypes.clear();
    });

    // Show "Opening file browser…" immediately — FilePicker.pickFile() blocks until
    // the system dialog closes, so without this the button tap looks like it did nothing.
    setState(() => _picking = true);

    try {
      // Mobile pickers filter by MIME/UTI and have none registered for .ifc, so a custom filter there
      // would grey the file out. Let the user pick any file and validate the extension below.
      final mobile = !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
      _logger.i('BIM pick: calling FilePicker.pickFile (platform=${defaultTargetPlatform.name}, web=$kIsWeb, mobile=$mobile)');
      final file = await FilePicker.pickFile(
        type: mobile ? FileType.any : FileType.custom,
        allowedExtensions: mobile ? null : const ['xlsx', 'ifc'],
      );
      if (!mounted) return;
      setState(() => _picking = false);

      if (file == null) {
        _logger.w('BIM pick: FilePicker returned null — user cancelled or platform did not deliver the file');
        return;
      }

      _logger.i('BIM pick: file received — name="${file.name}" ext="${file.extension}"');

      final ext = (file.extension ?? '').toLowerCase();
      if (ext != 'xlsx' && ext != 'ifc') {
        throw const FormatException(
            'Choose a COBie spreadsheet (.xlsx) or an IFC model (.ifc). Legacy .xls, .ifczip and .rvt files are not supported; '
            'export IFC from the authoring tool (Revit: File → Export → IFC).');
      }
      final isIfc = ext == 'ifc';
      final size = await file.length();
      _logger.i('BIM pick: file size=${formatBytes(size)}, isIfc=$isIfc');
      if (size > (isIfc ? _maxIfcBytes : _maxXlsxBytes)) {
        throw FormatException(
            'This file is ${formatBytes(size)}. The limit for in-app import is ${formatBytes(isIfc ? _maxIfcBytes : _maxXlsxBytes)}. '
            '${isIfc ? 'Ask for the MEP model on its own, or a COBie export, which is much smaller.' : ''}');
      }

      setState(() { _parsing = true; _parseStage = 'Reading file bytes…'; });
      _logger.i('BIM pick: reading bytes from "${file.name}"');
      final bytes = await file.readAsBytes();
      _logger.i('BIM pick: ${bytes.length} bytes read; starting parse');

      CobiePreview preview;
      String? schema;
      String? building;
      String? site;
      if (isIfc) {
        setState(() => _parseStage = 'Parsing IFC model structure…');
        _logger.i('BIM pick: dispatching IFC parse via compute()');
        final result = await compute(parseIfcBytes, bytes);
        preview = result.preview;
        schema = result.schemaVersion;
        building = result.buildingName;
        site = result.siteName;
        _logger.i('BIM pick: IFC compute() complete — schema=$schema building=$building site=$site');
      } else {
        setState(() => _parseStage = 'Reading COBie workbook…');
        _logger.i('BIM pick: dispatching COBie parse via compute()');
        preview = await compute(_parseCobieBytes, bytes);
        _logger.i('BIM pick: COBie compute() complete');
      }
      _logger.i('BIM parsed ($ext): ${preview.spaces.length} spaces, ${preview.equipment.length} equipment, '
          '${preview.jobs.length} jobs, ${preview.systems.length} systems, '
          '${preview.contacts.length} contacts, ${preview.spares.length} spares, '
          '${preview.warnings.length} warnings');

      if (!mounted) return;
      final italianDetected = _detectsItalian(preview);
      _logger.i('BIM pick: italianDetected=$italianDetected; scheduling post-frame setState');
      // On Flutter Web, compute() runs inline (no real isolate) and can fire
      // during an active frame, triggering "EngineFlutterView disposed" if setState
      // is called immediately.  Deferring to addPostFrameCallback ensures the
      // setState runs between frames rather than within one.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _fileName = file.name;
          _bytes = bytes;
          _sourceType = isIfc ? BimSourceType.ifc : BimSourceType.cobie;
          _schemaVersion = schema;
          _buildingName = building;
          _siteName = site;
          _preview = preview;
          _parsing = false;
          _parseStage = '';
          if (italianDetected) _translateEnabled = true;
        });
        _logger.i('BIM pick: done — preview is set, UI should show summary card');
      });
    } catch (e, st) {
      _logger.e('BIM parse failed', error: e, stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = e is FormatException ? e.message : 'Could not read this file: $e';
        _picking = false;
        _parsing = false;
        _parseStage = '';
      });
    }
  }

  CobiePreview _filtered(CobiePreview p) => _excludedTypes.isEmpty
      ? p
      : CobiePreview(
          spaces: p.spaces,
          equipment: p.equipment.where((e) => !_excludedTypes.contains(e.type)).toList(),
          jobs: p.jobs,
          systems: p.systems,
          contacts: p.contacts,
          spares: p.spares,
          warnings: p.warnings,
        );

  Future<void> _confirmImport() async {
    final preview = _preview;
    final user = FirebaseAuth.instance.currentUser;
    if (preview == null || user == null) return;

    setState(() {
      _importing = true;
      _error = null;
      _importStage = 'Preparing…';
      _importFraction = 0.0;
    });
    try {
      // ── Optional translation ──────────────────────────────────────────────
      CobiePreview importPreview = _filtered(preview);
      if (_translateEnabled) {
        if (mounted) setState(() { _importStage = 'Translating names…'; _importFraction = 0.0; });
        importPreview = await BimTranslationService.translateAndApply(
          importPreview,
          onProgress: (stage, fraction) {
            if (mounted) setState(() { _importStage = stage; _importFraction = fraction * 0.3; });
          },
        );
      }
      // ── Commit to Firestore ───────────────────────────────────────────────
      final result = await _service.commit(
        facilityId: widget.facilityId,
        fileName: _fileName ?? 'model',
        sizeBytes: _bytes?.length,
        preview: importPreview,
        userId: user.uid,
        sourceType: _sourceType ?? BimSourceType.cobie,
        schemaVersion: _schemaVersion,
        siteName: _siteName,
        sourceBytes: _keepOriginal ? _bytes : null,
        onProgress: (stage, fraction) {
          if (mounted) {
            setState(() {
              _importStage = stage;
              _importFraction = _translateEnabled ? 0.3 + fraction * 0.7 : fraction;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _preview = null;
        _bytes = null;
        _importing = false;
      });

      // Fire-and-forget: trigger AI analysis after a successful import.
      // Any failure here is non-fatal — the import already succeeded.
      _triggerAiAnalysis(widget.facilityId);
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
    final roleAsync = ref.watch(currentUserRoleProvider);
    final roleInfo = roleAsync.value;
    return ResponsiveScreenWrapper(
      title: 'Import BIM Data',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? '-',
      organization: roleInfo?.organization ?? '-',
      child: _buildBody(roleAsync),
    );
  }

  Widget _buildBody(AsyncValue<dynamic> role) {
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
        if (_picking) ...[
          _buildPickingIndicator(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_parsing) ...[
          _buildParsingProgress(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (_error != null) ...[
          AppErrorBanner(message: _error!),
          if (_importStage.isNotEmpty && !_importing) ...[
            const SizedBox(height: 6),
            Text('Last step reached: $_importStage', style: GoogleFonts.poppins(fontSize: 12, color: context.textSecondary)),
          ],
          const SizedBox(height: AppSpacing.md),
        ],
        if (_importing) ...[
          _buildImportProgress(),
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
                style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600, color: context.textPrimary)),
          ]),
          const SizedBox(height: 10),
          Text(
            'Import floors, rooms and equipment from a COBie spreadsheet (.xlsx) or an IFC model (.ifc). '
            'COBie files can also carry maintenance jobs. You will see a summary first, and nothing is saved until you confirm.\n\n'
            'Re-importing a revised file updates the same records: it never deletes anything, and it leaves your own edits '
            '(status, notes, price, history, a room you assigned) alone. COBie and IFC files of the same building that share '
            'IFC GlobalIds update one record rather than creating two.',
            style: GoogleFonts.poppins(fontSize: 13, height: 1.5, color: context.textSecondary),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 260,
              child: AppGradientButton(
                label: _preview == null ? 'Choose file (.xlsx or .ifc)' : 'Choose a different file',
                icon: Icons.upload_file_rounded,
                isLoading: _picking || _parsing,
                onPressed: (_picking || _parsing || _importing) ? null : _pickFile,
              ),
            ),
            Text('IFC up to ${formatBytes(_maxIfcBytes)} · COBie up to ${formatBytes(_maxXlsxBytes)}',
                style: GoogleFonts.poppins(fontSize: 12, color: context.textSecondary)),
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
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16, color: context.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              BimPill(label: isIfc ? (_schemaVersion ?? 'IFC') : 'COBie', color: AppColors.primary),
            ],
          ),
          if (_buildingName != null || _siteName != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (_siteName != null) 'Site: $_siteName',
                if (_buildingName != null) 'Building: $_buildingName',
              ].join('   '),
              style: GoogleFonts.poppins(fontSize: 13, color: context.textSecondary),
            ),
          ],
          Text(formatBytes(_bytes?.length), style: GoogleFonts.poppins(fontSize: 12, color: context.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: 12, runSpacing: 12, children: [
            BimStat(icon: Icons.layers_rounded, label: 'Floors', value: '${p.storeyCount}'),
            BimStat(icon: Icons.meeting_room_rounded, label: 'Rooms', value: '${p.roomCount}'),
            BimStat(icon: Icons.precision_manufacturing_rounded, label: 'Equipment', value: '${included.equipment.length}'),
            if (!isIfc) BimStat(icon: Icons.event_repeat_rounded, label: 'Maint. jobs', value: '${p.jobs.length}'),
            if (p.systems.isNotEmpty) BimStat(icon: Icons.account_tree_rounded, label: 'Systems', value: '${p.systems.length}'),
            if (p.contacts.isNotEmpty) BimStat(icon: Icons.contacts_rounded, label: 'Contacts', value: '${p.contacts.length}'),
            if (p.spares.isNotEmpty) BimStat(icon: Icons.inventory_2_rounded, label: 'Spares', value: '${p.spares.length}'),
          ]),
          if (storeys.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('Floors', style: _labelStyle),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in storeys.take(30))
                Chip(
                  label: Text(s.elevation == null ? s.name : '${s.name}  (${s.elevation!.toStringAsFixed(2)} m)',
                      style: GoogleFonts.poppins(fontSize: 12, color: context.textPrimary)),
                  backgroundColor: context.surfaceAltColor,
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
                  label: Text('$t (${typeCounts[t]})',
                      style: GoogleFonts.poppins(fontSize: 12, color: context.textPrimary)),
                  selected: !_excludedTypes.contains(t),
                  onSelected: _importing
                      ? null
                      : (on) => setState(() => on ? _excludedTypes.remove(t) : _excludedTypes.add(t)),
                  selectedColor: context.surfaceAltColor,
                  checkmarkColor: AppColors.primary,
                  backgroundColor: context.surfaceColor,
                  side: BorderSide(color: context.dividerColor),
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
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.chevron_right, size: 18, color: AppColors.warning),
                        title: Text(w, style: GoogleFonts.poppins(fontSize: 12)),
                      ),
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
              Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.precision_manufacturing_outlined, size: 20, color: context.textSecondary),
                  title: Text(e.name, style: GoogleFonts.poppins(fontSize: 13)),
                  subtitle: Text(
                    [
                      e.type,
                      if (e.typeName.isNotEmpty && e.typeName != e.type) e.typeName,
                      if (e.spaceName != null) e.spaceName!,
                      if (e.manufacturer != null) e.manufacturer!,
                      if (e.installationDate != null) 'Installed ${DateFormat('dd MMM yyyy').format(e.installationDate!)}',
                      if (e.warrantyEnd != null) 'Warranty to ${DateFormat('dd MMM yyyy').format(e.warrantyEnd!)}',
                      if (e.expectedLifeYears != null) '${e.expectedLifeYears} yr life',
                    ].join('  •  '),
                    style: GoogleFonts.poppins(fontSize: 11, color: context.textSecondary),
                  ),
                ),
              ),
          ],
          if (p.contacts.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.contacts_rounded, color: AppColors.primary),
                title: Text('${p.contacts.length} contact${p.contacts.length == 1 ? '' : 's'} (manufacturers, contractors)',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                children: [
                  for (final c in p.contacts.take(30))
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.person_outline, size: 18, color: context.textSecondary),
                        title: Text(c.name, style: GoogleFonts.poppins(fontSize: 12)),
                        subtitle: Text(
                          [
                            if (c.company != null) c.company!,
                            if (c.category != null) c.category!,
                            if (c.email != null) c.email!,
                          ].join('  •  '),
                          style: GoogleFonts.poppins(fontSize: 11, color: context.textSecondary),
                        ),
                      ),
                    ),
                  if (p.contacts.length > 30) Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+${p.contacts.length - 30} more', style: _hintStyle),
                  ),
                ],
              ),
            ),
          ],
          if (p.spares.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.inventory_2_rounded, color: AppColors.primary),
                title: Text('${p.spares.length} spare part${p.spares.length == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13)),
                children: [
                  for (final s in p.spares.take(30))
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.build_circle_outlined, size: 18, color: context.textSecondary),
                        title: Text(s.name, style: GoogleFonts.poppins(fontSize: 12)),
                        subtitle: Text(
                          [
                            if (s.typeName != null) s.typeName!,
                            if (s.partNumber != null) 'P/N ${s.partNumber!}',
                            if (s.supplier != null) s.supplier!,
                          ].join('  •  '),
                          style: GoogleFonts.poppins(fontSize: 11, color: context.textSecondary),
                        ),
                      ),
                    ),
                  if (p.spares.length > 30) Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('+${p.spares.length - 30} more', style: _hintStyle),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          // ── Translation option ─────────────────────────────────────────────
          const SizedBox(height: AppSpacing.sm),
          const Divider(),
          Row(
            children: [
              const Icon(Icons.translate_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Translate names to English',
                  style: GoogleFonts.poppins(
                      fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
              const Spacer(),
              Switch(
                value: _translateEnabled,
                activeThumbColor: AppColors.primary,
                onChanged: _importing ? null : (v) => setState(() => _translateEnabled = v),
              ),
            ],
          ),
          if (_translateEnabled) ...[
            const SizedBox(height: 6),
            Text(
              'Equipment names, room names, descriptions and system names will be translated '
              'from Italian to English when you tap Import — using the built-in BIM terminology '
              'glossary with no internet connection or API key required. '
              'The preview above shows the original names; translated names are what gets saved.',
              style: _hintStyle,
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Enable this if your file contains Italian names. Translation runs at import time '
              'using a built-in glossary — no internet or API key needed.',
              style: _hintStyle,
            ),
          ],
          const Divider(),
          // ── Keep original file ─────────────────────────────────────────────
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _keepOriginal,
            onChanged: _importing ? null : (v) => setState(() => _keepOriginal = v ?? true),
            title: Text('Keep a copy of the original source file', style: GoogleFonts.poppins(fontSize: 13)),
            subtitle: Text(
              _keepOriginal
                  ? 'The .xlsx / .ifc file will be stored privately and downloadable from BIM Models. '
                    'The building data (floors, rooms, equipment) is always imported regardless of this setting.'
                  : 'Only the building data will be saved — the original file will not be stored. '
                    'You can re-import from the file again later if needed.',
              style: _hintStyle,
            ),
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
            Align(
              alignment: Alignment.centerLeft,
              child: IntrinsicWidth(
                child: AppGradientButton(
                  label: _importing ? 'Importing…' : 'Import into this facility',
                  icon: Icons.check_rounded,
                  isLoading: _importing,
                  onPressed: _importing ? null : _confirmImport,
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextStyle get _labelStyle => GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary);
  TextStyle get _hintStyle => GoogleFonts.poppins(fontSize: 12, color: context.textSecondary);

  Widget _buildPickingIndicator() {
    return AppCard(
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Opening file browser…',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary)),
                const SizedBox(height: 2),
                Text('Select a .xlsx or .ifc file from your device.',
                    style: GoogleFonts.poppins(fontSize: 12, color: context.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParsingProgress() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Analysing file…',
                    style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const LinearProgressIndicator(
            backgroundColor: AppColors.surfaceAlt,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            minHeight: 5,
          ),
          const SizedBox(height: 8),
          Text(
            _parseStage.isNotEmpty ? _parseStage : 'Processing…',
            style: GoogleFonts.poppins(fontSize: 13, color: context.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Large IFC models can take up to a minute. A preview will appear when it\'s ready.',
            style: GoogleFonts.poppins(fontSize: 11, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildImportProgress() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Importing…',
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: context.textPrimary),
                ),
              ),
              Text(
                '${(_importFraction * 100).toInt()}%',
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _importFraction,
              minHeight: 7,
              backgroundColor: AppColors.surfaceAlt,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _importStage,
            style: GoogleFonts.poppins(fontSize: 13, color: context.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Returns true if the parsed preview looks like it contains Italian strings.
  /// Checks a sample of equipment and space names against the glossary — if any
  /// name is changed by translation, the file is likely Italian.
  bool _detectsItalian(CobiePreview preview) {
    final samples = [
      ...preview.equipment.take(20).map((e) => e.name),
      ...preview.spaces.take(10).map((s) => s.name),
    ];
    return samples.any((s) => s.isNotEmpty && ItalianBimGlossary.translate(s) != s);
  }

  Future<void> _triggerAiAnalysis(String facilityId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable(
            'analyzeEquipmentList',
            options: HttpsCallableOptions(timeout: const Duration(minutes: 10)),
          )
          .call({'facilityId': facilityId});
    } catch (e) {
      _logger.w('AI analysis trigger failed (non-fatal): $e');
    }
  }

  Widget _buildResult(BimImportResult r) {
    Widget line(String label, int created, int updated) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('$label: $created new, $updated updated', style: GoogleFonts.poppins(fontSize: 13)),
        );
    Widget count(String label, int n) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('$label: $n', style: GoogleFonts.poppins(fontSize: 13)),
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
          if (r.systemsWritten > 0) count('MEP systems', r.systemsWritten),
          if (r.contactsWritten > 0) count('Contacts', r.contactsWritten),
          if (r.sparesWritten > 0) count('Spare parts', r.sparesWritten),
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
            ElevatedButton.icon(
              onPressed: () {
                final roleInfo = ref.read(currentUserRoleProvider).value;
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => AiPmAnalysisScreen(
                      facilityId: widget.facilityId,
                      currentRole: roleInfo?.roleLabel ?? 'User',
                      organization: roleInfo?.organization ?? '-',
                    ),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: Text('View AI Analysis', style: GoogleFonts.poppins()),
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
