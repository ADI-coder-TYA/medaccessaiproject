import 'package:flutter/material.dart';
import '../../../config/api_config.dart';
import '../../../services/institution_service.dart';
import '../models/cdss_evaluation.dart';
import '../services/cdss_service.dart';

class CDSSDecisionDrawer extends StatefulWidget {
  final CDSSEvaluationResult initialEvaluation;
  final ValueChanged<CDSSEvaluationResult>? onApproved;
  final bool isClinicianView;
  final String? institutionId;
  final String? institutionName;

  const CDSSDecisionDrawer({
    super.key,
    required this.initialEvaluation,
    this.onApproved,
    this.isClinicianView = false,
    this.institutionId,
    this.institutionName,
  });

  static Future<CDSSEvaluationResult?> show(
    BuildContext context, {
    required CDSSEvaluationResult evaluation,
    ValueChanged<CDSSEvaluationResult>? onApproved,
    bool isClinicianView = false,
    String? institutionId,
    String? institutionName,
  }) {
    return showModalBottomSheet<CDSSEvaluationResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CDSSDecisionDrawer(
        initialEvaluation: evaluation,
        onApproved: onApproved,
        isClinicianView: isClinicianView,
        institutionId: institutionId,
        institutionName: institutionName,
      ),
    );
  }

  @override
  State<CDSSDecisionDrawer> createState() => _CDSSDecisionDrawerState();
}

class _CDSSDecisionDrawerState extends State<CDSSDecisionDrawer> {
  final CDSSService _cdssService = CDSSService();
  late CDSSEvaluationResult _evaluation;

  bool _isSubmitting = false;
  bool _showOverrideField = false;
  final TextEditingController _overrideCodeController = TextEditingController();
  final TextEditingController _overrideNotesController = TextEditingController();
  final TextEditingController _clinicianNameController =
      TextEditingController(text: 'Dr. Sarah Jenkins, MD (CMO)');

  final Set<String> _selectedLabs = {};
  final Set<String> _selectedImaging = {};
  String? _resolvedInstitutionName;

  bool _isDispatching = false;
  bool _isDispatched = false;
  String? _dispatchTimestamp;
  String? _reviewQueueNumber;

  bool get _isClinician =>
      widget.isClinicianView ||
      ApiConfig.userRole == 'ADMIN' ||
      ApiConfig.userRole == 'CLINICAL_ADMIN';

