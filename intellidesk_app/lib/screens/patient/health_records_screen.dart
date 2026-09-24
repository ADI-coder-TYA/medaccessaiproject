import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
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
          const LongitudinalHistoryScreen(),

          // Sub-Tab 2: Medical Passport & Clinical Summary
          const _MedicalPassportEhrView(),

          // Sub-Tab 3: Institutional Coverage & Benefits
          const _InstitutionalCoverageView(),
        ],
      ),
    );
  }
}

class _MedicalPassportEhrView extends StatelessWidget {
  const _MedicalPassportEhrView();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final patientName = user?.name ?? 'Alex Rivera';
    final patientId = user?.id ?? 'pat-demo-01';
    final institution = user?.institutionName ?? 'Columbia Health Network';

    return SingleChildScrollView(
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
                    _buildIdField('EMERGENCY CONTACT', '+1-555-0199'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 2. Active Clinical Allergy Profile
          _buildExpandableCard(
            icon: Icons.shield_outlined,
            title: 'Clinical Allergy Safeguards',
            subtitle: 'Real-time DDI & allergen contraindication filters',
            action: TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => PatientAllergyProfileScreen(patientId: patientId)),
                );
              },
              icon: const Icon(Icons.edit, size: 14, color: Color(0xFF0D9488)),
              label: const Text('Manage', style: TextStyle(color: Color(0xFF0D9488), fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            child: Column(
              children: [
                _buildAllergyRow('Penicillins & Beta-Lactams', 'Severe Anaphylaxis / Bronchospasm', const Color(0xFFEF4444)),
                const Divider(color: Color(0xFFE2E8F0)),
                _buildAllergyRow('Non-Steroidal Anti-Inflammatory (NSAIDs)', 'Urticaria & Gastric Distress', const Color(0xFFF59E0B)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 3. Active Medication Schedule
          _buildExpandableCard(
            icon: Icons.medication_outlined,
            title: 'Current Prescribed Regimen',
            subtitle: 'Verified by RxSentinel Optical OCR',
            child: Column(
              children: [
                _buildMedicationRow(
                  name: 'Lipitor (Atorvastatin)',
                  dosage: '20mg • Oral Tablet',
                  instructions: 'Once daily at bedtime',
                  status: 'Active',
                ),
                const Divider(color: Color(0xFFE2E8F0)),
                _buildMedicationRow(
                  name: 'Glucophage (Metformin)',
                  dosage: '500mg • Extended Release',
                  instructions: 'Twice daily with meals',
                  status: 'Active',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 4. Diagnostic & ICD-11 History
          _buildExpandableCard(
            icon: Icons.biotech_outlined,
            title: 'Recent Diagnostic Checkups',
            subtitle: 'WHO ICD-11 Coded Multimodal Screenings',
            child: Column(
              children: [
                _buildDiagnosticRow(
                  diagnosis: 'Acute Contact Dermatitis & Erythema',
                  icd11Code: 'EK02',
                  date: 'Yesterday, 3:42 PM',
                  risk: 'Moderate',
                  riskColor: const Color(0xFFD97706),
                ),
                const Divider(color: Color(0xFFE2E8F0)),
                _buildDiagnosticRow(
                  diagnosis: 'Mild Upper Respiratory Irritation',
                  icd11Code: 'CA01',
                  date: '2 Weeks Ago',
                  risk: 'Low',
                  riskColor: const Color(0xFF059669),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 5. Immunization Record
          _buildExpandableCard(
            icon: Icons.vaccines_outlined,
            title: 'Immunization Ledger',
            subtitle: 'Verified vaccination history',
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
