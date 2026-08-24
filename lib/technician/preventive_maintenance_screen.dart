import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:cmms/models/preventive_maintenance_task.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/services/pm_scheduling_service.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';

/// Facility-scoped preventive maintenance: reads directly from
/// facilities/{facilityId}/preventive_maintenance (populated by the legacy-data backfill,
/// manual "Schedule Activity" entries from Scope of Work, and — once later phases land —
/// OCR-derived rows), grouped by category with real status/notes/completion actions. Replaces
/// the previous global, unfiltered task browser that also permanently locked status updates
/// for any task without a manually-configured notification.
class PreventiveMaintenanceScreen extends StatefulWidget {
  final String facilityId;

  const PreventiveMaintenanceScreen({super.key, required this.facilityId});

  @override
  State<PreventiveMaintenanceScreen> createState() => _PreventiveMaintenanceScreenState();
}

class _PreventiveMaintenanceScreenState extends State<PreventiveMaintenanceScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();

  String? _selectedCategory;
  String _currentRole = 'User';
  String _organization = '-';

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _tasksStream;

  @override
  void initState() {
    super.initState();
    _logger.i('PreventiveMaintenanceScreen initialized: facilityId=${widget.facilityId}');
    _tasksStream = FirebaseFirestore.instance
        .collection('facilities')
        .doc(widget.facilityId)
        .collection('preventive_maintenance')
        .snapshots();
    _notificationService.initialize();
    _getCurrentUserRole();
  }

  Future<void> _getCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final adminDoc = await FirebaseFirestore.instance.collection('Admins').doc(user.uid).get();
      final developerDoc = await FirebaseFirestore.instance.collection('Developers').doc(user.uid).get();
      final technicianDoc = await FirebaseFirestore.instance.collection('Technicians').doc(user.uid).get();
      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();

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
        newRole = (userData != null && userData['role'] == 'Technician') ? 'Technician' : 'User';
      }

      if (mounted) {
        setState(() {
          _currentRole = newRole;
          _organization = newOrg;
        });
      }
    } catch (e) {
      _logger.e('Error getting user role: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveScreenWrapper(
      title: 'Preventive Maintenance',
      facilityId: widget.facilityId,
      currentRole: _currentRole,
      organization: _organization,
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.assignment, color: Colors.blueGrey[700], size: 28),
              const SizedBox(width: 12),
              Text(
                'Preventive Maintenance',
                style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blueGrey[800]),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _tasksStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                _logger.e('Error loading preventive maintenance tasks: ${snapshot.error}');
                return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins()));
              }

              final tasks = (snapshot.data?.docs ?? [])
                  .map((doc) => PreventiveMaintenanceTask.fromFirestore(doc, widget.facilityId))
                  .toList();

              return _selectedCategory == null ? _buildCategorySelection(tasks) : _buildTasksList(tasks);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySelection(List<PreventiveMaintenanceTask> tasks) {
    if (tasks.isEmpty) {
      return _emptyState(
        icon: Icons.category_outlined,
        title: 'No preventive maintenance tasks yet',
        subtitle: 'Upload a scope of work document or schedule an activity to get started',
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
          Text('Select Category', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey[800])),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                final categoryTasks = byCategory[category]!;
                final overdueCount = categoryTasks.where((t) => PmSchedulingService.isOverdue(dueDate: t.dueDate, isCompleted: t.status == PmTaskStatus.completed)).length;
                final completedCount = categoryTasks.where((t) => t.status == PmTaskStatus.completed).length;
                final inProgressCount = categoryTasks.where((t) => t.status == PmTaskStatus.inProgress).length;
                final pendingCount = categoryTasks.length - completedCount - inProgressCount;

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 3,
                  child: InkWell(
                    onTap: () => setState(() => _selectedCategory = category),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(category, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                              ),
                              Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _countChip('Total', categoryTasks.length, Colors.blueGrey),
                              _countChip('Pending', pendingCount, Colors.grey),
                              _countChip('In Progress', inProgressCount, Colors.indigo),
                              _countChip('Completed', completedCount, Colors.green),
                              if (overdueCount > 0) _countChip('Overdue', overdueCount, Colors.red),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList(List<PreventiveMaintenanceTask> allTasks) {
    final tasks = allTasks.where((t) => t.category == _selectedCategory).toList()
      ..sort((a, b) => (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100)));

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(onPressed: () => setState(() => _selectedCategory = null), icon: const Icon(Icons.arrow_back)),
              Expanded(
                child: Text('$_selectedCategory Tasks', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blueGrey[800])),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: tasks.isEmpty
                ? _emptyState(icon: Icons.assignment_outlined, title: 'No tasks in this category', subtitle: '')
                : ListView.builder(
                    itemCount: tasks.length,
                    itemBuilder: (context, index) => _taskCard(tasks[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(PreventiveMaintenanceTask task) {
    final overdue = PmSchedulingService.isOverdue(dueDate: task.dueDate, isCompleted: task.status == PmTaskStatus.completed);
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
                  child: Text(task.component, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _statusColor(displayStatus), borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    displayStatus.displayName,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.intervention, style: GoogleFonts.poppins(color: Colors.grey[700])),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.event_repeat, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('Every ${task.frequencyMonths} mo', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                if (task.dueDate != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text('Due: ${DateFormat.yMMMd().format(task.dueDate!)}', style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                ],
              ],
            ),
            if (task.notes != null && task.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Expanded(child: Text(task.notes!, style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[700]))),
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
                label: Text('Update Status', style: GoogleFonts.poppins(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateTaskStatus(PreventiveMaintenanceTask task, PmTaskStatus newStatus) async {
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
        // Roll the task forward to its next cycle instead of leaving it permanently
        // "Completed" — that's how a *recurring* maintenance task should behave.
        final nextDueDate = PmSchedulingService.computeDueDate(from: now, frequencyMonths: task.frequencyMonths);
        await ref.update({
          'status': PmTaskStatus.pending.value,
          'lastCompletedAt': Timestamp.fromDate(now),
          'dueDate': Timestamp.fromDate(nextDueDate),
          'notes': notes.isEmpty ? null : notes,
          'updatedAt': Timestamp.fromDate(now),
        });
        _showSnackBar('Marked completed — next due ${DateFormat.yMMMd().format(nextDueDate)}');
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
            Text('Marking task as ${status.displayName}', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: InputDecoration(labelText: 'Notes (optional)', border: const OutlineInputBorder(), labelStyle: GoogleFonts.poppins(), hintText: 'Add any relevant notes...'),
              style: GoogleFonts.poppins(),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, null), child: Text('Cancel', style: GoogleFonts.poppins())),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, notesController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: _statusColor(status), foregroundColor: Colors.white),
            child: Text('Update', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showTaskStatusMenu(PreventiveMaintenanceTask task) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update Task Status', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(task.component, style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600])),
            const SizedBox(height: 20),
            _statusOption(task, PmTaskStatus.pending),
            _statusOption(task, PmTaskStatus.inProgress),
            _statusOption(task, PmTaskStatus.completed),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel', style: GoogleFonts.poppins())),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusOption(PreventiveMaintenanceTask task, PmTaskStatus status) {
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
            color: isSelected ? _statusColor(status).withValues(alpha: 0.1) : Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? _statusColor(status) : Colors.grey[300]!, width: isSelected ? 2 : 1),
          ),
          child: Row(
            children: [
              Icon(_statusIcon(status), color: _statusColor(status), size: 24),
              const SizedBox(width: 12),
              Text(status.displayName, style: GoogleFonts.poppins(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? _statusColor(status) : Colors.black87)),
              if (isSelected) ...[const Spacer(), Icon(Icons.check_circle, color: _statusColor(status))],
            ],
          ),
        ),
      ),
    );
  }

  Widget _countChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text('$label: $count', style: GoogleFonts.poppins(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  Widget _emptyState({required IconData icon, required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title, style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey[600]), textAlign: TextAlign.center),
            if (subtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(subtitle, style: GoogleFonts.poppins(color: Colors.grey[500]), textAlign: TextAlign.center),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: GoogleFonts.poppins())));
    }
  }
}
