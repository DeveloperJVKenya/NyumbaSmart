import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/ai_pm_analysis.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/providers/bim_providers.dart';
import 'package:cmms/screens/pm/ai_pm_analysis_screen.dart';
import 'package:cmms/services/pm_scheduling_service.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Facility-scoped preventive maintenance.  Tasks are grouped by category,
/// generated automatically from BIM-linked equipment, and can be manually
/// edited or added.  Unknown equipment types go to a review queue so the
/// facility manager can decide whether to include them.
class PreventiveMaintenanceScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const PreventiveMaintenanceScreen({super.key, required this.facilityId});

  @override
  ConsumerState<PreventiveMaintenanceScreen> createState() =>
      _PreventiveMaintenanceScreenState();
}

class _PreventiveMaintenanceScreenState
    extends ConsumerState<PreventiveMaintenanceScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();

  String? _selectedCategory;
  String _currentRole = 'User';
  String _organization = '-';
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _tasksStream;
  late final Stream<AiPmAnalysisMeta?> _aiMetaStream;
  // bimEquipmentCount is now read via bimEquipmentCountProvider (Riverpod) in
  // _aiAnalysisCard() — no manual subscription or state field needed here.
  StreamSubscription<AiPmAnalysisMeta?>? _aiMetaSub;
  AiPmAnalysisMeta? _aiMeta;
  bool _aiMetaLoaded = false;

  @override
  void initState() {
    super.initState();
    _logger.i(
        'PreventiveMaintenanceScreen initialized: facilityId=${widget.facilityId}');
    _tasksStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('preventive_maintenance')
        .snapshots();
    _aiMetaStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('aiPmAnalysis')
        .doc('_meta')
        .snapshots()
        .map((s) => s.exists
            ? AiPmAnalysisMeta.fromMap(s.data()!, widget.facilityId)
            : null);
    _aiMetaSub = _aiMetaStream.listen((m) {
      if (mounted) setState(() { _aiMeta = m; _aiMetaLoaded = true; });
    });
    _notificationService.initialize();
  }

  @override
  void dispose() {
    _aiMetaSub?.cancel();
    super.dispose();
  }

  bool get _canGenerate =>
      _currentRole == 'Admin' ||
      _currentRole == 'Developer' ||
      _currentRole == 'Technician';

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserRoleProvider, (_, next) {
      final info = next.value;
      if (info == null || !mounted) return;
      setState(() {
        _currentRole = info.roleLabel;
        _organization = info.organization;
      });
    });
    return ResponsiveScreenWrapper(
      title: 'Preventive Maintenance',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      actions: _canGenerate
          ? [
              IconButton(
                icon: const Icon(Icons.auto_awesome_outlined),
                tooltip: 'AI PM Analysis',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiPmAnalysisScreen(
                      facilityId: widget.facilityId,
                      currentRole: _currentRole,
                      organization: _organization,
                    ),
                  ),
                ),
              ),
            ]
          : null,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(builder: (context, constraints) {
      return Column(
        // stretch propagates tight bounded constraints down — prevents
        // loose-infinite from reaching Rows with Expanded children.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _tasksStream,
              builder: (context, snapshot) {
                // Show spinner only on the very first open with no cached data.
                // Firestore returns a cache snapshot almost immediately on
                // subsequent visits, so hasData guards against an unnecessary flash.
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  _logger.e('Error loading PM tasks: ${snapshot.error}');
                  return Center(
                      child: Text('Error: ${snapshot.error}',
                          style: GoogleFonts.poppins()));
                }
                final tasks = (snapshot.data?.docs ?? [])
                    .map((doc) => PreventiveMaintenanceTask.fromFirestore(
                        doc, widget.facilityId))
                    .toList();

                _logger.i(
                  'PM tasks loaded: count=${tasks.length} '
                  'selectedCategory=$_selectedCategory',
                );
                return _selectedCategory == null
                    ? _buildCategorySelection(tasks)
                    : _buildTasksList(tasks);
              },
            ),
          ),
        ],
      );
    });
  }

  // ── Category overview ──────────────────────────────────────────────────────

  Widget _buildCategorySelection(List<PreventiveMaintenanceTask> tasks) {
    if (tasks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          _aiAnalysisCard(),
          Expanded(
            child: _emptyState(
              icon: Icons.auto_awesome_outlined,
              title: 'No preventive maintenance tasks yet',
              subtitle: _canGenerate
                  ? 'Run AI analysis above to generate PM tasks from your BIM equipment.'
                  : 'Ask your facility administrator to generate PM tasks from the installed equipment.',
            ),
          ),
        ]),
      );
    }

    final byCategory = <String, List<PreventiveMaintenanceTask>>{};
    for (final task in tasks) {
      byCategory.putIfAbsent(task.category, () => []).add(task);
    }
    final categories = byCategory.keys.toList()..sort();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Categories',
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                // ── AI Analysis entry card (always first) ────────────────
                _aiAnalysisCard(),
                // ── Category cards ───────────────────────────────────────
                ...categories.map((category) {
                  final ct = byCategory[category]!;
                  final overdueCount = ct
                      .where((t) => PmSchedulingService.isOverdue(
                          dueDate: t.dueDate,
                          isCompleted:
                              t.status == PmTaskStatus.completed))
                      .length;
                  final completedCount =
                      ct.where((t) => t.status == PmTaskStatus.completed).length;
                  final inProgressCount = ct
                      .where((t) => t.status == PmTaskStatus.inProgress)
                      .length;
                  final pendingCount =
                      ct.length - completedCount - inProgressCount;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      side: BorderSide(
                        color: overdueCount > 0
                            ? AppColors.error.withValues(alpha: 0.3)
                            : AppColors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    color: AppColors.card,
                    child: InkWell(
                      onTap: () => setState(() => _selectedCategory = category),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Overdue warning strip
                          if (overdueCount > 0)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.07),
                                borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(AppRadius.md)),
                                border: Border(
                                    bottom: BorderSide(
                                        color: AppColors.error.withValues(alpha: 0.15))),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.warning_amber_rounded,
                                      size: 13, color: AppColors.error),
                                  const SizedBox(width: 5),
                                  Text(
                                    '$overdueCount overdue task${overdueCount == 1 ? '' : 's'}',
                                    style: GoogleFonts.poppins(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.error),
                                  ),
                                ],
                              ),
                            ),
                          // Card body
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Category name + icon row
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceAlt,
                                        borderRadius:
                                            BorderRadius.circular(AppRadius.sm),
                                      ),
                                      child: Icon(_categoryIcon(category),
                                          size: 18, color: AppColors.primary),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(category,
                                              style: GoogleFonts.poppins(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.textPrimary)),
                                          Text(
                                            '${ct.length} task${ct.length == 1 ? '' : 's'}',
                                            style: GoogleFonts.poppins(
                                                fontSize: 11,
                                                color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Icon(Icons.chevron_right_rounded,
                                        color: AppColors.textSecondary, size: 20),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                // Stat tiles row
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final compact = constraints.maxWidth < 280;
                                    return Row(
                                      children: [
                                        _statTile('Total', ct.length,
                                            AppColors.primary, compact),
                                        const SizedBox(width: 6),
                                        _statTile('Pending', pendingCount,
                                            AppColors.textSecondary, compact),
                                        const SizedBox(width: 6),
                                        _statTile(
                                            'In Progress',
                                            inProgressCount,
                                            AppColors.primaryLight,
                                            compact),
                                        const SizedBox(width: 6),
                                        _statTile('Done', completedCount,
                                            AppColors.success, compact),
                                      ],
                                    );
                                  },
                                ),
                                // Completion progress bar
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.pill),
                                        child: LinearProgressIndicator(
                                          value: ct.isEmpty
                                              ? 0
                                              : completedCount / ct.length,
                                          backgroundColor:
                                              AppColors.success.withValues(alpha: 0.12),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  AppColors.success),
                                          minHeight: 5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      ct.isEmpty
                                          ? '0%'
                                          : '${(completedCount / ct.length * 100).round()}%',
                                      style: GoogleFonts.poppins(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.success),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiAnalysisCard() {
    final bimCount = ref.watch(bimEquipmentCountProvider(widget.facilityId)).asData?.value;
    return _aiAnalysisCardInner(_aiMeta, bimCount, _aiMetaLoaded);
  }

  Widget _aiAnalysisCardInner(AiPmAnalysisMeta? meta, int? bimCount, bool metaLoaded) {
    // Show a neutral loading card until the first Firestore event arrives.
    // Without this guard, a brief idle render flashes before the real state
    // is known, causing a visible flicker on every screen open.
    if (!metaLoaded) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI Equipment Analysis',
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary, fontSize: 13.5)),
                Text('Loading analysis status…',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
              ]),
            ),
          ]),
        ),
      );
    }

    final status = meta?.status ?? AiAnalysisStatus.idle;
    final isRunning = status == AiAnalysisStatus.running;
    final isDone = status == AiAnalysisStatus.done;
    final isPublished = isDone && meta?.publishedSowId != null;

    // Detect stale analysis: analysis is done but BIM equipment count has
    // since changed (new import or model deleted), so the results no longer
    // match what is in Firestore.
    final isStale = isDone &&
        bimCount != null &&
        (meta?.itemCount ?? 0) > 0 &&
        bimCount != meta!.itemCount;

    final displayCount = bimCount ?? meta?.itemCount ?? 0;
    final countLabel = '$displayCount';

    String subtitle;
    Color accentColor;
    IconData icon;

    if (isRunning) {
      subtitle = 'AI analysis in progress…';
      accentColor = AppColors.primary;
      icon = Icons.auto_awesome;
    } else if (isStale) {
      subtitle = 'Equipment list changed — $countLabel items ready, tap to re-run analysis';
      accentColor = AppColors.warning;
      icon = Icons.refresh_rounded;
    } else if (isPublished) {
      subtitle = 'Analysis published to Scope of Work — $countLabel items';
      accentColor = AppColors.success;
      icon = Icons.verified_outlined;
    } else if (isDone) {
      subtitle = '$countLabel items analysed — tap to review & publish';
      accentColor = AppColors.warning;
      icon = Icons.pending_actions_outlined;
    } else {
      subtitle = bimCount == null || bimCount == 0
          ? 'Tap to run AI analysis on your BIM equipment list'
          : 'Tap to run AI analysis on $countLabel BIM equipment items';
      accentColor = AppColors.primary;
      icon = Icons.auto_awesome_outlined;
    }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AiPmAnalysisScreen(
                  facilityId: widget.facilityId,
                  currentRole: _currentRole,
                  organization: _organization,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: isRunning
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: accentColor),
                        )
                      : Icon(icon, color: accentColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('AI Equipment Analysis',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontSize: 13.5)),
                    Text(subtitle,
                        style: GoogleFonts.poppins(
                            fontSize: 11.5, color: AppColors.textSecondary)),
                  ]),
                ),
                Icon(Icons.chevron_right_rounded, color: accentColor, size: 18),
              ]),
            ),
          ),
        );
  }

  // ── Task list (per category) ───────────────────────────────────────────────

  Widget _buildTasksList(List<PreventiveMaintenanceTask> allTasks) {
    final tasks = allTasks
        .where((t) => t.category == _selectedCategory)
        .toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(2100))
          .compareTo(b.dueDate ?? DateTime(2100)));

    final catColor = _categoryColor(_selectedCategory ?? '');
    final catIcon = _categoryIcon(_selectedCategory ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Category header strip ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: catColor.withValues(alpha: 0.08),
            border: Border(bottom: BorderSide(color: catColor.withValues(alpha: 0.2))),
          ),
          child: Row(children: [
            IconButton(
              onPressed: () => setState(() => _selectedCategory = null),
              icon: Icon(Icons.arrow_back_rounded, color: catColor),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32),
            ),
            const SizedBox(width: 6),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(catIcon, size: 18, color: catColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_selectedCategory ?? '',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('${tasks.length} task${tasks.length == 1 ? '' : 's'}',
                    style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
              ]),
            ),
          ]),
        ),
        Expanded(
          child: tasks.isEmpty
              ? _emptyState(
                  icon: Icons.assignment_outlined,
                  title: 'No tasks in this category',
                  subtitle: '')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) => _taskCard(tasks[index]),
                ),
        ),
      ],
    );
  }

  Widget _taskCard(PreventiveMaintenanceTask task) {
    final overdue = PmSchedulingService.isOverdue(
        dueDate: task.dueDate,
        isCompleted: task.status == PmTaskStatus.completed);
    final displayStatus = overdue ? PmTaskStatus.overdue : task.status;
    final catColor = _categoryColor(task.category);

    // Traffic-light due date color.
    Color dueDateColor = AppColors.textSecondary;
    String dueDateLabel = '';
    if (task.dueDate != null) {
      final now = DateTime.now();
      final diff = task.dueDate!.difference(now).inDays;
      dueDateLabel = DateFormat('d MMM yyyy').format(task.dueDate!);
      if (overdue) {
        dueDateColor = AppColors.error;
      } else if (diff <= 30) {
        dueDateColor = AppColors.warning;
      } else {
        dueDateColor = AppColors.success;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: overdue
              ? AppColors.error.withValues(alpha: 0.3)
              : AppColors.primary.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar: category accent + status ─────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.md)),
              border: Border(bottom: BorderSide(color: catColor.withValues(alpha: 0.12))),
            ),
            child: Row(children: [
              Icon(_categoryIcon(task.category), size: 13, color: catColor),
              const SizedBox(width: 5),
              Text(task.category,
                  style: GoogleFonts.poppins(
                      fontSize: 10.5, color: catColor, fontWeight: FontWeight.w600)),
              const Spacer(),
              _statusChip(displayStatus),
            ]),
          ),

          // ── Card body ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(task.component,
                        style: GoogleFonts.poppins(
                            fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                  if (_canGenerate) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _showEditTaskSheet(task),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ]),
                const SizedBox(height: 6),
                Text(task.intervention,
                    style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary)),
                const SizedBox(height: 10),

                // ── Meta chips row ──────────────────────────────────────
                Wrap(spacing: 8, runSpacing: 6, children: [
                  _metaChip(Icons.event_repeat_rounded,
                      _freqLabel(task.frequencyMonths), AppColors.primary),
                  if (task.dueDate != null)
                    _metaChip(Icons.calendar_today_rounded,
                        'Due $dueDateLabel', dueDateColor),
                  if (task.equipmentName != null &&
                      task.equipmentName!.isNotEmpty &&
                      task.equipmentName != task.component)
                    _metaChip(Icons.link_rounded, task.equipmentName!,
                        AppColors.textSecondary),
                ]),

                if (task.notes != null && task.notes!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(children: [
                      Icon(Icons.notes_rounded, size: 13, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(task.notes!,
                            style: GoogleFonts.poppins(
                                fontSize: 11.5, color: AppColors.textSecondary)),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showTaskStatusMenu(task),
                    icon: const Icon(Icons.update_rounded, size: 15),
                    label: Text('Update Status',
                        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(PmTaskStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_statusIcon(status), size: 11, color: color),
        const SizedBox(width: 4),
        Text(status.displayName,
            style: GoogleFonts.poppins(
                fontSize: 10.5, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _metaChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label,
              style: GoogleFonts.poppins(fontSize: 11, color: color),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ),
      ]),
    );
  }

  String _freqLabel(int months) {
    if (months == 1) return 'Monthly';
    if (months == 3) return 'Quarterly';
    if (months == 6) return 'Semi-annual';
    if (months == 12) return 'Annual';
    if (months % 12 == 0) return 'Every ${months ~/ 12} yrs';
    return 'Every ${months}mo';
  }

  // ── Task edit sheet ────────────────────────────────────────────────────────

  void _showEditTaskSheet(PreventiveMaintenanceTask task) {
    final interventionCtrl =
        TextEditingController(text: task.intervention);
    final freqCtrl =
        TextEditingController(text: task.frequencyMonths.toString());
    final notesCtrl = TextEditingController(text: task.notes ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(20))),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Edit Task',
                        style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              Text(task.component,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: Colors.grey[600])),
              const SizedBox(height: 16),
              TextField(
                controller: interventionCtrl,
                decoration: InputDecoration(
                    labelText: 'Maintenance intervention',
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.poppins()),
                style: GoogleFonts.poppins(),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: freqCtrl,
                decoration: InputDecoration(
                    labelText: 'Frequency (months)',
                    helperText:
                        'Changing the interval recalculates the next due date',
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.poppins()),
                style: GoogleFonts.poppins(),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.poppins()),
                style: GoogleFonts.poppins(),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    final newFreq =
                        int.tryParse(freqCtrl.text.trim()) ??
                            task.frequencyMonths;
                    final newIntervention =
                        interventionCtrl.text.trim();
                    if (newIntervention.isEmpty) return;

                    final now = DateTime.now();
                    // Recalculate due date if frequency changed.
                    final newDueDate = newFreq != task.frequencyMonths
                        ? PmSchedulingService.nextUpcomingOccurrence(
                            from: now, frequencyMonths: newFreq)
                        : task.dueDate;

                    Navigator.pop(ctx);
                    try {
                      await FirebaseFirestore.instance
                          .collection('facilities')
                          .doc(widget.facilityId)
                          .collection('preventive_maintenance')
                          .doc(task.id)
                          .update({
                        'intervention': newIntervention,
                        'frequencyMonths': newFreq,
                        if (newDueDate != null)
                          'dueDate': Timestamp.fromDate(newDueDate),
                        'notes': notesCtrl.text.trim().isEmpty
                            ? null
                            : notesCtrl.text.trim(),
                        'updatedAt': Timestamp.fromDate(now),
                        // If the due date changed, clear notification flags so
                        // the rescheduled task triggers fresh alerts.
                        if (newFreq != task.frequencyMonths) ...{
                          'notifiedAt': FieldValue.delete(),
                          'alertedAt': FieldValue.delete(),
                        },
                      });
                      if (mounted) _showSnackBar('Task updated');
                    } catch (e) {
                      _logger.e('Failed to update task: $e');
                      if (mounted) _showSnackBar('Update failed: $e');
                    }
                  },
                  child: Text('Save changes',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Status update ─────────────────────────────────────────────────────────

  Future<void> _updateTaskStatus(
      PreventiveMaintenanceTask task, PmTaskStatus newStatus) async {
    try {
      final notes = await _showNotesDialog(newStatus);
      if (notes == null) return;

      final now = DateTime.now();
      final ref = FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('preventive_maintenance')
          .doc(task.id);

      if (newStatus == PmTaskStatus.completed) {
        final user = FirebaseAuth.instance.currentUser;

        // Write status = 'completed' so the Cloud Function onPmTaskStatusChanged
        // picks it up and handles: history write, next-due recalculation, reset to
        // pending, and the pm_completed notification to the client.
        await ref.update({
          'status': PmTaskStatus.completed.value,
          'completedAt': Timestamp.fromDate(now),
          'completedBy': user?.uid ?? '',
          'completionNotes': notes.isEmpty ? null : notes,
          'updatedAt': Timestamp.fromDate(now),
        });
        _showSnackBar('Task marked complete — next due date being calculated...');
      } else {
        await ref.update({
          'status': newStatus.value,
          'notes': notes.isEmpty ? null : notes,
          'updatedAt': Timestamp.fromDate(now),
        });
        _showSnackBar('Task status updated to ${newStatus.displayName}');
      }
    } catch (e) {
      _logger.e('Error updating task status: $e');
      _showSnackBar('Error updating task status: $e');
    }
  }

  Future<String?> _showNotesDialog(PmTaskStatus status) async {
    final notesController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Task Status', style: GoogleFonts.poppins()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Marking task as ${status.displayName}',
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: InputDecoration(
                  labelText: 'Notes (optional)',
                  border: const OutlineInputBorder(),
                  labelStyle: GoogleFonts.poppins(),
                  hintText: 'Add any relevant notes...'),
              style: GoogleFonts.poppins(),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text('Cancel', style: GoogleFonts.poppins())),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, notesController.text.trim()),
            style: ElevatedButton.styleFrom(
                backgroundColor: _statusColor(status),
                foregroundColor: Colors.white),
            child: Text('Update', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showTaskStatusMenu(PreventiveMaintenanceTask task) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update Task Status',
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(task.component,
                style:
                    GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 20),
            _statusOption(task, PmTaskStatus.pending),
            _statusOption(task, PmTaskStatus.inProgress),
            _statusOption(task, PmTaskStatus.completed),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: GoogleFonts.poppins())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusOption(
      PreventiveMaintenanceTask task, PmTaskStatus status) {
    final isSelected = task.status == status;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          _updateTaskStatus(task, status);
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? _statusColor(status).withValues(alpha: 0.1)
                : Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: isSelected
                    ? _statusColor(status)
                    : Colors.grey[300]!,
                width: isSelected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(_statusIcon(status),
                  color: _statusColor(status), size: 24),
              const SizedBox(width: 12),
              Text(status.displayName,
                  style: GoogleFonts.poppins(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? _statusColor(status)
                          : Colors.black87)),
              if (isSelected) ...[
                const Spacer(),
                Icon(Icons.check_circle, color: _statusColor(status))
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _statTile(String label, int count, Color color, [bool compact = false]) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: compact ? 7 : 9, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border(top: BorderSide(color: color, width: 2.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$count',
              style: GoogleFonts.poppins(
                fontSize: compact ? 16 : 20,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.poppins(
                fontSize: compact ? 9 : 10,
                color: color.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  IconData _categoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'hvac':
        return Icons.ac_unit_rounded;
      case 'electrical':
        return Icons.bolt_rounded;
      case 'plumbing':
        return Icons.water_drop_rounded;
      case 'mechanical':
        return Icons.settings_rounded;
      case 'safety':
        return Icons.shield_rounded;
      case 'structural':
        return Icons.foundation_rounded;
      case 'furniture/fittings':
        return Icons.chair_rounded;
      case 'it equipment':
        return Icons.computer_rounded;
      case 'fire protection':
        return Icons.local_fire_department_rounded;
      case 'unclassified':
      case 'unknown':
        return Icons.help_outline_rounded;
      default:
        return Icons.build_rounded;
    }
  }

  Color _categoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'electrical':
        return const Color(0xFFF59E0B);
      case 'hvac':
        return const Color(0xFF06B6D4);
      case 'mechanical':
        return const Color(0xFF64748B);
      case 'plumbing':
        return const Color(0xFF3B82F6);
      case 'safety':
        return const Color(0xFFEF4444);
      case 'structural':
        return const Color(0xFF8B5CF6);
      case 'furniture/fittings':
        return const Color(0xFF10B981);
      default:
        return AppColors.primary;
    }
  }

  Widget _emptyState(
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 18, color: Colors.grey[600]),
                textAlign: TextAlign.center),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(subtitle,
                  style: GoogleFonts.poppins(color: Colors.grey[500]),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(PmTaskStatus status) {
    switch (status) {
      case PmTaskStatus.pending:
        return AppColors.textSecondary;
      case PmTaskStatus.due:
        return AppColors.warning;
      case PmTaskStatus.inProgress:
        return AppColors.primary;
      case PmTaskStatus.completed:
        return AppColors.success;
      case PmTaskStatus.overdue:
        return AppColors.error;
    }
  }

  IconData _statusIcon(PmTaskStatus status) {
    switch (status) {
      case PmTaskStatus.pending:
        return Icons.schedule;
      case PmTaskStatus.due:
        return Icons.notifications_active;
      case PmTaskStatus.inProgress:
        return Icons.play_circle;
      case PmTaskStatus.completed:
        return Icons.check_circle;
      case PmTaskStatus.overdue:
        return Icons.warning_rounded;
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message, style: GoogleFonts.poppins())));
    }
  }
}
