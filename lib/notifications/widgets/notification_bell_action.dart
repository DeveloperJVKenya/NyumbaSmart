import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/providers/notification_providers.dart';
import 'package:cmms/notifications/screens/notifications_screen.dart';

/// Shared appbar notification bell + unread badge, backed by
/// [unreadDigestCountProvider] — a single subscription reused everywhere
/// instead of every screen declaring its own `watchUnreadCount` stream.
class NotificationBellAction extends ConsumerWidget {
  const NotificationBellAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadDigestCountProvider).value ?? 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_active, color: Colors.white),
          tooltip: 'Notifications',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const NotificationsScreen()),
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            right: 6,
            top: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                child: Text(
                  unreadCount > 99 ? '99+' : '$unreadCount',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
