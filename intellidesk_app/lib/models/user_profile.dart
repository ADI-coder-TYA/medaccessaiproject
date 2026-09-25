import 'user_role.dart';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? studentId;
  final UserRole role;
  final String institutionId;
  final String? institutionName;
  final String? department;
  final String? avatarUrl;
  final String? token;

  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.studentId,
    required this.role,
    required this.institutionId,
    this.institutionName,
    this.department,
    this.avatarUrl,
    this.token,
  });

  String get fullName => name;
  String get institutionDisplayName =>
      (institutionName != null && institutionName!.isNotEmpty)
          ? institutionName!
          : institutionId;
  String get patientId => (studentId != null && studentId!.isNotEmpty) ? studentId! : id;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'User',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      studentId: json['studentId']?.toString() ?? json['student_id']?.toString(),
      role: UserRole.fromString(json['role']?.toString()),
      institutionId: json['institutionId']?.toString() ?? json['institution_id']?.toString() ?? 'edu-admin-123',
      institutionName: json['institutionName']?.toString() ?? json['institution_name']?.toString(),
      department: json['department']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      token: json['token']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'studentId': studentId,
      'role': role.code,
      'institutionId': institutionId,
      if (institutionName != null) 'institutionName': institutionName,
      'department': department,
      'avatarUrl': avatarUrl,
      'token': token,
    };
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? studentId,
    UserRole? role,
    String? institutionId,
    String? institutionName,
    String? department,
    String? avatarUrl,
    String? token,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      studentId: studentId ?? this.studentId,
      role: role ?? this.role,
      institutionId: institutionId ?? this.institutionId,
      institutionName: institutionName ?? this.institutionName,
      department: department ?? this.department,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      token: token ?? this.token,
    );
  }
}
