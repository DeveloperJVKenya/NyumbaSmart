import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/providers/notification_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

/// Authors a facility-scoped custom notification. On save, the `onCustomNotificationCreated`
/// Cloud Function trigger fans it out to every JV Almacis user's digest and sends FCM
/// immediately — custom notifications are a deliberate, human-authored message, so unlike due/
/// alert digests they deliver right away rather than waiting for the next hourly run. Once sent,
/// the facility notification record is immutable (see firestore.rules), so there's no "edit"
/// flow — only create.
class AddCustomNotificationScreen extends ConsumerStatefulWidget {
  const AddCustomNotificationScreen({super.key});

  @override
  ConsumerState<AddCustomNotificationScreen> createState() => _AddCustomNotificationScreenState();
}

class _AddCustomNotificationScreenState extends ConsumerState<AddCustomNotificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  String? _facilityId;
  String _priority = 'normal';
  bool _isSending = false;

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('New Notification', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
          return SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _facilityPicker(),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _titleController,
                    label: 'Title',
                    icon: Icons.title_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _bodyController,
                    maxLines: 4,
                    style: GoogleFonts.poppins(color: AppColors.textPrimary),
                    decoration: const InputDecoration(labelText: 'Message', prefixIcon: Icon(Icons.notes_rounded, color: AppColors.primary)),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Message is required' : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _prioritySelector(),
                  const SizedBox(height: AppSpacing.lg),
                  AppGradientButton(
                    label: _isSending ? 'Sending...' : 'Send Notification',
                    icon: Icons.send_rounded,
                    isLoading: _isSending,
                    onPressed: _isSending ? null : _submit,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _facilityPicker() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('Facilities').snapshots(),
      builder: (context, snapshot) {
        final facilities = snapshot.data?.docs ?? [];
        return DropdownButtonFormField<String>(
          initialValue: _facilityId,
          decoration: const InputDecoration(labelText: 'Facility', prefixIcon: Icon(Icons.apartment_rounded, color: AppColors.primary)),
          items: facilities
              .map((doc) => DropdownMenuItem(value: doc.id, child: Text(doc.data()['name'] ?? doc.id, style: GoogleFonts.poppins())))
              .toList(),
          onChanged: (value) => setState(() => _facilityId = value),
          validator: (v) => v == null ? 'Select a facility' : null,
        );
      },
    );
  }

  Widget _prioritySelector() {
    return Row(
      children: [
        Text('Priority', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(width: 16),
        ChoiceChip(
          label: Text('Normal', style: GoogleFonts.poppins(fontSize: 12.5, color: _priority == 'normal' ? Colors.white : AppColors.textPrimary)),
          selected: _priority == 'normal',
          onSelected: (_) => setState(() => _priority = 'normal'),
          selectedColor: AppColors.primary,
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: Text('Urgent', style: GoogleFonts.poppins(fontSize: 12.5, color: _priority == 'urgent' ? Colors.white : AppColors.textPrimary)),
          selected: _priority == 'urgent',
          onSelected: (_) => setState(() => _priority = 'urgent'),
          selectedColor: AppColors.error,
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isSending = true);
    try {
      await ref.read(notificationServiceProvider).createCustomNotification(
            facilityId: _facilityId!,
            title: _titleController.text.trim(),
            body: _bodyController.text.trim(),
            priority: _priority,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Notification sent', style: GoogleFonts.poppins()), backgroundColor: AppColors.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending notification: $e', style: GoogleFonts.poppins()), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}
