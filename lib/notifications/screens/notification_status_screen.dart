import 'package:flutter/material.dart';
import 'package:cmms/notifications/screens/notifications_screen.dart';

/// Landing screen when a notification is tapped (from the OS tray, or `onMessageOpenedApp`) —
/// simply shows the unified notification feed, which already reflects live read/unread state via
/// the `NotificationDigests` stream.
class NotificationStatusScreen extends StatelessWidget {
  const NotificationStatusScreen({super.key});

  @override
  Widget build(BuildContext context) => const NotificationsScreen();
}
