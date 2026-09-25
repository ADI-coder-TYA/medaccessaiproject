import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Service to resolve and cache institutional metadata for multi-tenant clinical routing.
class InstitutionService {
  InstitutionService._();

  static final Map<String, String> _cache = {};

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
        final name = data['institution']?['name']?.toString().trim();
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

  /// Manually seed or update cache
  static void cacheInstitutionName(String institutionId, String name) {
    if (institutionId.isNotEmpty && name.isNotEmpty) {
      _cache[institutionId.trim()] = name.trim();
    }
  }
}
