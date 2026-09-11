import 'package:cloud_firestore/cloud_firestore.dart';

class EmployeeRole {
  static const admin = 'admin';
  static const manager = 'manager';
  static const employee = 'employee';
  static const client = 'client';

  static const all = [admin, manager, employee, client];

  static String label(String role) {
    switch (role) {
      case admin:
        return 'Admin';
      case manager:
        return 'Manager';
      case employee:
        return 'Worker';
      case client:
        return 'Client';
      default:
        return role;
    }
  }
}

class Employee {
  final String id; // Firebase Auth uid, also the employees/{id} doc id
  final String firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String role; // "admin" | "manager" | "employee" | "client"
  final String? avatarUrl;
  final DateTime? createdAt;
  // Denormalized mirror of every project's `memberIds` this employee is on —
  // lets manager-scoping queries/rules filter without scanning all projects.
  final List<String> projectIds;
  final List<String> fcmTokens;

  const Employee({
    required this.id,
    required this.firstName,
    this.lastName,
    this.phone,
    this.email,
    required this.role,
    this.avatarUrl,
    this.createdAt,
    this.projectIds = const [],
    this.fcmTokens = const [],
  });

  bool get isAdmin => role == EmployeeRole.admin;
  bool get isManager => role == EmployeeRole.manager;
  bool get isClient => role == EmployeeRole.client;

  String get fullName =>
      [firstName, lastName].where((s) => s != null && s.isNotEmpty).join(' ');

  factory Employee.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Employee(
      id: doc.id,
      firstName: data['firstName'] as String? ?? '',
      lastName: data['lastName'] as String?,
      phone: data['phone'] as String?,
      email: data['email'] as String?,
      role: data['role'] as String? ?? EmployeeRole.employee,
      avatarUrl: data['avatarUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      projectIds: List<String>.from(data['projectIds'] as List? ?? const []),
      fcmTokens: List<String>.from(data['fcmTokens'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'firstName': firstName,
      'lastName': lastName,
      'phone': phone,
      'email': email,
      'role': role,
      'avatarUrl': avatarUrl,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'projectIds': projectIds,
      'fcmTokens': fcmTokens,
    };
  }

  Employee copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? role,
    String? avatarUrl,
    List<String>? projectIds,
  }) {
    return Employee(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      role: role ?? this.role,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      projectIds: projectIds ?? this.projectIds,
      fcmTokens: fcmTokens,
    );
  }
}
