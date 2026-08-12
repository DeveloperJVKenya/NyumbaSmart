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
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/models/scope_of_work_document.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/services/pm_regeneration_service.dart';
import 'package:cmms/services/pm_scheduling_service.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';
import 'package:cmms/widgets/pdf_viewer_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

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

  // Fixed id: exactly one scope-of-work document per facility, so "upload" always means
  // "replace this one document" rather than adding another to a list.
  static const String _documentId = 'current';

  bool _isBusy = false;

  DocumentReference<Map<String, dynamic>> get _docRef => FirebaseFirestore.instance
      .collection('facilities')
      .doc(widget.facilityId)
      .collection('scope_of_work_documents')
      .doc(_documentId);

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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _docRef.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final doc = snapshot.data;
        final exists = doc != null && doc.exists;
        final sow = exists ? ScopeOfWorkDocument.fromFirestore(doc, widget.facilityId) : null;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
            return SingleChildScrollView(
              padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(isMobile),
                  const SizedBox(height: AppSpacing.lg),
                  sow == null ? _emptyState() : _documentCard(sow),
                ],
              ),
            );
          },
        );
      },
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
              Text('Scope of Work', style: GoogleFonts.poppins(fontSize: isMobile ? 18 : 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('One document covering every maintenance category for this facility', style: GoogleFonts.poppins(fontSize: isMobile ? 12.5 : 13.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.folder_open_rounded, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text('No scope of work document uploaded yet', style: GoogleFonts.poppins(fontSize: 16, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
            const SizedBox(height: 20),
            AppGradientButton(
              label: 'Upload Document',
              icon: Icons.upload_file_rounded,
              isLoading: _isBusy,
              onPressed: _isBusy ? null : () => _pickAndUpload(isReplace: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentCard(ScopeOfWorkDocument sow) {
    final isPdf = sow.fileName.toLowerCase().endsWith('.pdf');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
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
                    Text(sow.title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text('Uploaded ${DateFormat('MMM dd, yyyy').format(sow.uploadedAt)}', style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary)),
                    if (sow.startDate != null) ...[
                      const SizedBox(height: 4),
                      Text('Maintenance starts ${DateFormat('MMM dd, yyyy').format(sow.startDate!)}', style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary)),
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
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    final platformFile = result.files.single;

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

      final fileName = platformFile.name;
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
        parseStatus: ScopeOfWorkParseStatus.pending,
        startDate: startDate,
      );
      await _docRef.set(sow.toMap());

      final updatedCount = await _regenerateSchedule(startDate);

      _showSnackBar(
        isReplace
            ? 'Document replaced — $updatedCount task${updatedCount == 1 ? '' : 's'} rescheduled from ${DateFormat('MMM dd, yyyy').format(startDate)}'
            : 'Document uploaded successfully',
      );
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
                    style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary),
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
                        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.3)),
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
        content: Text('This cannot be undone. Existing scheduled tasks are not affected.', style: GoogleFonts.poppins(color: AppColors.textSecondary)),
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
                decoration: const BoxDecoration(
                  color: AppColors.card,
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
                              color: AppColors.textSecondary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        Text(
                          'Schedule New Activity',
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'For work not already covered by the uploaded scope of work document',
                          style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary),
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
                          style: GoogleFonts.poppins(color: AppColors.textPrimary),
                          decoration: const InputDecoration(labelText: 'Component', prefixIcon: Icon(Icons.precision_manufacturing_rounded, color: AppColors.primary)),
                          validator: (value) => (value == null || value.trim().isEmpty) ? 'Component is required' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: interventionController,
                          maxLines: 3,
                          style: GoogleFonts.poppins(color: AppColors.textPrimary),
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
