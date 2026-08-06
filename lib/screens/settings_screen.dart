import 'package:cmms/notifications/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cmms/screens/profile_screen.dart';
import 'package:cmms/screens/about_screen.dart';
import 'package:cmms/screens/help_support_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:logger/logger.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const SettingsScreen({super.key, required this.facilityId});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();

  bool _notificationsEnabled = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  String _selectedTheme = 'System';
  String _selectedLanguage = 'English';
  bool _isLoadingNotifications = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final enabled = await _notificationService.areNotificationsEnabled();
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _isLoadingNotifications = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingNotifications = false;
        });
      }
    }
  }

  Future<void> _updateNotificationSettings(bool enabled) async {
    try {
      await _notificationService.setNotificationsEnabled(enabled);
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled ? 'Notifications enabled successfully' : 'Notifications disabled successfully',
              style: GoogleFonts.poppins(),
            ),
            backgroundColor: enabled ? AppColors.success : AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating notification settings: $e', style: GoogleFonts.poppins()),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Role/organization now come from the same provider the rest of the app
    // uses, instead of this screen's own copy of the
    // Admins/Developers/Technicians/Users lookup cascade.
    final roleInfo = ref.watch(currentUserRoleProvider).valueOrNull;

    return ResponsiveScreenWrapper(
      title: 'Settings',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? 'User',
      organization: roleInfo?.organization ?? '-',
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _sectionCard(
              title: 'User Profile',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.surfaceAlt,
                    child: Icon(Icons.person_rounded, color: AppColors.primary),
                  ),
                  title: Text(user?.email ?? 'User', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                  subtitle: Text('Tap to manage your profile', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionCard(
              title: 'Notifications',
              children: [
                if (_isLoadingNotifications)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  )
                else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Enable Notifications', style: GoogleFonts.poppins()),
                    subtitle: Text(
                      _notificationsEnabled ? 'Receive maintenance reminders' : 'Notifications are disabled',
                      style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    value: _notificationsEnabled,
                    onChanged: _updateNotificationSettings,
                    activeThumbColor: AppColors.primary,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Email Notifications', style: GoogleFonts.poppins()),
                    subtitle: Text('Receive notifications via email', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                    value: _emailNotifications,
                    activeThumbColor: AppColors.primary,
                    onChanged: _notificationsEnabled
                        ? (value) => setState(() => _emailNotifications = value)
                        : null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Push Notifications', style: GoogleFonts.poppins()),
                    subtitle: Text('Receive push notifications on device', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                    value: _pushNotifications,
                    activeThumbColor: AppColors.primary,
                    onChanged: _notificationsEnabled
                        ? (value) => setState(() => _pushNotifications = value)
                        : null,
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionCard(
              title: 'App Preferences',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.palette_rounded, color: AppColors.primary),
                  title: Text('Theme', style: GoogleFonts.poppins()),
                  subtitle: Text(_selectedTheme, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
                  onTap: () => _showThemeDialog(),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language_rounded, color: AppColors.primary),
                  title: Text('Language', style: GoogleFonts.poppins()),
                  subtitle: Text(_selectedLanguage, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
                  onTap: () => _showLanguageDialog(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionCard(
              title: 'Support & Information',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.help_rounded, color: AppColors.primary),
                  title: Text('Help & Support', style: GoogleFonts.poppins()),
                  subtitle: Text('Get help and contact support', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelpSupportScreen()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.info_rounded, color: AppColors.primary),
                  title: Text('About', style: GoogleFonts.poppins()),
                  subtitle: Text('App information and version', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AboutScreen()),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_rounded, color: AppColors.primary),
                  title: Text('Privacy Policy', style: GoogleFonts.poppins()),
                  subtitle: Text('View privacy policy', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.textSecondary),
                  onTap: () => _showPrivacyPolicy(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _sectionCard(
              title: 'Account',
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout_rounded, color: AppColors.error),
                  title: Text('Sign Out', style: GoogleFonts.poppins(color: AppColors.error, fontWeight: FontWeight.w600)),
                  subtitle: Text('Sign out of your account', style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
                  onTap: () => _showSignOutDialog(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Select Theme', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: RadioGroup<String>(
          groupValue: _selectedTheme,
          onChanged: (value) {
            setState(() => _selectedTheme = value!);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['System', 'Light', 'Dark'].map((theme) {
              return RadioListTile<String>(
                title: Text(theme, style: GoogleFonts.poppins()),
                value: theme,
                activeColor: AppColors.primary,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Select Language', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: RadioGroup<String>(
          groupValue: _selectedLanguage,
          onChanged: (value) {
            setState(() => _selectedLanguage = value!);
            Navigator.pop(context);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: ['English', 'Swahili'].map((language) {
              return RadioListTile<String>(
                title: Text(language, style: GoogleFonts.poppins()),
                value: language,
                activeColor: AppColors.primary,
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Privacy Policy', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: SingleChildScrollView(
          child: Text(
            'This CMMS application collects and processes data necessary for maintenance management operations. Your data is securely stored and processed in accordance with applicable data protection regulations.',
            style: GoogleFonts.poppins(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Sign Out', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to sign out?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _performSignOut();
            },
            child: Text('Sign Out', style: GoogleFonts.poppins(color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _performSignOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    } catch (e) {
      _logger.e('Error signing out: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error signing out: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }
}
