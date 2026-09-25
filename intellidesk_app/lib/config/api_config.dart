import 'dart:io' show Platform, Socket;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

/// Central API configuration.
/// Dynamically probes between adb reverse (127.0.0.1), Android emulator (10.0.2.2),
/// and local Wi-Fi LAN for zero-config connectivity across physical devices and emulators.
class ApiConfig {
  ApiConfig._(); // Prevent instantiation

  /// Local machine LAN IP address for physical device Wi-Fi debugging
  static const String serverIp = '172.23.223.214';
  static const String serverPort = '3000';
  static String? _detectedHost;
  static String? customHost;

  /// Fast TCP probe to detect reachable backend address on Android
  static Future<String> initHost() async {
    if (customHost != null && customHost!.isNotEmpty) {
      _detectedHost = customHost;
      return _detectedHost!;
    }
    if (kIsWeb) {
      _detectedHost = 'http://localhost:$serverPort';
      return _detectedHost!;
    }
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      _detectedHost = 'http://127.0.0.1:$serverPort';
      return _detectedHost!;
    }
    if (Platform.isAndroid) {
      final candidates = [
        '127.0.0.1', // adb reverse (USB physical device or emulator with port reverse)
        '10.0.2.2',  // standard Android emulator router loopback
        serverIp,    // host machine local Wi-Fi IP
      ];

      for (final ip in candidates) {
        try {
          final socket = await Socket.connect(
            ip,
            int.parse(serverPort),
            timeout: const Duration(milliseconds: 700),
          );
          socket.destroy();
          _detectedHost = 'http://$ip:$serverPort';
          debugPrint('🌐 [ApiConfig] Auto-detected backend at: $_detectedHost');
          return _detectedHost!;
        } catch (_) {}
      }
    }
    _detectedHost = 'http://127.0.0.1:$serverPort';
    return _detectedHost!;
  }

  static String get host {
    if (customHost != null && customHost!.isNotEmpty) return customHost!;
    if (_detectedHost != null) return _detectedHost!;
    if (kIsWeb) return 'http://localhost:$serverPort';
    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return 'http://127.0.0.1:$serverPort';
    }
    if (Platform.isAndroid) {
      // Default to 127.0.0.1 for adb reverse, fallback to serverIp
      return 'http://127.0.0.1:$serverPort';
    }
    return 'http://$serverIp:$serverPort';
  }

  static String get baseUrl => '$host/api/v1';

  static String get socketUrl => host;

  /// Safely resolves full API URI without accidental duplicate prefixes or slash collisions
  static Uri resolveUri(String path, [Map<String, dynamic>? queryParameters]) {
    String cleanPath = path.trim();
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://')) {
      final u = Uri.parse(cleanPath);
      return queryParameters != null ? u.replace(queryParameters: queryParameters) : u;
    }
    if (cleanPath.startsWith('/api/v1/')) {
      cleanPath = cleanPath.substring('/api/v1/'.length);
    } else if (cleanPath.startsWith('api/v1/')) {
      cleanPath = cleanPath.substring('api/v1/'.length);
    } else if (cleanPath.startsWith('/')) {
      cleanPath = cleanPath.substring(1);
    }
    final url = '$baseUrl/$cleanPath';
    final u = Uri.parse(url);
    return queryParameters != null ? u.replace(queryParameters: queryParameters) : u;
  }

  static const String supabaseUrl = 'https://iwxdsspvsenlhiigkakw.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml3eGRzc3B2c2VubGhpaWdrYWt3Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NjE4ODUwMywiZXhwIjoyMTAxNzY0NTAzfQ.GVNgQP9GvaIXJaKfND3r9TXwWQS9vkICdrcCWsF3Lws';

  static String institutionId = 'inst-001';
  static String? currentInstitutionId;
  static String? currentInstitutionName;

  static String get activeInstitutionId =>
      (currentInstitutionId != null && currentInstitutionId!.isNotEmpty)
          ? currentInstitutionId!
          : institutionId;

  static String get activeInstitutionName =>
      (currentInstitutionName != null && currentInstitutionName!.isNotEmpty)
          ? currentInstitutionName!
          : activeInstitutionId;

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
