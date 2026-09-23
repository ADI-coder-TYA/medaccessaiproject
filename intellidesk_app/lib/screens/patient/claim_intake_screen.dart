import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../config/api_config.dart';
import '../../theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../modules/pharmacy/models/medication_entity.dart';
import '../../modules/pharmacy/services/rx_sentinel_service.dart';
import '../../modules/pharmacy/ui/prescription_review_modal.dart';
import '../../modules/pharmacy/ui/patient_allergy_profile_screen.dart';
import 'claim_status_screen.dart';

class ClaimIntakeScreen extends StatefulWidget {
  const ClaimIntakeScreen({super.key});

  @override
  State<ClaimIntakeScreen> createState() => _ClaimIntakeScreenState();
}

class _ClaimIntakeScreenState extends State<ClaimIntakeScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _payoutController = TextEditingController();
  final RxSentinelService _sentinelService = RxSentinelService();

  String _selectedCategory = 'Medical Emergency & Inpatient Care';
  PlatformFile? _pickedFile;
  bool _isSubmitting = false;
  bool _isScanningRx = false;
  RxScanSummary? _rxScanSummary;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final userPhone = auth.user?.phone ?? ApiConfig.userPhone ?? '';
      if (userPhone.isNotEmpty) {
        final cleanPhone = userPhone.replaceAll(RegExp(r'[^0-9]'), '');
        if (_phoneController.text.isEmpty) {
          _phoneController.text = userPhone;
        }
        if (_payoutController.text.isEmpty && cleanPhone.isNotEmpty) {
          _payoutController.text = '$cleanPhone@upi';
        }
      }
    });
  }

  @override
  void dispose() {
    _descController.dispose();
    _phoneController.dispose();
    _payoutController.dispose();
    super.dispose();
  }

  final List<String> _clinicalCategories = [
    'Medical Emergency & Inpatient Care',
    'Prescription & Pharmacy Copay',
    'Mental Health & Crisis Intervention',
    'Diagnostic, Lab & Imaging Relief',
    'Physical Therapy & Dental Crisis',
    'General Health & Basic Welfare',
  ];

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedFile = result.files.first;
        });

        if (_selectedCategory == 'Prescription & Pharmacy Copay') {
          _scanPrescription();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error selecting document: $e')),
        );
      }
    }
  }

  Future<void> _scanPrescription() async {
    if (_pickedFile == null || _pickedFile!.bytes == null) return;

    setState(() => _isScanningRx = true);
    try {
      final auth = context.read<AuthProvider>();
      final patientId = auth.user?.id ?? auth.user?.studentId ?? 'guest-patient';
      final summary = await _sentinelService.parsePrescription(
        fileBytes: _pickedFile!.bytes,
        fileName: _pickedFile!.name,
        patientId: patientId,
      );

      if (mounted) {
        setState(() {
          _rxScanSummary = summary;
          _isScanningRx = false;
        });

        PrescriptionReviewModal.show(context, summary: summary);
      }
    } catch (_) {
      if (mounted) setState(() => _isScanningRx = false);
    }
  }

  Future<void> _submitClaim() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final patientPhone = _phoneController.text.trim().isNotEmpty
          ? _phoneController.text.trim()
          : (auth.user?.phone ?? ApiConfig.userPhone ?? '');
      final instId = auth.user?.institutionId ?? ApiConfig.activeInstitutionId;
      final payoutVpa = _payoutController.text.trim().isNotEmpty
          ? _payoutController.text.trim()
          : '${patientPhone.replaceAll(RegExp(r"[^0-9]"), "")}@upi';

      String? mediaUrl;
      if (_pickedFile != null && _pickedFile!.bytes != null) {
        final base64Str = base64Encode(_pickedFile!.bytes!);
        final mime = _pickedFile!.extension == 'pdf' ? 'application/pdf' : 'image/jpeg';
        mediaUrl = 'data:$mime;base64,$base64Str';
      }

      final payload = {
        'studentPhone': patientPhone,
        'patientPhone': patientPhone,
        'studentName': auth.user?.name ?? 'Registered Patient',
        'patientName': auth.user?.name ?? 'Registered Patient',
        'studentId': auth.user?.studentId,
        'patientId': auth.user?.id ?? auth.user?.studentId,
        'email': auth.user?.email ?? ApiConfig.userEmail,
        'description': _descController.text.trim(),
        'message': _descController.text.trim(),
        'clinicalCategory': _selectedCategory,
        'category': _selectedCategory,
        'institutionId': instId,
        'institution_id': instId,
        'media_url': mediaUrl,
        'payout_vpa': payoutVpa,
        'payout_method': 'RAZORPAY_UPI',
        'student_vpa': payoutVpa,
        'source': 'flutter-patient-portal',
        'requires_clinical_pharmacist_review': _rxScanSummary?.hasSafetyConflict ?? false,
        'rx_scan_summary': _rxScanSummary?.toJson(),
      };

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/intake/web'),
        headers: ApiConfig.patientHeaders,
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
        final resData = jsonDecode(response.body);
        final claimId = resData['ticketId'] ?? resData['claimId'] ?? resData['id'];

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ClaimStatusScreen(claimId: claimId),
            ),
          );
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to submit claim (${response.statusCode}). Please retry.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Connection error submitting claim: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.health_and_safety, color: Colors.white, size: 22),
            SizedBox(width: 8),
            Text('Submit Medical Claim / Copay'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primaryBrand.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.monitor_heart, color: AppTheme.primaryBrand, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Emergency Copay Relief Engine',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: AppTheme.primaryDark,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Autonomous ESI triage & instant hospital invoice verification. Approved copay grants are disbursed within minutes.',
                            style: TextStyle(fontSize: 12, color: AppTheme.textDark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Category
              const Text(
                'Clinical Category',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: _clinicalCategories
                    .map((cat) => DropdownMenuItem(value: cat, child: Text(cat, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCategory = val);
                },
              ),
              const SizedBox(height: 20),

              // Patient Phone
              const Text(
                'Emergency Contact / Phone Number',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: '+91 88268 10145 or (555) 019-2834',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.phone, size: 18),
                ),
              ),
              const SizedBox(height: 20),

              // Instant Copay Disbursement Account
              const Text(
                'Instant Copay Payout Account (UPI ID / VPA or Bank IMPS)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                'Approved emergency funds will be instantly disbursed to this account via RazorpayX multi-rail settlement.',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _payoutController,
                decoration: InputDecoration(
                  hintText: 'e.g. 8826810145@upi or student@okhdfcbank',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 20),

              // Description
              const Text(
                'Clinical Description & Symptoms',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descController,
                maxLines: 4,
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Please describe your medical situation or copay need' : null,
                decoration: InputDecoration(
                  hintText: 'Describe medical urgency, ER admission, prescribed medication, or copay breakdown...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 20),

              // Document Upload
              const Text(
                'Attach Hospital Bill, Lab Invoice, or Prescription (PDF/Image)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickDocument,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _pickedFile != null ? AppTheme.primaryBrand : AppTheme.borderSubtle,
                      width: _pickedFile != null ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        _pickedFile != null ? Icons.check_circle : Icons.cloud_upload_outlined,
                        color: _pickedFile != null ? AppTheme.primaryBrand : AppTheme.textMuted,
                        size: 32,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _pickedFile != null ? _pickedFile!.name : 'Click to select PDF or image invoice',
                        style: TextStyle(
                          fontWeight: _pickedFile != null ? FontWeight.bold : FontWeight.normal,
                          color: _pickedFile != null ? AppTheme.primaryDark : AppTheme.textDark,
                          fontSize: 13,
                        ),
                      ),
                      if (_pickedFile != null)
                        Text(
                          '${(_pickedFile!.size / 1024).toStringAsFixed(1)} KB • Ready for Poppler layout OCR',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                        ),
                    ],
                  ),
                ),
              ),

              // RxSentinel Prescription Analysis & Safety Review Card
              if (_pickedFile != null || _selectedCategory == 'Prescription & Pharmacy Copay') ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _rxScanSummary?.hasSafetyConflict == true
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _rxScanSummary?.hasSafetyConflict == true
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _rxScanSummary?.hasSafetyConflict == true
                                ? Icons.warning_amber_rounded
                                : Icons.verified_user_outlined,
                            color: _rxScanSummary?.hasSafetyConflict == true
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF059669),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _rxScanSummary == null
                                  ? 'RxSentinel Prescription Safety Check'
                                  : (_rxScanSummary!.hasSafetyConflict
                                      ? 'DDI / ALLERGY WARNING DETECTED'
                                      : 'PRESCRIPTION SAFE & VERIFIED'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: _rxScanSummary?.hasSafetyConflict == true
                                    ? const Color(0xFF991B1B)
                                    : const Color(0xFF065F46),
                              ),
                            ),
                          ),
                          if (_isScanningRx)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _rxScanSummary == null
                            ? 'Run optical entity extraction and check drug-drug interactions against your health record.'
                            : (_rxScanSummary!.hasSafetyConflict
                                ? 'Identified ${_rxScanSummary!.allergyConflicts.length} allergy conflicts and ${_rxScanSummary!.ddiWarnings.length} adverse interactions. Clinical review required.'
                                : 'Extracted ${_rxScanSummary!.extractedDrugs.length} medications. Zero contraindicated interactions or known allergy conflicts found.'),
                        style: TextStyle(
                          fontSize: 12,
                          color: _rxScanSummary?.hasSafetyConflict == true
                              ? const Color(0xFF7F1D1D)
                              : const Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (_pickedFile != null)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _rxScanSummary?.hasSafetyConflict == true
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFF0D9488),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              icon: const Icon(Icons.document_scanner_outlined, size: 16),
                              label: Text(
                                _rxScanSummary == null ? 'Scan & Check Interactions' : 'Review Full Rx Report',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              onPressed: _isScanningRx
                                  ? null
                                  : () {
                                      if (_rxScanSummary != null) {
                                        PrescriptionReviewModal.show(context, summary: _rxScanSummary!);
                                      } else {
                                        _scanPrescription();
                                      }
                                    },
                            ),
                          const Spacer(),
                          TextButton.icon(
                            icon: const Icon(Icons.shield_outlined, size: 16),
                            label: const Text('My Allergies', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              final auth = context.read<AuthProvider>();
                              final patientId = auth.user?.id ?? auth.user?.studentId ?? 'guest-patient';
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => PatientAllergyProfileScreen(patientId: patientId),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 28),

              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppTheme.emergencyRed, fontSize: 13),
                  ),
                ),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitClaim,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryBrand,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.send_rounded, size: 20, color: Colors.white),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Submit for Autonomous Triage & Copay',
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
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
    );
  }
}
