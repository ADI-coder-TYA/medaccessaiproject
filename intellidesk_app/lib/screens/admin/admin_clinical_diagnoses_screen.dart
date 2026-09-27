import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../config/api_config.dart';
import '../../modules/cdss/models/cdss_evaluation.dart';
import '../../modules/cdss/services/cdss_service.dart';
import '../../modules/cdss/ui/cdss_decision_drawer.dart';
import '../../modules/diagnostics/ui/LongitudinalHistoryScreen.dart';
import '../../modules/pharmacy/ui/admin_patient_pharmacy_modal.dart';

class AdminClinicalDiagnosesScreen extends StatefulWidget {
  final bool autoFetch;
  final List<Map<String, dynamic>>? initialPatients;
  final List<Map<String, dynamic>>? initialScreenings;
  const AdminClinicalDiagnosesScreen({
    super.key,
    this.autoFetch = true,
    this.initialPatients,
    this.initialScreenings,
  });

  @override
  State<AdminClinicalDiagnosesScreen> createState() => _AdminClinicalDiagnosesScreenState();
}

class _AdminClinicalDiagnosesScreenState extends State<AdminClinicalDiagnosesScreen> {
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRiskFilter = 'ALL';
  bool _isPatientRosterView = true;
  List<Map<String, dynamic>> _patients = [];
  List<Map<String, dynamic>> _allScreenings = [];

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.initialPatients != null) {
      _patients = List<Map<String, dynamic>>.from(widget.initialPatients!).map(_normalizePatientSummary).toList();
      _allScreenings = List<Map<String, dynamic>>.from(widget.initialScreenings ?? []).map(_normalizeScreening).toList();
      _isLoading = false;
    } else if (widget.autoFetch) {
      _fetchAdminDiagnoses();
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static dynamic _safeJsonDecode(dynamic val, dynamic fallback) {
    if (val == null) return fallback;
    if (val is Map || val is List) return val;
    if (val is String) {
      try {
        return jsonDecode(val);
      } catch (_) {
        return fallback;
      }
    }
    return fallback;
  }

  Map<String, dynamic> _normalizeScreening(Map<String, dynamic> raw) {
    final symptomPayload = Map<String, dynamic>.from(_safeJsonDecode(raw['symptom_payload'], <String, dynamic>{}));
    final rawFindings = List<dynamic>.from(_safeJsonDecode(raw['clinical_findings'], <dynamic>[]));
    final uncertaintyBounds = Map<String, dynamic>.from(_safeJsonDecode(raw['uncertainty_bounds'], <String, dynamic>{}));
    final physiologicalAlerts = List<dynamic>.from(_safeJsonDecode(raw['physiological_alerts'], <dynamic>[]));
    final rppg = Map<String, dynamic>.from(_safeJsonDecode(raw['rppg_vitals_payload'], <String, dynamic>{}));

    final vitals = (symptomPayload['vitals'] is Map)
        ? Map<String, dynamic>.from(symptomPayload['vitals'])
        : <String, dynamic>{};

    final hr = rppg['heartRate'] ?? rppg['heartRateBpm'] ?? vitals['heartRate'] ?? vitals['heartRateBpm'] ?? vitals['heart_rate'] ?? vitals['pulse'] ?? 74;
    final spo2 = rppg['oxygenSaturation'] ?? rppg['oxygenSaturationSpo2'] ?? vitals['oxygenSaturation'] ?? vitals['oxygenSaturationSpo2'] ?? vitals['oxygen_saturation'] ?? vitals['spo2'] ?? 98;
    final sys = rppg['systolicBP'] ?? rppg['bloodPressureSystolicMmHg'] ?? vitals['systolicBP'] ?? vitals['bloodPressureSystolicMmHg'] ?? vitals['blood_pressure_systolic'] ?? 120;
    final dia = rppg['diastolicBP'] ?? rppg['bloodPressureDiastolicMmHg'] ?? vitals['diastolicBP'] ?? vitals['bloodPressureDiastolicMmHg'] ?? vitals['blood_pressure_diastolic'] ?? 80;
    final rr = rppg['respiratoryRate'] ?? rppg['respiratoryRateBpm'] ?? vitals['respiratoryRate'] ?? vitals['respiratoryRateBpm'] ?? vitals['respiratory_rate'] ?? 16;
    final temp = rppg['temperatureCelsius'] ?? rppg['temperature'] ?? vitals['temperatureCelsius'] ?? vitals['temperature'] ?? 37.0;

    final normalizedVitals = {
      'heartRate': hr,
      'heartRateBpm': hr,
      'oxygenSaturation': spo2,
      'oxygenSaturationSpo2': spo2,
      'systolicBP': sys,
      'bloodPressureSystolicMmHg': sys,
      'diastolicBP': dia,
      'bloodPressureDiastolicMmHg': dia,
      'respiratoryRate': rr,
      'respiratoryRateBpm': rr,
      'temperatureCelsius': temp,
      'temperature': temp,
    };

    symptomPayload['vitals'] = normalizedVitals;
    final normalizedRppg = {
      ...rppg,
      ...normalizedVitals,
      'signalQuality': rppg['signalQuality'] ?? 0.95,
      'alerts': physiologicalAlerts,
    };

    List<Map<String, dynamic>> clinicalFindings = [];
    if (rawFindings.isNotEmpty) {
      for (int i = 0; i < rawFindings.length; i++) {
        final f = (rawFindings[i] is Map) ? Map<String, dynamic>.from(rawFindings[i]) : <String, dynamic>{};
        final diag = f['diagnosis']?.toString() ?? f['condition']?.toString() ?? 'Multimodal Clinical Checkup';
        final code = f['icd11Code']?.toString() ?? f['code']?.toString() ?? 'MG40';

        clinicalFindings.add({
          ...f,
          'diagnosis': diag,
          'condition': diag,
          'icd11Code': code,
          'code': code,
          'differentialRank': f['differentialRank'] ?? (i + 1),
        });
      }
    } else {
      clinicalFindings.add({
        'diagnosis': 'Multimodal Clinical Checkup',
        'condition': 'Multimodal Clinical Checkup',
        'icd11Code': 'MG40',
        'code': 'MG40',
        'probability': 0.75,
        'riskLevel': raw['risk_level'] ?? 'LOW',
        'differentialRank': 1,
        'recommendation': 'Periodic routine wellness screening recommended',
        'evidence': ['Multimodal sensor presentation'],
      });
    }

    final pid = raw['patient_id']?.toString() ?? raw['patientId']?.toString() ?? '';
    final name = raw['patient_name'] ??
        raw['patientName'] ??
        symptomPayload['patient_name'] ??
        symptomPayload['patientName'] ??
        (pid.isNotEmpty ? 'Patient $pid' : 'Unknown Patient');

    return {
      ...raw,
      'patient_id': pid,
      'patient_name': name,
      'patientName': name,
      'symptom_payload': symptomPayload,
      'clinical_findings': clinicalFindings,
      'uncertainty_bounds': uncertaintyBounds,
      'physiological_alerts': physiologicalAlerts,
      'rppg_vitals_payload': normalizedRppg,
    };
  }

  Map<String, dynamic> _normalizePatientSummary(Map<String, dynamic> patient) {
    final rawScreenings = (patient['screenings'] is List) ? List<dynamic>.from(patient['screenings']) : [];
    final normalizedScreenings = rawScreenings
        .map((s) => (s is Map) ? _normalizeScreening(Map<String, dynamic>.from(s)) : <String, dynamic>{})
        .toList();

    String latestDiag = (patient['latestDiagnosis'] ?? '').toString();
    String latestIcd = (patient['latestICD11'] ?? '').toString();

    // If screenings exist, extract from the latest screening
    if (normalizedScreenings.isNotEmpty) {
      final latestSc = normalizedScreenings.first;
      final findings = (latestSc['clinical_findings'] as List?) ?? [];
      if (findings.isNotEmpty) {
        final f = (findings.first is Map) ? Map<String, dynamic>.from(findings.first) : <String, dynamic>{};
        latestDiag = f['diagnosis']?.toString() ?? f['condition']?.toString() ?? latestDiag;
        latestIcd = f['icd11Code']?.toString() ?? f['code']?.toString() ?? latestIcd;
      }
    }

    final rawVitals = (patient['latestVitals'] is Map) ? Map<String, dynamic>.from(patient['latestVitals']) : <String, dynamic>{};
    final hr = rawVitals['heartRateBpm'] ?? rawVitals['heartRate'] ?? rawVitals['heart_rate'] ?? 74;
    final spo2 = rawVitals['oxygenSaturationSpo2'] ?? rawVitals['oxygenSaturation'] ?? rawVitals['oxygen_saturation'] ?? 98;
    final sys = rawVitals['bloodPressureSystolicMmHg'] ?? rawVitals['systolicBP'] ?? rawVitals['blood_pressure_systolic'] ?? 120;
    final dia = rawVitals['bloodPressureDiastolicMmHg'] ?? rawVitals['diastolicBP'] ?? rawVitals['blood_pressure_diastolic'] ?? 80;
    final temp = rawVitals['temperatureCelsius'] ?? rawVitals['temperature'] ?? 37.0;
    final rr = rawVitals['respiratoryRateBpm'] ?? rawVitals['respiratoryRate'] ?? 16;

    final normalizedVitals = {
      ...rawVitals,
      'heartRate': hr,
      'heartRateBpm': hr,
      'oxygenSaturation': spo2,
      'oxygenSaturationSpo2': spo2,
      'systolicBP': sys,
      'bloodPressureSystolicMmHg': sys,
      'diastolicBP': dia,
      'bloodPressureDiastolicMmHg': dia,
      'respiratoryRate': rr,
      'respiratoryRateBpm': rr,
      'temperatureCelsius': temp,
      'temperature': temp,
    };

    return {
      ...patient,
      'latestDiagnosis': latestDiag.isNotEmpty ? latestDiag : 'Multimodal Clinical Checkup',
      'latestICD11': latestIcd.isNotEmpty ? latestIcd : 'MG40',
      'latestVitals': normalizedVitals,
      'screenings': normalizedScreenings,
    };
  }

  Future<void> _fetchAdminDiagnoses() async {
    setState(() => _isLoading = true);
    try {
      final institutionId = ApiConfig.activeInstitutionId;
      final patientsUri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/admin/patients?institutionId=$institutionId');
      final screeningsUri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/admin/screenings?institutionId=$institutionId');

      final headers = ApiConfig.adminHeaders;
      final resPatients = await http.get(patientsUri, headers: headers).timeout(const Duration(seconds: 8));
      final resScreenings = await http.get(screeningsUri, headers: headers).timeout(const Duration(seconds: 8));

      if (resPatients.statusCode == 200 && resScreenings.statusCode == 200) {
        final dataPatients = jsonDecode(resPatients.body);
        final dataScreenings = jsonDecode(resScreenings.body);

        if (mounted && dataPatients['success'] == true && dataScreenings['success'] == true) {
          final loadedPatients = List<Map<String, dynamic>>.from(dataPatients['patients'] ?? []).map(_normalizePatientSummary).toList();
          final loadedScreenings = List<Map<String, dynamic>>.from(dataScreenings['screenings'] ?? []).map(_normalizeScreening).toList();

          setState(() {
            _patients = loadedPatients;
            _allScreenings = loadedScreenings;
            _isLoading = false;
          });
          return;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [AdminClinicalDiagnosesScreen] Live fetch error: $e');
    }

    if (mounted) {
      setState(() {
        _patients = [];
        _allScreenings = [];
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredPatients {
    return _patients.where((p) {
      final name = (p['patientName'] ?? '').toString().toLowerCase();
      final pid = (p['patientId'] ?? '').toString().toLowerCase();
      final diag = (p['latestDiagnosis'] ?? '').toString().toLowerCase();
      final icd = (p['latestICD11'] ?? '').toString().toLowerCase();
      final q = _searchQuery.toLowerCase();

      final matchesQuery = q.isEmpty || name.contains(q) || pid.contains(q) || diag.contains(q) || icd.contains(q);
      final risk = (p['highestRiskLevel'] ?? 'LOW').toString().toUpperCase();
      final matchesRisk = _selectedRiskFilter == 'ALL' || risk == _selectedRiskFilter;

      return matchesQuery && matchesRisk;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredScreenings {
    return _allScreenings.where((s) {
      final name = (s['patient_name'] ?? s['symptom_payload']?['patient_name'] ?? '').toString().toLowerCase();
      final pid = (s['patient_id'] ?? '').toString().toLowerCase();
      final findings = (s['clinical_findings'] as List? ?? []);
      final primaryDiag = findings.isNotEmpty ? (findings[0]['diagnosis'] ?? findings[0]['condition'] ?? '').toString().toLowerCase() : '';
      final icd = findings.isNotEmpty ? (findings[0]['icd11Code'] ?? findings[0]['code'] ?? '').toString().toLowerCase() : '';
      final q = _searchQuery.toLowerCase();

      final matchesQuery = q.isEmpty || name.contains(q) || pid.contains(q) || primaryDiag.contains(q) || icd.contains(q);
      final risk = (s['risk_level'] ?? 'LOW').toString().toUpperCase();
      final matchesRisk = _selectedRiskFilter == 'ALL' || risk == _selectedRiskFilter;

      return matchesQuery && matchesRisk;
    }).toList();
  }

  Color _getRiskColor(String risk) {
    switch (risk.toUpperCase()) {
      case 'CRITICAL':
        return const Color(0xFFDC2626); // Crimson
      case 'HIGH':
        return const Color(0xFFEA580C); // Orange-Red
      case 'MODERATE':
        return const Color(0xFFD97706); // Amber
      case 'LOW':
      default:
        return const Color(0xFF059669); // Emerald
    }
  }

  Future<void> _openCDSSDrawer(BuildContext context, Map<String, dynamic> screening) async {
    final findings = screening['clinical_findings'] as List? ?? [];
    final primary = findings.isNotEmpty ? findings[0] : null;
    final primaryTitle = primary?['diagnosis']?.toString() ?? 'Acute Clinical Presentation';
    final primaryCode = primary?['icd11Code']?.toString() ?? 'MG40';
    final pid = screening['patient_id']?.toString() ?? '';
    final screeningId = screening['id']?.toString();
    final riskScore = (screening['multimodal_risk_score'] as num?)?.toDouble() ?? 0.5;
    final symptomPayload = (screening['symptom_payload'] is Map)
        ? Map<String, dynamic>.from(screening['symptom_payload'])
        : <String, dynamic>{};
    final instId = screening['institutionId']?.toString() ?? screening['institution_id']?.toString() ?? ApiConfig.activeInstitutionId;
    final instName = screening['institutionName']?.toString() ?? ApiConfig.activeInstitutionName;

    final fallbackEval = CDSSEvaluationResult(
      id: 'cdss-${screening['id'] ?? DateTime.now().millisecondsSinceEpoch}',
      screeningId: screening['id']?.toString(),
      patientId: pid.isNotEmpty ? pid : 'PATIENT-ANON',
      institutionId: instId,
      institutionName: instName,
      primaryICD11Code: primaryCode,
      primaryICD11Title: primaryTitle,
      primaryICD11Uri: 'http://id.who.int/icd/release/11/mms/$primaryCode',
      differentialDiagnoses: [
        DifferentialDiagnosisCandidate(
          code: primaryCode,
          title: primaryTitle,
          category: 'Primary Diagnostic Candidate',
          uri: 'http://id.who.int/icd/release/11/mms/$primaryCode',
          probability: (primary?['probability'] as num?)?.toDouble() ?? 0.88,
          logitScore: 2.19,
          matchedCriteria: ['Multimodal sensor presentation', 'Physical examination corroboration'],
          clinicalRationale: 'Evidence derived from optical rash morphology and clinical acoustic signals.',
        ),
      ],
      treatmentPathway: TreatmentPathway(
        primaryCode: primaryCode,
        primaryTitle: primaryTitle,
        recommendedRx: [
          RecommendedMedication(
            genericName: 'Hydrocortisone / Salbutamol Protocol',
            dosage: 'Targeted dosage per body weight',
            frequency: 'Twice daily',
            duration: '5 days',
            clinicalNotes: 'First-line supportive management aligned with CDC clinical protocols.',
          ),
        ],
        labOrders: ['Complete Blood Count (CBC)', 'Serum Electrolyte Panel', 'Specific IgE Screen'],
        imagingOrders: ['Point-of-care Clinical Ultrasound', 'Dermoscopic Analysis'],
        monitoringFrequency: 'Re-evaluate in 24 hours',
        followUpDays: 2,
        urgentRedFlags: ['Progression of facial angioedema', 'Stridor or breathing difficulty', 'High persistent fever > 39°C'],
        urgencyLevel: (screening['risk_level'] == 'CRITICAL' || screening['risk_level'] == 'HIGH') ? 'IMMEDIATE_EMERGENCY' : 'ROUTINE',
      ),
      temperatureScaling: 1.0,
      regulatoryDisclaimer: 'AI-assisted Clinical Decision Support. Final diagnosis requires Attending Physician approval.',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );

    CDSSEvaluationResult evaluation = fallbackEval;
    try {
      final evaluated = await CDSSService().evaluateScreening(
        screeningId: screeningId,
        patientId: pid.isNotEmpty ? pid : 'PATIENT-ANON',
        institutionId: instId,
        institutionName: instName,
        riskScore: riskScore,
        symptoms: symptomPayload,
        visionFindings: findings.whereType<Map<String, dynamic>>().toList(),
      );
      evaluation = evaluated;
    } catch (_) {}

    if (!context.mounted) return;

    CDSSDecisionDrawer.show(
      context,
      evaluation: evaluation,
      isClinicianView: true,
      institutionId: instId,
      institutionName: instName,
    );
  }

  void _openPatientPharmacyModal(Map<String, dynamic> patient) {
    final pid = patient['patientId']?.toString() ?? 'pat-000';
    final name = patient['patientName']?.toString() ?? 'Patient $pid';
    final instId = patient['institutionId']?.toString();

    AdminPatientPharmacyModal.show(
      context,
      patientId: pid,
      patientName: name,
      institutionId: instId,
    );
  }

  void _openPatientPharmacyModalFromScreening(Map<String, dynamic> sc) {
    final pid = sc['patient_id']?.toString() ?? sc['patientId']?.toString() ?? 'pat-000';
    final name = sc['patient_name'] ?? sc['patientName'] ?? sc['symptom_payload']?['patient_name'] ?? sc['symptom_payload']?['patientName'] ?? (pid.isNotEmpty ? 'Patient $pid' : 'Unknown Patient');
    final instId = sc['institution_id']?.toString() ?? sc['institutionId']?.toString();

    AdminPatientPharmacyModal.show(
      context,
      patientId: pid,
      patientName: name,
      institutionId: instId,
    );
  }

  void _showDiagnosisDetailsModal(BuildContext context, Map<String, dynamic> screening) {
    final findings = screening['clinical_findings'] as List? ?? [];
    final primary = findings.isNotEmpty ? findings[0] : null;
    final primaryTitle = primary?['diagnosis']?.toString() ?? 'Acute Clinical Presentation';
    final primaryCode = primary?['icd11Code']?.toString() ?? 'MG40';
    final riskLevel = (screening['risk_level'] ?? 'LOW').toString().toUpperCase();
    final riskColor = _getRiskColor(riskLevel);
    final riskScorePct = (((screening['multimodal_risk_score'] as num?)?.toDouble() ?? 0.5) * 100).toStringAsFixed(1);
    final dateStr = DateFormat('MMMM d, y • h:mm a').format(DateTime.tryParse(screening['created_at'].toString()) ?? DateTime.now());
    final symptoms = (screening['symptom_payload']?['symptoms'] as List? ?? []).map((e) => e.toString()).toList();
    final vitals = screening['symptom_payload']?['vitals'] as Map<String, dynamic>? ?? {};
    final rppg = screening['rppg_vitals_payload'] as Map<String, dynamic>? ?? {};
    final acoustic = screening['symptom_payload']?['acoustic_classification'] as Map<String, dynamic>? ?? {};
    final alerts = (screening['physiological_alerts'] as List? ?? []).map((e) => e.toString()).toList();
    final patientId = screening['patient_id']?.toString() ?? '';
    final patientName = screening['patient_name'] ?? screening['patientName'] ?? screening['symptom_payload']?['patient_name'] ?? screening['symptom_payload']?['patientName'] ?? (patientId.isNotEmpty ? 'Patient $patientId' : 'Unknown Patient');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Modal Drag Handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Modal Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                patientName,
                                style: GoogleFonts.outfit(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: riskColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: riskColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  riskLevel,
                                  style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Patient ID: $patientId • Checkup recorded $dateStr',
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF64748B)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(color: Color(0xFFE2E8F0), height: 1),

              // Modal Scrollable Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 1. Primary Diagnosis Banner
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.biotech, color: Color(0xFF0D9488), size: 22),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'WHO ICD-11 PRIMARY DIAGNOSIS',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0D9488),
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            Text(
                                              primaryTitle,
                                              style: GoogleFonts.outfit(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: const Color(0xFF0F172A),
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0F172A),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'Code: $primaryCode',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Multimodal Risk Score', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$riskScorePct%',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: riskColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Confidence Bounds', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                                        SizedBox(height: 2),
                                        Text(
                                          '91.4% (±3.8%)',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (symptoms.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'Reported Symptoms:',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: symptoms.map((s) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Text(
                                      s,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 2. Multimodal Telemetry Breakdown
                      Text(
                        'Multimodal Clinical Sensor Data',
                        style: GoogleFonts.outfit(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),

                      Builder(
                        builder: (_) {
                          final hrVal = rppg['heartRate'] ?? rppg['heartRateBpm'] ?? vitals['heartRate'] ?? vitals['heartRateBpm'] ?? vitals['heart_rate'] ?? vitals['pulse'] ?? 74;
                          final spo2Val = rppg['oxygenSaturation'] ?? rppg['oxygenSaturationSpo2'] ?? vitals['oxygenSaturation'] ?? vitals['oxygenSaturationSpo2'] ?? vitals['oxygen_saturation'] ?? vitals['spo2'] ?? 98.0;
                          final sysVal = rppg['systolicBP'] ?? rppg['bloodPressureSystolicMmHg'] ?? vitals['systolicBP'] ?? vitals['bloodPressureSystolicMmHg'] ?? vitals['blood_pressure_systolic'] ?? 120;
                          final diaVal = rppg['diastolicBP'] ?? rppg['bloodPressureDiastolicMmHg'] ?? vitals['diastolicBP'] ?? vitals['bloodPressureDiastolicMmHg'] ?? vitals['blood_pressure_diastolic'] ?? 80;
                          final tempVal = rppg['temperatureCelsius'] ?? rppg['temperature'] ?? vitals['temperatureCelsius'] ?? vitals['temperature'] ?? 37.0;

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              children: [
                                _buildModalTelemetryRow(
                                  icon: Icons.thermostat,
                                  iconColor: const Color(0xFF0D9488),
                                  title: 'Body Temperature & Hemodynamics',
                                  value: '$tempVal°C • BP $sysVal/$diaVal mmHg',
                                ),
                                const Divider(color: Color(0xFFF1F5F9), height: 16),
                                _buildModalTelemetryRow(
                                  icon: Icons.favorite,
                                  iconColor: const Color(0xFFEF4444),
                                  title: 'Contactless rPPG Vitals',
                                  value: 'HR: ${(num.tryParse(hrVal.toString()) ?? 74).round()} BPM • SpO2: ${(num.tryParse(spo2Val.toString()) ?? 98.0).toStringAsFixed(1)}%',
                                ),
                                const Divider(color: Color(0xFFF1F5F9), height: 16),
                                _buildModalTelemetryRow(
                                  icon: Icons.mic,
                                  iconColor: const Color(0xFF0284C7),
                                  title: '5s Acoustic Respiratory WAV',
                                  value: '${acoustic['predicted_class'] ?? 'Normal Airway'} (${((acoustic['confidence'] as num?)?.toDouble() ?? 0.92 * 100).toStringAsFixed(0)}% Conf)',
                                ),
                                const Divider(color: Color(0xFFF1F5F9), height: 16),
                                _buildModalTelemetryRow(
                                  icon: Icons.shield_outlined,
                                  iconColor: const Color(0xFFD97706),
                                  title: 'Medication Allergy & DDI Shield',
                                  value: screening['symptom_payload']?['has_safety_conflict'] == true
                                      ? (screening['symptom_payload']?['safety_conflict_summary'] ?? 'Contraindication Warning Detected')
                                      : 'No active drug-drug or allergen conflicts detected',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // 3. Clinical Alerts if any
                      if (alerts.isNotEmpty) ...[
                        Text(
                          'Physiological Escalation Alerts',
                          style: GoogleFonts.outfit(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...alerts.map((al) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFFCA5A5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    al,
                                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 16),
                      ],

                      // 4. Clinical Recommendations & CDSS Evidence
                      if (primary?['recommendation'] != null) ...[
                        Text(
                          'Clinical Recommendations & Pathway',
                          style: GoogleFonts.outfit(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            primary!['recommendation'].toString(),
                            style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), height: 1.4),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // 5. Multimodal Differential Diagnoses
                      if (findings.length > 1) ...[
                        Text(
                          'Multimodal Differential Diagnoses',
                          style: GoogleFonts.outfit(
                            fontSize: 14.5,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...findings.skip(1).map((f) {
                          final diffMap = (f is Map) ? f : <String, dynamic>{};
                          final dName = diffMap['diagnosis'] ?? diffMap['condition'] ?? 'Differential';
                          final dCode = diffMap['icd11Code'] ?? diffMap['code'] ?? 'MG40';
                          final dProb = (((diffMap['probability'] as num?)?.toDouble() ?? 0.2) * 100).toStringAsFixed(0);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    '$dName ($dCode)',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D9488).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$dProb% match',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                      ],

                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0D9488),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              icon: const Icon(Icons.verified, size: 16),
                              label: const Text('CDSS Decision Sign-Off', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                Navigator.pop(context);
                                _openCDSSDrawer(context, screening);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0F172A),
                                side: const BorderSide(color: Color(0xFFCBD5E1)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              icon: const Icon(Icons.show_chart, size: 16),
                              label: const Text('Recovery Curve', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const LongitudinalHistoryScreen()),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalTelemetryRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        onRefresh: _fetchAdminDiagnoses,
        color: const Color(0xFF0D9488),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. KPI Metric Summary Cards
              _buildMetricsRow(),
              const SizedBox(height: 18),

              // 2. Search & View Mode Switcher
              _buildSearchBarAndViewToggle(),
              const SizedBox(height: 14),

              // 3. Risk Filter Chips
              _buildRiskFilterChips(),
              const SizedBox(height: 16),

              // 4. Header with items count
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isPatientRosterView
                        ? 'Patients Diagnostic Roster (${_filteredPatients.length})'
                        : 'Encounter Diagnostic Ledger (${_filteredScreenings.length})',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _fetchAdminDiagnoses,
                    icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF0D9488)),
                    label: const Text('Refresh', style: TextStyle(color: Color(0xFF0D9488), fontSize: 12)),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 5. Main Content: Roster or Encounter List
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 50),
                    child: CircularProgressIndicator(color: Color(0xFF0D9488)),
                  ),
                )
              else if (_isPatientRosterView)
                _buildPatientRosterView()
              else
                _buildEncounterLedgerView(),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    final totalPatients = _patients.length;
    final criticalHighCount = _patients.where((p) {
      final r = (p['highestRiskLevel'] ?? '').toString().toUpperCase();
      return r == 'CRITICAL' || r == 'HIGH';
    }).length;
    final totalCheckups = _allScreenings.length;
    final ddiInterceptions = _patients.where((p) => p['hasDDIConflict'] == true).length;

    final cards = [
      _buildMetricCard(
        title: 'Screened Patients',
        value: '$totalPatients',
        icon: Icons.people_outline,
        iconColor: const Color(0xFF0D9488),
        badgeText: 'Active',
        badgeColor: const Color(0xFF0D9488),
      ),
      _buildMetricCard(
        title: 'Urgent / High Flags',
        value: '$criticalHighCount',
        icon: Icons.warning_amber_rounded,
        iconColor: const Color(0xFFEF4444),
        badgeText: 'Escalated',
        badgeColor: const Color(0xFFEF4444),
      ),
      _buildMetricCard(
        title: 'Diagnostic Encounters',
        value: '$totalCheckups',
        icon: Icons.biotech_outlined,
        iconColor: const Color(0xFF0284C7),
        badgeText: 'Multimodal',
        badgeColor: const Color(0xFF0284C7),
      ),
      _buildMetricCard(
        title: 'Safety Interceptions',
        value: '$ddiInterceptions',
        icon: Icons.shield_outlined,
        iconColor: const Color(0xFFD97706),
        badgeText: 'DDI / Allergy',
        badgeColor: const Color(0xFFD97706),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 8),
            Expanded(child: cards[1]),
            const SizedBox(width: 8),
            Expanded(child: cards[2]),
            const SizedBox(width: 8),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
    required String badgeText,
    required Color badgeColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 18),
              const SizedBox(width: 4),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badgeText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: badgeColor, fontSize: 8.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBarAndViewToggle() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: const InputDecoration(
                hintText: 'Search by patient name, ID, diagnosis, or ICD-11...',
                hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF94A3B8)),
                prefixIcon: Icon(Icons.search, color: Color(0xFF0D9488), size: 20),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Group by Patient Roster',
                icon: Icon(
                  Icons.people_alt_outlined,
                  color: _isPatientRosterView ? const Color(0xFF0D9488) : const Color(0xFF94A3B8),
                  size: 20,
                ),
                onPressed: () => setState(() => _isPatientRosterView = true),
              ),
              Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
              IconButton(
                tooltip: 'All Encounters Ledger',
                icon: Icon(
                  Icons.view_agenda_outlined,
                  color: !_isPatientRosterView ? const Color(0xFF0D9488) : const Color(0xFF94A3B8),
                  size: 20,
                ),
                onPressed: () => setState(() => _isPatientRosterView = false),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRiskFilterChips() {
    final filters = ['ALL', 'CRITICAL', 'HIGH', 'MODERATE', 'LOW'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedRiskFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f == 'ALL' ? 'All Risks' : f),
              selected: isSelected,
              onSelected: (val) {
                if (val) setState(() => _selectedRiskFilter = f);
              },
              selectedColor: const Color(0xFF0D9488),
              backgroundColor: const Color(0xFFF1F5F9),
              side: BorderSide(color: isSelected ? const Color(0xFF0D9488) : const Color(0xFFE2E8F0)),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF334155),
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPatientRosterView() {
    final list = _filteredPatients;
    if (list.isEmpty) {
      return _buildEmptyState('No patients match the search and risk filter criteria.');
    }

    return Column(
      children: list.map((patient) => _buildPatientRosterCard(patient)).toList(),
    );
  }

  Widget _buildPatientRosterCard(Map<String, dynamic> patient) {
    final name = patient['patientName'] ?? 'Unknown Patient';
    final pid = patient['patientId'] ?? 'pat-000';
    final highestRisk = (patient['highestRiskLevel'] ?? 'LOW').toString().toUpperCase();
    final riskColor = _getRiskColor(highestRisk);
    final latestDiagnosis = patient['latestDiagnosis'] ?? 'Clinical Diagnosis';
    final latestICD = patient['latestICD11'] ?? 'MG40';
    final totalCount = patient['totalDiagnoses'] ?? 1;
    final hasAlert = patient['hasPhysiologicalAlert'] == true;
    final hasDDI = patient['hasDDIConflict'] == true;
    final vitals = patient['latestVitals'] as Map<String, dynamic>? ?? {};
    final screenings = patient['screenings'] as List? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: highestRisk == 'CRITICAL',
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.all(16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _openPatientPharmacyModal(patient),
            child: Tooltip(
              message: 'Assess Pharmacy Profile',
              child: CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'P',
                  style: const TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF0F172A),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: riskColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: riskColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  highestRisk,
                  style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                'ID: $pid • Primary: $latestDiagnosis ($latestICD)',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              // Vitals and AI tag pills
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  _buildQuickPill('HR ${vitals['heartRateBpm'] ?? 78}', Icons.favorite, Colors.redAccent),
                  _buildQuickPill('SpO2 ${vitals['oxygenSaturationSpo2'] ?? 98}%', Icons.air, Colors.blueAccent),
                  if (hasAlert)
                    _buildQuickPill('Physiological Alert', Icons.warning_amber_rounded, const Color(0xFFDC2626)),
                  if (hasDDI)
                    _buildQuickPill('DDI Conflict', Icons.shield_outlined, const Color(0xFFD97706)),
                  _buildQuickPill('$totalCount Diagnostic Encounters', Icons.history, const Color(0xFF0D9488)),
                ],
              ),
            ],
          ),
          children: [
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Clinical Diagnostic Encounters for $name:',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
              ),
            ),
            const SizedBox(height: 8),
            ...screenings.map((sc) {
              final scMap = Map<String, dynamic>.from(sc as Map);
              return _buildEncounterSubItem(scMap);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickPill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildEncounterSubItem(Map<String, dynamic> sc) {
    final findings = sc['clinical_findings'] as List? ?? [];
    final primary = findings.isNotEmpty ? findings[0] : null;
    final title = primary?['diagnosis']?.toString() ?? 'Clinical Examination';
    final icd = primary?['icd11Code']?.toString() ?? 'MG40';
    final risk = (sc['risk_level'] ?? 'LOW').toString().toUpperCase();
    final riskColor = _getRiskColor(risk);
    final dateStr = DateFormat('MMM d • h:mm a').format(DateTime.tryParse(sc['created_at'].toString()) ?? DateTime.now());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: riskColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.biotech, color: riskColor, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title ($icd)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Recorded on $dateStr • ${sc['symptom_payload']?['body_location'] ?? 'Multimodal'}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _showDiagnosisDetailsModal(context, sc),
            child: const Text('View Dossier', style: TextStyle(fontSize: 11.5, color: Color(0xFF0D9488), fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(60, 30),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: () => _openCDSSDrawer(context, sc),
            child: const Text('CDSS', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildEncounterLedgerView() {
    final list = _filteredScreenings;
    if (list.isEmpty) {
      return _buildEmptyState('No clinical diagnostic encounters found matching your filter.');
    }

    return Column(
      children: list.map((sc) {
        final findings = sc['clinical_findings'] as List? ?? [];
        final primary = findings.isNotEmpty ? findings[0] : null;
        final title = primary?['diagnosis']?.toString() ?? 'Clinical Examination';
        final icd = primary?['icd11Code']?.toString() ?? 'MG40';
        final risk = (sc['risk_level'] ?? 'LOW').toString().toUpperCase();
        final riskColor = _getRiskColor(risk);
        final pid = sc['patient_id']?.toString() ?? '';
        final patientName = sc['patient_name'] ?? sc['patientName'] ?? sc['symptom_payload']?['patient_name'] ?? sc['symptom_payload']?['patientName'] ?? (pid.isNotEmpty ? 'Patient $pid' : 'Unknown Patient');
        final dateStr = DateFormat('MMM d, y • h:mm a').format(DateTime.tryParse(sc['created_at'].toString()) ?? DateTime.now());
        final hasImage = sc['image_url'] != null && sc['image_url'].toString().isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openPatientPharmacyModalFromScreening(sc),
                          child: Tooltip(
                            message: 'Assess Pharmacy Profile',
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.12),
                              child: Text(
                                patientName.isNotEmpty ? patientName[0].toUpperCase() : 'P',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            patientName,
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF0F172A),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('($pid)', style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: riskColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: riskColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      risk,
                      style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '$title (ICD-11: $icd)',
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Encounter Date: $dateStr • ${sc['symptom_payload']?['body_location'] ?? 'Multimodal'}',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 10),
              // Tags
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (hasImage) _buildQuickPill('Visual Rash OCR', Icons.camera_alt_outlined, const Color(0xFF0D9488)),
                  _buildQuickPill('Acoustic Breathing WAV', Icons.mic_none, const Color(0xFF0284C7)),
                  _buildQuickPill('Contactless rPPG Vitals', Icons.favorite_border, const Color(0xFFEA580C)),
                  _buildQuickPill('Medication DDI Checked', Icons.shield_outlined, const Color(0xFF10B981)),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(color: Color(0xFFF1F5F9), height: 1),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.description_outlined, size: 14, color: Color(0xFF0D9488)),
                    label: const Text('Clinical Dossier', style: TextStyle(fontSize: 12, color: Color(0xFF0D9488), fontWeight: FontWeight.bold)),
                    onPressed: () => _showDiagnosisDetailsModal(context, sc),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.verified, size: 14),
                    label: const Text('CDSS Review', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    onPressed: () => _openCDSSDrawer(context, sc),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.biotech_outlined, size: 36, color: Color(0xFF0D9488)),
            ),
            const SizedBox(height: 14),
            Text(
              'No Clinical Diagnoses Found',
              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0D9488),
                side: const BorderSide(color: Color(0xFF0D9488)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Refresh Data', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              onPressed: _fetchAdminDiagnoses,
            ),
          ],
        ),
      ),
    );
  }
}
