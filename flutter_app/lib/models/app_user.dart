import 'package:cloud_firestore/cloud_firestore.dart';

/// Roles in DyadeSpace. Admin = Sam, Manager = Alex,
/// Worker = crew (Chris, Dan, Eli, Finn), Delivery = Drew.
enum UserRole { admin, manager, worker, delivery }

UserRole userRoleFromString(String? value) {
  return UserRole.values.firstWhere(
    (r) => r.name == value,
    orElse: () => UserRole.worker,
  );
}

class AppUser {
  final String id;
  final String name;
  final String email;
  final String phone;
  final UserRole role;
  final bool active;

  /// Preferred app language: 'en' or 'fr'.
  final String language;

  /// Profile photo download URL, if the user set one.
  /// Null when no photo was ever set.
  final String? photoUrl;

  /// Notification prefs, by type key: 'taskAssigned',
  /// 'clockInOut', 'chatMessages', 'eodReport'. A missing key
  /// (or a missing map) means ON — everything is on by
  /// default, and the Settings screen only ever writes
  /// explicit offs.
  final Map<String, bool> notifPrefs;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    required this.role,
    this.active = true,
    this.language = 'en',
    this.photoUrl,
    this.notifPrefs = const {},
  });

  /// True unless the user explicitly turned this type off.
  bool notifEnabled(String key) => notifPrefs[key] ?? true;

  bool get isAdminOrManager =>
      role == UserRole.admin || role == UserRole.manager;

  factory AppUser.fromFirestore(DocumentSnapshot doc) {
    return AppUser.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      role: userRoleFromString(map['role'] as String?),
      active: map['active'] as bool? ?? true,
      language: map['language'] as String? ?? 'en',
      photoUrl: map['photoUrl'] as String?,
      notifPrefs: (map['notifPrefs'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, v == true)),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'role': role.name,
      'active': active,
      'language': language,
      'photoUrl': photoUrl,
      'notifPrefs': notifPrefs,
    };
  }
}
