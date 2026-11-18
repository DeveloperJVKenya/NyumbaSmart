import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cmms/models/ai_pm_analysis.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/services/pm_analysis_export_service.dart';
import 'package:cmms/services/pm_scheduling_service.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/utils/web_download_stub.dart'
    if (dart.library.js_interop) 'package:cmms/utils/web_download_web.dart';

const List<String> _categoryOrder = [
  'Electrical', 'HVAC', 'Mechanical', 'Plumbing', 'Safety', 'Structural',
  'Furniture/Fittings', 'Unknown',
];

const Map<String, IconData> _categoryIcons = {
  'Electrical': Icons.electric_bolt,
  'HVAC': Icons.ac_unit,
  'Mechanical': Icons.settings,
  'Plumbing': Icons.water_drop,
  'Safety': Icons.security,
  'Structural': Icons.foundation,
  'Furniture/Fittings': Icons.chair,
  'Unknown': Icons.help_outline,
};

const Map<String, Color> _categoryColors = {
  'Electrical': Color(0xFFF59E0B),
  'HVAC': Color(0xFF06B6D4),
  'Mechanical': Color(0xFF64748B),
  'Plumbing': Color(0xFF3B82F6),
  'Safety': Color(0xFFEF4444),
  'Structural': Color(0xFF8B5CF6),
  'Furniture/Fittings': Color(0xFF10B981),
  'Unknown': Color(0xFF9CA3AF),
};

class AiPmAnalysisScreen extends StatefulWidget {
  final String facilityId;
  final String currentRole;
  final String organization;

  const AiPmAnalysisScreen({
    super.key,
    required this.facilityId,
    required this.currentRole,
    required this.organization,
  });

  @override
  State<AiPmAnalysisScreen> createState() => _AiPmAnalysisScreenState();
}

class _AiPmAnalysisScreenState extends State<AiPmAnalysisScreen> {
  final _db = FirebaseFirestore.instance;
  final _log = Logger(printer: PrettyPrinter(methodCount: 1, noBoxingByDefault: false));
  final Set<String> _expandedCategories = Set.from(_categoryOrder);
  final Set<String> _selected = {};
  bool _selectMode = false;
  bool _verifying = false;
  bool _showExcluded = false;
  bool _isTriggering = false; // true from button-press until stream shows running


  bool get _canVerify =>
      widget.currentRole == 'Admin' || widget.currentRole == 'Developer';

  CollectionReference<Map<String, dynamic>> get _analysisRef =>
      _db.collection('facilities').doc(widget.facilityId).collection('aiPmAnalysis');

  Stream<AiPmAnalysisMeta?> get _metaStream => _analysisRef
      .doc('_meta')
      .snapshots()
      .map((snap) => snap.exists
          ? AiPmAnalysisMeta.fromMap(snap.data()!, widget.facilityId)
          : null);

