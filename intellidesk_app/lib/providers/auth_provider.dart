import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_profile.dart';
import '../models/user_role.dart';
import '../services/api_service.dart';
import '../services/institution_service.dart';

class AuthProvider extends ChangeNotifier {
  UserProfile? _user;
  bool _isLoading = false;
  String? _errorMessage;
  final ApiService _apiService = ApiService();

  static const String _sessionKey = 'intellidesk_auth_session';

  UserProfile? get user => _user;
  UserProfile? get userProfile => _user;
  UserRole get role => _user?.role ?? UserRole.student;
  String? get token => _user?.token;

  bool get isAuthenticated => _user != null;
  bool get isPatient => _user?.role.isPatient ?? true;
  bool get isStudent => isPatient;
  bool get isAdmin => _user?.role == UserRole.admin;
  bool get isAuditor => _user?.role == UserRole.auditor;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  AuthProvider() {
    initSession();
  }

  /// Initialize session from local storage if previously logged in.
  Future<void> initSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedData = prefs.getString(_sessionKey);
      if (savedData != null) {
        final decoded = json.decode(savedData) as Map<String, dynamic>;
        _user = UserProfile.fromJson(decoded);
        _syncApiConfig();
        notifyListeners();
        // Asynchronously refresh live tenant metadata from backend
        refreshProfile();
      }
    } catch (e) {
      debugPrint('Error loading saved auth session: $e');
    }
  }

  /// Refresh user profile and tenant institution from backend
  Future<void> refreshProfile() async {
    if (_user == null && ApiConfig.userEmail == null && ApiConfig.userPhone == null) return;
    try {
      final email = _user?.email ?? ApiConfig.userEmail;
      final phone = _user?.phone ?? ApiConfig.userPhone;
      final queryParams = <String, String>{
        if (email != null && email.isNotEmpty) 'email': email,
        if (phone != null && phone.isNotEmpty) 'phone': phone,
      };
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/me').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);
      final res = await http.get(uri, headers: ApiConfig.patientHeaders).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = json.decode(res.body) as Map<String, dynamic>;
        if (data['success'] == true && data['user'] != null) {
          final userData = Map<String, dynamic>.from(data['user']);
          _user = UserProfile.fromJson(userData);
          await _persistSession();
          _syncApiConfig();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Error refreshing user profile: $e');
    }
  }

  void _syncApiConfig() {
    ApiConfig.authToken = _user?.token;
    ApiConfig.userRole = _user?.role.code;
    ApiConfig.userEmail = _user?.email;
    ApiConfig.userName = _user?.name;
    ApiConfig.userPhone = _user?.phone;
    ApiConfig.userId = _user?.id;
    ApiConfig.userDepartment = _user?.department;
    final instId = _user?.institutionId;
    if (instId != null && instId.isNotEmpty) {
      ApiConfig.institutionId = instId;
      ApiConfig.currentInstitutionId = instId;
    } else {
      ApiConfig.institutionId = 'inst-001';
      ApiConfig.currentInstitutionId = 'inst-001';
    }
    ApiConfig.currentInstitutionName = _user?.institutionName;
  }

  /// Perform authentication login via backend API or fallback to mock profile
  Future<bool> login({
    required String email,
    required String password,
    required UserRole role,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _apiService.login(
        email: email,
        password: password,
        role: role.code,
      );

      if (res['success'] == true && res['user'] != null) {
        final userData = Map<String, dynamic>.from(res['user']);
        if (res['token'] != null) {
          userData['token'] = res['token'];
        }
        _user = UserProfile.fromJson(userData);

        // Dynamically resolve and cache authentic institution name from DB
        final effectiveInstId = _user!.institutionId;
        final resolvedName = await InstitutionService.getInstitutionName(effectiveInstId);
        _user = _user!.copyWith(institutionName: resolvedName);
        ApiConfig.currentInstitutionName = resolvedName;

        await _persistSession();
        _syncApiConfig();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _isLoading = false;
        _errorMessage = res['error']?.toString() ?? 'Invalid credentials or patient not registered.';
        notifyListeners();
        return false;
      }
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  /// One-tap demo login as Alex Rivera (Patient / Member)
  Future<void> loginAsPatient() async {
    final success = await login(
      email: 'alex.rivera@campushealth.edu',
      password: 'Patient@123',
      role: UserRole.student,
    );
    if (!success) {
      _user = const UserProfile(
        id: 'usr_pat_001',
        name: 'Alex Rivera',
        email: 'alex.rivera@campushealth.edu',
        studentId: 'PAT-2026-001',
        role: UserRole.patient,
        department: 'General Health & Outpatient Care',
        institutionId: 'inst-001',
        phone: '+91 98765 43210',
        avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150',
        token: 'jwt_mock_token_patient_alex_rivera',
      );
      await _persistSession();
      _syncApiConfig();
      notifyListeners();
    }
  }

  /// Backward compatibility alias
  Future<void> loginAsStudent() => loginAsPatient();

  /// One-tap demo login as Dr. Sarah Chen (Chief Medical Officer)
  Future<void> loginAsAdmin() async {
    final success = await login(
      email: 'admin@campushealth.edu',
      password: 'Patient@123',
      role: UserRole.admin,
    );
    if (!success) {
      _user = const UserProfile(
        id: 'usr_adm_999',
        name: 'Dr. Sarah Chen, MD',
        email: 'admin@campushealth.edu',
        role: UserRole.admin,
        department: 'Clinical Triage & Emergency Copay Desk',
        institutionId: 'inst-001',
        phone: '+91 98111 22334',
        avatarUrl: 'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=150',
        token: 'jwt_mock_token_admin_sarah_chen',
      );
      await _persistSession();
      _syncApiConfig();
      notifyListeners();
    }
  }

  /// Register new Healthcare Facility Admin and batch-import patient roster
  Future<bool> signupAdminWithRoster({
    required String instituteName,
    required String adminName,
    required String adminEmail,
    required String password,
    required String institutionCode,
    String? department,
    String? phone,
    double? initialFundPool,
    required String defaultStudentPassword,
    required List<Map<String, String>> rosterStudents,
  }) async {
    return registerInstitution(
      instituteName: instituteName,
      adminName: adminName,
      adminEmail: adminEmail,
      password: password,
      institutionId: institutionCode,
      department: department,
      phone: phone,
      initialFundPool: initialFundPool,
      defaultStudentPassword: defaultStudentPassword,
      students: rosterStudents.map((s) => Map<String, dynamic>.from(s)).toList(),
    );
  }

  /// Register new Institution Admin and batch-import student roster
  Future<bool> registerInstitution({
    required String instituteName,
    required String adminName,
    required String adminEmail,
    required String password,
    String defaultStudentPassword = 'Patient@123',
    required String institutionId,
    String? department,
    String? phone,
    double? initialFundPool,
    required List<Map<String, dynamic>> students,
    String? csvContent,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      try {
        final res = await _apiService.registerInstitution(
          instituteName: instituteName,
          adminName: adminName,
          adminEmail: adminEmail,
          password: password,
          defaultStudentPassword: defaultStudentPassword,
          institutionId: institutionId,
          department: department,
          phone: phone,
          initialFundPool: initialFundPool,
          students: students,
          csvContent: csvContent,
        );

        if (res['success'] == true && res['admin'] != null) {
          final adminData = Map<String, dynamic>.from(res['admin']);
          _user = UserProfile.fromJson(adminData);
        } else {
          _createFallbackAdmin(instituteName, adminName, adminEmail, institutionId, department, phone);
        }
      } catch (backendError) {
        debugPrint('Backend registration error, fallback to local registration: $backendError');
        _createFallbackAdmin(instituteName, adminName, adminEmail, institutionId, department, phone);
      }

      await _persistSession();
      _syncApiConfig();
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Institution Registration Failed: ${e.toString()}';
      notifyListeners();
      return false;
    }
  }

  /// Change password for logged in user
  Future<bool> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    if (_user == null) return false;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _apiService.changePassword(
        email: _user!.email,
        oldPassword: oldPassword,
        newPassword: newPassword,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isLoading = false;
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      notifyListeners();
      return false;
    }
  }

  void _createFallbackAdmin(String instituteName, String adminName, String adminEmail, String instId, [String? department, String? phone]) {
    _user = UserProfile(
      id: 'usr_adm_${DateTime.now().millisecondsSinceEpoch}',
      name: adminName.isNotEmpty ? adminName : 'Chief Medical Officer',
      email: adminEmail.isNotEmpty ? adminEmail : 'admin@campushealth.edu',
      role: UserRole.admin,
      department: department ?? '$instituteName Clinical Triage',
      institutionId: instId,
      phone: phone ?? '+91 98111 22334',
      token: 'jwt_mock_token_admin_$instId',
    );
  }

  Future<void> signOut() => logout();

  /// Logout and clear saved authentication session
  Future<void> logout() async {
    _user = null;
    _errorMessage = null;
    _syncApiConfig();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
    } catch (e) {
      debugPrint('Error removing saved session: $e');
    }
    notifyListeners();
  }

  Future<void> _persistSession() async {
    if (_user == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, json.encode(_user!.toJson()));
    } catch (e) {
      debugPrint('Error persisting session: $e');
    }
  }
}
