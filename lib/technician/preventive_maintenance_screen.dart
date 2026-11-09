import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/services/pm_generation_service.dart';
import 'package:cmms/services/pm_scheduling_service.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Facility-scoped preventive maintenance.  Tasks are grouped by category,
/// generated automatically from BIM-linked equipment, and can be manually
/// edited or added.  Unknown equipment types go to a review queue so the
/// facility manager can decide whether to include them.
class PreventiveMaintenanceScreen extends StatefulWidget {
  final String facilityId;

  const PreventiveMaintenanceScreen({super.key, required this.facilityId});

  @override
  State<PreventiveMaintenanceScreen> createState() =>
      _PreventiveMaintenanceScreenState();
}

class _PreventiveMaintenanceScreenState
    extends State<PreventiveMaintenanceScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();

  String? _selectedCategory;
  String _currentRole = 'User';
  String _organization = '-';
  bool _generating = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _tasksStream;
  late final Stream<List<PmReviewItem>> _reviewStream;

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
    _reviewStream = PmGenerationService.reviewQueueStream(widget.facilityId);
    _notificationService.initialize();
    _getCurrentUserRole();
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final adminDoc = await FirebaseFirestore.instance
          .collection('Admins')
          .doc(user.uid)
          .get();
      final developerDoc = await FirebaseFirestore.instance
          .collection('Developers')
          .doc(user.uid)
          .get();
      final technicianDoc = await FirebaseFirestore.instance
          .collection('Technicians')
          .doc(user.uid)
          .get();
      final userDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(user.uid)
          .get();

      String newRole = 'User';
      String newOrg = '-';

      if (adminDoc.exists) {
        newRole = 'Admin';
        newOrg = adminDoc.data()?['organization'] ?? '-';
      } else if (developerDoc.exists) {
        newRole = 'Developer';
        newOrg = 'JV Almacis';
      } else if (technicianDoc.exists) {
        newRole = 'Technician';
        newOrg = technicianDoc.data()?['organization'] ?? '-';
      } else if (userDoc.exists) {
        final userData = userDoc.data();
        newRole = (userData != null && userData['role'] == 'Technician')
            ? 'Technician'
            : 'User';
      }

      if (mounted) setState(() { _currentRole = newRole; _organization = newOrg; });
    } catch (e) {
      _logger.e('Error getting user role: $e');
    }
  }

  bool get _canGenerate =>
      _currentRole == 'Admin' ||
      _currentRole == 'Developer' ||
      _currentRole == 'Technician';

  Future<void> _generateFromBim() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _generating = true);
    try {
      final result = await PmGenerationService.generate(
        facilityId: widget.facilityId,
        userId: user.uid,
      );
      if (mounted) {
        _showSnackBar(
          result.created > 0 || result.queued > 0
              ? 'Created ${result.created} tasks. '
                '${result.queued > 0 ? '${result.queued} items need review.' : ''}'
              : result.skipped > 0
                  ? 'All equipment already scheduled (${result.skipped} items).'
                  : 'No BIM-linked equipment found.',
        );
      }
    } catch (e) {
      _logger.e('PM generation failed: $e');
      if (mounted) _showSnackBar('Generation failed: $e');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Preventive Maintenance',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      actions: _canGenerate
          ? [
              _generating
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.auto_awesome_outlined),
                      tooltip: 'Generate from BIM equipment',
                      onPressed: _generateFromBim,
                    ),
            ]
          : null,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return StreamBuilder<List<PmReviewItem>>(
      stream: _reviewStream,
      builder: (context, reviewSnap) {
        final reviewItems = reviewSnap.data ?? [];
        return Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _tasksStream,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    _logger.e(
                        'Error loading PM tasks: ${snapshot.error}');
                    return Center(
                        child: Text('Error: ${snapshot.error}',
                            style: GoogleFonts.poppins()));
                  }
                  final tasks = (snapshot.data?.docs ?? [])
                      .map((doc) => PreventiveMaintenanceTask.fromFirestore(
                          doc, widget.facilityId))
                      .toList();

                  return _selectedCategory == null
                      ? _buildCategorySelection(tasks, reviewItems)
                      : _buildTasksList(tasks);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Category overview ──────────────────────────────────────────────────────

  Widget _buildCategorySelection(
      List<PreventiveMaintenanceTask> tasks,
      List<PmReviewItem> reviewItems) {
    if (tasks.isEmpty && reviewItems.isEmpty) {
      return _emptyState(
        icon: Icons.auto_awesome_outlined,
        title: 'No preventive maintenance tasks yet',
        subtitle: _canGenerate
            ? 'Tap the ✦ icon in the top bar to generate tasks from installed BIM equipment.'
            : 'Ask your facility administrator to generate PM tasks from the installed equipment.',
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
          Text('Select Category',
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey[800])),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                // ── Review queue banner ──────────────────────────────────
                if (reviewItems.isNotEmpty)
                  _reviewBanner(reviewItems),
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
                    elevation: 3,
                    child: InkWell(
                      onTap: () =>
                          setState(() => _selectedCategory = category),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(category,
                                      style: GoogleFonts.poppins(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold)),
                                ),
                                Icon(Icons.arrow_forward_ios,
                                    color: Colors.grey[400], size: 16),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _countChip('Total', ct.length, Colors.blueGrey),
                                _countChip('Pending', pendingCount, Colors.grey),
                                _countChip('In Progress', inProgressCount,
                                    Colors.indigo),
                                _countChip(
                                    'Completed', completedCount, Colors.green),
                                if (overdueCount > 0)
                                  _countChip('Overdue', overdueCount, Colors.red),
                              ],
                            ),
                          ],
                        ),
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

  Widget _reviewBanner(List<PmReviewItem> items) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.amber[50],
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.amber[300]!)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showReviewQueue(items),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.pending_actions_rounded,
                  color: Colors.amber[800], size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${items.length} equipment item${items.length == 1 ? '' : 's'} need review',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold,
                            color: Colors.amber[900])),
                    Text(
                        'These equipment types have no default PM template. '
                        'Tap to accept or dismiss each one.',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: Colors.amber[800])),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.amber[700]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Review queue sheet ────────────────────────────────────────────────────

  void _showReviewQueue(List<PmReviewItem> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.pending_actions_rounded,
                        color: Colors.amber[700]),
                    const SizedBox(width: 10),
                    Text('Equipment Needing Review',
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Text(
                'These items were imported from BIM but have no default '
                'maintenance template. Accept to create a custom schedule or '
                'dismiss to exclude them.',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (_, i) => _reviewItemTile(items[i], ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _reviewItemTile(PmReviewItem item, BuildContext sheetCtx) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.equipmentName,
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Row(children: [
              _typeChip(item.equipmentType),
              const SizedBox(width: 6),
              _typeChip(item.equipmentCategory),
            ]),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 16),
                    label: Text('Dismiss',
                        style: GoogleFonts.poppins(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red[700],
                        side: BorderSide(color: Colors.red[200]!)),
                    onPressed: () async {
                      await PmGenerationService.dismissReviewItem(
                          facilityId: widget.facilityId,
                          itemId: item.id);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 16),
                    label: Text('Accept',
                        style: GoogleFonts.poppins(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey[700],
                        foregroundColor: Colors.white),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      _showAcceptReviewItemSheet(item);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAcceptReviewItemSheet(PmReviewItem item) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final categoryCtrl = TextEditingController(text: item.equipmentCategory);
    final interventionCtrl = TextEditingController();
    final freqCtrl = TextEditingController(text: '12');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
              Text('Create PM task for',
                  style: GoogleFonts.poppins(
                      fontSize: 16, color: Colors.grey[600])),
              Text(item.equipmentName,
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: categoryCtrl,
                decoration: InputDecoration(
                    labelText: 'Category',
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.poppins()),
                style: GoogleFonts.poppins(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: interventionCtrl,
                decoration: InputDecoration(
                    labelText: 'Maintenance intervention',
                    hintText: 'e.g. Inspect, clean and test',
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
                    border: const OutlineInputBorder(),
                    labelStyle: GoogleFonts.poppins()),
                style: GoogleFonts.poppins(),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: () async {
                    final freq = int.tryParse(freqCtrl.text.trim()) ?? 12;
                    final intervention = interventionCtrl.text.trim();
                    if (intervention.isEmpty) return;
                    Navigator.pop(ctx);
                    await PmGenerationService.acceptReviewItem(
                      facilityId: widget.facilityId,
                      userId: user.uid,
                      item: item,
                      category: categoryCtrl.text.trim().isEmpty
                          ? item.equipmentCategory
                          : categoryCtrl.text.trim(),
                      intervention: intervention,
                      frequencyMonths: freq,
                    );
                    if (mounted) {
                      _showSnackBar('PM task created for ${item.equipmentName}');
                    }
                  },
                  child: Text('Create task',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
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

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                  onPressed: () =>
                      setState(() => _selectedCategory = null),
                  icon: const Icon(Icons.arrow_back)),
              Expanded(
                child: Text('$_selectedCategory Tasks',
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueGrey[800])),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: tasks.isEmpty
                ? _emptyState(
                    icon: Icons.assignment_outlined,
                    title: 'No tasks in this category',
                    subtitle: '')
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) =>
                        _taskCard(tasks[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(PreventiveMaintenanceTask task) {
    final overdue = PmSchedulingService.isOverdue(
        dueDate: task.dueDate,
        isCompleted: task.status == PmTaskStatus.completed);
    final displayStatus = overdue ? PmTaskStatus.overdue : task.status;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(task.component,
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                // Edit button (Admin / Developer / Technician only)
                if (_canGenerate)
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 18, color: Colors.blueGrey[400]),
                    tooltip: 'Edit task',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showEditTaskSheet(task),
                  ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: _statusColor(displayStatus),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    displayStatus.displayName,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.intervention,
                style: GoogleFonts.poppins(color: Colors.grey[700])),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.event_repeat, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('Every ${task.frequencyMonths} mo',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey[600])),
                if (task.dueDate != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('Due: ${DateFormat.yMMMd().format(task.dueDate!)}',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: Colors.grey[600])),
                ],
              ],
            ),
            if (task.equipmentName != null &&
                task.equipmentName!.isNotEmpty &&
                task.equipmentName != task.component) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.link, size: 14, color: Colors.blueGrey[300]),
                const SizedBox(width: 4),
                Text(task.equipmentName!,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: Colors.blueGrey[400])),
              ]),
            ],
            if (task.notes != null && task.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(task.notes!,
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: Colors.grey[700]))),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showTaskStatusMenu(task),
                icon: const Icon(Icons.edit, size: 16),
                label: Text('Update Status',
                    style: GoogleFonts.poppins(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
      ),
    );
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
                      backgroundColor: Colors.blueGrey[700],
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
        final nextDueDate = PmSchedulingService.computeDueDate(
            from: now, frequencyMonths: task.frequencyMonths);
        await ref.update({
          'status': PmTaskStatus.pending.value,
          'lastCompletedAt': Timestamp.fromDate(now),
          'dueDate': Timestamp.fromDate(nextDueDate),
          'notes': notes.isEmpty ? null : notes,
          'updatedAt': Timestamp.fromDate(now),
          // Clear notification flags so the new cycle triggers fresh alerts.
          'notifiedAt': FieldValue.delete(),
          'alertedAt': FieldValue.delete(),
        });
        _showSnackBar(
            'Marked completed — next due ${DateFormat.yMMMd().format(nextDueDate)}');
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

  Widget _countChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text('$label: $count',
          style: GoogleFonts.poppins(
              color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _typeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: Colors.blueGrey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blueGrey[200]!)),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 11, color: Colors.blueGrey[700])),
    );
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
        return Colors.blueGrey;
      case PmTaskStatus.due:
        return Colors.orange;
      case PmTaskStatus.inProgress:
        return Colors.indigo;
      case PmTaskStatus.completed:
        return Colors.green;
      case PmTaskStatus.overdue:
        return Colors.red;
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
