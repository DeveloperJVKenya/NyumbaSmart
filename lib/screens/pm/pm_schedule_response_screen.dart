import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cmms/models/pm_schedule_response.dart';
import 'package:cmms/theme/app_theme.dart';

/// Opened from a client advance-notification deep-link.
/// Shows the equipment name + planned maintenance date and lets the client
/// Accept (keep the date) or Reschedule (pick a new date).
/// Writes a [PmScheduleResponse] document, which the Cloud Function
/// `onPmScheduleResponseCreated` picks up to notify the admin/technician.
class PmScheduleResponseScreen extends StatefulWidget {
  final String facilityId;
  final String taskId;
  final String equipmentName;
  final DateTime plannedDate;

  const PmScheduleResponseScreen({
    super.key,
    required this.facilityId,
    required this.taskId,
    required this.equipmentName,
    required this.plannedDate,
  });

  @override
  State<PmScheduleResponseScreen> createState() => _PmScheduleResponseScreenState();
}

class _PmScheduleResponseScreenState extends State<PmScheduleResponseScreen> {
  bool _submitting = false;
  bool _submitted = false;
  PmClientAction? _submittedAction;

  Future<void> _respond(PmClientAction action, {DateTime? newDate}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final response = PmScheduleResponse(
        id: '',
        facilityId: widget.facilityId,
        clientUid: user.uid,
        taskId: widget.taskId,
        equipmentName: widget.equipmentName,
        plannedDate: widget.plannedDate,
        clientAction: action,
        newDate: newDate,
        respondedAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('pmScheduleResponses')
          .doc(widget.taskId)
          .set(response.toMap());

      if (mounted) {
        setState(() {
          _submitting = false;
          _submitted = true;
          _submittedAction = action;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit response: $e')),
        );
      }
    }
  }

  Future<void> _pickRescheduleDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.plannedDate.isAfter(now) ? widget.plannedDate : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked != null && mounted) {
      await _respond(PmClientAction.rescheduled, newDate: picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Maintenance Notification',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 15)),
        backgroundColor: AppColors.card,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _submitted ? _resultView() : _responseView(),
        ),
      ),
    );
  }

  Widget _responseView() {
    final dateStr = DateFormat('EEEE, d MMMM yyyy').format(widget.plannedDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 24, offset: const Offset(0, 12)),
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
                child: Icon(Icons.build_outlined, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Scheduled Maintenance',
                      style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
                  Text(widget.equipmentName,
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
            const SizedBox(height: 20),
            Divider(height: 1, color: AppColors.primary.withValues(alpha: 0.08)),
            const SizedBox(height: 16),
            Row(children: [
              Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Planned date', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
            ]),
            const SizedBox(height: 4),
            Text(dateStr,
                style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 20),
            Text(
              'Our maintenance team is scheduled to service this equipment on the date above. '
              'Please let us know if this date works for you, or propose a new date.',
              style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
          ]),
        ),
        const Spacer(),
        // ── Action buttons ─────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : () => _respond(PmClientAction.accepted),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            icon: _submitting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle_outline, size: 20),
            label: Text('Accept this date', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _submitting ? null : _pickRescheduleDate,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: BorderSide(color: AppColors.warning.withValues(alpha: 0.6)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            icon: const Icon(Icons.edit_calendar_outlined, size: 20),
            label: Text('Propose new date', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _resultView() {
    final accepted = _submittedAction == PmClientAction.accepted;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: (accepted ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            accepted ? Icons.check_circle_rounded : Icons.event_available_rounded,
            size: 56,
            color: accepted ? AppColors.success : AppColors.warning,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          accepted ? 'Date Accepted' : 'Reschedule Requested',
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          accepted
              ? 'You have confirmed the maintenance date. We will be in touch before the visit.'
              : 'Your preferred date has been sent to the maintenance team. They will confirm shortly.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 32),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: Text('Done', style: GoogleFonts.poppins()),
        ),
      ]),
    );
  }
}
