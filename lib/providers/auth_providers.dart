import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:rxdart/rxdart.dart';
import 'package:cmms/models/user_model.dart';

/// Single source of truth for "who is signed in" — replaces the ad hoc
/// `FirebaseAuth.instance.currentUser` checks previously duplicated in
/// login_screen.dart, splashscreen.dart, dashboard_screen.dart, etc.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Resolved role + organization for the current user, replacing the
/// `Admins -> Developers -> Technicians -> Users` cascade that used to be
/// duplicated near-verbatim in 4 different files.
class UserRoleInfo {
  final UserRole role;
  final String organization;
  final bool isDeveloper;

  const UserRoleInfo({
    required this.role,
    required this.organization,
    this.isDeveloper = false,
  });

  /// The exact string keys already used by menu-filtering logic
  /// (responsive_screen_wrapper.dart's `_getMenuItemsForRole`) and stored
  /// in Firestore — kept as-is so no data/menu-config migration is needed.
  String get roleLabel => role.label;

  /// "JV Almacis" (the service-provider org) staff manage other orgs;
  /// everyone else is scoped to their own organization ("client").
  bool get isServiceProviderOrg => organization == 'JV Almacis';
  bool get isClient => !isServiceProviderOrg;

  factory UserRoleInfo.signedOut() =>
      const UserRoleInfo(role: UserRole.unassigned, organization: '-');

  UserRoleInfo copyWith({UserRole? role, String? organization, bool? isDeveloper}) {
    return UserRoleInfo(
      role: role ?? this.role,
      organization: organization ?? this.organization,
      isDeveloper: isDeveloper ?? this.isDeveloper,
    );
  }
}

/// Centralizes the role-resolution cascade and the "self-heal" write-back
/// (previously `DashboardScreen._updateUserRoleAndOrganization`) in one
/// place instead of 4 duplicated implementations.
class RoleService {
  RoleService({FirebaseFirestore? firestore, Logger? logger})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _logger = logger ?? Logger(printer: PrettyPrinter());

  final FirebaseFirestore _firestore;
  final Logger _logger;

  /// Live role/organization for [uid]. Any Admin/Technician/Developer/Users
  /// collection write for this uid propagates automatically, matching the
  /// previous multi-listener behavior in dashboard_screen.dart.
  ///
  /// Deliberately does NOT self-heal on every emission: an assign/remove
  /// batch writes two documents (a role collection + `Users/{uid}`) that are
  /// two independent Firestore listeners here, so they can arrive out of
  /// order. Self-healing on each transient combination previously caused a
  /// write-back-into-own-input feedback loop (the write re-triggers the
  /// `Users` listener, re-triggering this stream, potentially self-healing
  /// again) that showed up as continuous role flicker, including cases where
  /// it settled on a stale/reverted role. `resolveOnce` remains the only
  /// self-heal path. `debounceTime` lets a batch's two listener updates
  /// settle before resolving; `distinct` skips re-emitting an unchanged role.
  Stream<UserRoleInfo> watch(String uid) {
    final admins = _firestore.collection('Admins').doc(uid).snapshots();
    final developers = _firestore.collection('Developers').doc(uid).snapshots();
    final technicians = _firestore.collection('Technicians').doc(uid).snapshots();
    final users = _firestore.collection('Users').doc(uid).snapshots();

    return Rx.combineLatest4<DocumentSnapshot, DocumentSnapshot, DocumentSnapshot,
        DocumentSnapshot, UserRoleInfo>(
      admins,
      developers,
      technicians,
      users,
      (adminDoc, developerDoc, technicianDoc, userDoc) => _resolve(
        adminDoc: adminDoc,
        developerDoc: developerDoc,
        technicianDoc: technicianDoc,
        userDoc: userDoc,
      ),
    )
        .debounceTime(const Duration(milliseconds: 300))
        .distinct((prev, next) =>
            prev.role == next.role &&
            prev.organization == next.organization &&
            prev.isDeveloper == next.isDeveloper);
  }

