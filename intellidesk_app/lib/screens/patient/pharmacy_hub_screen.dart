import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../modules/pharmacy/models/medication_entity.dart';
import '../../modules/pharmacy/services/rx_sentinel_service.dart';
import '../../modules/pharmacy/ui/prescription_review_modal.dart';
import '../../modules/pharmacy/ui/patient_allergy_profile_screen.dart';

class PharmacyHubScreen extends StatefulWidget {
  const PharmacyHubScreen({super.key});

  @override
  State<PharmacyHubScreen> createState() => _PharmacyHubScreenState();
}

class _PharmacyHubScreenState extends State<PharmacyHubScreen> {
  final RxSentinelService _sentinelService = RxSentinelService();
  bool _isScanning = false;
  PlatformFile? _pickedFile;

  String _getPatientId(BuildContext context) {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      return auth.user?.id ?? 'pat-demo-01';
    } catch (_) {
      return 'pat-demo-01';
    }
  }

  final List<Map<String, String>> _demoActiveMeds = [
    {
      'brand': 'Lipitor',
      'generic': 'Atorvastatin',
      'dosage': '20mg',
      'frequency': 'Once daily at bedtime',
      'status': 'ACTIVE',
      'indication': 'Hypercholesterolemia',
    },
    {
      'brand': 'Glucophage',
      'generic': 'Metformin',
      'dosage': '500mg',
      'frequency': 'Twice daily with meals',
      'status': 'ACTIVE',
      'indication': 'Type 2 Diabetes',
    },
  ];

  Future<void> _pickAndScanPrescription() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedFile = result.files.first;
          _isScanning = true;
        });

        final auth = context.read<AuthProvider>();
        final summary = await _sentinelService.parsePrescription(
          fileBytes: _pickedFile!.bytes,
          fileName: _pickedFile!.name,
          patientId: auth.user?.id ?? 'PATIENT-DEMO',
          activeMedications: _demoActiveMeds.map((m) => m['generic']!).toList(),
          allergies: ['PENICILLINS'],
        );

        if (mounted) {
          setState(() => _isScanning = false);
          PrescriptionReviewModal.show(context, summary: summary);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Prescription scan failed: $e')),
        );
      }
    }
  }

  void _runSampleScan() async {
    setState(() => _isScanning = true);
    final auth = context.read<AuthProvider>();
    final summary = await _sentinelService.parsePrescription(
      rawText: 'Augmentin 625mg PO BID 7 days\nIbuprofen 400mg PO TID PRN 5 days\nWarfarin 5mg PO QD',
      patientId: auth.user?.id ?? 'PATIENT-DEMO',
      activeMedications: ['Warfarin'],
      allergies: ['PENICILLINS'],
    );
    if (mounted) {
      setState(() => _isScanning = false);
      PrescriptionReviewModal.show(context, summary: summary);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'RxSentinel Smart Pharmacy',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Allergy Profile',
            icon: const Icon(Icons.shield_outlined, color: Color(0xFF0D9488)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientAllergyProfileScreen(patientId: _getPatientId(context)),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Banner
            _buildHeroBanner(),
            const SizedBox(height: 18),

            // Scan Prescription Card
            _buildScanCard(),
            const SizedBox(height: 20),

            // Allergies Management Tile
            _buildAllergyProfileTile(),
            const SizedBox(height: 20),

            // Active Medications Roster
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Active Medications Roster',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${_demoActiveMeds.length} Active',
                  style: const TextStyle(color: Color(0xFF0D9488), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._demoActiveMeds.map((med) => _buildMedicationItem(med)),
            const SizedBox(height: 20),

            // DDI Safety Sentinel Matrix Info
            _buildSafetyGuidelinesCard(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D9488), Color(0xFF0F766E), Color(0xFF115E59)],
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
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI Drug Safety Sentinel',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Real-Time DDI & Allergy Verification',
                    style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Scans prescription handwriting, matches ~2,000 RxNorm entities, checks pairwise drug-drug interactions, and screens patient allergen cross-reactivity.',
            style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildScanCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
        children: [
          Row(
            children: [
              const Icon(Icons.document_scanner_outlined, color: Color(0xFF0D9488), size: 22),
              const SizedBox(width: 10),
              Text(
                'Prescription Document OCR',
                style: GoogleFonts.outfit(color: const Color(0xFF0F172A), fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload doctor prescription image or PDF to extract medications, dosages, and verify against active roster.',
            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: _isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file, size: 18),
                  label: Text(_isScanning ? 'Analyzing OCR...' : 'Upload Prescription'),
                  onPressed: _isScanning ? null : _pickAndScanPrescription,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D9488),
                  side: const BorderSide(color: Color(0xFF0D9488)),
                  minimumSize: const Size(120, 48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Demo Scan'),
                onPressed: _isScanning ? null : _runSampleScan,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllergyProfileTile() {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatientAllergyProfileScreen(patientId: _getPatientId(context)),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
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
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Patient Allergy Profile',
                    style: TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Profiled: PENICILLINS (Anaphylaxis Risk) • NSAIDs',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Color(0xFF94A3B8), size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationItem(Map<String, String> med) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.medication_liquid_outlined, color: Color(0xFF0D9488), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      med['brand']!,
                      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${med['generic']})',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${med['dosage']} • ${med['frequency']}',
                  style: const TextStyle(color: Color(0xFF0D9488), fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  'Indication: ${med['indication']}',
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
            child: const Text(
              'ACTIVE',
              style: TextStyle(color: Color(0xFF0D9488), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyGuidelinesCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Color(0xFF0D9488), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'MedAccess AI continuously correlates newly prescribed pharmaceuticals against your active medication ledger to intercept severe adverse events before ingestion.',
              style: TextStyle(color: Color(0xFF334155), fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
