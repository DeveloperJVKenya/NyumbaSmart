import 'package:cmms/notifications/screens/system_notification_detail_screen.dart';
import 'package:cmms/notifications/screens/custom_notification_detail_screen.dart';
import 'package:cmms/notifications/screens/add_custom_notification_screen.dart';
import 'package:cmms/notifications/screens/edit_custom_notification_screen.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cmms/notifications/models/system_notification_model.dart';
import 'package:cmms/notifications/models/custom_notification_model.dart';
import 'package:cmms/notifications/services/system_notification_service.dart';
import 'package:cmms/notifications/services/custom_notification_service.dart';
import 'package:cmms/notifications/utils/date_calculator.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with TickerProviderStateMixin {
  final SystemNotificationService _systemNotificationService = SystemNotificationService();
  final CustomNotificationService _customNotificationService = CustomNotificationService();
  
  final Logger _logger = Logger();
  late TabController _mainTabController;
  late TabController _systemTabController;
  late TabController _customTabController;
  
  final Set<String> _selectedNotifications = {};
  bool _isSelectionMode = false;
  String _userOrganization = '';
  
  // Test notification state - REMOVED COUNTDOWN LOGIC
  bool _isSendingTest = false;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _systemTabController = TabController(length: 2, vsync: this);
    _customTabController = TabController(length: 2, vsync: this); // Changed from 3 to 2
    _getUserOrganization();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _systemTabController.dispose();
    _customTabController.dispose();
    super.dispose();
  }

  Future<void> _getUserOrganization() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('Users').doc(user.uid).get();
        if (userDoc.exists) {
          setState(() {
            _userOrganization = userDoc.data()?['organization'] ?? '';
          });
        }
      } catch (e) {
        _logger.e('Error getting user organization: $e');
      }
    }
  }

  void _toggleSelection(String notificationId) {
    setState(() {
      if (_selectedNotifications.contains(notificationId)) {
        _selectedNotifications.remove(notificationId);
      } else {
        _selectedNotifications.add(notificationId);
      }
      
      if (_selectedNotifications.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _enterSelectionMode(String notificationId) {
    setState(() {
      _isSelectionMode = true;
      _selectedNotifications.add(notificationId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedNotifications.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isSelectionMode ? '${_selectedNotifications.length} selected' : 'Notifications',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.blueGrey,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: _exitSelectionMode,
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
        actions: _isSelectionMode
            ? [
                // Removed copy button, kept only delete
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white),
                  onPressed: _deleteSelectedNotifications,
                  tooltip: 'Delete',
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _mainTabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.bold),
          unselectedLabelStyle: GoogleFonts.poppins(),
          tabs: const [
            Tab(text: 'System'),
            Tab(text: 'Custom'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          _buildSystemNotificationsTab(),
          _buildCustomNotificationsTab(),
        ],
      ),
    );
  }

  Widget _buildSystemNotificationsTab() {
    return Column(
      children: [
        Container(
          color: Colors.grey[100],
          child: TabBar(
            controller: _systemTabController,
            labelColor: Colors.blueGrey[800],
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Colors.blueGrey,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Notifications'),
              Tab(text: 'Alerts'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _systemTabController,
            children: [
              _buildSystemNotificationsList(SystemNotificationType.notification),
              _buildSystemNotificationsList(SystemNotificationType.alert),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCustomNotificationsTab() {
    return Column(
      children: [
        Container(
          color: Colors.grey[100],
          child: TabBar(
            controller: _customTabController,
            labelColor: Colors.blueGrey[800],
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: Colors.blueGrey,
            labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
            tabs: const [
              Tab(text: 'Notifications'),
              Tab(text: 'Test'), // Removed Alerts tab
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _customTabController,
            children: [
              _buildCustomNotificationsList(CustomNotificationType.notification),
              _buildTestNotificationsList(), // Removed alerts view
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSystemNotificationsList(SystemNotificationType type) {
    return StreamBuilder<List<SystemNotificationModel>>(
      stream: _systemNotificationService.getSystemNotifications(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return _buildErrorWidget('Error loading notifications: ${snapshot.error}');
        }
        final allNotifications = snapshot.data ?? [];
        final filteredNotifications = allNotifications
            .where((n) => n.type == type)
            .where((n) => !_selectedNotifications.contains(n.id))
            .toList();

        // Sort by closest date first, but move triggered ones to bottom
        filteredNotifications.sort((a, b) {
          if (a.isTriggered && !b.isTriggered) return 1;
          if (!a.isTriggered && b.isTriggered) return -1;
          if (a.isTriggered && b.isTriggered) {
            return (b.triggeredAt ?? b.notificationDate).compareTo(a.triggeredAt ?? a.notificationDate);
          }
          return a.notificationDate.compareTo(b.notificationDate);
        });

        if (filteredNotifications.isEmpty) {
          return _buildEmptyWidget(
            'No ${type.name.capitalize()} Notifications',
            'System ${type.name} notifications will appear here when generated',
            type == SystemNotificationType.alert ? Icons.warning : Icons.notifications_none,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8.0),
          itemCount: filteredNotifications.length,
          itemBuilder: (context, index) {
            final notification = filteredNotifications[index];
            return _buildSystemNotificationItem(notification);
          },
        );
      },
    );
  }

  Widget _buildCustomNotificationsList(CustomNotificationType type) {
    if (_userOrganization.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: StreamBuilder<List<CustomNotificationModel>>(
        stream: _customNotificationService.getCustomNotificationsByType(_userOrganization, type),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _buildErrorWidget('Error loading custom notifications: ${snapshot.error}');
          }
          final notifications = snapshot.data ?? [];
          final filteredNotifications = notifications
              .where((n) => !_selectedNotifications.contains(n.id))
              .toList();

          if (filteredNotifications.isEmpty) {
            return _buildEmptyWidget(
              'No Custom ${type.name.capitalize()} Notifications',
              'Custom ${type.name} notifications will appear here when created',
              type == CustomNotificationType.alert ? Icons.warning : Icons.add_alert,
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: filteredNotifications.length,
            itemBuilder: (context, index) {
              final notification = filteredNotifications[index];
              return _buildCustomNotificationItem(notification);
            },
          );
        },
      ),
      floatingActionButton: type == CustomNotificationType.notification
          ? FloatingActionButton.extended(
              onPressed: () => _showAddCustomNotificationScreen(),
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text('Custom Notification', style: GoogleFonts.poppins()),
            )
          : null,
    );
  }

  Widget _buildTestNotificationsList() {
    if (_userOrganization.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Column(
        children: [
          // Test notification info card with dark grey theme
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.science, color: Colors.blueGrey[700], size: 24),
                    const SizedBox(width: 12),
                    Text(
                      'Test Notification System',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.blueGrey[800],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Send test notifications to verify the system is working correctly. Test notifications will trigger after 2 minutes.',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.blueGrey[700],
                  ),
                ),
              ],
            ),
          ),
          // REMOVED: Send Test Button from here - only keeping the floating action button
          const SizedBox(height: 24),
          // Test notifications list
          Expanded(
            child: StreamBuilder<List<CustomNotificationModel>>(
              stream: _customNotificationService.getCustomNotificationsByType(_userOrganization, CustomNotificationType.test),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildErrorWidget('Error loading test notifications: ${snapshot.error}');
                }
                final notifications = snapshot.data ?? [];
                if (notifications.isEmpty) {
                  return _buildEmptyWidget(
                    'No Test Notifications',
                    'Test notifications you send will appear here',
                    Icons.science,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: notifications.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return _TestNotificationItem(
                      key: ValueKey(notification.id),
                      notification: notification,
                      onDelete: () => _handleTestNotificationAction('delete', notification),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSendingTest ? null : _sendTestNotification,
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.send),
        label: Text('Send Test', style: GoogleFonts.poppins()),
      ),
    );
  }

  Widget _buildSystemNotificationItem(SystemNotificationModel notification) {
    final user = FirebaseAuth.instance.currentUser;
    final isRead = user != null && notification.readByUsers.any((r) => r.userId == user.uid);
    final isSelected = _selectedNotifications.contains(notification.id);

    Color statusColor;
    IconData statusIcon;
    
    if (notification.type == SystemNotificationType.alert) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    } else if (notification.isOverdue) {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    } else if (notification.isDueToday) {
      statusColor = Colors.blue;
      statusIcon = Icons.schedule;
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue[50] : (isRead ? Colors.grey[50] : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue[300]! : Colors.grey[200]!,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(notification.id);
          } else {
            _openSystemNotificationDetail(notification);
          }
        },
        onLongPress: () {
          if (!_isSelectionMode) {
            _enterSelectionMode(notification.id);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(statusIcon, color: statusColor, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            notification.title,
                            style: GoogleFonts.poppins(
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          notification.triggeredAt != null
                              ? DateFormat.jm().format(notification.triggeredAt!)
                              : DateFormat.jm().format(notification.notificationDate),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.body,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      NotificationDateCalculator.getRelativeDateString(notification.nextInspectionDate),
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ...notification.categories.take(3).map((category) => Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            category,
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )),
                        if (notification.categories.length > 3)
                          Text(
                            '+${notification.categories.length - 3} more',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: Colors.grey[500],
                            ),
                          ),
                        const Spacer(),
                        if (isRead)
                          Icon(Icons.done_all, color: Colors.blue[600], size: 16)
                        else if (notification.isTriggered)
                          Icon(Icons.done, color: Colors.grey[400], size: 16),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Selection indicator
              if (_isSelectionMode)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : Colors.grey[400],
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomNotificationItem(CustomNotificationModel notification) {
    final user = FirebaseAuth.instance.currentUser;
    final isRead = user != null && notification.readByUsers.any((r) => r.userId == user.uid);
    final isSelected = _selectedNotifications.contains(notification.id);

    Color statusColor;
    IconData statusIcon;
    
    if (notification.type == CustomNotificationType.alert) {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    } else if (notification.isOverdue) {
      statusColor = Colors.red;
      statusIcon = Icons.error;
    } else if (notification.isDueToday) {
      statusColor = Colors.blue;
      statusIcon = Icons.schedule;
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue[50] : (isRead ? Colors.grey[50] : Colors.white),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? Colors.blue[300]! : Colors.grey[200]!,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: () {
          if (_isSelectionMode) {
            _toggleSelection(notification.id);
          } else {
            _openCustomNotificationDetail(notification);
          }
        },
        onLongPress: () {
          if (!_isSelectionMode) {
            _enterSelectionMode(notification.id);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status indicator
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(statusIcon, color: statusColor, size: 16),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${notification.component} - ${notification.category}',
                            style: GoogleFonts.poppins(
                              fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                              fontSize: 14,
                              color: Colors.grey[800],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) => _handleCustomNotificationAction(value, notification),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'edit', // Changed from 'copy' to 'edit'
                              child: Row(
                                children: [
                                  const Icon(Icons.edit, size: 16), // Changed icon from copy to edit
                                  const SizedBox(width: 8),
                                  Text('Edit', style: GoogleFonts.poppins()), // Changed text
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  const Icon(Icons.delete, size: 16, color: Colors.red),
                                  const SizedBox(width: 8),
                                  Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                          child: Icon(Icons.more_vert, color: Colors.grey[600], size: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      notification.intervention,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: Colors.grey[600],
                        fontWeight: isRead ? FontWeight.normal : FontWeight.w500,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Due: ${NotificationDateCalculator.getRelativeDateString(notification.nextInspectionDate)}',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.grey[500],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Every ${notification.frequency} months',
                            style: GoogleFonts.poppins(
                              fontSize: 10,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const Spacer(),
                        if (isRead)
                          Icon(Icons.done_all, color: Colors.blue[600], size: 16)
                        else if (notification.isTriggered)
                          Icon(Icons.done, color: Colors.grey[400], size: 16),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Selection indicator
              if (_isSelectionMode)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  child: Icon(
                    isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.blue : Colors.grey[400],
                    size: 20,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendTestNotification() async {
    if (_userOrganization.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Organization not found', style: GoogleFonts.poppins()),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isSendingTest = true;
    });

    try {
      final notificationIds = await _customNotificationService.sendTestNotification(_userOrganization);
      
      if (notificationIds.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Test notification scheduled! Will trigger in 2 minutes.',
                style: GoogleFonts.poppins(),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to schedule test notification', style: GoogleFonts.poppins()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      _logger.e('Error sending test notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e', style: GoogleFonts.poppins()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSendingTest = false;
        });
      }
    }
  }

  void _handleTestNotificationAction(String action, CustomNotificationModel notification) async {
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete Test Notification', style: GoogleFonts.poppins()),
          content: Text(
            'Are you sure you want to delete this test notification?',
            style: GoogleFonts.poppins(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: GoogleFonts.poppins()),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('Delete', style: GoogleFonts.poppins()),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        try {
          await _customNotificationService.deleteCustomNotification(notification.id);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Test notification deleted', style: GoogleFonts.poppins()),
                backgroundColor: Colors.green,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error deleting notification: $e', style: GoogleFonts.poppins()),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  void _handleCustomNotificationAction(String action, CustomNotificationModel notification) async {
    switch (action) {
      case 'edit': // Changed from 'copy' to 'edit'
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => EditCustomNotificationScreen(notification: notification),
          ),
        );
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete Notification', style: GoogleFonts.poppins()),
            content: Text('Are you sure you want to delete this custom notification?', style: GoogleFonts.poppins()),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('Cancel', style: GoogleFonts.poppins()),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text('Delete', style: GoogleFonts.poppins()),
              ),
            ],
          ),
        );
        
        if (confirmed == true) {
          try {
            await _customNotificationService.deleteCustomNotification(notification.id);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Notification deleted successfully', style: GoogleFonts.poppins()),
                  backgroundColor: Colors.green,
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error deleting notification: $e', style: GoogleFonts.poppins()),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        }
        break;
    }
  }

  void _showAddCustomNotificationScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddCustomNotificationScreen(organization: _userOrganization),
      ),
    );
  }

  void _openSystemNotificationDetail(SystemNotificationModel notification) async {
    // Mark as read when opened
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && notification.isTriggered) {
      await _systemNotificationService.markNotificationAsRead(notification.id, user.uid);
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SystemNotificationDetailScreen(notification: notification),
        ),
      );
    }
  }

  void _openCustomNotificationDetail(CustomNotificationModel notification) async {
    // Mark as read when opened
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && notification.isTriggered) {
      await _customNotificationService.markNotificationAsRead(notification.id, user.uid);
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CustomNotificationDetailScreen(notification: notification),
        ),
      );
    }
  }

  void _deleteSelectedNotifications() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Notifications', style: GoogleFonts.poppins()),
        content: Text('Are you sure you want to delete ${_selectedNotifications.length} selected notifications?', style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete', style: GoogleFonts.poppins()),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        for (final notificationId in _selectedNotifications) {
          await _customNotificationService.deleteCustomNotification(notificationId);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_selectedNotifications.length} notifications deleted successfully', style: GoogleFonts.poppins()),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting notifications: $e', style: GoogleFonts.poppins()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
      
      _exitSelectionMode();
    }
  }

  Widget _buildEmptyWidget(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              style: GoogleFonts.poppins(
                color: Colors.grey[500],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error Loading Notifications',
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.red[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              error,
              style: GoogleFonts.poppins(
                color: Colors.red[500],
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                // Trigger rebuild
              });
            },
            icon: const Icon(Icons.refresh),
            label: Text('Retry', style: GoogleFonts.poppins()),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// OPTIMIZED: Separate widget to prevent unnecessary rebuilds - REMOVED COUNTDOWN LOGIC
class _TestNotificationItem extends StatelessWidget {
  final CustomNotificationModel notification;
  final VoidCallback onDelete;

  const _TestNotificationItem({
    super.key,
    required this.notification,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isTriggered = notification.isTriggered;

    return Container(
      decoration: BoxDecoration(
        color: isTriggered ? Colors.green[50] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTriggered ? Colors.green[200]! : Colors.grey[300]!,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isTriggered ? Colors.green : Colors.blueGrey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isTriggered ? Icons.check_circle : Icons.schedule,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test Notification',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey[800],
                        ),
                      ),
                      Text(
                        'Organization: ${notification.organization}',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete, size: 16, color: Colors.red),
                          const SizedBox(width: 8),
                          Text('Delete', style: GoogleFonts.poppins(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                  child: Icon(Icons.more_vert, color: Colors.grey[600], size: 16),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Status Row
            Row(
              children: [
                // Status Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isTriggered
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.blueGrey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isTriggered ? 'Triggered' : 'Scheduled',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isTriggered
                          ? Colors.green[700]
                          : Colors.blueGrey[700],
                    ),
                  ),
                ),
                
                const Spacer(),
                
                // Stats
                if (isTriggered) ...[
                  if (notification.sentCount > 0)
                    Text(
                      '${notification.sentCount} sent',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.green[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (notification.failedCount > 0) ...[
                    if (notification.sentCount > 0) const SizedBox(width: 8),
                    Text(
                      '${notification.failedCount} failed',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.red[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ],
            ),
            
            // Timestamp
            const SizedBox(height: 8),
            Text(
              isTriggered && notification.triggeredAt != null
                  ? 'Triggered: ${DateFormat('MMM dd, HH:mm').format(notification.triggeredAt!)}'
                  : 'Created: ${DateFormat('MMM dd, HH:mm').format(notification.createdAt)}',
              style: GoogleFonts.poppins(
                fontSize: 10,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1)}";
  }
}