  Stream<List<AiPmAnalysisItem>> get _itemsStream => _analysisRef
      .where(FieldPath.documentId, isNotEqualTo: '_meta')
      .orderBy(FieldPath.documentId)
      .snapshots()
      .map((snap) => snap.docs.map(AiPmAnalysisItem.fromFirestore).toList());

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AiPmAnalysisMeta?>(
      stream: _metaStream,
      builder: (context, metaSnap) {
        final meta = metaSnap.data;
        return ResponsiveScreenWrapper(
          title: 'PM AI Analysis',
          facilityId: widget.facilityId,
          currentRole: widget.currentRole,
          organization: widget.organization,
          actions: [
            if (!_selectMode)
              IconButton(
                icon: Icon(
                  _showExcluded ? Icons.visibility_off_outlined : Icons.filter_list_outlined,
                  color: _showExcluded ? AppColors.error : null,
                ),
                tooltip: _showExcluded ? 'Hide excluded items' : 'Show excluded items',
                onPressed: () => setState(() => _showExcluded = !_showExcluded),
              ),
            if (meta != null && !_selectMode)
              PopupMenuButton<String>(
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Export',
                onSelected: _handleExport,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'csv', child: Text('Download CSV')),
                  PopupMenuItem(value: 'xlsx', child: Text('Download Excel')),
                  PopupMenuItem(value: 'pdf', child: Text('Download PDF')),
                  PopupMenuItem(value: 'docx', child: Text('Download DOCX')),
                ],
              ),
            // Run / Update analysis button — Admin/Developer only.
            // Shows a spinner immediately on press and while running.
            if (_canVerify && !_selectMode)
              if (_isTriggering || meta?.status == AiAnalysisStatus.running)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    meta == null || meta.status == AiAnalysisStatus.idle
                        ? Icons.auto_awesome_outlined
                        : Icons.refresh_outlined,
                  ),
                  tooltip: meta == null || meta.status == AiAnalysisStatus.idle
                      ? 'Run AI Analysis'
                      : 'Update Analysis',
                  onPressed: meta == null || meta.status == AiAnalysisStatus.idle
                      ? _triggerAnalysis
                      : _reanalyse,
                ),
          ],
          // Both action bars live in Scaffold.bottomNavigationBar (bounded by
          // viewport) to avoid "BoxConstraints forces an infinite width" errors
          // that fire when a Column child with crossAxisAlignment.stretch
          // receives unconstrained cross-axis constraints on Flutter web.
          bottomBar: _selectMode && _selected.isNotEmpty
              ? _bulkAssignBar()
              : (_canVerify ? _verifyBar(meta) : null),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _statusBanner(meta),
                  Expanded(
                    child: StreamBuilder<List<AiPmAnalysisItem>>(
                      stream: _itemsStream,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final items = snap.data ?? [];
                        if (items.isEmpty && (meta == null || meta.status == AiAnalysisStatus.idle)) {
                          return _emptyState();
                        }
                        if (items.isEmpty && meta?.status == AiAnalysisStatus.running) {
                          return _runningPlaceholder();
                        }
                        return _buildTable(items, meta);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _statusBanner(AiPmAnalysisMeta? meta) {
    if (meta == null || meta.status == AiAnalysisStatus.idle) return const SizedBox(height: 0);
    if (meta.status == AiAnalysisStatus.running) {
      return ColoredBox(
        color: AppColors.primary.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Flexible(child: Text('AI analysis in progress…', style: GoogleFonts.poppins(fontSize: 13))),
          ]),
        ),
      );
    }
    if (meta.status == AiAnalysisStatus.failed) {
      return ColoredBox(
        color: AppColors.error.withValues(alpha: 0.1),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, color: AppColors.error, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text('Analysis failed: ${meta.errorMessage ?? 'Unknown error'}',
                  style: GoogleFonts.poppins(fontSize: 13, color: AppColors.error)),
            ),
          ]),
        ),
      );
    }
    return const SizedBox(height: 0);
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.auto_awesome_outlined, size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('No AI Analysis Yet',
              style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'If you have already imported a BIM model, tap below to run the AI analysis now.\n'
            'Otherwise, import a BIM model first from the BIM screen.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
          ),
          if (_canVerify) ...[
            const SizedBox(height: 24),
            // Align prevents the button from inheriting any tight infinite
            // cross-axis width from an ancestor Column with stretch.
            Align(
              child: ElevatedButton.icon(
                onPressed: _isTriggering ? null : _triggerAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
                icon: _isTriggering
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  _isTriggering ? 'Starting…' : 'Run AI Analysis',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _runningPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: 20),
          Text('AI Analysis Running',
              style: GoogleFonts.poppins(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            'The AI is scanning all equipment from your BIM model and generating '
            'personalised preventive maintenance schedules. This normally takes '
            '30 – 90 seconds depending on the number of assets.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.6),
          ),
          const SizedBox(height: 24),
          _stepIndicator(Icons.inventory_2_outlined, 'Reading equipment list from BIM data'),
          _stepIndicator(Icons.psychology_outlined, 'Analysing each asset with AI'),
          _stepIndicator(Icons.schedule_outlined, 'Generating maintenance frequencies'),
          _stepIndicator(Icons.checklist_outlined, 'Writing results to database'),
          const SizedBox(height: 8),
          Text('Do not close this screen.',
              style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _stepIndicator(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: AppColors.primary.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(label, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
      ]),
    );
  }

  Widget _buildTable(List<AiPmAnalysisItem> items, AiPmAnalysisMeta? meta) {
    final excludedCount = items.where((i) => i.excluded).length;
    final visibleItems = _showExcluded ? items : items.where((i) => !i.excluded).toList();

    final grouped = <String, List<AiPmAnalysisItem>>{};
    for (final item in visibleItems) {
      final cat = item.effectiveCategory;
      grouped.putIfAbsent(cat, () => []).add(item);
    }

    final orderedCategories = [
      ..._categoryOrder.where(grouped.containsKey),
      ...grouped.keys.where((k) => !_categoryOrder.contains(k))..toList()
    ];

    final unknownCount = (grouped['Unknown'] ?? []).length;
    final isPublished = meta?.status == AiAnalysisStatus.done &&
        meta?.publishedSowId != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 80),
      children: [
        if (excludedCount > 0 && !_showExcluded)
          _excludedBanner(excludedCount),
        if (unknownCount > 0)
          _unknownBanner(unknownCount),
        if (isPublished)
          _publishedBanner(meta!.publishedSowId!),
        const SizedBox(height: 4),
        if (grouped.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                _showExcluded
                    ? 'All items are excluded from PM scheduling.'
                    : 'All items have been excluded. Toggle the filter above to view them.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          )
        else
          ...orderedCategories.map((cat) => _categorySection(cat, grouped[cat]!)),
      ],
    );
  }

  Widget _excludedBanner(int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.block_outlined, color: AppColors.error, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$count item${count == 1 ? '' : 's'} excluded from PM scheduling. '
            'Tap the filter icon to view or restore them.',
            style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.error),
          ),
        ),
      ]),
    );
  }

  Widget _unknownBanner(int count) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Icon(Icons.warning_amber_rounded, color: AppColors.accent, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$count item${count == 1 ? '' : 's'} have unknown categories — assign categories before publishing.',
            style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.warning),
          ),
        ),
      ]),
    );
  }

  Widget _publishedBanner(String sowId) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(Icons.check_circle_outline, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text('Published to Scope of Work',
            style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.primary)),
      ]),
    );
  }

  Widget _categorySection(String category, List<AiPmAnalysisItem> items) {
    final color = _categoryColors[category] ?? const Color(0xFF9CA3AF);
    final icon = _categoryIcons[category] ?? Icons.category;
    final isExpanded = _expandedCategories.contains(category);

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() {
            if (isExpanded) {
              _expandedCategories.remove(category);
            } else {
              _expandedCategories.add(category);
            }
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surfaceAlt,
            child: Row(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(category,
                    style: GoogleFonts.poppins(fontSize: 13.5, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${items.length}',
                    style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
              ),
              const SizedBox(width: 6),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 20, color: AppColors.textSecondary),
            ]),
          ),
        ),
        if (isExpanded)
          _tableForCategory(items),
      ],
    );
  }

  static const double _tableMinWidth = 860.0;

  static const _colBorder = BorderSide(color: Color(0xFFE5E7EB), width: 1);

  Widget _tableForCategory(List<AiPmAnalysisItem> items) {
    return LayoutBuilder(builder: (ctx, box) {
      final needsHScroll = box.maxWidth < _tableMinWidth;
      final tableWidth = needsHScroll ? _tableMinWidth : box.maxWidth;

      final headerStyle = GoogleFonts.poppins(
        fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary,
      );

      // Shared helper: a header cell with right separator + padding.
      Widget hCell(String label, int flex) => Expanded(
            flex: flex,
            child: Container(
              decoration: const BoxDecoration(border: Border(right: _colBorder)),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Text(label, style: headerStyle),
            ),
          );

      Widget table = SizedBox(
        width: tableWidth,
        child: Column(
          children: [
            // ── Header row ──────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surfaceAlt,
                border: Border(
                  top: _colBorder,
                  bottom: BorderSide(color: Color(0xFFD1D5DB), width: 1),
                ),
              ),
              child: Row(children: [
                if (_selectMode) const SizedBox(width: 32),
                hCell('Element Type', 3),
                hCell('Category', 2),
                hCell('Maintenance Interval', 2),
                hCell('Reason for Maintenance', 4),
                hCell('Est. Hours', 1),
                hCell('Tools', 2),
                const SizedBox(width: 36),
              ]),
            ),
            // ── Data rows ───────────────────────────────────────────────────
            ...items.indexed.map(
              (pair) => _itemRow(pair.$2, rowIndex: pair.$1),
            ),
          ],
        ),
      );

      return needsHScroll
          ? SingleChildScrollView(scrollDirection: Axis.horizontal, child: table)
          : table;
    });
  }

  Widget _itemRow(AiPmAnalysisItem item, {required int rowIndex}) {
    final isSelected = _selected.contains(item.id);
    final catColor = _categoryColors[item.effectiveCategory] ?? const Color(0xFF9CA3AF);
    final isExcluded = item.excluded;
    final isOdd = rowIndex.isOdd;

    final textStyle = GoogleFonts.poppins(
      fontSize: 12.5,
      fontWeight: FontWeight.w500,
      decoration: isExcluded ? TextDecoration.lineThrough : null,
      color: isExcluded ? AppColors.textSecondary.withValues(alpha: 0.5) : null,
    );
    final subStyle = GoogleFonts.poppins(
      fontSize: 11.5,
      color: isExcluded
          ? AppColors.textSecondary.withValues(alpha: 0.4)
          : AppColors.textSecondary,
      decoration: isExcluded ? TextDecoration.lineThrough : null,
    );

    // Each data cell: right border + padding, fills row height via IntrinsicHeight parent.
    Widget dCell(Widget child, int flex) => Expanded(
          flex: flex,
          child: Container(
            decoration: BoxDecoration(
              border: Border(right: _colBorder),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: child,
          ),
        );

    // Base row background — alternating stripe, overridden by selection/exclusion.
    Color rowBg;
    if (isExcluded) {
      rowBg = AppColors.error.withValues(alpha: 0.03);
    } else if (isSelected) {
      rowBg = AppColors.primary.withValues(alpha: 0.08);
    } else {
      rowBg = isOdd ? const Color(0xFFF9FAFB) : AppColors.card;
    }

    return GestureDetector(
      onLongPress: () => setState(() {
        _selectMode = true;
        _selected.add(item.id);
      }),
      child: Container(
        decoration: BoxDecoration(
          color: rowBg,
          border: const Border(bottom: _colBorder),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_selectMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Checkbox(
                  value: isSelected,
                  onChanged: (v) => setState(() {
                    if (v == true) { _selected.add(item.id); } else { _selected.remove(item.id); }
                    if (_selected.isEmpty) _selectMode = false;
                  }),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            // Element Type
            dCell(
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (isExcluded) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 4),
                    child: Icon(Icons.block_outlined, size: 12, color: AppColors.error.withValues(alpha: 0.5)),
                  ),
                ],
                Expanded(
                  child: SelectableText(
                    item.typeName.isNotEmpty ? item.typeName : item.equipmentName,
                    style: textStyle,
                  ),
                ),
              ]),
              3,
            ),
            // Category
            dCell(
              Wrap(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: isExcluded ? 0.05 : 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(item.effectiveCategory,
                      style: GoogleFonts.poppins(
                        fontSize: 10.5,
                        color: catColor.withValues(alpha: isExcluded ? 0.4 : 1.0),
                        fontWeight: FontWeight.w500,
                      )),
                ),
              ]),
              2,
            ),
            // Maintenance Interval
            dCell(SelectableText(_frequencyLabel(item.frequencyMonths), style: subStyle), 2),
            // Reason for Maintenance
            dCell(
              SelectableText(item.reason, style: subStyle, maxLines: 3),
              4,
            ),
            // Estimated Hours
            dCell(
              SelectableText(
                '${item.estimatedHours % 1 == 0 ? item.estimatedHours.toInt() : item.estimatedHours}h',
                style: subStyle,
              ),
              1,
            ),
            // Tools
            dCell(
              SelectableText(
                item.tools.isEmpty ? '—' : item.tools.join(', '),
                style: subStyle,
                maxLines: 3,
              ),
              2,
            ),
            if (_canVerify)
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: AppColors.textSecondary),
                tooltip: 'Actions',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onSelected: (action) async {
                  if (action == 'edit' && !isExcluded) {
                    _showEditDialog(item);
                  } else if (action == 'exclude') {
                    await _analysisRef.doc(item.id).update({'excluded': true});
                  } else if (action == 'restore') {
                    await _analysisRef.doc(item.id).update({'excluded': false});
                  }
                },
                itemBuilder: (_) => [
                  if (!isExcluded)
                    const PopupMenuItem(value: 'edit', child: Row(children: [
                      Icon(Icons.edit_outlined, size: 16), SizedBox(width: 8), Text('Edit'),
                    ])),
                  if (!isExcluded)
                    PopupMenuItem(value: 'exclude', child: Row(children: [
                      Icon(Icons.block_outlined, size: 16, color: AppColors.error),
                      const SizedBox(width: 8),
                      Text('Exclude from PM', style: TextStyle(color: AppColors.error)),
                    ]))
                  else
                    const PopupMenuItem(value: 'restore', child: Row(children: [
                      Icon(Icons.undo_outlined, size: 16), SizedBox(width: 8), Text('Restore to PM'),
                    ])),
                ],
              )
            else
              const SizedBox(width: 36),
          ]),
        ),
      ),
    );
  }

  String _frequencyLabel(int months) {
    if (months == 1) return 'Monthly';
    if (months == 3) return 'Every 3 months';
    if (months == 6) return 'Every 6 months';
    if (months == 12) return 'Annual';
    if (months == 24) return 'Every 2 years';
    if (months % 12 == 0) return 'Every ${months ~/ 12} years';
    return 'Every $months months';
  }

  Widget _bulkAssignBar() {
    return SafeArea(
      child: Container(
        color: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Text('${_selected.length} selected',
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          const Spacer(),
          TextButton.icon(
            onPressed: _showBulkCategoryAssign,
            icon: const Icon(Icons.category_outlined, color: Colors.white, size: 18),
            label: Text('Category', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
          ),
          TextButton.icon(
            onPressed: _bulkExclude,
            icon: const Icon(Icons.block_outlined, color: Colors.white, size: 18),
            label: Text('Exclude', style: GoogleFonts.poppins(color: Colors.white, fontSize: 12)),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => setState(() { _selected.clear(); _selectMode = false; }),
          ),
        ]),
      ),
    );
  }

  Future<void> _bulkExclude() async {
    final batch = _db.batch();
    for (final id in _selected) {
      batch.update(_analysisRef.doc(id), {'excluded': true});
    }
    await batch.commit();
    if (mounted) setState(() { _selected.clear(); _selectMode = false; });
  }

  Widget _verifyBar(AiPmAnalysisMeta? meta) {
    final isPublished = meta?.publishedSowId != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.primary.withValues(alpha: 0.15))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            if (isPublished)
              Expanded(
                child: Text('Published ✓',
                    style: GoogleFonts.poppins(color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
            if (!isPublished)
              Expanded(child: Text('Review all items then publish to Scope of Work.',
                  style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary))),
            if (!isPublished)
              ElevatedButton.icon(
                onPressed: _verifying ? null : _verifyAndPublish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  // Override global theme minimumSize (double.infinity) so this
                  // button doesn't crash when Scaffold.bottomNavigationBar
                  // receives infinite-width constraints on Flutter web.
                  minimumSize: const Size(0, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: _verifying
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_outlined, size: 18),
                label: Text(_verifying ? 'Publishing…' : 'Verify & Publish',
                    style: GoogleFonts.poppins(fontSize: 13)),
              ),
            if (isPublished)
              OutlinedButton.icon(
                onPressed: _reanalyse,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  side: BorderSide(color: AppColors.primary.withValues(alpha: 0.6)),
                  foregroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.refresh, size: 16),
                label: Text('Re-analyse', style: GoogleFonts.poppins(fontSize: 12)),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showEditDialog(AiPmAnalysisItem item) async {
    String selectedCategory = item.editedCategory ?? item.category;
    int freq = item.editedFrequencyMonths ?? item.aiFrequencyMonths;
    double estHours = item.editedEstimatedHours ?? item.aiEstimatedHours;
    final reasonController = TextEditingController(text: item.editedReason ?? item.aiReason);
    final toolsController = TextEditingController(text: (item.editedTools ?? item.aiTools).join(', '));
    final sparesController = TextEditingController(text: (item.editedSpares ?? item.aiSpares).join(', '));

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(item.equipmentName,
              style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI values:  ${item.aiFrequencyMonths} months  •  ${item.aiReason}',
                  style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              Text('Category', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              DropdownButton<String>(
                value: selectedCategory,
                isExpanded: true,
                isDense: true,
                underline: Container(height: 1, color: Colors.grey.shade400),
                items: [..._categoryOrder.where((c) => c != 'Unknown'), 'Unknown'].map((c) =>
                    DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => selectedCategory = v ?? selectedCategory),
              ),
              const SizedBox(height: 10),
              Text('Frequency (months)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              Row(children: [
                IconButton(icon: const Icon(Icons.remove, size: 18), onPressed: freq > 1 ? () => setState(() => freq--) : null),
                Text('$freq', style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                IconButton(icon: const Icon(Icons.add, size: 18), onPressed: freq < 60 ? () => setState(() => freq++) : null),
                const SizedBox(width: 8),
                Text(_frequencyLabel(freq), style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
              ]),
              const SizedBox(height: 10),
              Text('Est. Time (hours)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              Row(children: [
                IconButton(
                  icon: const Icon(Icons.remove, size: 18),
                  onPressed: estHours > 0.25 ? () => setState(() => estHours = (estHours - 0.25).clamp(0.25, 8.0)) : null,
                ),
                Text('${estHours % 1 == 0 ? estHours.toInt() : estHours}h',
                    style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: estHours < 8 ? () => setState(() => estHours = (estHours + 0.25).clamp(0.25, 8.0)) : null,
                ),
              ]),
              const SizedBox(height: 10),
              Text('Maintenance Reason', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              TextFormField(
                controller: reasonController,
                maxLines: 3,
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(8)),
              ),
              const SizedBox(height: 10),
              Text('Tools Required (comma-separated)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              TextFormField(
                controller: toolsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.all(8),
                  hintText: 'e.g. multimeter, torque wrench',
                ),
              ),
              const SizedBox(height: 10),
              Text('Spare Parts / Materials (comma-separated)', style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w500)),
              TextFormField(
                controller: sparesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.all(8),
                  hintText: 'e.g. filter cartridge, O-ring',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                List<String> parseList(String s) => s
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                await _analysisRef.doc(item.id).update({
                  'editedCategory': selectedCategory,
                  'editedFrequencyMonths': freq,
                  'editedReason': reasonController.text.trim(),
                  'editedTools': parseList(toolsController.text),
                  'editedEstimatedHours': estHours,
                  'editedSpares': parseList(sparesController.text),
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    reasonController.dispose();
    toolsController.dispose();
    sparesController.dispose();
  }

  Future<void> _showBulkCategoryAssign() async {
    String? picked;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Assign Category', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: DropdownButtonFormField<String>(
          hint: const Text('Select category'),
          items: _categoryOrder.where((c) => c != 'Unknown').map((c) =>
              DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => picked = v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (picked == null) return;
              final batch = _db.batch();
              for (final id in _selected) {
                batch.update(_analysisRef.doc(id), {'editedCategory': picked});
              }
              await batch.commit();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() { _selected.clear(); _selectMode = false; });
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyAndPublish() async {
    final itemsSnap = await _analysisRef
        .where(FieldPath.documentId, isNotEqualTo: '_meta')
        .get();

    final allItems = itemsSnap.docs.map(AiPmAnalysisItem.fromFirestore).toList();
    // Skip items the user manually excluded from PM scheduling.
    final items = allItems.where((i) => !i.excluded).toList();

    if (items.isEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Nothing to Publish', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Text('All items have been excluded. Restore at least one item before publishing.',
              style: GoogleFonts.poppins(fontSize: 13)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    final unknownItems = items.where((i) => i.effectiveCategory == 'Unknown').toList();
    if (unknownItems.isNotEmpty) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Assign Unknown Categories', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: Text(
            '${unknownItems.length} item${unknownItems.length == 1 ? '' : 's'} '
            'still have an Unknown category. Assign categories to all items before publishing.',
            style: GoogleFonts.poppins(fontSize: 13),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Verify & Publish', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text(
          'This will verify ${items.length} items and publish them to the Scope of Work section. Continue?',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Publish')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _verifying = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final now = DateTime.now();
      final verifiedAt = Timestamp.fromDate(now);
      final verifiedBy = user?.uid ?? '';

      // ── 1. Batch-verify all aiPmAnalysis items ───────────────────────────────
      const chunkSize = 240;
      for (var i = 0; i < items.length; i += chunkSize) {
        final chunk = items.sublist(i, (i + chunkSize).clamp(0, items.length));
        final b = _db.batch();
        for (final item in chunk) {
          b.update(_analysisRef.doc(item.id), {
            'verificationStatus': 'verified',
            'verifiedBy': verifiedBy,
            'verifiedAt': verifiedAt,
            'publishedAt': verifiedAt,
          });
        }
        await b.commit();
      }

      // ── 2. Create the SoW document + update _meta ────────────────────────────
      final sowRef = _db.collection('facilities').doc(widget.facilityId)
          .collection('scope_of_work_documents').doc();
      final bSow = _db.batch();
      bSow.set(sowRef, {
        'facilityId': widget.facilityId,
        'title': 'BIM AI Generated PM Schedule',
        'sourceType': 'bimAiGenerated',
        'parseStatus': 'confirmed',
        'uploadedAt': verifiedAt,
        'uploadedBy': verifiedBy,
        'fileName': 'ai_pm_analysis.json',
        'downloadUrl': '',
        'itemCount': items.length,
        'aiPmAnalysisId': 'current',
      });
      bSow.update(_analysisRef.doc('_meta'), {'publishedSowId': sowRef.id});
      await bSow.commit();

      // ── 3. Upsert PM tasks from published AI items ───────────────────────────
      // Load existing PM tasks that have an equipmentId so we can update rather
      // than duplicate.
      final pmRef = _db.collection('facilities').doc(widget.facilityId)
          .collection('preventive_maintenance');
      final allEquipmentIds = items.map((e) => e.equipmentId).toSet().toList();
      final existingByEquipmentId = <String, String>{};
      for (var qi = 0; qi < allEquipmentIds.length; qi += 30) {
        final idChunk = allEquipmentIds.sublist(
            qi, (qi + 30).clamp(0, allEquipmentIds.length));
        final snap = await pmRef.where('equipmentId', whereIn: idChunk).get();
        for (final d in snap.docs) {
          final eqId = d.data()['equipmentId'] as String?;
          if (eqId != null) existingByEquipmentId[eqId] = d.id;
        }
      }

      // Load review queue entries so we can resolve them.
      final queueSnap = await _db.collection('facilities').doc(widget.facilityId)
          .collection('pm_review_queue')
          .where('status', isEqualTo: 'pending')
          .get();
      final queueByEquipmentId = <String, String>{
        for (final d in queueSnap.docs)
          if (d.data()['equipmentId'] != null)
            d.data()['equipmentId'] as String: d.id,
      };

      // Batch create/update PM tasks (max 2 ops per item: task + queue entry).
      for (var i = 0; i < items.length; i += chunkSize) {
        final chunk = items.sublist(i, (i + chunkSize).clamp(0, items.length));
        final bPm = _db.batch();
        for (final item in chunk) {
          final cat = item.effectiveCategory;
          final freq = item.frequencyMonths;
          final reason = item.reason;
          final dueDate = PmSchedulingService.computeDueDate(
              from: now, frequencyMonths: freq);

          final existingTaskId = existingByEquipmentId[item.equipmentId];
          if (existingTaskId != null) {
            bPm.update(pmRef.doc(existingTaskId), {
              'category': cat,
              'frequencyMonths': freq,
              'intervention': reason,
              'toolsRequired': item.tools,
              'estimatedHours': item.estimatedHours,
              'spares': item.spares,
              'sourceDocId': sowRef.id,
              'updatedAt': verifiedAt,
            });
          } else {
            final newRef = pmRef.doc();
            bPm.set(newRef, {
              'taskType': 'preventive_maintenance',
              'facilityId': widget.facilityId,
              'category': cat,
              'component': item.equipmentName,
              'intervention': reason,
              'frequencyMonths': freq,
              'toolsRequired': item.tools,
              'estimatedHours': item.estimatedHours,
              'spares': item.spares,
              'dueDate': Timestamp.fromDate(dueDate),
              'status': PmTaskStatus.pending.value,
              'origin': PmTaskOrigin.bim.value,
              'sourceDocId': sowRef.id,
              'equipmentId': item.equipmentId,
              'equipmentName': item.equipmentName,
              'createdBy': verifiedBy,
              'createdAt': verifiedAt,
              'updatedAt': verifiedAt,
            });
          }

          // Resolve matching review queue entry if present.
          final queueItemId = queueByEquipmentId[item.equipmentId];
          if (queueItemId != null) {
            bPm.update(
              _db.collection('facilities').doc(widget.facilityId)
                  .collection('pm_review_queue').doc(queueItemId),
              {'status': 'accepted', 'resolvedBy': verifiedBy, 'resolvedAt': verifiedAt},
            );
          }
        }
        await bPm.commit();
      }

      if (mounted) {
        final excludedCount = allItems.length - items.length;
        final excludedNote = excludedCount > 0 ? ' ($excludedCount excluded)' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            'Published ${items.length} items to Scope of Work and created PM tasks$excludedNote')),
        );
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _reanalyse() async {
    // Clear published link then re-run; _triggerAnalysis writes 'running' immediately.
    try {
      await _analysisRef.doc('_meta').update({'publishedSowId': null});
    } catch (_) {}
    await _triggerAnalysis();
  }

  Future<void> _triggerAnalysis() async {
    if (!mounted || _isTriggering) return;
    _log.i('triggerAnalysis: START facilityId=${widget.facilityId}');

    // 1. Show spinner immediately — don't wait for the stream to pick up 'running'.
    setState(() => _isTriggering = true);

    // 2. Write 'running' to Firestore right now so the status banner appears
    //    on this device before the Cloud Function even starts writing.
    try {
      await _analysisRef.doc('_meta').set(
        {'status': 'running', 'startedAt': FieldValue.serverTimestamp(), 'itemCount': 0},
        SetOptions(merge: true),
      );
    } catch (e) {
      _log.w('triggerAnalysis: could not pre-write status=running: $e');
    }

    // 3. Fire the Cloud Function WITHOUT awaiting — the Firestore streams
    //    drive all subsequent UI updates as items arrive in real-time.
    _log.i('triggerAnalysis: calling Cloud Function (fire-and-forget)');
    FirebaseFunctions.instance
        .httpsCallable(
          'analyzeEquipmentList',
          options: HttpsCallableOptions(timeout: const Duration(minutes: 10)),
        )
        .call({'facilityId': widget.facilityId})
        .then((result) {
          _log.i('triggerAnalysis: Cloud Function returned → ${result.data}');
          if (mounted) {
            setState(() => _isTriggering = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('AI analysis complete — review the results below.')),
            );
          }
        })
        .catchError((Object e) {
          _log.e('triggerAnalysis: ERROR', error: e);
          // Write failed status so the status banner reflects the error.
          _analysisRef.doc('_meta').update({
            'status': 'failed',
            'errorMessage': e.toString(),
          }).catchError((_) {});
          if (mounted) {
            setState(() => _isTriggering = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Analysis failed: $e')),
            );
          }
        });
  }

  Future<void> _handleExport(String format) async {
    final itemsSnap = await _analysisRef
        .where(FieldPath.documentId, isNotEqualTo: '_meta')
        .get();
    final items = itemsSnap.docs.map(AiPmAnalysisItem.fromFirestore).toList();
    if (items.isEmpty) return;
    {

      late Uint8List bytes;
      late String fileName;
      late String mime;

      switch (format) {
        case 'csv':
          bytes = PmAnalysisExportService.toCsv(items);
          fileName = 'pm_analysis.csv';
          mime = 'text/csv';
        case 'xlsx':
          bytes = PmAnalysisExportService.toXlsx(items);
          fileName = 'pm_analysis.xlsx';
          mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        case 'pdf':
          bytes = await PmAnalysisExportService.toPdf(items);
          fileName = 'pm_analysis.pdf';
          mime = 'application/pdf';
        case 'docx':
          bytes = await PmAnalysisExportService.toDocx(items);
          fileName = 'pm_analysis.docx';
          mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
        default:
          return;
      }

      await _saveFile(bytes, fileName, mime);
    }
  }

  Future<void> _saveFile(Uint8List bytes, String fileName, String mime) async {
    if (kIsWeb) {
      triggerWebDownload(bytes, fileName, mime);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
    }
  }
}

