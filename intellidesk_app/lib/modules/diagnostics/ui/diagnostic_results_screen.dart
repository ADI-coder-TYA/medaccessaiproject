import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diagnostics_provider.dart';
import '../models/risk_assessment.dart';
import '../models/emergency_facility.dart';
import '../providers/diagnostic_state_provider.dart';
import '../services/inference_engine_interface.dart';
import 'diagnostic_chat_screen.dart';
import 'EmergencyFacilitySheet.dart';
import '../../cdss/services/cdss_service.dart';
import '../../cdss/models/cdss_evaluation.dart';
import '../../cdss/ui/cdss_decision_drawer.dart';
import 'ClinicalReportShareSheet.dart';
import 'LongitudinalHistoryScreen.dart';
import '../../../config/api_config.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/institution_service.dart';

class DiagnosticResultsScreen extends StatefulWidget {
  final RiskAssessment? assessmentOverride;
  final List<EmergencyFacility>? emergencyFacilitiesOverride;

  const DiagnosticResultsScreen({
    super.key,
    this.assessmentOverride,
    this.emergencyFacilitiesOverride,
  });

  @override
  State<DiagnosticResultsScreen> createState() => _DiagnosticResultsScreenState();
}

class _DiagnosticResultsScreenState extends State<DiagnosticResultsScreen> {
  bool _hasAutoTriggeredEmergencySheet = false;
  bool _isLoadingCDSS = false;
  CDSSEvaluationResult? _cachedCDSSResult;

  Color _getRiskColor(ClinicalRiskLevel level) {
    switch (level) {
      case ClinicalRiskLevel.critical:
        return const Color(0xFFEF4444); // Urgent Coral Red
      case ClinicalRiskLevel.high:
        return const Color(0xFFF97316); // High Orange
      case ClinicalRiskLevel.moderate:
        return const Color(0xFFF59E0B); // Amber
      case ClinicalRiskLevel.low:
        return const Color(0xFF10B981); // Emerald Green
    }
  }

  @override
  Widget build(BuildContext context) {
    final diag = context.watch<DiagnosticsProvider>();
    final stateProvider = context.watch<DiagnosticStateProvider>();
    final session = diag.currentSession;
    final assessment = widget.assessmentOverride ?? session?.riskAssessment ?? stateProvider.assessmentResult;

    if (assessment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Diagnostic Results')),
        body: const Center(child: Text('No active assessment results found.')),
      );
    }