  /// One-shot resolution (used right after sign-in/sign-up, before the
  /// live dashboard listener takes over).
  Future<UserRoleInfo> resolveOnce(String uid) async {
    final adminDoc = await _firestore.collection('Admins').doc(uid).get();
    final developerDoc = await _firestore.collection('Developers').doc(uid).get();
    final technicianDoc = await _firestore.collection('Technicians').doc(uid).get();
    final userDoc = await _firestore.collection('Users').doc(uid).get();
    final info = _resolve(
      adminDoc: adminDoc,
      developerDoc: developerDoc,
      technicianDoc: technicianDoc,
      userDoc: userDoc,
    );
    await _selfHeal(uid, info);
    return info;
  }

  /// True only for callers present in the `Admins` collection — used to
  /// gate technician-role assignment (role_assignment_screen.dart).
  Future<bool> isAdmin(String uid) async {
    final adminDoc = await _firestore.collection('Admins').doc(uid).get();
    return adminDoc.exists;
  }

  Future<String?> adminOrganization(String uid) async {
    final adminDoc = await _firestore.collection('Admins').doc(uid).get();
    if (!adminDoc.exists) return null;
    return adminDoc.data()?['organization'] as String? ?? '-';
  }

  UserRoleInfo _resolve({
    required DocumentSnapshot adminDoc,
    required DocumentSnapshot developerDoc,
    required DocumentSnapshot technicianDoc,
    required DocumentSnapshot userDoc,
  }) {
    if (adminDoc.exists) {
      final data = adminDoc.data() as Map<String, dynamic>?;
      return UserRoleInfo(role: UserRole.admin, organization: data?['organization'] ?? '-');
    }
    if (developerDoc.exists) {
      // Developers are treated as Technicians of the internal org.
      return const UserRoleInfo(
        role: UserRole.technician,
        organization: 'JV Almacis',
        isDeveloper: true,
      );
    }
    if (technicianDoc.exists) {
      final data = technicianDoc.data() as Map<String, dynamic>?;
      return UserRoleInfo(
        role: UserRole.technician,
        organization: data?['organization'] ?? '-',
      );
    }
    if (userDoc.exists) {
      final data = userDoc.data() as Map<String, dynamic>?;
      return UserRoleInfo(
        role: UserRoleX.fromString(data?['role'] as String?),
        organization: data?['organization'] ?? '-',
      );
    }
    return const UserRoleInfo(role: UserRole.user, organization: '-');
  }

  /// Writes the resolved role/organization back onto `Users/{uid}` when it
  /// has drifted (e.g. an Admin doc was added but Users wasn't updated
  /// yet). Firestore-side denormalization only — no behavior change from
  /// the previous dashboard_screen.dart implementation.
  Future<void> _selfHeal(String uid, UserRoleInfo info) async {
    try {
      final userDoc = await _firestore.collection('Users').doc(uid).get();
      if (!userDoc.exists) return;
      final data = userDoc.data() as Map<String, dynamic>;
      final driftedRole = data['role'] != info.roleLabel;
      final driftedOrg = data['organization'] == null || data['organization'] != info.organization;
      if (!driftedRole && !driftedOrg) return;

      await _firestore.collection('Users').doc(uid).set(
        {'role': info.roleLabel, 'organization': info.organization},
        SetOptions(merge: true),
      );
      _logger.i('Self-healed Users/$uid: role=${info.roleLabel}, organization=${info.organization}');
    } catch (e) {
      _logger.e('RoleService self-heal failed for $uid: $e');
    }
  }
}

final roleServiceProvider = Provider<RoleService>((ref) => RoleService());

/// Live role info for whoever is currently signed in. `unassigned`/`'-'`
/// organization when signed out.
final currentUserRoleProvider = StreamProvider<UserRoleInfo>((ref) {
  final authState = ref.watch(authStateProvider);
  final roleService = ref.watch(roleServiceProvider);

  return authState.when(
    data: (user) {
      if (user == null) return Stream.value(UserRoleInfo.signedOut());
      return roleService.watch(user.uid);
    },
    loading: () => const Stream<UserRoleInfo>.empty(),
    error: (e, st) => Stream.value(UserRoleInfo.signedOut()),
  );
});
