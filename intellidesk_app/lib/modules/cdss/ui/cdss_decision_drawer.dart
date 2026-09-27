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
      color: const Color(0xFF0F172A), // Slate 900
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.90,
        child: Column(
          children: [
            // Drag handle
            const SizedBox(height: 12),
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.psychology_outlined, color: Color(0xFF14B8A6), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Clinical Decision Support (CDSS)',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'WHO ICD-11 Medical Coding & Treatment Pathways',
                        style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(_evaluation),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Technical Guardrail 1: Deterministic Mandatory Regulatory Disclaimer
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.gavel, color: Colors.amber, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _evaluation.regulatoryDisclaimer,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.amberAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white12, height: 20),

          // Scrollable Clinical Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              children: [
                // 1. Primary Diagnosis Badge
                _buildPrimaryDiagnosisCard(),
                const SizedBox(height: 16),

                // 2. Ranked Differential Diagnosis (DDx)
                const Text(
                  'Differential Diagnosis (DDx) Probability Ranking',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                ..._evaluation.differentialDiagnoses.map((ddx) => _buildDDxItem(ddx)),
                const SizedBox(height: 20),

                // 3. Recommended Treatment Pathway
                _buildSectionHeader('🧪 Evidence-Based Treatment Pathway'),
                const SizedBox(height: 8),

                // Diagnostic Labs
                _buildSubheader('Laboratory Diagnostic Orders'),
                ...pathway.labOrders.map(
                  (lab) => CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    activeColor: const Color(0xFF0D9488),
                    title: Text(lab, style: const TextStyle(color: Colors.white, fontSize: 13)),
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
                const SizedBox(height: 8),

                // Diagnostic Imaging
                if (pathway.imagingOrders.isNotEmpty) ...[
                  _buildSubheader('Diagnostic Imaging Requests'),
                  ...pathway.imagingOrders.map(
                    (img) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF0D9488),
                      title: Text(img, style: const TextStyle(color: Colors.white, fontSize: 13)),
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
                  const SizedBox(height: 8),
                ],

                // Recommended Rx
                _buildSubheader('First-Line Pharmacological Guidelines'),
                ...pathway.recommendedRx.map((rx) => _buildMedicationCard(rx)),
                const SizedBox(height: 12),

                // Red Flags
                if (pathway.urgentRedFlags.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Clinical Red Flags to Watch',
                              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ...pathway.urgentRedFlags.map(
                          (rf) => Text('• $rf', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // 4. Clinician Provenance & Approval Card (Guardrail 3) vs Institutional Routing
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
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _evaluation.primaryICD11Code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _evaluation.primaryICD11Title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.link, size: 14, color: Colors.tealAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _evaluation.primaryICD11Uri,
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
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
        color: isTop ? const Color(0xFF0D9488).withOpacity(0.12) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTop ? const Color(0xFF0D9488) : Colors.white10,
        ),
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
                  '${ddx.code} - ${ddx.title}',
                  style: TextStyle(
                    color: isTop ? const Color(0xFF14B8A6) : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct%',
                style: TextStyle(
                  color: isTop ? const Color(0xFF14B8A6) : Colors.grey[400],
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ddx.probability,
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(
                isTop ? const Color(0xFF0D9488) : Colors.blueGrey,
              ),
            ),
          ),
          if (ddx.clinicalRationale.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              ddx.clinicalRationale,
              style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMedicationCard(RecommendedMedication rx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
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
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${rx.dosage} (${rx.frequency})',
                  style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${rx.clinicalNotes} • Duration: ${rx.duration}',
            style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
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
        color: app.isOverridden ? Colors.purple.withOpacity(0.15) : const Color(0xFF0D9488).withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: app.isOverridden ? Colors.purpleAccent : const Color(0xFF0D9488),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                app.isOverridden ? Icons.edit_note : Icons.verified,
                color: app.isOverridden ? Colors.purpleAccent : const Color(0xFF0D9488),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  app.isOverridden
                      ? 'Clinician Override Signed (${app.originalCode} ➔ ${app.overriddenCode})'
                      : 'Attending Clinician Approved',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: app.isOverridden ? Colors.purpleAccent : Colors.tealAccent,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Signed by: ${app.clinicianName} (${app.clinicianId})',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Text(
            'Approved at: ${app.approvedAt}',
            style: TextStyle(color: Colors.grey[400], fontSize: 11),
          ),
          if (app.overrideNotes != null) ...[
            const SizedBox(height: 4),
            Text(
              'Notes: ${app.overrideNotes}',
              style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Provenance SHA256: ${app.signatureHash.length >= 16 ? app.signatureHash.substring(0, 16) : app.signatureHash}...',
            style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalActionBox() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Attending Physician Sign-Off & Provenance',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _clinicianNameController,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Clinician Name & Credentials',
            labelStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: const Color(0xFF1E293B),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 12),

        // Technical Guardrail 4: Minimum 48px Touch Target Button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            key: const Key('approveTreatmentPlanButton'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline, color: Colors.white),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'Approve Treatment Pathway (ICD-11)',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            onPressed: _isSubmitting ? null : () => _handleApproval(isOverride: false),
          ),
        ),
        const SizedBox(height: 10),

        // Override toggle
        Center(
          child: TextButton.icon(
            onPressed: () => setState(() => _showOverrideField = !_showOverrideField),
            icon: Icon(
              _showOverrideField ? Icons.expand_less : Icons.edit_outlined,
              size: 16,
              color: Colors.tealAccent,
            ),
            label: Text(
              _showOverrideField ? 'Hide Diagnostic Override' : 'Override AI Diagnosis (ICD-11)',
              style: const TextStyle(color: Colors.tealAccent, fontSize: 12.5),
            ),
          ),
        ),

        // Override Input Box
        if (_showOverrideField) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purpleAccent.withOpacity(0.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Diagnostic Code Override',
                  style: TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _overrideCodeController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'New ICD-11 Code (e.g. CA40, QC10, 1B10.0)',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _overrideNotesController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Clinical Justification & Notes',
                    labelStyle: TextStyle(color: Colors.grey[400]),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    key: const Key('confirmOverrideButton'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purpleAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.save_as, color: Colors.white),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Sign & Confirm Override',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
        const Text(
          'Institutional Clinical Assignment & Review',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.local_hospital_rounded,
                      color: Color(0xFF14B8A6),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assigned Institution',
                          style: TextStyle(
                            fontSize: 11.5,
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
                      color: const Color(0xFFF59E0B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.5)),
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
              const Divider(color: Color(0xFF334155), height: 1),
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
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF10B981),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Active in Institution Admin Roster (${_evaluation.patientId})',
                        style: const TextStyle(
                          color: Colors.white70,
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
    return Text(
      title,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
    );
  }

  Widget _buildSubheader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        title,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.grey[300]),
      ),
    );
  }
}