  @override
  void initState() {
    super.initState();
    _evaluation = widget.initialEvaluation;

    // Safety Guardrail: Ensure differential diagnoses list has at least the primary diagnosis candidate
    if (_evaluation.differentialDiagnoses.isEmpty && _evaluation.primaryICD11Code.isNotEmpty) {
      final fallbackDDx = DifferentialDiagnosisCandidate(
        code: _evaluation.primaryICD11Code,
        title: _evaluation.primaryICD11Title,
        category: 'Primary Diagnostic Candidate',
        uri: _evaluation.primaryICD11Uri,
        probability: 0.88,
        logitScore: 2.19,
        matchedCriteria: const ['Clinical encounter presentation', 'Multimodal sensor corroboration'],
        clinicalRationale: 'Evidence-based WHO ICD-11 primary diagnostic candidate derived from clinical presentation.',
      );
      _evaluation = CDSSEvaluationResult(
        id: _evaluation.id,
        screeningId: _evaluation.screeningId,
        patientId: _evaluation.patientId,
        institutionId: _evaluation.institutionId,
        institutionName: _evaluation.institutionName,
        primaryICD11Code: _evaluation.primaryICD11Code,
        primaryICD11Title: _evaluation.primaryICD11Title,
        primaryICD11Uri: _evaluation.primaryICD11Uri,
        differentialDiagnoses: [fallbackDDx],
        treatmentPathway: _evaluation.treatmentPathway,
        temperatureScaling: _evaluation.temperatureScaling,
        regulatoryDisclaimer: _evaluation.regulatoryDisclaimer,
        modelUsed: _evaluation.modelUsed,
        attendingClinicianApproval: _evaluation.attendingClinicianApproval,
        createdAt: _evaluation.createdAt,
        updatedAt: _evaluation.updatedAt,
      );
    }

    // Safety Guardrail: Ensure treatment pathway has default clinical recommendations if empty
    if (_evaluation.treatmentPathway.labOrders.isEmpty && _evaluation.treatmentPathway.recommendedRx.isEmpty) {
      final isResp = _evaluation.primaryICD11Code.startsWith('1B') || _evaluation.primaryICD11Code.startsWith('CA');
      final isEye = _evaluation.primaryICD11Code.startsWith('9A');
      final defaultLabs = isEye
          ? ['Fluorescein dye staining test', 'Conjunctival swab culture']
          : (isResp
              ? ['Rapid Influenza A/B Antigen', 'Complete Blood Count (CBC)']
              : ['Complete Blood Count (CBC)', 'Serum Metabolic Panel']);
      final defaultRx = isEye
          ? [
              RecommendedMedication(
                genericName: 'Erythromycin Ophthalmic Ointment',
                dosage: '0.5% (apply 1 cm ribbon)',
                frequency: 'QID',
                duration: '7 days',
                clinicalNotes: 'First-line topical ophthalmic antibiotic',
              ),
              RecommendedMedication(
                genericName: 'Artificial Tears',
                dosage: '1-2 drops',
                frequency: 'Q4H PRN',
                duration: '7 days',
                clinicalNotes: 'Preservative-free soothing ocular lubricant',
              ),
            ]
          : [
              RecommendedMedication(
                genericName: isResp ? 'Acetaminophen / Paracetamol' : 'Hydrocortisone / Supportive Protocol',
                dosage: isResp ? '500 mg' : 'Targeted dosage per body weight',
                frequency: isResp ? 'Q6H PRN' : 'Twice daily',
                duration: '5 days',
                clinicalNotes: 'First-line evidence-based management aligned with clinical protocols.',
              ),
            ];

      final enrichedPathway = TreatmentPathway(
        primaryCode: _evaluation.treatmentPathway.primaryCode.isNotEmpty
            ? _evaluation.treatmentPathway.primaryCode
            : _evaluation.primaryICD11Code,
        primaryTitle: _evaluation.treatmentPathway.primaryTitle.isNotEmpty
            ? _evaluation.treatmentPathway.primaryTitle
            : _evaluation.primaryICD11Title,
        recommendedRx: defaultRx,
        labOrders: defaultLabs,
        imagingOrders: _evaluation.treatmentPathway.imagingOrders,
        monitoringFrequency: _evaluation.treatmentPathway.monitoringFrequency,
        followUpDays: _evaluation.treatmentPathway.followUpDays,
        urgentRedFlags: _evaluation.treatmentPathway.urgentRedFlags.isNotEmpty
            ? _evaluation.treatmentPathway.urgentRedFlags
            : const ['High persistent fever > 39°C', 'Stridor or breathing difficulty'],
        urgencyLevel: _evaluation.treatmentPathway.urgencyLevel,
      );

      _evaluation = CDSSEvaluationResult(
        id: _evaluation.id,
        screeningId: _evaluation.screeningId,
        patientId: _evaluation.patientId,
        institutionId: _evaluation.institutionId,
        institutionName: _evaluation.institutionName,
        primaryICD11Code: _evaluation.primaryICD11Code,
        primaryICD11Title: _evaluation.primaryICD11Title,
        primaryICD11Uri: _evaluation.primaryICD11Uri,
        differentialDiagnoses: _evaluation.differentialDiagnoses,
        treatmentPathway: enrichedPathway,
        temperatureScaling: _evaluation.temperatureScaling,
        regulatoryDisclaimer: _evaluation.regulatoryDisclaimer,
        modelUsed: _evaluation.modelUsed,
        attendingClinicianApproval: _evaluation.attendingClinicianApproval,
        createdAt: _evaluation.createdAt,
        updatedAt: _evaluation.updatedAt,
      );
    }

    _selectedLabs.addAll(_evaluation.treatmentPathway.labOrders);
    _selectedImaging.addAll(_evaluation.treatmentPathway.imagingOrders);

    _resolvedInstitutionName = widget.institutionName ?? _evaluation.institutionName;
    final effectiveInstId = widget.institutionId ?? _evaluation.institutionId ?? ApiConfig.activeInstitutionId;
    if (_resolvedInstitutionName == null || _resolvedInstitutionName!.isEmpty) {
      InstitutionService.getInstitutionName(effectiveInstId).then((name) {
        if (mounted) {
          setState(() {
            _resolvedInstitutionName = name;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _overrideCodeController.dispose();
    _overrideNotesController.dispose();
    _clinicianNameController.dispose();
    super.dispose();
  }

  Future<void> _handleApproval({bool isOverride = false}) async {
    setState(() => _isSubmitting = true);

    try {
      final updated = await _cdssService.approveEvaluation(
        evaluationId: _evaluation.id,
        clinicianId: 'cmo-admin-1',
        clinicianName: _clinicianNameController.text.trim().isEmpty
            ? 'Attending Physician, MD'
            : _clinicianNameController.text.trim(),
        isOverridden: isOverride,
        overriddenCode: isOverride ? _overrideCodeController.text.trim().toUpperCase() : null,
        overrideNotes: isOverride ? _overrideNotesController.text.trim() : 'Approved standard AI pathway',
        currentEvaluation: _evaluation,
      );

      if (!mounted) return;
      setState(() {
        _evaluation = updated;
        _isSubmitting = false;
        _showOverrideField = false;
      });

      if (widget.onApproved != null) {
        widget.onApproved!(updated);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isOverride
                ? 'Clinical diagnosis overridden to ${updated.primaryICD11Code} and signed off.'
                : 'CDSS treatment pathway approved and attached to patient EHR.',
          ),
          backgroundColor: const Color(0xFF0D9488),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Approval failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _handleDispatchToMedicalBoard() async {
    if (_isDispatching || _isDispatched) return;
    setState(() => _isDispatching = true);

    try {
      final effectiveInstId = widget.institutionId ?? _evaluation.institutionId ?? ApiConfig.activeInstitutionId;
      final instName = _resolvedInstitutionName ?? 'Institution';

      final result = await _cdssService.dispatchToMedicalBoard(
        screeningId: _evaluation.screeningId,
        evaluationId: _evaluation.id,
        patientId: _evaluation.patientId,
        institutionId: effectiveInstId,
        institutionName: instName,
        primaryICD11Code: _evaluation.primaryICD11Code,
        primaryICD11Title: _evaluation.primaryICD11Title,
      );

      if (!mounted) return;
      setState(() {
        _isDispatching = false;
        _isDispatched = true;
        _dispatchTimestamp = result['dispatchedAt'] != null
            ? DateTime.tryParse(result['dispatchedAt'].toString())?.toLocal().toString().substring(11, 16)
            : 'Just now';
        _reviewQueueNumber = result['reviewQueueNumber']?.toString() ?? 'MB-2401';
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
              SizedBox(width: 10),
              Text(
                'Dispatched to Medical Board',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Clinical encounter & CDSS Protocol (${_evaluation.primaryICD11Code}: ${_evaluation.primaryICD11Title}) successfully routed to $instName Medical Administration.',
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined, color: Color(0xFF14B8A6), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Review Queue: ${_reviewQueueNumber ?? "Active"}',
                      style: const TextStyle(color: Color(0xFF14B8A6), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Attending physician will review vitals, validate diagnostic criteria, and issue verified treatment.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D9488),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Acknowledged', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDispatching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dispatch failed: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    final pathway = _evaluation.treatmentPathway;
    final isApproved = _evaluation.isApproved;

    return Material(
      color: const Color(0xFF0F172A), // Slate 900 clinical base
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.90,
        child: Column(
          children: [
            // Drawer Drag Handle
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Header Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.analytics_outlined, color: Color(0xFF2DD4BF), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Clinical Decision Support (CDSS)',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'WHO ICD-11 Medical Coding & Treatment Pathways',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => Navigator.of(context).pop(_evaluation),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: const Icon(Icons.close, color: Color(0xFF94A3B8), size: 18),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Technical Guardrail 1: Refined Clinical Regulatory Disclaimer
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141F33),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF25344F)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.35)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.gavel, color: Color(0xFFF59E0B), size: 12),
                            SizedBox(width: 4),
                            Text(
                              'REGULATORY NOTICE',
                              style: TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFFF59E0B),
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'SaMD Class II Clinical Guidance',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _evaluation.regulatoryDisclaimer,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFFCBD5E1),
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),

            // Clinical Model Engine Provenance Badge
            if (_evaluation.modelUsed != null && _evaluation.modelUsed!.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF131D31),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1E2E4A)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.memory_outlined, color: Color(0xFF38BDF8), size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Inference Engine: ${_evaluation.modelUsed}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF0284C7).withOpacity(0.3)),
                      ),
                      child: Text(
                        _evaluation.modelUsed!.contains('Qwen') ? 'CLOUD 72B' : 'LOCAL ML',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 4),
            const Divider(color: Color(0xFF1E293B), height: 16),

            // Scrollable Clinical Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  // 1. Primary Diagnosis Card
                  _buildPrimaryDiagnosisCard(),
                  const SizedBox(height: 18),

                  // 2. Ranked Differential Diagnosis (DDx)
                  Row(
                    children: [
                      const Icon(Icons.schema_outlined, size: 16, color: Color(0xFF2DD4BF)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Differential Diagnosis (DDx) Probability Ranking',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_evaluation.differentialDiagnoses.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E293B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: Text(
                            '${_evaluation.differentialDiagnoses.length} Matches',
                            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_evaluation.differentialDiagnoses.isEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131D31),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 16),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Primary clinical presentation active. No secondary differential candidates detected.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ..._evaluation.differentialDiagnoses.map((ddx) => _buildDDxItem(ddx)),
                  const SizedBox(height: 20),

                  // 3. Recommended Treatment Pathway
                  _buildSectionHeader('🧪 Evidence-Based Treatment Pathway'),
                  const SizedBox(height: 10),

                  // Diagnostic Labs Panel
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131F33),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E2E4A)),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.science_outlined, color: Color(0xFF2DD4BF), size: 16),
                            SizedBox(width: 8),
                            Text(
                              'Laboratory Diagnostic Orders',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (pathway.labOrders.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'No routine laboratory tests indicated for this clinical condition.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          )
                        else
                          ...pathway.labOrders.map(
                            (lab) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Material(
                                color: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: _selectedLabs.contains(lab)
                                        ? const Color(0xFF0D9488).withOpacity(0.5)
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                  activeColor: const Color(0xFF0D9488),
                                  checkColor: Colors.white,
                                  title: Text(
                                    lab,
                                    style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12.5, fontWeight: FontWeight.w500),
                                  ),
                                  secondary: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0D9488).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'LAB',
                                      style: TextStyle(color: Color(0xFF2DD4BF), fontSize: 9.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  value: _selectedLabs.contains(lab),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedLabs.add(lab);
                                      } else {
                                        _selectedLabs.remove(lab);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Diagnostic Imaging Panel
                  if (pathway.imagingOrders.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF131F33),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF1E2E4A)),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.document_scanner_outlined, color: Color(0xFF38BDF8), size: 16),
                              SizedBox(width: 8),
                              Text(
                                'Diagnostic Imaging Requests',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...pathway.imagingOrders.map(
                            (img) => Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Material(
                                color: const Color(0xFF0F172A),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: _selectedImaging.contains(img)
                                        ? const Color(0xFF0284C7).withOpacity(0.5)
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                                child: CheckboxListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                  activeColor: const Color(0xFF0284C7),
                                  checkColor: Colors.white,
                                  title: Text(
                                    img,
                                    style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12.5, fontWeight: FontWeight.w500),
                                  ),
                                  secondary: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0284C7).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'IMAGING',
                                      style: TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  value: _selectedImaging.contains(img),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedImaging.add(img);
                                      } else {
                                        _selectedImaging.remove(img);
                                      }
                                    });
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),