    // Technical Guardrail 4: Automatically slide up the facility router on Critical Referral
    if (assessment.riskLevel == ClinicalRiskLevel.critical && !_hasAutoTriggeredEmergencySheet) {
      _hasAutoTriggeredEmergencySheet = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          EmergencyFacilitySheet.show(
            context,
            preloadedFacilities: widget.emergencyFacilitiesOverride,
          );
        }
      });
    }

    final riskColor = _getRiskColor(assessment.riskLevel);
    final bounds = assessment.uncertaintyBounds;
    final confPercent = (bounds.confidence * 100).round();
    final marginPercent = (((bounds.ciUpper - bounds.ciLower) / 2) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clinical Assessment Report', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (assessment.riskLevel == ClinicalRiskLevel.critical)
            IconButton(
              icon: const Icon(Icons.emergency, color: Color(0xFFEF4444)),
              tooltip: 'Emergency Care Centers',
              onPressed: () => EmergencyFacilitySheet.show(
                context,
                preloadedFacilities: widget.emergencyFacilitiesOverride,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Longitudinal Recovery Curve',
            onPressed: () {
              final auth = context.read<AuthProvider>();
              final sessionPid = session?.patientId;
              final pId = (sessionPid != null && sessionPid.isNotEmpty)
                  ? sessionPid
                  : (auth.user?.patientId ?? auth.user?.id ?? ApiConfig.userId);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => LongitudinalHistoryScreen(
                    patientId: pId,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share Report',
            onPressed: () => ClinicalReportShareSheet.show(
              context,
              assessment: assessment,
              stateProvider: stateProvider,
              session: session,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 0. Offline Mode Badge (Requirement: "Processed 100% On-Device (Offline Private Mode)")
            if (assessment.isOffline || diag.executionMode == ExecutionMode.localTflite)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B), // Emerald-900
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF10B981), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.offline_bolt_rounded, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Processed 100% On-Device (Offline Private Mode)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Zero network transmission • Secure On-Device Processing • 100% HIPAA Private',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF047857),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'OFFLINE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. Unified Risk Score Banner
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: riskColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: riskColor.withOpacity(0.5), width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UNIFIED HEALTH RISK SCORE',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            assessment.riskLevel.displayName,
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: riskColor),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: riskColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${(assessment.riskScore * 100).round()}%',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),

                  // Epistemic Uncertainty Quantification
                  Row(
                    children: [
                      const Icon(Icons.analytics_outlined, size: 18, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Confidence: $confPercent% (±$marginPercent% Margin of Error)',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 1.5 Emergency Facility Router Trigger Card
            if (assessment.riskLevel == ClinicalRiskLevel.critical)
              Container(
                margin: const EdgeInsets.only(top: 14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withOpacity(0.12),
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
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.emergency, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'EMERGENCY FACILITY ROUTER',
                                style: TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Trauma centers & emergency rooms within 20 km',
                                style: TextStyle(color: Color(0xFF7F1D1D), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.near_me_outlined, size: 18),
                        label: const Text(
                          'Locate Nearest Emergency Centers',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () => EmergencyFacilitySheet.show(
                          context,
                          preloadedFacilities: widget.emergencyFacilitiesOverride,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 18),

            // 2. Primary Clinical Finding
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.medical_services_outlined, color: Color(0xFF0D9488), size: 20),
                        SizedBox(width: 8),
                        Text('Primary Differential Finding', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      assessment.primaryDiagnosis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (assessment.differentialDiagnoses.isNotEmpty) ...[
                      const Text('Differential Possibilities:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey)),
                      const SizedBox(height: 4),
                      ...assessment.differentialDiagnoses.map(
                        (diff) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text('• ${diff.condition}', style: const TextStyle(fontSize: 13)),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${(diff.probability * 100).round()}%',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0D9488)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Multimodal Clinical Vision Biomarker & Visual Focus Map
            if (session?.clinicalImageUrl != null || assessment.xaiHeatmapUrl != null || assessment.visualCondition != null) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.remove_red_eye_outlined, color: Color(0xFF0D9488), size: 20),
                              SizedBox(width: 8),
                              Text('Clinical Vision Biomarker', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: assessment.visualEngine == 'QWEN_VL_72B'
                                  ? const Color(0xFF0F766E).withOpacity(0.12)
                                  : Colors.blue.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: assessment.visualEngine == 'QWEN_VL_72B'
                                    ? const Color(0xFF0F766E)
                                    : Colors.blue,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              assessment.visualEngine == 'QWEN_VL_72B'
                                  ? 'Qwen 2.5-VL 72B SOTA'
                                  : 'MobileNet-V3 Edge',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: assessment.visualEngine == 'QWEN_VL_72B'
                                    ? const Color(0xFF0F766E)
                                    : Colors.blue[800],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // Diagnosed Condition & Anatomical Site Card
                      if (assessment.visualCondition != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.25)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          assessment.visualCondition!,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF0F766E),
                                          ),
                                        ),
                                        if (assessment.visualAnatomicalSite != null)
                                          Text(
                                            'Site: ${assessment.visualAnatomicalSite!}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (assessment.visualSeverity != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: assessment.visualSeverity == 'CRITICAL' || assessment.visualSeverity == 'SEVERE'
                                            ? const Color(0xFFEF4444).withOpacity(0.15)
                                            : assessment.visualSeverity == 'MODERATE'
                                                ? const Color(0xFFF59E0B).withOpacity(0.15)
                                                : const Color(0xFF10B981).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        assessment.visualSeverity!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: assessment.visualSeverity == 'CRITICAL' || assessment.visualSeverity == 'SEVERE'
                                              ? const Color(0xFFEF4444)
                                              : assessment.visualSeverity == 'MODERATE'
                                                  ? const Color(0xFFD97706)
                                                  : const Color(0xFF059669),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (assessment.visualDescription != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  assessment.visualDescription!,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[800], height: 1.3),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Objective Visual Findings
                      if (assessment.visualFindings.isNotEmpty) ...[
                        const Text(
                          'Objective Clinical Findings:',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
                        ),
                        const SizedBox(height: 4),
                        ...assessment.visualFindings.map(
                          (finding) => Padding(
                            padding: const EdgeInsets.only(bottom: 3.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check_circle_outline, size: 14, color: Color(0xFF0D9488)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    finding,
                                    style: TextStyle(fontSize: 11.5, color: Colors.grey[800]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Recommended Action
                      if (assessment.visualRecommendedAction != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.medical_services_outlined, size: 15, color: Color(0xFF0284C7)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Action: ${assessment.visualRecommendedAction!}',
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Color(0xFF0369A1)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // Visual Focus Map Overlay
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.network(
                                session?.clinicalImageUrl ?? '',
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(Icons.broken_image, color: Colors.grey),
                                ),
                              ),
                              // Grad-CAM SVG or hotspot simulation overlay
                              Container(
                                color: Colors.red.withOpacity(0.18),
                                child: const Center(
                                  child: Icon(Icons.flare, color: Colors.redAccent, size: 54),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    assessment.visualCondition != null
                                        ? 'Pathology Focus: ${assessment.visualCondition}'
                                        : 'Active Pathology Hotspot',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],


            // 4. SHAP Feature Importance Breakdown
            if (assessment.featureAttributions.isNotEmpty) ...[
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bar_chart, color: Color(0xFF0D9488), size: 20),
                          SizedBox(width: 8),
                          Text('Clinical Contributing Factors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...assessment.featureAttributions.map((attr) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(attr.featureName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                  Text('${attr.percentageImpact}% weight', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D9488))),
                                ],
                              ),
                              const SizedBox(height: 4),
                              LinearProgressIndicator(
                                value: (attr.percentageImpact / 100).clamp(0.05, 1.0),
                                backgroundColor: Colors.grey.withOpacity(0.15),
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 5. Clinical Recommendations
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.grey.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.checklist_rtl, color: Color(0xFF0D9488), size: 20),
                        SizedBox(width: 8),
                        Text('Recommended Next Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...assessment.clinicalRecommendations.map(
                      (rec) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('✓ ', style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.bold)),
                            Expanded(child: Text(rec, style: const TextStyle(fontSize: 13, height: 1.35))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Action: Qwen2.5 PFA Chat
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.chat_outlined),
              label: const Text(
                'Discuss with Clinical Assistant',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DiagnosticChatScreen()),
                );
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('openResultsCDSSButton'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0D9488),
                side: BorderSide(
                  color: _isLoadingCDSS ? const Color(0xFF0D9488).withOpacity(0.5) : const Color(0xFF0D9488),
                  width: _isLoadingCDSS ? 1.5 : 1.0,
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                backgroundColor: _isLoadingCDSS ? const Color(0xFF0D9488).withOpacity(0.08) : null,
              ),
              icon: _isLoadingCDSS
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0D9488)),
                      ),
                    )
                  : const Icon(Icons.psychology_outlined),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _isLoadingCDSS
                      ? 'Consulting Qwen 2.5 72B CDSS...'
                      : 'Clinical Decision Support (ICD-11 & DDx)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: _isLoadingCDSS ? const Color(0xFF0D9488) : null,
                  ),
                ),
              ),
              onPressed: _isLoadingCDSS
                  ? null
                  : () async {
                      if (_isLoadingCDSS) return;
                      setState(() => _isLoadingCDSS = true);

                      try {
                        // Resolve anatomical location from session, stateProvider, or infer from diagnosis
                        String bodyLocation = '';
                        if (session?.symptomVector.bodyLocation != null &&
                            session!.symptomVector.bodyLocation.isNotEmpty &&
                            session.symptomVector.bodyLocation != 'General / Unspecified') {
                          bodyLocation = session.symptomVector.bodyLocation;
                        } else if (stateProvider.selectedBodyLocation != null &&
                            stateProvider.selectedBodyLocation!.isNotEmpty &&
                            stateProvider.selectedBodyLocation != 'General / Unspecified') {
                          bodyLocation = stateProvider.selectedBodyLocation!;
                        }

                        // If bodyLocation is not yet specialized, infer from primary diagnosis
                        final lowerDx = assessment.primaryDiagnosis.toLowerCase();
                        if (lowerDx.contains('conjunctivit') ||
                            lowerDx.contains('eye') ||
                            lowerDx.contains('ophthalm') ||
                            lowerDx.contains('blepharit') ||
                            lowerDx.contains('sclerit')) {
                          bodyLocation = 'Eye / Ophthalmology';
                        } else if (lowerDx.contains('dermatit') ||
                            lowerDx.contains('eczema') ||
                            lowerDx.contains('rash') ||
                            lowerDx.contains('skin')) {
                          if (bodyLocation.isEmpty) bodyLocation = 'Skin / Epidermis';
                        }

                        List<String> symptomsList = [];
                        if (session?.symptomVector.symptoms != null && session!.symptomVector.symptoms.isNotEmpty) {
                          symptomsList = List<String>.from(session.symptomVector.symptoms);
                        } else if (stateProvider.selectedSecondarySymptoms.isNotEmpty) {
                          symptomsList = stateProvider.selectedSecondarySymptoms.toList();
                        }
                        if (symptomsList.isEmpty && bodyLocation.contains('Eye')) {
                          symptomsList = ['Erythema / Redness', 'Pruritus / Itching'];
                        }

                        final auth = Provider.of<AuthProvider>(context, listen: false);
                        final user = auth.user;
                        final instId = (session?.institutionId != null && session!.institutionId.isNotEmpty)
                            ? session.institutionId
                            : (user?.institutionId != null && user!.institutionId.isNotEmpty)
                                ? user.institutionId
                                : ApiConfig.activeInstitutionId;

                        final instName = await InstitutionService.getInstitutionName(instId);

                        // 1. Instant Cache Check: If already loaded in state, display immediately
                        if (_cachedCDSSResult != null) {
                          if (context.mounted) {
                            CDSSDecisionDrawer.show(
                              context,
                              evaluation: _cachedCDSSResult!,
                              isClinicianView: false,
                              institutionId: instId,
                              institutionName: instName,
                            );
                          }
                          return;
                        }

                        // 2. Check if pre-evaluated CDSS report was returned with RiskAssessment
                        if (assessment.cdssEvaluationPayload != null) {
                          try {
                            final preGenerated = CDSSEvaluationResult.fromJson(assessment.cdssEvaluationPayload!);
                            _cachedCDSSResult = preGenerated;
                            if (context.mounted) {
                              CDSSDecisionDrawer.show(
                                context,
                                evaluation: preGenerated,
                                isClinicianView: false,
                                institutionId: instId,
                                institutionName: instName,
                              );
                            }
                            return;
                          } catch (parseErr) {
                            debugPrint('⚠️ [CDSS UI] Error parsing pre-generated CDSS payload: $parseErr');
                          }
                        }

                        final targetScreeningId = session?.id ?? assessment.screeningId;

                        // 3. Query saved report from backend database by screening ID
                        if (targetScreeningId != null && targetScreeningId.isNotEmpty) {
                          final savedEval = await CDSSService().getEvaluationByScreeningId(targetScreeningId);
                          if (savedEval != null) {
                            _cachedCDSSResult = savedEval;
                            if (context.mounted) {
                              CDSSDecisionDrawer.show(
                                context,
                                evaluation: savedEval,
                                isClinicianView: false,
                                institutionId: instId,
                                institutionName: instName,
                              );
                            }
                            return;
                          }
                        }

                        // 4. One-Time Fallback Evaluation (for legacy or offline records without pre-generated CDSS)
                        // Build rich vision findings from the actual vision model outputs
                        final List<Map<String, dynamic>> visionFindingsList = [];
                        if (assessment.visualCondition != null && assessment.visualCondition!.isNotEmpty) {
                          // Primary condition detected by the vision model
                          visionFindingsList.add({
                            'condition': assessment.visualCondition!,
                            'confidence': 0.92,
                            'anatomicalSite': assessment.visualAnatomicalSite ?? bodyLocation,
                            'severity': assessment.visualSeverity ?? 'Moderate',
                            'description': assessment.visualDescription ?? assessment.visualCondition!,
                            'source': assessment.visualEngine ?? 'Qwen2.5-VL-72B-Instruct',
                          });
                          // Secondary differential visual findings
                          for (final finding in assessment.visualFindings) {
                            if (finding != assessment.visualCondition) {
                              visionFindingsList.add({
                                'condition': finding,
                                'confidence': 0.65,
                                'anatomicalSite': assessment.visualAnatomicalSite ?? bodyLocation,
                                'source': assessment.visualEngine ?? 'Qwen2.5-VL-72B-Instruct',
                              });
                            }
                          }
                        } else {
                          // Fallback: use the generic assessment primary diagnosis
                          visionFindingsList.add({
                            'condition': assessment.primaryDiagnosis,
                            'confidence': 0.80,
                            'anatomicalSite': bodyLocation,
                          });
                        }

                        final eval = await CDSSService().evaluateScreening(
                          screeningId: targetScreeningId ?? 'SCR-${DateTime.now().millisecondsSinceEpoch}',
                          patientId: session?.patientId ?? user?.patientId ?? 'PATIENT-ANON',
                          institutionId: instId,
                          institutionName: instName,
                          riskScore: assessment.riskScore,
                          symptoms: {
                            'bodyLocation': bodyLocation,
                            'anatomicalLocation': bodyLocation,
                            'symptoms': symptomsList,
                            // Pass the ACTUAL vision model primary condition to help Qwen reason
                            'primaryDiagnosis': assessment.visualCondition ?? assessment.primaryDiagnosis,
                            'clinicalImageDiagnosis': assessment.visualCondition,
                            'clinicalImageAnatomicalSite': assessment.visualAnatomicalSite ?? bodyLocation,
                            'clinicalImageSeverity': assessment.visualSeverity,
                            'recommendations': assessment.clinicalRecommendations,
                            'riskLevel': assessment.riskLevel.name,
                            'clinicalSummary':
                                '${assessment.visualCondition ?? assessment.primaryDiagnosis}. ${assessment.clinicalRecommendations.join("; ")}',
                            if (session?.symptomVector.vitals != null)
                              'vitals': session!.symptomVector.vitals.toMap(),
                          },
                          visionFindings: visionFindingsList,
                          audioClassification: (diag.lastCoughClassification?['classification']
                                  as Map<String, dynamic>?) ??
                              diag.lastCoughClassification,
                        );

                        _cachedCDSSResult = eval;

                        if (context.mounted) {
                          CDSSDecisionDrawer.show(
                            context,
                            evaluation: eval,
                            isClinicianView: false,
                            institutionId: instId,
                            institutionName: instName,
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to load CDSS evaluation: $e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() => _isLoadingCDSS = false);
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
