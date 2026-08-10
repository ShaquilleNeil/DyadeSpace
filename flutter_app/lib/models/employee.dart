import 'package:cloud_firestore/cloud_firestore.dart';

class Employee {
  final String id; // Firebase Auth uid, also the employees/{id} doc id
  final String firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String role; // "manager" | "employee"
  final String? avatarUrl;
  final DateTime? createdAt;

  const Employee({
    required this.id,
    required this.firstName,
    this.lastName,
    this.phone,
    this.email,
    required this.role,
    this.avatarUrl,
    this.createdAt,
  });

  bool get isManager => role == 'manager';

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
      role: data['role'] as String? ?? 'employee',
      avatarUrl: data['avatarUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
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
    };
  }

  Employee copyWith({
    String? firstName,
    String? lastName,
    String? phone,
    String? email,
    String? role,
    String? avatarUrl,
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
    );
  }
}
