import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/utils/app_date_format.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/models/ai_pm_analysis.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/models/scope_of_work_document.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/pm/ai_pm_analysis_screen.dart';
import 'package:cmms/services/pm_analysis_export_service.dart';
import 'package:cmms/services/pm_regeneration_service.dart';
import 'package:cmms/services/pm_scheduling_service.dart';
import 'package:cmms/services/scope_of_work_excel_parser.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/pdf_viewer_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/utils/web_download_stub.dart'
    if (dart.library.js_interop) 'package:cmms/utils/web_download_web.dart';

/// Scope of Work: exactly one scope-of-work document per facility (a single file is expected
/// to cover every category — Civil/Electrical/Cooling/etc. — at once, so there's no per-document
/// categorization). Uploading a new file replaces the existing one and, since the uploader picks
/// the real maintenance start date, regenerates every task's schedule anchored to that date
/// rather than retroactively marking anything overdue. A secondary action schedules an activity
/// that wasn't in the uploaded document; both sources land in the same
/// facilities/{facilityId}/preventive_maintenance collection shown on the Preventive
/// Maintenance screen.
class ScheduleMaintenanceScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const ScheduleMaintenanceScreen({super.key, required this.facilityId});

  @override
  ConsumerState<ScheduleMaintenanceScreen> createState() => _ScheduleMaintenanceScreenState();
}

