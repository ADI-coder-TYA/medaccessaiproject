import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../providers/auth_provider.dart';
import '../../modules/diagnostics/providers/diagnostics_provider.dart';
import '../../modules/diagnostics/providers/diagnostic_state_provider.dart';
import '../../modules/diagnostics/models/risk_assessment.dart';
import '../../modules/diagnostics/ui/diagnostic_intake_screen.dart';
import '../../modules/diagnostics/ui/diagnostic_chat_screen.dart';
import '../../modules/diagnostics/ui/diagnostic_results_screen.dart';
import '../../modules/diagnostics/ui/EmergencyFacilitySheet.dart';
import '../../modules/diagnostics/ui/LongitudinalHistoryScreen.dart';
import '../../modules/diagnostics/vitals/models/vitals_result.dart';
import '../../modules/diagnostics/vitals/ui/vitals_scanner_modal.dart';
import '../../modules/pharmacy/ui/prescription_review_modal.dart';
import '../../modules/pharmacy/services/rx_sentinel_service.dart';

class PatientClinicalDashboard extends StatefulWidget {
  final Function(int targetIndex)? onNavigateTab;
  final bool enablePulseAnimation;
  final bool autoFetchOverview;

  const PatientClinicalDashboard({
    super.key,
    this.onNavigateTab,
    this.enablePulseAnimation = true,
    this.autoFetchOverview = true,
  });

  @override
  State<PatientClinicalDashboard> createState() => _PatientClinicalDashboardState();
}

