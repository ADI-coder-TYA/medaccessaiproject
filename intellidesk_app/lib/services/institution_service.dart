import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Service to resolve and cache institutional metadata for multi-tenant clinical routing.
class InstitutionService {
  InstitutionService._();

  static final Map<String, String> _cache = {};
  static final Map<String, String> _adminCache = {};

  /// Fetches the authentic institution name from Supabase public.institutions table or backend API.
  static Future<String> getInstitutionName(String? institutionId) async {
    final cleanId = (institutionId ?? ApiConfig.activeInstitutionId).trim();
    if (cleanId.isEmpty) return 'Healthcare Institution';

    if (_cache.containsKey(cleanId)) {
      return _cache[cleanId]!;
    }

    // 1. Query Backend API
    try {
      final endpoint = ApiConfig.resolveUri('auth/institution/$cleanId');
      final response = await http
          .get(endpoint, headers: ApiConfig.patientHeaders)
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final inst = data['institution'];
        final name = inst?['name']?.toString().trim();
        final admin = inst?['administratorName']?.toString().trim();
        if (admin != null && admin.isNotEmpty) {
          _adminCache[cleanId] = admin;
        }
        if (name != null && name.isNotEmpty) {
          _cache[cleanId] = name;
          return name;
        }
      }
    } catch (_) {}

    // 2. Direct Supabase REST fallback on public.institutions table
    try {
      final supabaseUri = Uri.parse(
        '${ApiConfig.supabaseUrl}/rest/v1/institutions?id=eq.$cleanId&select=id,name',
      );
      final response = await http.get(
        supabaseUri,
        headers: {
          'apikey': ApiConfig.supabaseAnonKey,
          'Authorization': 'Bearer ${ApiConfig.supabaseAnonKey}',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (list is List && list.isNotEmpty) {
          final name = list[0]['name']?.toString().trim();
          if (name != null && name.isNotEmpty) {
            _cache[cleanId] = name;
            return name;
          }
        }
      }
    } catch (_) {}

    // If no row exists or lookup fails, return the clean institution ID as fallback
    _cache[cleanId] = cleanId;
    return cleanId;
  }

  /// Fetches the designated clinical administrator for the institution (defaults to Dr. Aditya).
  static Future<String> getInstitutionAdministrator(String? institutionId) async {
    final cleanId = (institutionId ?? ApiConfig.activeInstitutionId).trim();
    if (cleanId.isEmpty) return 'Dr. Aditya';

    if (_adminCache.containsKey(cleanId)) {
      return _adminCache[cleanId]!;
    }

    // 1. Query Backend API
    try {
      final endpoint = ApiConfig.resolveUri('auth/institution/$cleanId');
      final response = await http
          .get(endpoint, headers: ApiConfig.patientHeaders)
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final inst = data['institution'];
        final admin = inst?['administratorName']?.toString().trim();
        final name = inst?['name']?.toString().trim();
        if (name != null && name.isNotEmpty) {
          _cache[cleanId] = name;
        }
        if (admin != null && admin.isNotEmpty) {
          _adminCache[cleanId] = admin;
          return admin;
        }
      }
    } catch (_) {}

    // 2. Direct Supabase REST fallback on public.profiles table
    try {
      final supabaseUri = Uri.parse(
        '${ApiConfig.supabaseUrl}/rest/v1/profiles?institution_id=eq.$cleanId&role=eq.CLINICAL_ADMIN&select=full_name,name',
      );
      final response = await http.get(
        supabaseUri,
        headers: {
          'apikey': ApiConfig.supabaseAnonKey,
          'Authorization': 'Bearer ${ApiConfig.supabaseAnonKey}',
        },
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body);
        if (list is List && list.isNotEmpty) {
          final admin = (list[0]['full_name'] ?? list[0]['name'])?.toString().trim();
          if (admin != null && admin.isNotEmpty) {
            _adminCache[cleanId] = admin;
            return admin;
          }
        }
      }
    } catch (_) {}

    _adminCache[cleanId] = 'Dr. Aditya';
    return 'Dr. Aditya';
  }

  /// Manually seed or update cache
  static void cacheInstitutionName(String institutionId, String name) {
    if (institutionId.isNotEmpty && name.isNotEmpty) {
      _cache[institutionId.trim()] = name.trim();
    }
  }

  /// Manually seed or update administrator cache
  static void cacheInstitutionAdministrator(String institutionId, String admin) {
    if (institutionId.isNotEmpty && admin.isNotEmpty) {
      _adminCache[institutionId.trim()] = admin.trim();
    }
  }
}