class _ScheduleMaintenanceScreenState extends ConsumerState<ScheduleMaintenanceScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());

  static const List<String> _activityCategorySuggestions = ['Civil', 'Electrical', 'Water Sanitation', 'Cooling'];

  // Fixed id: exactly one scope-of-work document per facility.
  static const String _documentId = 'current';

  bool _isBusy = false;

  // Manual upload is hidden by default; Admins/Developers can reveal it.
  bool _showManualUpload = false;

  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore.instance
      .collection('facilities')
      .doc(widget.facilityId)
      .collection('scope_of_work_documents')
      .doc(_documentId);

  Stream<AiPmAnalysisMeta?> get _aiMetaStream => FirebaseFirestore.instance
      .collection('facilities')
      .doc(widget.facilityId)
      .collection('aiPmAnalysis')
      .doc('_meta')
      .snapshots()
      .map((snap) => snap.exists
          ? AiPmAnalysisMeta.fromMap(snap.data()!, widget.facilityId)
          : null);

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;

    return ResponsiveScreenWrapper(
      title: 'Scope of Work',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? 'User',
      organization: roleInfo?.organization ?? '-',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isBusy ? null : () => _showScheduleActivitySheet(context),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add_task_rounded, color: Colors.white),
        label: Text('Schedule Activity', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
      ),
      child: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(top: false, child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    final role = roleInfo?.roleLabel ?? 'User';
    final canManage = role == 'Admin' || role == 'Developer';

    return StreamBuilder<AiPmAnalysisMeta?>(
      stream: _aiMetaStream,
      builder: (context, aiSnap) {
        final aiMeta = aiSnap.data;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _docRef.snapshots(),
          builder: (context, sowSnap) {
            if (sowSnap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final sowDoc = sowSnap.data;
            final sow = (sowDoc != null && sowDoc.exists)
                ? ScopeOfWorkDocument.fromFirestore(sowDoc, widget.facilityId)
                : null;

            return LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
                final hp = isMobile ? AppSpacing.md : AppSpacing.xl;
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(hp, AppSpacing.md, hp, hp),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _header(isMobile),
                      const SizedBox(height: AppSpacing.lg),

                      // ── AI-generated SoW (primary) ──────────────────────
                      _aiSowCard(aiMeta, role),
                      const SizedBox(height: AppSpacing.md),

                      // ── Manual upload (hidden, Admin/Developer toggle) ───
                      if (canManage) ...[
                        TextButton.icon(
                          onPressed: () => setState(() => _showManualUpload = !_showManualUpload),
                          icon: Icon(
                            _showManualUpload ? Icons.visibility_off_outlined : Icons.upload_file_outlined,
                            size: 16,
                            color: context.textSecondary,
                          ),
                          label: Text(
                            _showManualUpload ? 'Hide legacy upload' : 'Show legacy upload',
                            style: GoogleFonts.poppins(fontSize: 12, color: context.textSecondary),
                          ),
                        ),
                        if (_showManualUpload) ...[
                          const SizedBox(height: 8),
                          sow == null ? _legacyEmptyState() : _documentCard(sow),
                        ],
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _aiSowCard(AiPmAnalysisMeta? meta, String role) {
    final canNavigate = role == 'Admin' || role == 'Developer' || role == 'Technician';
    final isPublished = meta?.publishedSowId != null;
    final isRunning = meta?.status == AiAnalysisStatus.running;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.auto_awesome_outlined,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('AI-Generated Scope of Work',
                  style: GoogleFonts.poppins(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              Text('Sourced from BIM model AI analysis',
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, color: context.textSecondary)),
            ]),
          ),
          if (isPublished)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text('Published',
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success)),
            ),
          if (isRunning)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5)),
                const SizedBox(width: 6),
                Text('Running',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent)),
              ]),
            ),
        ]),
        const SizedBox(height: 16),

        if (!isPublished && !isRunning)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'No published AI analysis yet. Import a BIM model and run the AI analysis to generate the Scope of Work.',
              style: GoogleFonts.poppins(
                  fontSize: 13, color: context.textSecondary),
            ),
          ),

        if (isPublished) ...[
          Row(children: [
            _statChip(Icons.list_alt_rounded, '${meta!.itemCount} items'),
            const SizedBox(width: 8),
            if (meta.completedAt != null)
              _statChip(Icons.access_time_rounded,
                  AppDateFormat.format(meta.completedAt!)),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _dlButton('CSV', Icons.table_chart_outlined, 'csv'),
            _dlButton('Excel', Icons.grid_on_outlined, 'xlsx'),
            _dlButton('PDF', Icons.picture_as_pdf_outlined, 'pdf'),
            _dlButton('DOCX', Icons.article_outlined, 'docx'),
          ]),
          const SizedBox(height: 4),
        ],

        if (canNavigate) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final roleInfo = ref.read(currentUserRoleProvider).value;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AiPmAnalysisScreen(
                    facilityId: widget.facilityId,
                    currentRole: roleInfo?.roleLabel ?? 'User',
                    organization: roleInfo?.organization ?? '-',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: Text('Open AI Analysis',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
              foregroundColor: AppColors.primary,
            ),
          ),
        ],
      ]),
    );
  }

  Widget _statChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.surfaceAltColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: context.textSecondary),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11.5, color: context.textSecondary)),
      ]),
    );
  }

  Widget _dlButton(String label, IconData icon, String format) {
    return OutlinedButton.icon(
      onPressed: () => _handleAiExport(format),
      icon: Icon(icon, size: 15),
      label: Text(label, style: GoogleFonts.poppins(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
    );
  }

  Future<void> _handleAiExport(String format) async {
    final itemsSnap = await FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('aiPmAnalysis')
        .where(FieldPath.documentId, isNotEqualTo: '_meta')
        .get();
    final items = itemsSnap.docs.map(AiPmAnalysisItem.fromFirestore).toList();
    if (items.isEmpty) {
      _showSnackBar('No analysis items to export');
      return;
    }

    late Uint8List bytes;
    late String fileName;
    late String mime;
    switch (format) {
      case 'csv':
        bytes = PmAnalysisExportService.toCsv(items);
        fileName = 'pm_scope_of_work.csv';
        mime = 'text/csv';
      case 'xlsx':
        bytes = PmAnalysisExportService.toXlsx(items);
        fileName = 'pm_scope_of_work.xlsx';
        mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'pdf':
        bytes = await PmAnalysisExportService.toPdf(items);
        fileName = 'pm_scope_of_work.pdf';
        mime = 'application/pdf';
      case 'docx':
        bytes = await PmAnalysisExportService.toDocx(items);
        fileName = 'pm_scope_of_work.docx';
        mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return;
    }

    if (kIsWeb) {
      triggerWebDownload(bytes, fileName, mime);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes);
      await OpenFile.open(file.path);
    }
  }

  Widget _legacyEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          Icon(Icons.folder_open_rounded,
              size: 48, color: context.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text('No legacy document uploaded',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 16),
          AppGradientButton(
            label: 'Upload Document',
            icon: Icons.upload_file_rounded,
            isLoading: _isBusy,
            onPressed: _isBusy ? null : () => _pickAndUpload(isReplace: false),
          ),
        ]),
      ),
    );
  }

  Widget _header(bool isMobile) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.md),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          child: const Icon(Icons.work_outline_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Scope of Work', style: GoogleFonts.poppins(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: context.textPrimary)),
              const SizedBox(height: 2),
              Text('One document covering every maintenance category for this facility', style: GoogleFonts.poppins(fontSize: isMobile ? 12.5 : 13.5, color: context.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }


  Widget _documentCard(ScopeOfWorkDocument sow) {
    final isPdf = sow.fileName.toLowerCase().endsWith('.pdf');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (isPdf ? AppColors.error : AppColors.success).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.table_chart_rounded, color: isPdf ? AppColors.error : AppColors.success, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sow.title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    const SizedBox(height: 6),
                    Text('Uploaded ${AppDateFormat.format(sow.uploadedAt)}', style: GoogleFonts.poppins(fontSize: 12.5, color: context.textSecondary)),
                    if (sow.startDate != null) ...[
                      const SizedBox(height: 4),
                      Text('Maintenance starts ${AppDateFormat.format(sow.startDate!)}', style: GoogleFonts.poppins(fontSize: 12.5, color: context.textSecondary)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _actionButton('View', Icons.visibility_rounded, () => _viewDocument(sow)),
              _actionButton('Download', Icons.download_rounded, () => _downloadDocument(sow)),
              _actionButton('Replace', Icons.change_circle_outlined, _isBusy ? null : () => _pickAndUpload(isReplace: true)),
              _actionButton('Delete', Icons.delete_outline_rounded, _isBusy ? null : () => _deleteDocument(sow), destructive: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback? onPressed, {bool destructive = false}) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: destructive ? AppColors.error : AppColors.primary),
      label: Text(label, style: GoogleFonts.poppins(color: destructive ? AppColors.error : AppColors.primary, fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: (destructive ? AppColors.error : AppColors.primary).withValues(alpha: 0.4))),
    );
  }

  Future<void> _pickAndUpload({required bool isReplace}) async {
    final platformFile = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'pdf'],
    );
    if (platformFile == null) return;
    final fileName = platformFile.name;
    final isExcel = ScopeOfWorkSourceTypeExtension.fromFileName(fileName) == ScopeOfWorkSourceType.excel;

    // Excel workbooks are unambiguous (fixed column names, no OCR/fuzzy mapping needed), so
    // parsing happens client-side right after picking — but nothing is written until the user
    // reviews a preview and confirms, so a wrong file never silently pollutes the schedule.
    List<ParsedScopeOfWorkRow>? parsedRows;
    if (isExcel) {
      try {
        final bytes = await platformFile.readAsBytes();
        parsedRows = ScopeOfWorkExcelParser.parse(bytes);
      } catch (e) {
        _showSnackBar('Could not read this Excel file: $e');
        return;
      }
      if (!mounted) return;
      final confirmed = await _showExcelPreview(parsedRows);
      if (confirmed != true) return;
    }

    if (!mounted) return;
    final startDate = await _pickStartDate(context);
    if (startDate == null) return; // user cancelled

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('Please log in to upload');
      return;
    }

    setState(() => _isBusy = true);
    try {
      // Replacing: remove the previous file from Storage first so it doesn't linger orphaned.
      if (isReplace) {
        final existing = await _docRef.get();
        final oldUrl = existing.data()?['downloadUrl'] as String?;
        if (oldUrl != null) {
          try {
            await FirebaseStorage.instance.refFromURL(oldUrl).delete();
          } catch (e) {
            _logger.w('Could not delete previous scope of work file (continuing): $e');
          }
        }
      }

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('facilities/${widget.facilityId}/schedule_maintenance/${DateTime.now().millisecondsSinceEpoch}_$fileName');

      if (kIsWeb || Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final bytes = await platformFile.readAsBytes();
        await storageRef.putData(bytes, SettableMetadata(customMetadata: {'uploadedBy': user.uid}));
      } else {
        final path = platformFile.path;
        if (path == null) throw 'Failed to get file path';
        await storageRef.putFile(File(path), SettableMetadata(customMetadata: {'uploadedBy': user.uid}));
      }

      final downloadUrl = await storageRef.getDownloadURL();
      final sourceType = ScopeOfWorkSourceTypeExtension.fromFileName(fileName) ?? ScopeOfWorkSourceType.excel;

      final sow = ScopeOfWorkDocument(
        id: _documentId,
        facilityId: widget.facilityId,
        title: fileName,
        fileName: fileName,
        downloadUrl: downloadUrl,
        uploadedAt: DateTime.now(),
        uploadedBy: user.uid,
        sourceType: sourceType,
        parseStatus: isExcel ? ScopeOfWorkParseStatus.parsed : ScopeOfWorkParseStatus.pending,
        startDate: startDate,
      );
      await _docRef.set(sow.toMap());

      int? tasksCreated;
      if (isExcel && parsedRows != null) {
        tasksCreated = await _commitExcelTasks(parsedRows, startDate, user.uid);
      }

      final updatedCount = await _regenerateSchedule(startDate);

      final message = StringBuffer();
      if (tasksCreated != null) {
        message.write('$tasksCreated task${tasksCreated == 1 ? '' : 's'} scheduled from ${AppDateFormat.format(startDate)}');
      } else if (isReplace) {
        message.write('Document replaced — $updatedCount task${updatedCount == 1 ? '' : 's'} rescheduled from ${AppDateFormat.format(startDate)}');
      } else {
        message.write('Document uploaded successfully');
      }
      _showSnackBar(message.toString());
    } catch (e) {
      _logger.e('Error uploading scope of work document: $e');
      _showSnackBar('Error uploading document: $e');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  /// Recomputes every existing task's due date anchored at [startDate], walking forward in
  /// each task's own frequency until landing on a date that isn't in the past — a fresh upload
  /// plans realistically from here on, rather than instantly flagging things overdue.
  Future<int> _regenerateSchedule(DateTime startDate) {
    return PmRegenerationService.regenerateFacilitySchedule(
      facilityId: widget.facilityId,
      startDate: startDate,
    );
  }

  Future<DateTime?> _pickStartDate(BuildContext context) async {
    final now = DateTime.now();
    final defaultStart = DateTime(now.year, 1, 1);

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) {
        DateTime selected = defaultStart;
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              title: Text('Maintenance Start Date', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'When did (or will) maintenance activities in this document actually begin? '
                    'Defaults to Jan 1 of this year, but change it if activities start mid-month or mid-year — '
                    'every task\'s schedule is planned from this date.',
                    style: GoogleFonts.poppins(fontSize: 13, color: context.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dialogContext,
                        initialDate: selected,
                        firstDate: DateTime(now.year - 2),
                        lastDate: DateTime(now.year + 2),
                      );
                      if (picked != null) setDialogState(() => selected = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: context.textSecondary.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Text(DateFormat('MMMM dd, yyyy').format(selected), style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('Cancel', style: GoogleFonts.poppins())),
                AppGradientButton(label: 'Continue', onPressed: () => Navigator.pop(dialogContext, selected)),
              ],
            );
          },
        );
      },
    );
  }

  /// Shows a summary of what was parsed out of the workbook and lets the user back out before
  /// anything is written — the schema is unambiguous so the parse itself is trusted, but a
  /// wrong file (or a template that doesn't match) should never silently create a pile of
  /// incorrect tasks.
  Future<bool?> _showExcelPreview(List<ParsedScopeOfWorkRow> rows) {
    final categories = rows.map((r) => r.category).where((c) => c.isNotEmpty).toSet();
    final sample = rows.take(5).toList();

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Review Parsed Tasks', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${rows.length} maintenance task${rows.length == 1 ? '' : 's'} detected across '
                '${categories.length} categor${categories.length == 1 ? 'y' : 'ies'}.',
                style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary),
              ),
              const SizedBox(height: 12),
              Text('Sample:', style: GoogleFonts.poppins(fontSize: 12.5, color: context.textSecondary)),
              const SizedBox(height: 6),
              ...sample.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.surfaceAltColor,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${row.category} — ${row.component}', style: GoogleFonts.poppins(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                        const SizedBox(height: 2),
                        Text(row.intervention, style: GoogleFonts.poppins(fontSize: 11.5, color: context.textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('Every ${row.frequencyMonths} month${row.frequencyMonths == 1 ? '' : 's'}', style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ],
                    ),
                  ),
                ),
              ),
              if (rows.length > sample.length)
                Text('...and ${rows.length - sample.length} more', style: GoogleFonts.poppins(fontSize: 12, color: context.textSecondary, fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel', style: GoogleFonts.poppins())),
          AppGradientButton(label: 'Confirm & Schedule', onPressed: () => Navigator.pop(dialogContext, true)),
        ],
      ),
    );
  }

  /// Replaces this facility's Excel-derived tasks with the freshly parsed set — simplest correct
  /// behavior for a re-upload (these are operational schedule records, not historical data worth
  /// diffing/reconciling). Manually-added tasks are untouched. Returns the number created.
  Future<int> _commitExcelTasks(List<ParsedScopeOfWorkRow> rows, DateTime startDate, String uid) async {
    final tasksRef = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('preventive_maintenance');

    final existingExcelTasks = await tasksRef
        .where('origin', isEqualTo: PmTaskOrigin.excel.value)
        .where('sourceDocId', isEqualTo: _documentId)
        .get();

    final now = DateTime.now();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in existingExcelTasks.docs) {
      batch.delete(doc.reference);
    }
    for (final row in rows) {
      final dueDate = PmSchedulingService.nextOccurrenceFromAnchor(
        anchor: startDate,
        frequencyMonths: row.frequencyMonths,
        notBefore: now,
      );
      final task = PreventiveMaintenanceTask(
        id: '',
        facilityId: widget.facilityId,
        category: row.category,
        component: row.component,
        intervention: row.intervention,
        frequencyMonths: row.frequencyMonths,
        dueDate: dueDate,
        status: PmTaskStatus.pending,
        origin: PmTaskOrigin.excel,
        sourceDocId: _documentId,
        createdBy: uid,
        createdAt: now,
        updatedAt: now,
      );
      batch.set(tasksRef.doc(), task.toMap());
    }
    await batch.commit();

    return rows.length;
  }

  Future<void> _viewDocument(ScopeOfWorkDocument sow) async {
    try {
      if (kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final uri = Uri.parse(sow.downloadUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Could not open document';
        }
      } else if (sow.fileName.toLowerCase().endsWith('.pdf')) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/${sow.fileName}';
        await Dio().download(sow.downloadUrl, filePath);
        if (await File(filePath).exists() && mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (context) => PDFViewerScreen(filePath: filePath, fileName: sow.fileName)));
        }
      } else {
        _showSnackBar('Only PDF preview is supported on mobile — use Download instead');
      }
    } catch (e) {
      _showSnackBar('Error viewing document: $e');
    }
  }

  Future<void> _downloadDocument(ScopeOfWorkDocument sow) async {
    try {
      if (kIsWeb) {
        final uri = Uri.parse(sow.downloadUrl);
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (Platform.isAndroid || Platform.isIOS) {
        var status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        if (!status.isGranted) {
          _showSnackBar('Storage permission denied');
          return;
        }
        final downloadsDir = await getExternalStorageDirectory();
        final filePath = '${downloadsDir!.path}/${sow.fileName}';
        await Dio().download(sow.downloadUrl, filePath);
        _showSnackBar('Downloaded to $filePath');
        return;
      }
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${sow.fileName}';
      await Dio().download(sow.downloadUrl, filePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Downloaded ${sow.fileName}', style: GoogleFonts.poppins()),
            action: SnackBarAction(label: 'Open', onPressed: () => OpenFile.open(filePath)),
          ),
        );
      }
    } catch (e) {
      _showSnackBar('Error downloading document: $e');
    }
  }

  Future<void> _deleteDocument(ScopeOfWorkDocument sow) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Delete scope of work document?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text('This cannot be undone. Existing scheduled tasks are not affected.', style: GoogleFonts.poppins(color: context.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text('Cancel', style: GoogleFonts.poppins())),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text('Delete', style: GoogleFonts.poppins(color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseStorage.instance.refFromURL(sow.downloadUrl).delete();
      await _docRef.delete();
      _showSnackBar('Document deleted');
    } catch (e) {
      _showSnackBar('Error deleting document: $e');
    }
  }

  Future<void> _showScheduleActivitySheet(BuildContext context) async {
    final categoryController = TextEditingController();
    final componentController = TextEditingController();
    final interventionController = TextEditingController();
    final frequencyController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              return Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.85),
                decoration: BoxDecoration(
                  color: context.cardColor,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                ),
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 20),
                            decoration: BoxDecoration(
                              color: context.textSecondary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Text(
                          'Schedule New Activity',
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'For work not already covered by the uploaded scope of work document',
                          style: GoogleFonts.poppins(fontSize: 12.5, color: context.textSecondary),
                        ),
                        const SizedBox(height: 20),
                        AppTextField(
                          controller: categoryController,
                          label: 'Category',
                          icon: Icons.category_rounded,
                          validator: (value) => (value == null || value.trim().isEmpty) ? 'Category is required' : null,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _activityCategorySuggestions
                              .map(
                                (suggestion) => ActionChip(
                                  label: Text(suggestion, style: GoogleFonts.poppins(fontSize: 12)),
                                  onPressed: () => setSheetState(() => categoryController.text = suggestion),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: componentController,
                          maxLines: 2,
                          style: GoogleFonts.poppins(color: context.textPrimary),
                          decoration: const InputDecoration(labelText: 'Component', prefixIcon: Icon(Icons.precision_manufacturing_rounded, color: AppColors.primary)),
                          validator: (value) => (value == null || value.trim().isEmpty) ? 'Component is required' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: interventionController,
                          maxLines: 3,
                          style: GoogleFonts.poppins(color: context.textPrimary),
                          decoration: const InputDecoration(labelText: 'Intervention', prefixIcon: Icon(Icons.build_rounded, color: AppColors.primary)),
                          validator: (value) => (value == null || value.trim().isEmpty) ? 'Intervention is required' : null,
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: frequencyController,
                          label: 'Frequency (months)',
                          icon: Icons.event_repeat_rounded,
                          keyboardType: TextInputType.number,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Frequency is required';
                            final parsed = int.tryParse(value.trim());
                            if (parsed == null || parsed <= 0) return 'Enter a valid number of months';
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        Align(
                          alignment: Alignment.centerRight,
                          child: AppGradientButton(
                            label: 'Save Activity',
                            icon: Icons.check_rounded,
                            onPressed: () {
                              if (!(formKey.currentState?.validate() ?? false)) return;
                              Navigator.pop(sheetContext);
                              _saveActivity(
                                category: categoryController.text.trim(),
                                component: componentController.text.trim(),
                                intervention: interventionController.text.trim(),
                                frequencyMonths: int.parse(frequencyController.text.trim()),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _saveActivity({
    required String category,
    required String component,
    required String intervention,
    required int frequencyMonths,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnackBar('Please log in to save activities');
      return;
    }

    try {
      final now = DateTime.now();
      // Seeds onto the annual Jan-1-aligned plan (e.g. a 6-month task lands on the nearest
      // upcoming end-of-June/end-of-December slot) rather than an arbitrary "today + N months"
      // date, while not retroactively marking a brand-new task overdue.
      final dueDate = PmSchedulingService.nextUpcomingOccurrence(from: now, frequencyMonths: frequencyMonths);

      final task = PreventiveMaintenanceTask(
        id: '',
        facilityId: widget.facilityId,
        category: category,
        component: component,
        intervention: intervention,
        frequencyMonths: frequencyMonths,
        dueDate: dueDate,
        status: PmTaskStatus.pending,
        origin: PmTaskOrigin.manual,
        createdBy: user.uid,
        createdAt: now,
        updatedAt: now,
      );

      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('preventive_maintenance')
          .add(task.toMap());

      _showSnackBar('Activity saved successfully');
      _logger.i('Saved manual preventive maintenance activity for facility ${widget.facilityId}: $category / $component');
    } catch (e) {
      _logger.e('Error saving activity: $e');
      _showSnackBar('Error saving activity: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
    }
  }
}
