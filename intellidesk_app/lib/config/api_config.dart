import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Central API configuration.
/// On Android emulators, `localhost` resolves to the emulator device itself,
/// not the host machine. Use `10.0.2.2` as the host instead.
class ApiConfig {
  ApiConfig._(); // Prevent instantiation

  /// Local machine LAN IP address for physical device debugging
  static const String serverIp = '172.22.14.64';
  static const String serverPort = '3000';

  static String get host {
    if (kIsWeb) return 'http://localhost:$serverPort';
    return 'http://$serverIp:$serverPort';
  }

  static String get baseUrl => '$host/api/v1';

  static String get socketUrl => host;

  static const String supabaseUrl = 'https://iwxdsspvsenlhiigkakw.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3eGRzc3B2c2VubGhpaWdrYWt3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NjE4ODUwMywiZXhwIjoyMTAxNzY0NTAzfQ.GVNgQP9GvaIXJaKfND3r9TXwWQS9vkICdrcCWsF3Lws';

  static String institutionId = 'inst-001';
  static String? currentInstitutionId;

  static String get activeInstitutionId =>
      (currentInstitutionId != null && currentInstitutionId!.isNotEmpty)
          ? currentInstitutionId!
          : institutionId;

  // Demo fallback credentials
  static const String defaultAdminToken = 'jwt_mock_token_admin_sarah_chen';
  static const String defaultAdminRole = 'ADMIN';

  // Dynamic session credentials synchronized from AuthProvider
  static String? authToken;
  static String? userRole;
  static String? userEmail;
  static String? userName;
  static String? userPhone;
  static String? userId;
  static String? userDepartment;
  static String preferredContactChannel = 'Email';
  static String selectedLanguage = 'English';

  /// Returns standard headers for patient / member requests
  static Map<String, String> get patientHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-institution-id': activeInstitutionId,
      'x-user-role': userRole ?? 'PATIENT',
      if (authToken != null) 'Authorization': 'Bearer $authToken',
    };
    if (userEmail != null) headers['x-user-email'] = userEmail!;
    if (userName != null) headers['x-user-name'] = userName!;
    return headers;
  }

  /// Backward compatibility alias
  static Map<String, String> get studentHeaders => patientHeaders;

  /// Returns standard headers for admin JSON API requests
  static Map<String, String> get adminHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'x-institution-id': activeInstitutionId,
      'x-user-role': userRole ?? defaultAdminRole,
      'Authorization': 'Bearer ${authToken ?? defaultAdminToken}',
    };
    if (userEmail != null) {
      headers['x-user-email'] = userEmail!;
    }
    return headers;
  }

  /// Returns standard headers for admin requests without Content-Type (GET, DELETE, Multipart)
  static Map<String, String> get adminAuthHeaders {
    final headers = <String, String>{
      'x-institution-id': activeInstitutionId,
      'x-user-role': userRole ?? defaultAdminRole,
      'Authorization': 'Bearer ${authToken ?? defaultAdminToken}',
    };
    if (userEmail != null) {
      headers['x-user-email'] = userEmail!;
    }
    return headers;
  }
}
