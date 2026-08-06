import 'package:cloud_firestore/cloud_firestore.dart';

/// Typed role used by app logic (menus, route guards, provider state).
///
/// Firestore itself still stores role as a free-form string across the
/// `Admins`/`Developers`/`Technicians`/`Users` collections (see
/// `RoleService` in lib/providers/auth_providers.dart) — this enum is only
/// how the app *reasons* about that value once read. No Firestore field
/// names or stored string values change.
enum UserRole { admin, technician, user, unassigned }

extension UserRoleX on UserRole {
  /// Matches the exact strings already stored/compared throughout the app
  /// (e.g. dashboard_screen.dart, responsive_screen_wrapper.dart) so
  /// existing users keep their current role with no data migration.
  String get label {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.technician:
        return 'Technician';
      case UserRole.user:
        return 'User';
      case UserRole.unassigned:
        return '-';
    }
  }

  static UserRole fromString(String? value) {
    switch (value) {
      case 'Admin':
        return UserRole.admin;
      case 'Technician':
        return UserRole.technician;
      case '-':
      case null:
        return UserRole.unassigned;
      default:
        return UserRole.user;
    }
  }
}

class UserModel {
  final String id;
  final String username;
  final String email;
  final DateTime createdAt;
  final String role;
  final String organization;

  UserModel({
    required this.id,
    required this.username,
    required this.email,
    required this.createdAt,
    required this.role,
    required this.organization,
  });

  UserRole get roleEnum => UserRoleX.fromString(role);

  // Convert UserModel to Firestore-compatible map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'createdAt': createdAt,
      'role': role,
      'organization': organization,
    };
  }

  // Create UserModel from Firestore document
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      username: map['username'] ?? '',
      email: map['email'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      role: map['role'] ?? '-',
      organization: map['organization'] ?? '-',
    );
  }
}
