import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/notification_service.dart';
import 'package:cmms/theme/app_theme.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final NotificationService _notificationService = NotificationService();

  bool _notificationsEnabled = true;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _screenWakeEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final notificationsEnabled = await _notificationService.areNotificationsEnabled();
      final soundEnabled = await _notificationService.isSoundEnabled();
      final vibrationEnabled = await _notificationService.isVibrationEnabled();
      final screenWakeEnabled = await _notificationService.isScreenWakeEnabled();

      if (mounted) {
        setState(() {
          _notificationsEnabled = notificationsEnabled;
          _soundEnabled = soundEnabled;
          _vibrationEnabled = vibrationEnabled;
          _screenWakeEnabled = screenWakeEnabled;
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Error loading settings: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateNotificationsEnabled(bool enabled) async {
    try {
      await _notificationService.setNotificationsEnabled(enabled);
      setState(() => _notificationsEnabled = enabled);
      _showSnackBar(enabled ? 'Notifications enabled' : 'Notifications disabled', enabled ? AppColors.success : AppColors.warning);
    } catch (e) {
      _logger.e('Error updating notifications enabled: $e');
      _showSnackBar('Error updating notification settings: $e', AppColors.error);
    }
  }

  Future<void> _updateSoundEnabled(bool enabled) async {
    try {
      await _notificationService.setSoundEnabled(enabled);
      setState(() => _soundEnabled = enabled);
      _showSnackBar(enabled ? 'Notification sound enabled' : 'Notification sound disabled', enabled ? AppColors.success : AppColors.warning);
    } catch (e) {
      _logger.e('Error updating sound setting: $e');
      _showSnackBar('Error updating sound setting: $e', AppColors.error);
    }
  }

  Future<void> _updateVibrationEnabled(bool enabled) async {
    try {
      await _notificationService.setVibrationEnabled(enabled);
      setState(() => _vibrationEnabled = enabled);
      _showSnackBar(enabled ? 'Notification vibration enabled' : 'Notification vibration disabled', enabled ? AppColors.success : AppColors.warning);
    } catch (e) {
      _logger.e('Error updating vibration setting: $e');
      _showSnackBar('Error updating vibration setting: $e', AppColors.error);
    }
  }

  Future<void> _updateScreenWakeEnabled(bool enabled) async {
    try {
      await _notificationService.setScreenWakeEnabled(enabled);
      setState(() => _screenWakeEnabled = enabled);
      _showSnackBar(enabled ? 'Screen wake enabled for urgent notifications' : 'Screen wake disabled', enabled ? AppColors.success : AppColors.warning);
    } catch (e) {
      _logger.e('Error updating screen wake setting: $e');
      _showSnackBar('Error updating screen wake setting: $e', AppColors.error);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message, style: GoogleFonts.poppins()), backgroundColor: color, duration: const Duration(seconds: 3)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text('Notification Settings', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isMobile = AppBreakpoints.isMobile(constraints.maxWidth);
                return SingleChildScrollView(
                  padding: EdgeInsets.all(isMobile ? AppSpacing.md : AppSpacing.xl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Notification Preferences', style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 6),
                      Text('Configure how you receive maintenance notifications and alerts', style: GoogleFonts.poppins(color: AppColors.textSecondary, fontSize: 13.5)),
                      const SizedBox(height: AppSpacing.lg),
                      _sectionCard(
                        icon: Icons.notifications_rounded,
                        title: 'General',
                        children: [
                          _settingTile(
                            title: 'Enable Notifications',
                            subtitle: 'Receive maintenance task notifications and alerts',
                            value: _notificationsEnabled,
                            onChanged: _updateNotificationsEnabled,
                            icon: Icons.notifications_active_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _sectionCard(
                        icon: Icons.phone_android_rounded,
                        title: 'Device',
                        children: [
                          _settingTile(
                            title: 'Sound',
                            subtitle: 'Play sound when notifications arrive',
                            value: _soundEnabled,
                            onChanged: _notificationsEnabled ? _updateSoundEnabled : null,
                            icon: Icons.volume_up_rounded,
                          ),
                          const Divider(),
                          _settingTile(
                            title: 'Vibration',
                            subtitle: 'Vibrate device for notifications',
                            value: _vibrationEnabled,
                            onChanged: _notificationsEnabled ? _updateVibrationEnabled : null,
                            icon: Icons.vibration_rounded,
                          ),
                          const Divider(),
                          _settingTile(
                            title: 'Screen Wake',
                            subtitle: 'Wake screen for urgent notifications and alerts',
                            value: _screenWakeEnabled,
                            onChanged: _notificationsEnabled ? _updateScreenWakeEnabled : null,
                            icon: Icons.screen_lock_portrait_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(AppRadius.md)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline_rounded, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Notifications are sent 5 days before maintenance is due, with an urgent alert '
                                '1 day before. Due tasks are checked hourly, and any unread notification is '
                                're-sent after 4 hours. Due/alert notifications go to JV Almacis (the '
                                'maintenance contractor); custom notifications are facility-scoped and deliver '
                                'immediately. Delivery works whether the app is open, backgrounded, or closed.',
                                style: GoogleFonts.poppins(fontSize: 12.5, color: AppColors.textPrimary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _sectionCard({required IconData icon, required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _settingTile({
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool)? onChanged,
    required IconData icon,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
        child: Icon(icon, color: AppColors.primary),
      ),
      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: onChanged != null ? AppColors.textPrimary : AppColors.textSecondary)),
      subtitle: Text(subtitle, style: GoogleFonts.poppins(fontSize: 12, color: AppColors.textSecondary)),
      trailing: Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
    );
  }
}
