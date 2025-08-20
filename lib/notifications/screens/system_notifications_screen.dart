import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/notifications/services/system_notification_service.dart';
import 'package:cmms/notifications/screens/notifications_screen.dart';
import 'package:cmms/notifications/screens/notification_settings_screen.dart';

class SystemNotificationsScreen extends StatefulWidget {
  const SystemNotificationsScreen({super.key});

  @override
  State<SystemNotificationsScreen> createState() => _SystemNotificationsScreenState();
}

class _SystemNotificationsScreenState extends State<SystemNotificationsScreen> {
  final Logger _logger = Logger(printer: PrettyPrinter());
  final SystemNotificationService _systemNotificationService = SystemNotificationService();
  
  bool _autoNotificationsEnabled = false;
  bool _isLoading = true;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final autoEnabled = await _systemNotificationService.areAutoNotificationsEnabled();
      
      if (mounted) {
        setState(() {
          _autoNotificationsEnabled = autoEnabled;
          _isLoading = false;
        });
      }
    } catch (e) {
      _logger.e('Error loading settings: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleAutoNotifications(bool enabled) async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
    });

    try {
      if (enabled) {
        // Generate system notifications
        _showSnackBar('Generating automatic notifications...', Colors.blue);
        await _systemNotificationService.generateSystemNotifications();
        _showSnackBar('Automatic notifications enabled and generated successfully!', Colors.green);
      } else {
        await _systemNotificationService.setAutoNotificationsEnabled(false);
        _showSnackBar('Automatic notifications disabled', Colors.orange);
      }

      setState(() {
        _autoNotificationsEnabled = enabled;
        _isGenerating = false;
      });

    } catch (e) {
      _logger.e('Error toggling auto notifications: $e');
      setState(() {
        _isGenerating = false;
      });
      _showSnackBar('Error updating automatic notifications: $e', Colors.red);
    }
  }

  Future<void> _regenerateNotifications() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Regenerate Notifications', style: GoogleFonts.poppins()),
        content: Text(
          'This will regenerate all system notifications based on current maintenance tasks. Continue?',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
            child: Text('Regenerate', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() {
        _isGenerating = true;
      });

      try {
        _showSnackBar('Regenerating system notifications...', Colors.blue);
        await _systemNotificationService.regenerateSystemNotifications();
        _showSnackBar('System notifications regenerated successfully!', Colors.green);
      } catch (e) {
        _logger.e('Error regenerating notifications: $e');
        _showSnackBar('Error regenerating notifications: $e', Colors.red);
      } finally {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  void _showSnackBar(String message, Color color) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.poppins()),
          backgroundColor: color,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'System Notifications',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const NotificationSettingsScreen(),
                ),
              );
            },
            tooltip: 'Notification Settings',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Text(
                    'System Notification Management',
                    style: GoogleFonts.poppins(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage automatic system notifications for maintenance tasks',
                    style: GoogleFonts.poppins(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Automatic Notifications Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.autorenew, color: Colors.green[700], size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Automatic System Notifications',
                                  style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey[800],
                                  ),
                                ),
                              ),
                              if (_isGenerating)
                                const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                Switch(
                                  value: _autoNotificationsEnabled,
                                  onChanged: _toggleAutoNotifications,
                                  activeThumbColor: Colors.green,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _autoNotificationsEnabled
                                ? 'Automatic notifications are enabled. The system will generate and send maintenance reminders based on task frequencies.'
                                : 'Enable automatic notifications to have the system generate maintenance reminders for all tasks.',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          if (_autoNotificationsEnabled) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _isGenerating ? null : _regenerateNotifications,
                                    icon: const Icon(Icons.refresh),
                                    label: Text(
                                      'Regenerate Notifications',
                                      style: GoogleFonts.poppins(),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // View Notifications Card
                  Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.notifications, color: Colors.blue[700], size: 28),
                              const SizedBox(width: 12),
                              Text(
                                'View Notifications',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey[800],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'View and manage all system notifications, including read status and details',
                            style: GoogleFonts.poppins(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const NotificationsScreen(),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.list),
                              label: Text(
                                'View All Notifications',
                                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Information Card
                  Card(
                    elevation: 2,
                    color: Colors.blue[50],
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[700]),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'System Information',
                                  style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '• System notifications are generated automatically based on maintenance task frequencies\n'
                            '• Notifications are sent 5 days before maintenance is due\n'
                            '• Alerts are sent 1 day before maintenance is due\n'
                            '• Only users from "JV Almacis" organization receive notifications\n'
                            '• Notifications are sent at 9:00 AM and 11:00 AM (retry)\n'
                            '• Tasks with same dates are grouped into single notifications\n'
                            '• Read status is tracked for each user individually',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