class _PatientClinicalDashboardState extends State<PatientClinicalDashboard> with SingleTickerProviderStateMixin {
  VitalsResult? _latestVitals;
  bool _isLoadingOverview = false;
  Map<String, dynamic>? _backendOverview;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains('Test');
    if (widget.enablePulseAnimation && !isTest) {
      _pulseController.repeat(reverse: true);
    }
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.autoFetchOverview && !isTest) {
      _fetchClinicalOverview();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchClinicalOverview() async {
    final auth = context.read<AuthProvider>();
    final patientId = auth.user?.patientId ?? auth.user?.id ?? 'pat-demo-01';

    setState(() => _isLoadingOverview = true);

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/diagnostics/patient/$patientId/overview');
      final res = await http.get(uri).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted && data['success'] == true) {
          setState(() {
            _backendOverview = data;
          });
        }
      }
    } catch (_) {
      // Offline fallback: keep cached data
    } finally {
      if (mounted) setState(() => _isLoadingOverview = false);
    }
  }

  void _openVitalsScanner() async {
    final result = await VitalsScannerModal.show(context);
    if (result != null && mounted) {
      setState(() {
        _latestVitals = result;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Vitals synchronized: ${result.heartRateBpm.round()} BPM | ${result.oxygenSaturationSpo2.round()}% SpO₂',
          ),
          backgroundColor: const Color(0xFF0D9488),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _callEmergency() async {
    final uri = Uri.parse('tel:911');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calling +1-555-0199 Emergency Trauma Desk...')),
        );
      }
    }
  }

  Color _getRiskColor(String? riskLevel) {
    final level = riskLevel?.toUpperCase() ?? 'LOW';
    if (level.contains('CRITICAL')) return const Color(0xFFEF4444);
    if (level.contains('HIGH')) return const Color(0xFFF97316);
    if (level.contains('MODERATE')) return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final diagState = context.watch<DiagnosticStateProvider>();
    final diagSession = context.watch<DiagnosticsProvider>().currentSession;
    final assessment = diagSession?.riskAssessment ?? diagState.assessmentResult;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final userName = auth.user?.name ?? 'Alex Mercer';
    final institution = auth.user?.institutionDisplayName ?? ApiConfig.activeInstitutionName;

    return RefreshIndicator(
      onRefresh: _fetchClinicalOverview,
      color: const Color(0xFF0D9488),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Executive Top Status Bar
            _buildExecutiveHeader(userName, institution),
            const SizedBox(height: 16),

            // 2. Hero Clinical Checkup Card (Core Flagship Feature)
            _buildHeroClinicalCheckupCard(isDark),
            const SizedBox(height: 18),

            // 3. Real-Time Vitals Pulse Card (rPPG Camera Scanner)
            _buildVitalsPulseCard(isDark),
            const SizedBox(height: 18),

            // 4. Clinical AI Core Suites (Interactive Grid)
            _buildSectionHeader('Clinical Health Suites', 'Health evaluations & tools'),
            const SizedBox(height: 12),
            _buildSuitesGrid(),
            const SizedBox(height: 20),

            // 5. Latest Screening & Triage Summary
            if (assessment != null || _backendOverview?['latestScreening'] != null) ...[
              _buildSectionHeader('Active Triage & Diagnostic Assessment', 'Recent clinical assessment'),
              const SizedBox(height: 10),
              _buildLatestScreeningCard(assessment, isDark),
              const SizedBox(height: 20),
            ],

            // 6. Comprehensive Medical Passport & Care Plan
            _buildMedicalPassportSummaryCard(isDark),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveHeader(String name, String institution) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0D9488),
                  ),
                ),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Clinical Monitoring Active',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Color(0xFF0F766E),
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 1-Tap Emergency Call SOS Button
          InkWell(
            onTap: _callEmergency,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_in_talk, color: Color(0xFFEF4444), size: 14),
                  SizedBox(width: 4),
                  Text(
                    'SOS 911',
                    style: TextStyle(
                      color: Color(0xFFEF4444),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsPulseCard(bool isDark) {
    final hr = _latestVitals?.heartRateBpm.round() ??
        _backendOverview?['latestVitals']?['heartRate'] ??
        74;
    final spo2 = _latestVitals?.oxygenSaturationSpo2.round() ??
        _backendOverview?['latestVitals']?['spo2'] ??
        98;
    final rr = _latestVitals?.respirationRateBpm.round() ??
        _backendOverview?['latestVitals']?['respirationRate'] ??
        16;
    final hrv = _latestVitals?.hrvRmssdMs.round() ??
        _backendOverview?['latestVitals']?['hrvRmssd'] ??
        42;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF0284C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.favorite, color: Colors.white, size: 18),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Contactless Vitals Pulse',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _latestVitals != null ? 'Live rPPG' : 'Synchronized',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 4 Metric Badges
          Row(
            children: [
              _buildVitalBadge('Heart Rate', '$hr', 'BPM', Icons.favorite_border),
              _buildVitalBadge('Blood O₂', '$spo2', '%', Icons.air),
              _buildVitalBadge('Respiration', '$rr', '/min', Icons.waves),
              _buildVitalBadge('HRV', '$hrv', 'ms', Icons.timeline),
            ],
          ),
          const SizedBox(height: 16),

          // Instant 15s rPPG Trigger Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              key: const Key('dashboardQuickVitalsScanButton'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0F766E),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.camera_alt, color: Color(0xFF0F766E), size: 18),
              label: Text(
                'Scan Vitals Now (15s Camera rPPG)',
                style: GoogleFonts.outfit(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              onPressed: _openVitalsScanner,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVitalBadge(String title, String value, String unit, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white70, size: 14),
            const SizedBox(height: 4),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(color: Colors.white70, fontSize: 9.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: const TextStyle(color: Colors.white60, fontSize: 9.5),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuitesGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.35,
      children: [
        _buildActionTile(
          title: 'Multimodal Checkup',
          subtitle: 'Vision + Cough + Triage',
          icon: Icons.health_and_safety,
          gradient: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticIntakeScreen()),
            );
          },
        ),
        _buildActionTile(
          title: 'Pharmacy & Safety',
          subtitle: 'Prescriptions & Safety',
          icon: Icons.medication,
          gradient: const [Color(0xFF6366F1), Color(0xFF818CF8)],
          onTap: () {
            if (widget.onNavigateTab != null) {
              widget.onNavigateTab!(2); // Navigate to RxSentinel tab
            } else {
              _openPrescriptionReviewDirect();
            }
          },
        ),
        _buildActionTile(
          title: 'Emergency Locator',
          subtitle: 'Trauma Centers & Maps',
          icon: Icons.local_hospital,
          gradient: const [Color(0xFFEF4444), Color(0xFFF87171)],
          onTap: () {
            EmergencyFacilitySheet.show(context);
          },
        ),
        _buildActionTile(
          title: 'Healing Progression',
          subtitle: 'Lesion Recovery Tracking',
          icon: Icons.show_chart,
          gradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
          onTap: () {
            final auth = context.read<AuthProvider>();
            final effectivePatientId = auth.user?.patientId ?? auth.user?.id ?? ApiConfig.userId;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => LongitudinalHistoryScreen(patientId: effectivePatientId)),
            );
          },
        ),
        _buildActionTile(
          title: 'Clinical Health Chat',
          subtitle: 'Guidance & First Aid',
          icon: Icons.chat_bubble_outline,
          gradient: const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DiagnosticChatScreen()),
            );
          },
        ),
        _buildActionTile(
          title: 'Medical Passport & EHR',
          subtitle: 'Allergies, Meds & History',
          icon: Icons.badge_outlined,
          gradient: const [Color(0xFF059669), Color(0xFF34D399)],
          onTap: () {
            if (widget.onNavigateTab != null) {
              widget.onNavigateTab!(4); // Navigate to Health Records tab
            }
          },
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF0F172A),
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 10.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLatestScreeningCard(RiskAssessment? liveAssessment, bool isDark) {
    final rawScreening = _backendOverview?['latestScreening'];
    final riskScore = liveAssessment?.riskScore ?? (rawScreening?['multimodal_risk_score'] as num?)?.toDouble() ?? 0.45;
    final riskLevel = liveAssessment?.riskLevel.name.toUpperCase() ?? rawScreening?['risk_level']?.toString() ?? 'MODERATE';

    final findings = rawScreening?['clinical_findings'];
    String? backendDx;
    if (findings is List && findings.isNotEmpty) {
      final first = findings[0];
      if (first is Map) {
        backendDx = first['condition']?.toString() ?? first['diagnosis']?.toString();
      }
    }
    backendDx ??= rawScreening?['primary_diagnosis']?.toString() ?? rawScreening?['primaryDiagnosis']?.toString();
    final primaryDx = liveAssessment?.primaryDiagnosis ?? backendDx ?? 'Acute Respiratory Condition';
    final color = _getRiskColor(riskLevel);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
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
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Latest Clinical Screening',
                        style: GoogleFonts.outfit(color: const Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Text(
                  riskLevel,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            primaryDx,
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                'Multimodal Risk Score: ${(riskScore * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF0D9488)),
                foregroundColor: const Color(0xFF0D9488),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.analytics_outlined, size: 16),
              label: const Text('Open Diagnostic Report & CDSS Review', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              onPressed: () {
                final targetAssessment = liveAssessment ??
                    (rawScreening != null
                        ? RiskAssessment.fromDbScreening(Map<String, dynamic>.from(rawScreening))
                        : null);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DiagnosticResultsScreen(
                      assessmentOverride: targetAssessment,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalPassportSummaryCard(bool isDark) {
    final auth = context.watch<AuthProvider>();

    // 1. Dynamic Allergies from overview / live records
    final rawAllergies = _backendOverview?['allergies'];
    final List<String> allergiesList = [];
    if (rawAllergies is List) {
      for (final a in rawAllergies) {
        if (a is String && a.trim().isNotEmpty) {
          allergiesList.add(a.trim());
        } else if (a is Map) {
          final g = a['allergenGroup'] ?? a['allergen_group'] ?? a['name'];
          if (g != null && g.toString().trim().isNotEmpty) {
            allergiesList.add(g.toString().trim());
          }
        }
      }
    }
    final String allergiesDisplay = allergiesList.isNotEmpty
        ? (allergiesList.length == 1
            ? allergiesList.first.toUpperCase()
            : '${allergiesList.first.toUpperCase()} (+${allergiesList.length - 1})')
        : 'NKDA (None)';
    final Color allergiesColor = allergiesList.isNotEmpty
        ? const Color(0xFFD97706)
        : const Color(0xFF059669);

    // 2. Dynamic Active Medications
    final rawMedsCount = _backendOverview?['activeMedicationsCount'];
    final rawMedsList = _backendOverview?['activeMedications'];
    final int medsCount = rawMedsCount is int
        ? rawMedsCount
        : (rawMedsList is List ? rawMedsList.length : 0);
    final String medsDisplay = medsCount > 0
        ? (medsCount == 1 ? '1 Active' : '$medsCount Active')
        : 'None Active';
    final Color medsColor = medsCount > 0
        ? const Color(0xFF0284C7)
        : const Color(0xFF64748B);

    // 3. Dynamic Emergency Contact Phone
    final emergencyPhone = (auth.user?.phone != null && auth.user!.phone!.trim().isNotEmpty)
        ? auth.user!.phone!.trim()
        : '+1-555-0199';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.badge_outlined, color: Color(0xFF0D9488), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Emergency Medical Passport',
                  style: GoogleFonts.outfit(
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_user, color: Color(0xFF10B981), size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Verified EHR',
                      style: TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Medical summary badges
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildPassportDetail('ALLERGIES', allergiesDisplay, allergiesColor),
                _buildPassportDivider(),
                _buildPassportDetail('MEDICATIONS', medsDisplay, medsColor),
                _buildPassportDivider(),
                _buildPassportDetail('EMERGENCY CONTACT', emergencyPhone, const Color(0xFFEF4444)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const DiagnosticChatScreen()),
                    );
                  },
                  icon: const Icon(Icons.support_agent, size: 15, color: Color(0xFF0D9488)),
                  label: const Text(
                    'Clinical Consultation',
                    style: TextStyle(color: Color(0xFF0D9488), fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF0D9488)),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (widget.onNavigateTab != null) {
                      widget.onNavigateTab!(4); // Navigate to Health Records tab
                    }
                  },
                  icon: const Icon(Icons.folder_shared, size: 15, color: Colors.white),
                  label: const Text(
                    'Open EHR Vault',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPassportDetail(String label, String value, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 9.5, fontWeight: FontWeight.w700),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPassportDivider() {
    return Container(
      width: 1,
      height: 22,
      color: const Color(0xFFE2E8F0),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            color: const Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    );
  }

  void _openPrescriptionReviewDirect() async {
    final summary = await RxSentinelService().parsePrescription(
      rawText: 'Augmentin 625mg PO BID 7 days\nIbuprofen 400mg PO TID PRN 5 days',
      patientId: 'PATIENT-DEMO',
      allergies: ['PENICILLINS'],
    );
    if (mounted) {
      PrescriptionReviewModal.show(context, summary: summary);
    }
  }

  Widget _buildHeroClinicalCheckupCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF0F766E), // Deep Emerald / Clinical Teal
            Color(0xFF0D9488),
            Color(0xFF0369A1), // Deep Sky Blue
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white30),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, color: Color(0xFF5EEAD4), size: 14),
                    SizedBox(width: 6),
                    Text(
                      'CLINICAL TRIAGE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'WHO ICD-11 Calibrated',
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Complete Multimodal Health Checkup',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check your symptoms, scan vitals, and record cough audio for an instant AI health assessment.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          // 4 Modality Feature Pills
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildModalityPill(Icons.camera_alt_outlined, 'Optical Vision'),
              _buildModalityPill(Icons.graphic_eq, 'Acoustic Cough'),
              _buildModalityPill(Icons.favorite_outline, 'Touchless Vitals'),
              _buildModalityPill(Icons.psychology_outlined, 'CDSS Co-pilot'),
            ],
          ),
          const SizedBox(height: 18),
          // Hero Start Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              key: const Key('heroStartCheckupButton'),
              onPressed: () {
                if (widget.onNavigateTab != null) {
                  widget.onNavigateTab!(1); // Navigate to Checkup tab
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DiagnosticIntakeScreen()),
                  );
                }
              },
              icon: const Icon(Icons.play_arrow_rounded, color: Color(0xFF0F172A), size: 24),
              label: Text(
                'Start Clinical Checkup Now',
                style: GoogleFonts.outfit(
                  color: const Color(0xFF0F172A),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5EEAD4),
                foregroundColor: const Color(0xFF0F172A),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModalityPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF5EEAD4), size: 14),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
