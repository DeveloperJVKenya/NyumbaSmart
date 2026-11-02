import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/utils/module_usage_tracker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cmms/screens/profile_screen.dart';
import 'package:cmms/screens/about_screen.dart';
import 'package:cmms/screens/help_support_screen.dart';
import 'package:cmms/widgets/responsive_screen_wrapper.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:logger/logger.dart';

// ── Prefs keys ────────────────────────────────────────────────────────────────
const _kTheme = 'ns_pref_theme';
const _kLanguage = 'ns_pref_language';
const _kDateFormat = 'ns_pref_date_format';
const _kEmailNotif = 'ns_pref_email_notifications';
const _kPushNotif = 'ns_pref_push_notifications';
const _kWOAlerts = 'ns_pref_wo_alerts';

class SettingsScreen extends ConsumerStatefulWidget {
  final String facilityId;

  const SettingsScreen({super.key, required this.facilityId});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();

  // Notification state
  bool _notificationsEnabled = true;
  bool _emailNotifications = true;
  bool _pushNotifications = true;
  bool _workOrderAlerts = true;
  bool _isLoadingNotifications = true;

  // Preferences state
  String _selectedTheme = 'System';
  String _selectedLanguage = 'English';
  String _selectedDateFormat = 'DD/MM/YYYY';

  @override
  void initState() {
    super.initState();
    _loadAllPrefs();
  }