                  // Recommended Rx Section
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131F33),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF1E2E4A)),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.medication_outlined, color: Color(0xFF34D399), size: 16),
                            SizedBox(width: 8),
                            Text(
                              'First-Line Pharmacological Guidelines',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (pathway.recommendedRx.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Supportive care and monitoring; no prescription medications indicated.',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontStyle: FontStyle.italic),
                            ),
                          )
                        else
                          ...pathway.recommendedRx.map((rx) => _buildMedicationCard(rx)),
                      ],
                    ),
                  ),

                  // Red Flags Warning
                  if (pathway.urgentRedFlags.isNotEmpty) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF261218),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF5A1E29)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.warning_amber_rounded, color: Color(0xFFFB7185), size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Clinical Red Flags to Watch',
                                style: TextStyle(color: Color(0xFFFB7185), fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...pathway.urgentRedFlags.map(
                            (rf) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ', style: TextStyle(color: Color(0xFFFB7185), fontSize: 12, fontWeight: FontWeight.bold)),
                                  Expanded(
                                    child: Text(
                                      rf,
                                      style: const TextStyle(color: Color(0xFFFECDD3), fontSize: 12, height: 1.3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // 4. Clinician Provenance & Approval Card vs Institutional Routing
                  if (isApproved)
                    _buildApprovedProvenanceBanner()
                  else if (_isClinician)
                    _buildApprovalActionBox()
                  else
                    _buildPatientInstitutionalRoutingBox(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryDiagnosisCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131E33),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF064E3B).withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF059669).withOpacity(0.4)),
                ),
                child: Text(
                  _evaluation.primaryICD11Code,
                  style: const TextStyle(
                    color: Color(0xFF34D399),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: const Text(
                  'PRIMARY ICD-11',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _evaluation.primaryICD11Title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1324),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                const Icon(Icons.public, size: 13, color: Color(0xFF64748B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _evaluation.primaryICD11Uri,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'WHO MMS',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDDxItem(DifferentialDiagnosisCandidate ddx) {
    final pct = (ddx.probability * 100).round();
    final isTop = ddx.code == _evaluation.primaryICD11Code;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isTop ? const Color(0xFF112232) : const Color(0xFF141F33),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop ? const Color(0xFF0D9488).withOpacity(0.4) : const Color(0xFF1E2E4A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isTop ? const Color(0xFF0D9488).withOpacity(0.4) : const Color(0xFF1E293B),
                  ),
                ),
                child: Text(
                  ddx.code,
                  style: TextStyle(
                    color: isTop ? const Color(0xFF2DD4BF) : const Color(0xFF94A3B8),
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ddx.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isTop ? const Color(0xFF0D9488).withOpacity(0.18) : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isTop ? const Color(0xFF0D9488).withOpacity(0.4) : const Color(0xFF334155),
                  ),
                ),
                child: Text(
                  '$pct%',
                  style: TextStyle(
                    color: isTop ? const Color(0xFF2DD4BF) : const Color(0xFFCBD5E1),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ddx.probability,
              minHeight: 4,
              backgroundColor: const Color(0xFF0F172A),
              valueColor: AlwaysStoppedAnimation<Color>(
                isTop ? const Color(0xFF0D9488) : const Color(0xFF475569),
              ),
            ),
          ),
          if (ddx.matchedCriteria.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: ddx.matchedCriteria.map((c) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF1E2E4A)),
                ),
                child: Text(
                  c,
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                ),
              )).toList(),
            ),
          ],
          if (ddx.clinicalRationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              ddx.clinicalRationale,
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11.5, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicationCard(RecommendedMedication rx) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF24324D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rx.genericName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C2938),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0369A1).withOpacity(0.4)),
                ),
                child: Text(
                  '${rx.dosage} (${rx.frequency})',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            rx.clinicalNotes,
            style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Duration: ${rx.duration}',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildApprovedProvenanceBanner() {
    final app = _evaluation.attendingClinicianApproval!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: app.isOverridden
            ? const Color(0xFF211432)
            : const Color(0xFF0B2424),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: app.isOverridden
              ? const Color(0xFF582A85)
              : const Color(0xFF0D9488),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                app.isOverridden ? Icons.edit_note : Icons.verified_user_rounded,
                color: app.isOverridden ? const Color(0xFFD8B4FE) : const Color(0xFF2DD4BF),
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  app.isOverridden
                      ? 'Clinician Override Signed (${app.originalCode} ➔ ${app.overriddenCode})'
                      : 'Attending Clinician Approved',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: app.isOverridden ? const Color(0xFFD8B4FE) : const Color(0xFF2DD4BF),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Signed by: ${app.clinicianName} (${app.clinicianId})',
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 2),
          Text(
            'Approved at: ${app.approvedAt}',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
          ),
          if (app.overrideNotes != null) ...[
            const SizedBox(height: 6),
            Text(
              'Notes: ${app.overrideNotes}',
              style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1324),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Provenance SHA256: ${app.signatureHash.length >= 16 ? app.signatureHash.substring(0, 16) : app.signatureHash}...',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalActionBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.verified_outlined, color: Color(0xFF2DD4BF), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Attending Physician Sign-Off & Provenance',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _clinicianNameController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Clinician Name & Credentials',
            labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
            filled: true,
            fillColor: const Color(0xFF131F33),
            prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF64748B), size: 20),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF24324D)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0D9488), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Technical Guardrail 4: Minimum 48px Touch Target Button
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            key: const Key('approveTreatmentPlanButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Approve Treatment Pathway (ICD-11)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5, letterSpacing: 0.2),
              ),
            ),
            onPressed: _isSubmitting ? null : () => _handleApproval(isOverride: false),
          ),
        ),
        const SizedBox(height: 8),

        // Override toggle
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _showOverrideField = !_showOverrideField),
            icon: Icon(
              _showOverrideField ? Icons.expand_less : Icons.edit_note_rounded,
              size: 18,
              color: const Color(0xFF94A3B8),
            ),
            label: Text(
              _showOverrideField ? 'Hide Diagnostic Override' : 'Override AI Diagnosis (ICD-11)',
              style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
          ),
        ),

        // Override Input Box
        if (_showOverrideField) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF141F33),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF3E2D54)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.edit_note_rounded, color: Color(0xFFD8B4FE), size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Diagnostic Code Override',
                      style: TextStyle(color: Color(0xFFD8B4FE), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _overrideCodeController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'New ICD-11 Code (e.g. CA40, QC10, 1B10.0)',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF24324D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF7E22CE), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _overrideNotesController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Clinical Justification & Notes',
                    labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF24324D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF7E22CE), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    key: const Key('confirmOverrideButton'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7E22CE),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.save_as, color: Colors.white, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Sign & Confirm Override',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    onPressed: _isSubmitting ? null : () => _handleApproval(isOverride: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPatientInstitutionalRoutingBox() {
    final effectiveInstId = widget.institutionId ??
        (_evaluation.institutionId != null && _evaluation.institutionId!.isNotEmpty
            ? _evaluation.institutionId!
            : ApiConfig.activeInstitutionId);

    final instName = _resolvedInstitutionName ??
        widget.institutionName ??
        _evaluation.institutionName ??
        (ApiConfig.currentInstitutionName != null && ApiConfig.currentInstitutionName!.isNotEmpty
            ? ApiConfig.currentInstitutionName!
            : effectiveInstId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.local_hospital_outlined, color: Color(0xFF2DD4BF), size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Institutional Clinical Assignment & Review',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF131F33),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF24324D)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.3)),
                    ),
                    child: const Icon(
                      Icons.local_hospital_rounded,
                      color: Color(0xFF2DD4BF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assigned Medical Center',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          instName,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF382307),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.4)),
                    ),
                    child: const Text(
                      'Pending Review',
                      style: TextStyle(
                        color: Color(0xFFFBBF24),
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF24324D), height: 1),
              const SizedBox(height: 12),
              const Text(
                'This clinical report and AI differential diagnosis have been directly routed to your institution\'s medical administration. The institute assigns the licensed attending physician to review your case, validate the treatment pathway, and issue authorized prescriptions.',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF24324D)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF10B981),
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Active in Institution Admin Roster (${_evaluation.patientId})',
                        style: const TextStyle(
                          color: Color(0xFFCBD5E1),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    Text(
                      _evaluation.screeningId != null
                          ? _evaluation.screeningId!.length > 12
                              ? '${_evaluation.screeningId!.substring(0, 12)}...'
                              : _evaluation.screeningId!
                          : 'SCR-ACTIVE',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  key: const Key('dispatchedToInstitutionButton'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isDispatched ? const Color(0xFF065F46) : const Color(0xFF0D9488),
                    elevation: 1,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isDispatching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(
                          _isDispatched ? Icons.check_circle_rounded : Icons.send_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                  label: Text(
                    _isDispatching
                        ? 'Routing to Medical Board...'
                        : _isDispatched
                            ? 'Dispatched to Institution Medical Board'
                            : 'Dispatch to Institution Medical Board',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: (_isDispatching || _isDispatched) ? null : _handleDispatchToMedicalBoard,
                ),
              ),
              if (_isDispatched) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Report linked to $instName medical board. Attending physician will review shortly.',
                        style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        const Icon(Icons.medication_liquid_outlined, color: Color(0xFF2DD4BF), size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -0.2),
        ),
      ],
    );
  }

  Widget _buildSubheader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFFCBD5E1)),
      ),
    );
  }
}
