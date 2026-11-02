import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _departmentController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _phoneController.dispose();
    _departmentController.dispose();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          _userProfile = data;
          _displayNameController.text = data['displayName'] ?? data['username'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _departmentController.text = data['department'] ?? '';
        });
      }
    } catch (e) {
      _logger.e('Error loading user profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await FirebaseFirestore.instance.collection('Users').doc(user.uid).set({
        'displayName': _displayNameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'department': _departmentController.text.trim(),
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Profile updated', style: GoogleFonts.poppins()),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ));
        _loadUserProfile();
      }
    } catch (e) {
      _logger.e('Error updating profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update: $e', style: GoogleFonts.poppins()),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = _displayNameController.text.trim().isNotEmpty
        ? _displayNameController.text.trim()
        : (user?.email?.split('@').first ?? 'User');
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, size: 20),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('My Profile',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          if (!_isLoading)
            TextButton.icon(
              onPressed: () {
                if (_isEditing) {
                  _updateProfile();
                } else {
                  setState(() => _isEditing = true);
                }
              },
              icon: Icon(_isEditing ? Icons.check_rounded : Icons.edit_rounded,
                  size: 18, color: AppColors.primary),
              label: Text(_isEditing ? 'Save' : 'Edit',
                  style: GoogleFonts.poppins(
                      fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ),
          if (_isEditing)
            TextButton(
              onPressed: () {
                setState(() => _isEditing = false);
                _loadUserProfile();
              },
              child: Text('Cancel',
                  style: GoogleFonts.poppins(fontSize: 13.5, color: AppColors.textSecondary)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Avatar hero
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 6)),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2.5),
                            ),
                            child: Center(
                              child: Text(initial,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(displayName,
                              style: GoogleFonts.plusJakartaSans(
                                  fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text(user?.email ?? '',
                              style: GoogleFonts.poppins(
                                  fontSize: 12.5, color: Colors.white.withValues(alpha: 0.75))),
                          if (_userProfile?['role'] != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              ),
                              child: Text(_userProfile!['role'],
                                  style: GoogleFonts.poppins(
                                      fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Editable fields card
                    _sectionCard(
                      title: 'Profile Details',
                      icon: Icons.person_rounded,
                      color: AppColors.primary,
                      children: [
                        _fieldRow(
                          icon: Icons.badge_rounded,
                          iconColor: AppColors.primary,
                          label: 'Display Name',
                          controller: _displayNameController,
                          editing: _isEditing,
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a display name' : null,
                        ),
                        _divider(),
                        _fieldRow(
                          icon: Icons.phone_rounded,
                          iconColor: const Color(0xFF12B886),
                          label: 'Phone Number',
                          controller: _phoneController,
                          editing: _isEditing,
                          keyboardType: TextInputType.phone,
                        ),
                        _divider(),
                        _fieldRow(
                          icon: Icons.business_center_rounded,
                          iconColor: const Color(0xFF748FFC),
                          label: 'Department',
                          controller: _departmentController,
                          editing: _isEditing,
                        ),
                        _divider(),
                        _readOnlyRow(
                          icon: Icons.email_rounded,
                          iconColor: const Color(0xFFFF922B),
                          label: 'Email Address',
                          value: user?.email ?? '—',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Account stats card
                    _sectionCard(
                      title: 'Account Info',
                      icon: Icons.info_outline_rounded,
                      color: const Color(0xFF339AF0),
                      children: [
                        _statRow(
                          icon: Icons.calendar_today_rounded,
                          iconColor: const Color(0xFF339AF0),
                          label: 'Member Since',
                          value: _fmt(user?.metadata.creationTime),
                        ),
                        _divider(),
                        _statRow(
                          icon: Icons.login_rounded,
                          iconColor: const Color(0xFF12B886),
                          label: 'Last Sign In',
                          value: _fmt(user?.metadata.lastSignInTime),
                        ),
                        _divider(),
                        _statRow(
                          icon: Icons.verified_user_rounded,
                          iconColor: const Color(0xFF9775FA),
                          label: 'Auth Provider',
                          value: user?.providerData.firstOrNull?.providerId == 'google.com'
                              ? 'Google'
                              : 'Email / Password',
                        ),
                      ],
                    ),

                    if (_isEditing) ...[
                      const SizedBox(height: 24),
                      AppGradientButton(
                        label: 'Save Changes',
                        icon: Icons.check_rounded,
                        isLoading: _isSaving,
                        onPressed: _isSaving ? null : _updateProfile,
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(width: 10),
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ...children,
        ],
      ),
    );
  }

  Widget _fieldRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required TextEditingController controller,
    required bool editing,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: editing
                ? TextFormField(
                    controller: controller,
                    keyboardType: keyboardType,
                    validator: validator,
                    style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: label,
                      labelStyle: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textSecondary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: const UnderlineInputBorder(),
                      focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
                      const SizedBox(height: 3),
                      Text(
                        controller.text.isEmpty ? 'Not set' : controller.text,
                        style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: controller.text.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.poppins(fontSize: 11.5, color: AppColors.textSecondary)),
                const SizedBox(height: 3),
                Text(value,
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFE9ECEF),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text('Read-only',
                style: GoogleFonts.poppins(fontSize: 10.5, color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _statRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
          ),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _divider() =>
      const Divider(height: 1, indent: 65, endIndent: 0, color: Color(0xFFF3F4F6));

  String _fmt(DateTime? dt) {
    if (dt == null) return '—';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
