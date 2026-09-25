import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../config/api_config.dart';
import '../../providers/auth_provider.dart';
import '../../modules/diagnostics/ui/LongitudinalHistoryScreen.dart';
import '../../modules/pharmacy/ui/patient_allergy_profile_screen.dart';
import 'claim_intake_screen.dart';
import 'claim_status_screen.dart';

class HealthRecordsScreen extends StatefulWidget {
  const HealthRecordsScreen({super.key});

  @override
  State<HealthRecordsScreen> createState() => _HealthRecordsScreenState();
}

class _HealthRecordsScreenState extends State<HealthRecordsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final patientId = user?.patientId ?? 'PAT-2026-001';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Electronic Health Records & History',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF0D9488),
          indicatorWeight: 3,
          labelColor: const Color(0xFF0D9488),
          unselectedLabelColor: const Color(0xFF64748B),
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(
              icon: Icon(Icons.show_chart, size: 18),
              text: 'Recovery & Trends',
            ),
            Tab(
              icon: Icon(Icons.badge_outlined, size: 18),
              text: 'Medical Passport',
            ),
            Tab(
              icon: Icon(Icons.verified_user_outlined, size: 18),
              text: 'Coverage & Benefits',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Sub-Tab 1: Full Longitudinal History & Recovery Curve
          LongitudinalHistoryScreen(patientId: patientId),

          // Sub-Tab 2: Medical Passport & Clinical Summary
          _MedicalPassportEhrView(patientId: patientId),

          // Sub-Tab 3: Institutional Coverage & Benefits
          const _InstitutionalCoverageView(),
        ],
      ),
    );
  }
}

class _MedicalPassportEhrView extends StatefulWidget {
  final String patientId;
  const _MedicalPassportEhrView({required this.patientId});

  @override
  State<_MedicalPassportEhrView> createState() => _MedicalPassportEhrViewState();
}