  Future<void> _loadAllPrefs() async {
    try {
      final enabled = await _notificationService.areNotificationsEnabled();
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _notificationsEnabled = enabled;
          _emailNotifications = prefs.getBool(_kEmailNotif) ?? true;
          _pushNotifications = prefs.getBool(_kPushNotif) ?? true;
          _workOrderAlerts = prefs.getBool(_kWOAlerts) ?? true;
          _selectedTheme = prefs.getString(_kTheme) ?? 'System';
          _selectedLanguage = prefs.getString(_kLanguage) ?? 'English';
          _selectedDateFormat = prefs.getString(_kDateFormat) ?? 'DD/MM/YYYY';
          _isLoadingNotifications = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingNotifications = false);
    }
  }

  Future<void> _setNotifications(bool v) async {
    await _notificationService.setNotificationsEnabled(v);
    if (mounted) setState(() => _notificationsEnabled = v);
  }

  Future<void> _setBoolPref(String key, bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, v);
  }

  Future<void> _setStringPref(String key, String v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, v);
  }

  @override
  Widget build(BuildContext context) {
    final roleInfo = ref.watch(currentUserRoleProvider).value;
    return ResponsiveScreenWrapper(
      title: 'Settings',
      facilityId: widget.facilityId,
      currentRole: roleInfo?.roleLabel ?? 'User',
      organization: roleInfo?.organization ?? '-',
      child: _buildBody(roleInfo),
    );
  }

  Widget _buildBody(UserRoleInfo? info) {
    final user = FirebaseAuth.instance.currentUser;
    final role = info?.roleLabel ?? 'User';
    final org = info?.organization ?? '-';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileCard(user, role, org),
          const SizedBox(height: 20),
          _SettingSection(
            icon: Icons.manage_accounts_rounded,
            color: AppColors.primary,
            title: 'Account',
            tiles: [
              _SettingTile(
                icon: Icons.person_rounded,
                iconColor: AppColors.primary,
                title: 'Edit Profile',
                subtitle: user?.displayName ?? user?.email ?? 'Manage your profile',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.lock_reset_rounded,
                iconColor: const Color(0xFF9775FA),
                title: 'Change Password',
                subtitle: 'Send a password reset link to your email',
                onTap: _showPasswordReset,
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.verified_user_rounded,
                iconColor: const Color(0xFF12B886),
                title: 'Account Security',
                subtitle: 'Authentication managed via Firebase',
                trailing: _infoBadge('Secure'),
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingSection(
            icon: Icons.notifications_rounded,
            color: const Color(0xFFFF922B),
            title: 'Notifications',
            tiles: _isLoadingNotifications
                ? [
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  ]
                : [
                    _SwitchTile(
                      icon: Icons.notifications_active_rounded,
                      iconColor: const Color(0xFFFF922B),
                      title: 'Enable Notifications',
                      subtitle: _notificationsEnabled
                          ? 'Receiving maintenance alerts'
                          : 'All notifications disabled',
                      value: _notificationsEnabled,
                      onChanged: _setNotifications,
                      showDivider: true,
                    ),
                    _SwitchTile(
                      icon: Icons.email_rounded,
                      iconColor: const Color(0xFF339AF0),
                      title: 'Email Notifications',
                      subtitle: 'Reports and summaries via email',
                      value: _emailNotifications,
                      enabled: _notificationsEnabled,
                      onChanged: (v) {
                        setState(() => _emailNotifications = v);
                        _setBoolPref(_kEmailNotif, v);
                      },
                      showDivider: true,
                    ),
                    _SwitchTile(
                      icon: Icons.phonelink_ring_rounded,
                      iconColor: const Color(0xFF12B886),
                      title: 'Push Notifications',
                      subtitle: 'Real-time alerts on this device',
                      value: _pushNotifications,
                      enabled: _notificationsEnabled,
                      onChanged: (v) {
                        setState(() => _pushNotifications = v);
                        _setBoolPref(_kPushNotif, v);
                      },
                      showDivider: true,
                    ),
                    _SwitchTile(
                      icon: Icons.work_history_rounded,
                      iconColor: const Color(0xFF4C6EF5),
                      title: 'Work Order Alerts',
                      subtitle: 'Notified on new assignments',
                      value: _workOrderAlerts,
                      enabled: _notificationsEnabled,
                      onChanged: (v) {
                        setState(() => _workOrderAlerts = v);
                        _setBoolPref(_kWOAlerts, v);
                      },
                    ),
                  ],
          ),
          const SizedBox(height: 16),
          _SettingSection(
            icon: Icons.tune_rounded,
            color: const Color(0xFF748FFC),
            title: 'Display & Language',
            tiles: [
              _SettingTile(
                icon: Icons.palette_rounded,
                iconColor: const Color(0xFF748FFC),
                title: 'Theme',
                subtitle: 'Choose your preferred look',
                trailing: _valueBadge(_selectedTheme),
                onTap: () => _showPicker(
                  title: 'App Theme',
                  options: ['System', 'Light', 'Dark'],
                  current: _selectedTheme,
                  onPick: (v) {
                    setState(() => _selectedTheme = v);
                    _setStringPref(_kTheme, v);
                  },
                ),
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.language_rounded,
                iconColor: const Color(0xFF20C997),
                title: 'Language',
                subtitle: 'App display language',
                trailing: _valueBadge(_selectedLanguage),
                onTap: () => _showPicker(
                  title: 'Language',
                  options: ['English', 'Swahili'],
                  current: _selectedLanguage,
                  onPick: (v) {
                    setState(() => _selectedLanguage = v);
                    _setStringPref(_kLanguage, v);
                  },
                ),
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.date_range_rounded,
                iconColor: const Color(0xFFFF6B6B),
                title: 'Date Format',
                subtitle: 'How dates are shown across the app',
                trailing: _valueBadge(_selectedDateFormat),
                onTap: () => _showPicker(
                  title: 'Date Format',
                  options: ['DD/MM/YYYY', 'MM/DD/YYYY', 'YYYY-MM-DD'],
                  current: _selectedDateFormat,
                  onPick: (v) {
                    setState(() => _selectedDateFormat = v);
                    _setStringPref(_kDateFormat, v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingSection(
            icon: Icons.dashboard_customize_rounded,
            color: const Color(0xFFCC5DE8),
            title: 'Quick Access & Data',
            tiles: [
              _SettingTile(
                icon: Icons.restart_alt_rounded,
                iconColor: const Color(0xFFCC5DE8),
                title: 'Reset Quick Access',
                subtitle: 'Clears usage history — restores 4 default modules',
                onTap: _confirmResetQuickAccess,
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.cleaning_services_rounded,
                iconColor: const Color(0xFF94D82D),
                title: 'Clear App Cache',
                subtitle: 'Removes locally cached preferences',
                onTap: _confirmClearCache,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _SettingSection(
            icon: Icons.support_agent_rounded,
            color: const Color(0xFF12B886),
            title: 'Support & Help',
            tiles: [
              _SettingTile(
                icon: Icons.help_rounded,
                iconColor: const Color(0xFF12B886),
                title: 'Help Center',
                subtitle: 'Guides, FAQs and tutorials',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpSupportScreen())),
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.bug_report_rounded,
                iconColor: const Color(0xFFFF922B),
                title: 'Report an Issue',
                subtitle: 'Send feedback or report a bug',
                onTap: _showReportIssue,
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.info_rounded,
                iconColor: AppColors.primary,
                title: 'About NyumbaSmart',
                subtitle: 'Version, changelog and licenses',
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen())),
                showDivider: true,
              ),
              _SettingTile(
                icon: Icons.privacy_tip_rounded,
                iconColor: const Color(0xFF748FFC),
                title: 'Privacy Policy',
                subtitle: 'Data handling and storage practices',
                onTap: _showPrivacyPolicy,
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Sign Out — standalone danger card
          _buildSignOutCard(),
        ],
      ),
    );
  }

  // ── Profile hero card ───────────────────────────────────────────────────────

  Widget _buildProfileCard(User? user, String role, String org) {
    final email = user?.email ?? 'No email';
    final displayName = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!
        : email.split('@').first;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.22),
              blurRadius: 20,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.45), width: 2),
            ),
            child: Center(
              child: Text(
                initial,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: -0.3),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, color: Colors.white.withValues(alpha: 0.75)),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    _heroBadge(role == '-' ? 'Pending' : role),
                    if (org != '-') _heroBadge(org),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Text('Edit',
                  style: GoogleFonts.poppins(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }

  // ── Sign out card ───────────────────────────────────────────────────────────

  Widget _buildSignOutCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
              color: AppColors.error.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: _SettingTile(
        icon: Icons.logout_rounded,
        iconColor: AppColors.error,
        title: 'Sign Out',
        subtitle: 'End your session and return to login',
        isDestructive: true,
        onTap: _showSignOutDialog,
      ),
    );
  }

  // ── Trailing widgets ────────────────────────────────────────────────────────

  Widget _valueBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppColors.primary)),
    );
  }

  Widget _infoBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF12B886).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label,
          style: GoogleFonts.poppins(
              fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF12B886))),
    );
  }

  // ── Dialogs ─────────────────────────────────────────────────────────────────

  void _showPicker({
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onPick,
  }) {
    String selected = current;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Text(title,
              style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700, fontSize: 16)),
          contentPadding: const EdgeInsets.only(top: 8, bottom: 4),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: options.map((opt) {
              return RadioListTile<String>(
                title: Text(opt, style: GoogleFonts.poppins(fontSize: 14)),
                value: opt,
                groupValue: selected,
                activeColor: AppColors.primary,
                onChanged: (v) {
                  setD(() => selected = v!);
                  onPick(v!);
                  Navigator.pop(ctx);
                },
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showPasswordReset() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Reset Password',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text(
          'A password reset link will be sent to:\n\n${user!.email}',
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseAuth.instance
                    .sendPasswordResetEmail(email: user.email!);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Reset link sent to ${user.email}',
                        style: GoogleFonts.poppins()),
                    backgroundColor: AppColors.success,
                  ));
                }
              } catch (e) {
                _logger.e('Password reset error: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error: $e', style: GoogleFonts.poppins()),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: Text('Send Link', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _confirmResetQuickAccess() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Reset Quick Access',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text(
          'Your usage history will be cleared and the 4 default modules will be shown again.',
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFCC5DE8)),
            onPressed: () async {
              Navigator.pop(context);
              await ModuleUsageTracker.reset();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content:
                      Text('Quick Access reset to defaults', style: GoogleFonts.poppins()),
                  backgroundColor: const Color(0xFFCC5DE8),
                ));
              }
            },
            child: Text('Reset', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _confirmClearCache() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Clear Cache',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text(
          'Locally cached preferences and data will be removed. You may need to reconfigure some settings.',
          style: GoogleFonts.poppins(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF94D82D)),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final prefs = await SharedPreferences.getInstance();
                // Clear app prefs but leave auth-related keys intact
                final keysToRemove = [
                  _kTheme, _kLanguage, _kDateFormat,
                  _kEmailNotif, _kPushNotif, _kWOAlerts,
                ];
                for (final k in keysToRemove) {
                  await prefs.remove(k);
                }
                await _loadAllPrefs();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Cache cleared', style: GoogleFonts.poppins()),
                    backgroundColor: AppColors.success,
                  ));
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error: $e', style: GoogleFonts.poppins()),
                    backgroundColor: AppColors.error,
                  ));
                }
              }
            },
            child: Text('Clear', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showReportIssue() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Report an Issue',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('To report a bug or suggest a feature, reach out via:',
                style: GoogleFonts.poppins(fontSize: 13.5)),
            const SizedBox(height: 14),
            _contactRow(Icons.email_rounded, 'Email', 'support@nyumbasmart.co.ke'),
            const SizedBox(height: 8),
            _contactRow(Icons.phone_rounded, 'WhatsApp', '+254 700 000 000'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primary, size: 16),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.poppins(fontSize: 11, color: AppColors.textSecondary)),
            Text(value, style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ],
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Privacy Policy',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Text(
            'NyumbaSmart collects and processes data necessary for facility and maintenance management. '
            'Your data is securely stored in Firebase and processed in accordance with applicable '
            'data protection regulations.\n\n'
            'We do not sell or share your personal data with third parties. '
            'All maintenance records, assets and facility data are owned by your organization.\n\n'
            'For full details or a data deletion request, contact support@nyumbasmart.co.ke.',
            style: GoogleFonts.poppins(fontSize: 13.5, height: 1.6),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text('Sign Out',
            style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700, color: AppColors.error)),
        content: Text('Are you sure you want to sign out of NyumbaSmart?',
            style: GoogleFonts.poppins(fontSize: 13.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(context);
              _performSignOut();
            },
            child: Text('Sign Out',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
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
          SnackBar(
              content: Text('Error signing out: $e', style: GoogleFonts.poppins())),
        );
      }
    }
  }
}

