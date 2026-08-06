import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:logger/logger.dart';
import 'package:cmms/providers/auth_providers.dart';
import 'package:cmms/theme/app_theme.dart';
import 'package:cmms/theme/app_widgets.dart';

class RoleAssignmentScreen extends ConsumerStatefulWidget {
  const RoleAssignmentScreen({super.key});

  @override
  ConsumerState<RoleAssignmentScreen> createState() => _RoleAssignmentScreenState();
}

class _RoleAssignmentScreenState extends ConsumerState<RoleAssignmentScreen> {
  final TextEditingController _uidController = TextEditingController();
  final Logger _logger = Logger();
  final GlobalKey<ScaffoldMessengerState> _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> _assignRole(String uid) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _snack('No authenticated user');
        return;
      }

      // Admin check + organization now go through RoleService, the same
      // source of truth the rest of the app uses, instead of this screen's
      // own inline Firestore lookup.
      final roleService = ref.read(roleServiceProvider);
      final isAdmin = await roleService.isAdmin(user.uid);
      if (!isAdmin) {
        _snack('Only Admins can assign Technician roles');
        return;
      }
      final adminOrg = await roleService.adminOrganization(user.uid) ?? '-';
      if (adminOrg == '-') {
        _snack('Admin organization not set');
        return;
      }

      final userDoc = await FirebaseFirestore.instance.collection('Users').doc(uid).get();
      if (!userDoc.exists) {
        _snack('User not found');
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;
      if (userData['role'] != '-') {
        _snack('User already has a role: ${userData['role']}');
        return;
      }

      final roleData = {
        'username': userData['username'] ?? '',
        'email': userData['email'] ?? '',
        'organization': adminOrg,
        'createdAt': Timestamp.now(),
        'isDisabled': false,
      };

      _logger.i('Assigning Technician role to Users/$uid with organization: $adminOrg');
      await FirebaseFirestore.instance.collection('Technicians').doc(uid).set(roleData);
      try {
        await FirebaseFirestore.instance.collection('Users').doc(uid).update({'role': 'Technician'});
      } catch (e) {
        _logger.e('Failed to update role in Users collection: $e');
        _snack('Technician role assigned, but failed to update user role: $e', color: AppColors.warning);
        return;
      }

      await _logActivity('Assigned Technician role to $uid (User: ${userData['username']}, Organization: $adminOrg)');
      _snack('Technician role assigned successfully!', color: AppColors.success);
      _uidController.clear();
    } catch (e) {
      _logger.e('Error assigning role to Users/$uid: $e');
      _snack('Error assigning role: $e');
    }
  }

  void _snack(String message, {Color? color}) {
    if (!mounted) return;
    _messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.poppins()), backgroundColor: color),
    );
  }

  Future<void> _logActivity(String action) async {
    try {
      await FirebaseFirestore.instance.collection('admin_logs').add({
        'action': action,
        'timestamp': Timestamp.now(),
        'adminUid': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (e) {
      _logger.e('Error logging activity: $e');
    }
  }

  @override
  void dispose() {
    _uidController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = AppBreakpoints.isMobile(MediaQuery.of(context).size.width);

    return ScaffoldMessenger(
      key: _messengerKey,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Assign Technician Role', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
          flexibleSpace: const DecoratedBox(decoration: BoxDecoration(gradient: AppColors.primaryGradient)),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select or Enter User to Assign Technician Role',
                    style: GoogleFonts.poppins(
                      fontSize: isMobile ? 18 : 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: _uidController,
                            label: 'User UID',
                            hint: 'e.g., abc123xyz789',
                            icon: Icons.badge_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: () {
                              if (_uidController.text.isEmpty) {
                                _snack('Please enter a User UID');
                                return;
                              }
                              _assignRole(_uidController.text);
                            },
                            style: ElevatedButton.styleFrom(minimumSize: const Size(110, 54)),
                            child: const Text('Assign'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Available Users (Unassigned Role)',
                    style: GoogleFonts.poppins(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('Users').where('role', isEqualTo: '-').snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                        }
                        if (snapshot.hasError) {
                          _logger.e('Firestore error: ${snapshot.error}');
                          return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.poppins(color: AppColors.error)));
                        }
                        final users = snapshot.data?.docs ?? [];
                        if (users.isEmpty) {
                          return Center(child: Text('No eligible users found.', style: GoogleFonts.poppins(color: AppColors.textSecondary)));
                        }

                        return ListView.builder(
                          itemCount: users.length,
                          itemBuilder: (context, index) {
                            final user = users[index].data() as Map<String, dynamic>;
                            final uid = users[index].id;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: AppCard(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const CircleAvatar(
                                    backgroundColor: AppColors.surfaceAlt,
                                    child: Icon(Icons.person_outline, color: AppColors.primary),
                                  ),
                                  title: Text(user['username'] ?? 'No Username', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                                  subtitle: Text('Email: ${user['email'] ?? 'N/A'}', style: GoogleFonts.poppins(fontSize: 12.5)),
                                  trailing: ElevatedButton(
                                    onPressed: () => _assignRole(uid),
                                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40), padding: const EdgeInsets.symmetric(horizontal: 16)),
                                    child: const Text('Assign', style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