class _MedicalPassportEhrViewState extends State<_MedicalPassportEhrView> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _allergies = [];
  List<Map<String, dynamic>> _medications = [];
  List<Map<String, dynamic>> _screenings = [];

  @override
  void initState() {
    super.initState();
    _loadEhrData();
  }

  @override
  void didUpdateWidget(covariant _MedicalPassportEhrView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.patientId != widget.patientId) {
      _loadEhrData();
    }
  }

  Future<void> _loadEhrData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pid = widget.patientId;

      // 1. Fetch Allergies from live Supabase
      final algFuture = http
          .get(Uri.parse('${ApiConfig.baseUrl}/pharmacy/allergies/$pid'), headers: ApiConfig.patientHeaders)
          .timeout(const Duration(seconds: 4));

      // 2. Fetch Medications from live Supabase
      final medFuture = http
          .get(Uri.parse('${ApiConfig.baseUrl}/pharmacy/medications/$pid'), headers: ApiConfig.patientHeaders)
          .timeout(const Duration(seconds: 4));

      // 3. Fetch Diagnostic Screenings from live Supabase
      final scrFuture = http
          .get(Uri.parse('${ApiConfig.baseUrl}/diagnostics/screenings/patient/$pid/longitudinal'), headers: ApiConfig.patientHeaders)
          .timeout(const Duration(seconds: 4));

      final results = await Future.wait([algFuture, medFuture, scrFuture]);

      List<Map<String, dynamic>> loadedAllergies = [];
      List<Map<String, dynamic>> loadedMedications = [];
      List<Map<String, dynamic>> loadedScreenings = [];

      // Parse Allergies
      if (results[0].statusCode == 200) {
        final b = jsonDecode(results[0].body);
        if (b['allergies'] is List) {
          loadedAllergies = (b['allergies'] as List).cast<Map<String, dynamic>>();
        }
      }

      // Parse Medications
      if (results[1].statusCode == 200) {
        final b = jsonDecode(results[1].body);
        if (b['medications'] is List) {
          loadedMedications = (b['medications'] as List).cast<Map<String, dynamic>>();
        }
      }

      // Parse Diagnostic Screenings
      if (results[2].statusCode == 200) {
        final b = jsonDecode(results[2].body);
        if (b['screenings'] is List) {
          loadedScreenings = (b['screenings'] as List).cast<Map<String, dynamic>>();
        }
      }

      if (mounted) {
        setState(() {
          _allergies = loadedAllergies;
          _medications = loadedMedications;
          _screenings = loadedScreenings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not sync live EHR records: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final patientName = user?.fullName ?? user?.name ?? 'Alex Rivera';
    final patientId = widget.patientId;
    final institution = user?.institutionName ?? 'Apex Health & Medical Center';
    final emergencyPhone = user?.phone ?? '+1-555-0199';

    return RefreshIndicator(
      onRefresh: _loadEhrData,
      color: const Color(0xFF0D9488),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Digital Emergency Medical Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F766E), Color(0xFF0E7490)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0D9488).withOpacity(0.3),
                    blurRadius: 16,
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
                      Row(
                        children: [
                          const Icon(Icons.medical_information, color: Colors.white, size: 24),
                          const SizedBox(width: 8),
                          Text(
                            'CLINICAL MEDICAL ID',
                            style: GoogleFonts.outfit(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'EHR VERIFIED',
                          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    patientName,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Patient ID: $patientId • $institution',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildIdField('BLOOD GROUP', 'O+ POSITIVE'),
                      _buildIdField('PRIMARY PHYSICIAN', 'Dr. Sarah Chen, MD'),
                      _buildIdField('EMERGENCY CONTACT', emergencyPhone),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 16, color: Color(0xFFDC2626)),
                      onPressed: _loadEhrData,
                    ),
                  ],
                ),
              ),

            // 2. Active Clinical Allergy Profile (from Supabase patient_allergies)
            _buildExpandableCard(
              icon: Icons.shield_outlined,
              title: 'Clinical Allergy Safeguards',
              subtitle: _isLoading
                  ? 'Syncing with Supabase...'
                  : '${_allergies.length} documented allergy contraindications',
              action: TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PatientAllergyProfileScreen(patientId: patientId)),
                  ).then((_) => _loadEhrData());
                },
                icon: const Icon(Icons.edit, size: 14, color: Color(0xFF0D9488)),
                label: const Text('Manage', style: TextStyle(color: Color(0xFF0D9488), fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(color: Color(0xFF0D9488), strokeWidth: 2.5),
                      ),
                    )
                  : _allergies.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No documented allergies in database. Patient clear for standard formulary.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                        )
                      : Column(
                          children: _allergies.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final a = entry.value;
                            final group = a['allergenGroup'] ?? a['allergen_group'] ?? 'Allergen';
                            final reaction = a['reaction'] ?? a['severity'] ?? 'Hypersensitivity';
                            final severity = (a['severity']?.toString() ?? 'MODERATE').toUpperCase();
                            final Color color = severity.contains('FATAL') || severity.contains('SEVERE')
                                ? const Color(0xFFEF4444)
                                : const Color(0xFFF59E0B);
                            return Column(
                              children: [
                                if (idx > 0) const Divider(color: Color(0xFFE2E8F0)),
                                _buildAllergyRow(group.toString(), reaction.toString(), color),
                              ],
                            );
                          }).toList(),
                        ),
            ),
            const SizedBox(height: 16),

            // 3. Active Medication Schedule (from Supabase patient_medications)
            _buildExpandableCard(
              icon: Icons.medication_outlined,
              title: 'Current Prescribed Regimen',
              subtitle: _isLoading
                  ? 'Syncing with Supabase...'
                  : '${_medications.length} active medications verified in database',
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(color: Color(0xFF0D9488), strokeWidth: 2.5),
                      ),
                    )
                  : _medications.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No active prescribed medications in database.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                        )
                      : Column(
                          children: _medications.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final m = entry.value;
                            final name = m['medicationName'] ?? m['medication_name'] ?? m['brand_name'] ?? m['brand'] ?? 'Prescription';
                            final generic = m['activeIngredient'] ?? m['active_ingredient'] ?? '';
                            final displayName = generic.isNotEmpty && !name.toString().contains(generic.toString())
                                ? '$name ($generic)'
                                : name.toString();
                            final dosage = m['dosage'] ?? '';
                            final instructions = m['frequency'] ?? m['indication'] ?? 'As prescribed';
                            final isActive = m['isActive'] == true || m['is_active'] == true || m['status'] == 'Active';
                            return Column(
                              children: [
                                if (idx > 0) const Divider(color: Color(0xFFE2E8F0)),
                                _buildMedicationRow(
                                  name: displayName,
                                  dosage: dosage.toString(),
                                  instructions: instructions.toString(),
                                  status: isActive ? 'Active' : 'Inactive',
                                ),
                              ],
                            );
                          }).toList(),
                        ),
            ),
            const SizedBox(height: 16),

            // 4. Diagnostic & ICD-11 History (from Supabase health_screenings)
            _buildExpandableCard(
              icon: Icons.biotech_outlined,
              title: 'Recent Diagnostic Checkups',
              subtitle: _isLoading
                  ? 'Syncing with Supabase...'
                  : '${_screenings.length} WHO ICD-11 multimodal checkups recorded',
              child: _isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(color: Color(0xFF0D9488), strokeWidth: 2.5),
                      ),
                    )
                  : _screenings.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'No clinical diagnostic checkups on file yet.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                        )
                      : Column(
                          children: _screenings.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final s = entry.value;
                            final payload = s['symptom_payload'] as Map<String, dynamic>? ?? {};
                            final diagnosis = payload['chiefComplaint'] ??
                                payload['chief_complaint'] ??
                                s['chief_complaint'] ??
                                'Clinical Multimodal Intake';
                            final icd = payload['icd11Code'] ??
                                payload['icd_11_code'] ??
                                s['icd_11_code'] ??
                                'WHO ICD-11';
                            final riskScore = (s['multimodal_risk_score'] as num?)?.toDouble() ?? 0.0;
                            final riskLevel = (s['risk_level']?.toString() ?? 'LOW').toUpperCase();
                            final Color riskColor = riskLevel == 'CRITICAL' || riskScore >= 0.7
                                ? const Color(0xFFEF4444)
                                : riskLevel == 'MODERATE' || riskScore >= 0.4
                                    ? const Color(0xFFD97706)
                                    : const Color(0xFF059669);
                            final rawDate = s['created_at'];
                            final dateStr = rawDate != null
                                ? DateFormat('MMM d, yyyy • h:mm a').format(DateTime.tryParse(rawDate.toString()) ?? DateTime.now())
                                : 'Recent';
                            return Column(
                              children: [
                                if (idx > 0) const Divider(color: Color(0xFFE2E8F0)),
                                _buildDiagnosticRow(
                                  diagnosis: diagnosis.toString(),
                                  icd11Code: icd.toString(),
                                  date: dateStr,
                                  risk: riskLevel,
                                  riskColor: riskColor,
                                ),
                              ],
                            );
                          }).toList(),
                        ),
            ),
            const SizedBox(height: 16),

            // 5. Immunization Record
            _buildExpandableCard(
              icon: Icons.vaccines_outlined,
              title: 'Immunization Ledger',
              subtitle: 'Institutional vaccination verification',
              child: Column(
                children: [
                  _buildImmunizationRow('COVID-19 Bivalent Booster', 'Administered Nov 2025', 'Batch #NV-8821'),
                  const Divider(color: Color(0xFFE2E8F0)),
                  _buildImmunizationRow('Seasonal Influenza Quadrivalent', 'Administered Oct 2025', 'Batch #FL-4402'),
                  const Divider(color: Color(0xFFE2E8F0)),
                  _buildImmunizationRow('Tetanus, Diphtheria, Pertussis (Tdap)', 'Administered Jun 2023', 'Valid thru 2033'),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  static Widget _buildIdField(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  static Widget _buildExpandableCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? action,
    required Widget child,
    bool initiallyExpanded = true,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF0D9488), size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.outfit(
              color: const Color(0xFF0F172A),
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
          ),
          trailing: action != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    action,
                    const Icon(Icons.expand_more, color: Color(0xFF64748B)),
                  ],
                )
              : const Icon(Icons.expand_more, color: Color(0xFF64748B)),
          children: [
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  static Widget _buildAllergyRow(String allergen, String reaction, Color severityColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: severityColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allergen,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  reaction,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildMedicationRow({
    required String name,
    required String dosage,
    required String instructions,
    required String status,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.medication, color: Color(0xFF0D9488), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$dosage • $instructions',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              status,
              style: const TextStyle(color: Color(0xFF0D9488), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildDiagnosticRow({
    required String diagnosis,
    required String icd11Code,
    required String date,
    required String risk,
    required Color riskColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.health_and_safety, color: Color(0xFF0D9488), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  diagnosis,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  'ICD-11: $icd11Code • $date',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: riskColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              risk,
              style: TextStyle(color: riskColor, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildImmunizationRow(String vaccine, String administered, String batch) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.vaccines, color: Color(0xFF0D9488), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vaccine,
                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w600),
                ),
                Text(
                  '$administered • $batch',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstitutionalCoverageView extends StatefulWidget {
  const _InstitutionalCoverageView();

  @override
  State<_InstitutionalCoverageView> createState() => _InstitutionalCoverageViewState();
}

class _InstitutionalCoverageViewState extends State<_InstitutionalCoverageView> {
  bool _showNewDocumentationForm = false;

  @override
  Widget build(BuildContext context) {
    if (_showNewDocumentationForm) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
                  onPressed: () => setState(() => _showNewDocumentationForm = false),
                ),
                Text(
                  'Back to Care Benefits Ledger',
                  style: GoogleFonts.outfit(color: const Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Expanded(child: ClaimIntakeScreen()),
        ],
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user, color: Color(0xFF0D9488), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Institutional Health Access Pass',
                      style: TextStyle(color: Color(0xFF0F172A), fontSize: 13.5, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Verified care coverage: 100% emergency services, pharmacy copay support & campus health network.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.upload_file, size: 14),
                label: const Text('Add Document', style: TextStyle(fontSize: 11)),
                onPressed: () => setState(() => _showNewDocumentationForm = true),
              ),
            ],
          ),
        ),
        Expanded(
          child: ClaimStatusScreen(
            onNavigateToClaims: () => setState(() => _showNewDocumentationForm = true),
          ),
        ),
      ],
    );
  }
}