// ── Section card ──────────────────────────────────────────────────────────────

class _SettingSection extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final List<Widget> tiles;

  const _SettingSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.tiles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
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
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 17),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          ClipRRect(
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(AppRadius.lg),
              bottomRight: Radius.circular(AppRadius.lg),
            ),
            child: Column(children: tiles),
          ),
        ],
      ),
    );
  }
}

// ── Setting tile ──────────────────────────────────────────────────────────────

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool showDivider;

  const _SettingTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor =
        isDestructive ? AppColors.error : AppColors.textPrimary;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 19),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.poppins(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    (onTap != null
                        ? const Icon(Icons.chevron_right_rounded,
                            size: 19, color: Color(0xFFADB5BD))
                        : const SizedBox.shrink()),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(
              height: 1, indent: 67, endIndent: 0, color: Color(0xFFF3F4F6)),
      ],
    );
  }
}

// ── Switch tile ───────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final bool showDivider;

  const _SwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    this.enabled = true,
    required this.onChanged,
    this.showDivider = false,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? iconColor : const Color(0xFFADB5BD);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: effectiveColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: effectiveColor, size: 19),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(subtitle,
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                activeThumbColor: iconColor,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ),
        if (showDivider)
          const Divider(
              height: 1, indent: 67, endIndent: 0, color: Color(0xFFF3F4F6)),
      ],
    );
  }
}
