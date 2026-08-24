import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cmms/notifications/models/digest_item.dart';
import 'package:cmms/notifications/providers/notification_providers.dart';
import 'package:cmms/notifications/screens/notifications_screen.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/screens/dashboard_screen.dart';
import 'package:cmms/theme/app_theme.dart';

/// A compact, dismissible banner for the most recent unread digest — "6 notifications from 2
/// facilities" — with an expand affordance revealing the per-facility breakdown. Backed by a real
/// Riverpod stream ([latestUnreadDigestProvider]) instead of the previous hand-rolled 1-second
/// polling combinator.
class FloatingNotificationWidget extends ConsumerStatefulWidget {
  const FloatingNotificationWidget({super.key});

  @override
  ConsumerState<FloatingNotificationWidget> createState() => _FloatingNotificationWidgetState();
}

class _FloatingNotificationWidgetState extends ConsumerState<FloatingNotificationWidget> with SingleTickerProviderStateMixin {
  static const _autoDismissDelay = Duration(seconds: 6);

  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  bool _expanded = false;
  String? _dismissedDigestId;

  Timer? _autoDismissTimer;
  String? _timerDigestId;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(duration: const Duration(milliseconds: 400), vsync: this);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _slideController.dispose();
    _autoDismissTimer?.cancel();
    super.dispose();
  }

  // Hides the banner locally after a few seconds — it must NOT mark the digest as
  // read, so the appbar bell badge keeps counting it until the user actually opens it.
  void _scheduleAutoDismiss(String digestId) {
    _autoDismissTimer?.cancel();
    _timerDigestId = digestId;
    _autoDismissTimer = Timer(_autoDismissDelay, () {
      if (mounted) setState(() => _dismissedDigestId = digestId);
    });
  }

  void _cancelAutoDismiss() {
    _autoDismissTimer?.cancel();
    _autoDismissTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    final digest = ref.watch(latestUnreadDigestProvider);

    if (digest == null || digest.id == _dismissedDigestId) {
      _cancelAutoDismiss();
      return const SizedBox.shrink();
    }

    // Don't restart the timer on every rebuild — only when a genuinely new digest
    // becomes the latest unread one, and only while the user isn't mid-read (expanded).
    if (!_expanded && _timerDigestId != digest.id) {
      _scheduleAutoDismiss(digest.id);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_slideController.isAnimating && !_slideController.isCompleted) {
        _slideController.forward();
      }
    });

    return Positioned(
      top: MediaQuery.of(context).padding.top + 10,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: _buildBanner(digest),
      ),
    );
  }

  Widget _buildBanner(DigestItem digest) {
    final isUrgent = digest.isUrgent;
    final accent = isUrgent ? AppColors.error : AppColors.primary;

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, isUrgent ? AppColors.error.withValues(alpha: 0.85) : AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => _openNotifications(digest),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(isUrgent ? Icons.warning_rounded : Icons.notifications_active_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(digest.title, style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(digest.body, style: GoogleFonts.poppins(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _expanded = !_expanded;
                        if (_expanded) {
                          _cancelAutoDismiss();
                        } else {
                          _scheduleAutoDismiss(digest.id);
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(_expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.white70),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        _cancelAutoDismiss();
                        setState(() => _dismissedDigestId = digest.id);
                      },
                      child: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...digest.facilities.map((facility) => _facilityRow(digest, facility)),
          ],
        ),
      ),
    );
  }

  Widget _facilityRow(DigestItem digest, DigestFacilityGroup facility) {
    return InkWell(
      onTap: () => _openFacility(digest, facility),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.15)))),
        child: Row(
          children: [
            const Icon(Icons.apartment_rounded, color: Colors.white70, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(facility.facilityName, style: GoogleFonts.poppins(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
            Text('${facility.count}', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }

  void _openNotifications(DigestItem digest) {
    _cancelAutoDismiss();
    setState(() => _dismissedDigestId = digest.id);
    Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
  }

  void _openFacility(DigestItem digest, DigestFacilityGroup facility) {
    final userId = ref.read(authStateProvider).value?.uid;
    if (userId != null) ref.read(notificationServiceProvider).markDigestRead(userId, digest.id);

    _cancelAutoDismiss();
    setState(() => _dismissedDigestId = digest.id);

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => DashboardScreen(facilityId: facility.facilityId, role: '')),
    );
  }
}
