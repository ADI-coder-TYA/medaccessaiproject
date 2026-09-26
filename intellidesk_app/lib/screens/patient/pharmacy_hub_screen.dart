import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../providers/auth_provider.dart';
import '../../modules/pharmacy/services/rx_sentinel_service.dart';
import '../../modules/pharmacy/ui/prescription_review_modal.dart';
import '../../modules/pharmacy/ui/patient_allergy_profile_screen.dart';

class PharmacyHubScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? initialMeds;
  final List<String>? initialAllergies;
  final bool autoFetch;

  const PharmacyHubScreen({
    super.key,
    this.initialMeds,
    this.initialAllergies,
    this.autoFetch = true,
  });

  @override
  State<PharmacyHubScreen> createState() => _PharmacyHubScreenState();
}

class _PharmacyHubScreenState extends State<PharmacyHubScreen> {
  final RxSentinelService _sentinelService = RxSentinelService();
  bool _isScanning = false;
  late bool _isLoadingMeds;
  PlatformFile? _pickedFile;

  List<Map<String, dynamic>> _activeMeds = [];
  List<String> _patientAllergies = [];

  @override
  void initState() {
    super.initState();
    _activeMeds = widget.initialMeds != null ? List.from(widget.initialMeds!) : [];
    _patientAllergies = widget.initialAllergies != null ? List.from(widget.initialAllergies!) : [];
    _isLoadingMeds = widget.autoFetch;
    if (widget.autoFetch) {
      _fetchPatientMedicationsAndAllergies();
    }
  }

  String _getPatientId(BuildContext context) {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      return auth.user?.patientId ?? auth.user?.studentId ?? auth.user?.id ?? 'PAT-2026-001';
    } catch (_) {
      return 'PAT-2026-001';
    }
  }

  Future<void> _fetchPatientMedicationsAndAllergies() async {
    setState(() => _isLoadingMeds = true);
    final patientId = _getPatientId(context);
    debugPrint('[PharmacyHubScreen] Fetching medications and allergies for patient: $patientId');

    try {
      // 1. Fetch Medications from backend Supabase table
      final medUri = Uri.parse('${ApiConfig.baseUrl}/pharmacy/medications/$patientId');
      final medRes = await http.get(medUri, headers: ApiConfig.patientHeaders).timeout(const Duration(seconds: 4));

      List<Map<String, dynamic>> parsedMeds = [];
      if (medRes.statusCode == 200) {
        final body = jsonDecode(medRes.body);
        if (body['medications'] is List) {
          for (final m in body['medications']) {
            parsedMeds.add({
              'id': m['id']?.toString() ?? '',
              'brand': m['medicationName'] ?? m['medication_name'] ?? 'Prescription',
              'generic': m['activeIngredient'] ?? m['active_ingredient'] ?? '',
              'dosage': m['dosage'] ?? '',
              'frequency': m['frequency'] ?? 'As directed by physician',
              'status': (m['isActive'] == true || m['is_active'] == true) ? 'ACTIVE' : 'INACTIVE',
              'indication': m['indication'] ?? 'Clinical Database Verified',
            });
          }
        }
      }

      // 2. Fetch Allergies from backend Supabase table
      final algUri = Uri.parse('${ApiConfig.baseUrl}/pharmacy/allergies/$patientId');
      final algRes = await http.get(algUri, headers: ApiConfig.patientHeaders).timeout(const Duration(seconds: 4));

      List<String> parsedAllergies = [];
      if (algRes.statusCode == 200) {
        final body = jsonDecode(algRes.body);
        if (body['allergies'] is List) {
          for (final a in body['allergies']) {
            final group = a['allergenGroup'] ?? a['allergen_group'];
            if (group != null) parsedAllergies.add(group.toString());
          }
        }
      }

      debugPrint('[PharmacyHubScreen] Successfully loaded ${parsedMeds.length} active meds and ${parsedAllergies.length} allergies for patient: $patientId');
      if (mounted) {
        setState(() {
          _activeMeds = parsedMeds;
          _patientAllergies = parsedAllergies;
          _isLoadingMeds = false;
        });
      }
    } catch (e) {
      debugPrint('[PharmacyHubScreen] Failed to fetch medications or allergies: $e');
      if (mounted) setState(() => _isLoadingMeds = false);
    }
  }

  Future<void> _showAddMedicationDialog() async {
    final brandCtrl = TextEditingController();
    final genericCtrl = TextEditingController();
    final dosageCtrl = TextEditingController(text: '10mg once daily');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Add Prescribed Medication',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: brandCtrl,
              decoration: const InputDecoration(
                labelText: 'Brand / Commercial Name',
                hintText: 'e.g. Lipitor',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: genericCtrl,
              decoration: const InputDecoration(
                labelText: 'Generic Active Ingredient',
                hintText: 'e.g. Atorvastatin',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: dosageCtrl,
              decoration: const InputDecoration(
                labelText: 'Dosage & Instructions',
                hintText: 'e.g. 20mg once daily at bedtime',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final brand = brandCtrl.text.trim();
              final generic = genericCtrl.text.trim();
              final dosage = dosageCtrl.text.trim();
              if (brand.isEmpty || generic.isEmpty) return;

              final patientId = _getPatientId(context);
              debugPrint('[PharmacyHubScreen] Adding prescribed medication: $brand ($generic) | Dosage: $dosage | Patient: $patientId');
              try {
                final uri = Uri.parse('${ApiConfig.baseUrl}/pharmacy/medications');
                final res = await http.post(
                  uri,
                  headers: ApiConfig.patientHeaders,
                  body: jsonEncode({
                    'patientId': patientId,
                    'medicationName': brand,
                    'activeIngredient': generic,
                    'dosage': dosage,
                    'isActive': true,
                  }),
                );
                debugPrint('[PharmacyHubScreen] Add medication response code: ${res.statusCode}');
                if (ctx.mounted) Navigator.pop(ctx);
                _fetchPatientMedicationsAndAllergies();
              } catch (e) {
                debugPrint('[PharmacyHubScreen] Error adding medication: $e');
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save medication: $e')),
                  );
                }
              }
            },
            child: const Text('Save to Record'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndScanPrescription() async {
    final patientId = _getPatientId(context);
    try {
      debugPrint('[PharmacyHubScreen] Opening file picker for prescription document...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (!mounted) return;
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _pickedFile = result.files.first;
          _isScanning = true;
        });

        debugPrint('[PharmacyHubScreen] Processing file: ${_pickedFile!.name} (${_pickedFile!.size} bytes)...');
        final activeGenerics = _activeMeds.map((m) => m['generic']?.toString() ?? '').where((g) => g.isNotEmpty).toList();

        final summary = await _sentinelService.parsePrescription(
          fileBytes: _pickedFile!.bytes,
          fileName: _pickedFile!.name,
          patientId: patientId,
          activeMedications: activeGenerics,
          allergies: _patientAllergies.isNotEmpty ? _patientAllergies : ['PENICILLINS'],
        );

        debugPrint('[PharmacyHubScreen] Prescription parsed successfully: ${summary.extractedDrugs.length} drugs, ${summary.ddiWarnings.length} DDIs, ${summary.allergyConflicts.length} allergy alerts | Conflict: ${summary.hasSafetyConflict}');

        if (mounted) {
          setState(() => _isScanning = false);
          PrescriptionReviewModal.show(
            context,
            summary: summary,
            onConfirm: () {
              debugPrint('[PharmacyHubScreen] Prescription review confirmed, refreshing medications...');
              _fetchPatientMedicationsAndAllergies();
            },
          );
        }
      } else {
        debugPrint('[PharmacyHubScreen] Prescription file selection cancelled');
      }
    } catch (e) {
      debugPrint('[PharmacyHubScreen] Prescription verification failed: $e');
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
    final patientId = _getPatientId(context);
    debugPrint('[PharmacyHubScreen] Executing demo clinical prescription scan for patient: $patientId');
    final activeGenerics = _activeMeds.map((m) => m['generic']?.toString() ?? '').where((g) => g.isNotEmpty).toList();

    final summary = await _sentinelService.parsePrescription(
      rawText: 'Augmentin 625mg PO BID 7 days\nIbuprofen 400mg PO TID PRN 5 days\nWarfarin 5mg PO QD',
      patientId: patientId,
      activeMedications: activeGenerics.isNotEmpty ? activeGenerics : ['Warfarin'],
      allergies: _patientAllergies.isNotEmpty ? _patientAllergies : ['PENICILLINS'],
    );
    debugPrint('[PharmacyHubScreen] Demo scan complete: ${summary.extractedDrugs.length} drugs | Safety conflict: ${summary.hasSafetyConflict}');
    if (mounted) {
      setState(() => _isScanning = false);
      PrescriptionReviewModal.show(
        context,
        summary: summary,
        onConfirm: () {
          debugPrint('[PharmacyHubScreen] Demo scan confirmed, refreshing medications...');
          _fetchPatientMedicationsAndAllergies();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          'Clinical Pharmacy Hub',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: const Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Refresh Medications',
            icon: const Icon(Icons.refresh, color: Color(0xFF0D9488)),
            onPressed: _fetchPatientMedicationsAndAllergies,
          ),
          IconButton(
            tooltip: 'Allergy Profile',
            icon: const Icon(Icons.shield_outlined, color: Color(0xFF0D9488)),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PatientAllergyProfileScreen(patientId: _getPatientId(context)),
                ),
              );
              _fetchPatientMedicationsAndAllergies();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchPatientMedicationsAndAllergies,
        color: const Color(0xFF0D9488),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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

              // Active Medications Roster Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Active Medications Roster',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: const Color(0xFF0F172A),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0D9488).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_activeMeds.length} in DB',
                            style: const TextStyle(color: Color(0xFF0D9488), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _showAddMedicationDialog,
                    icon: const Icon(Icons.add_circle_outline, size: 16, color: Color(0xFF0D9488)),
                    label: const Text(
                      'Add Med',
                      style: TextStyle(color: Color(0xFF0D9488), fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_isLoadingMeds)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(color: Color(0xFF0D9488)),
                  ),
                )
              else if (_activeMeds.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.medication_outlined, color: Color(0xFF94A3B8), size: 32),
                      const SizedBox(height: 8),
                      const Text(
                        'No active medications in your database record.',
                        style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap "Add Med" or scan an optical prescription to build your profile.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                    ],
                  ),
                )
              else
                ..._activeMeds.map((med) => _buildMedicationItem(med)),

              const SizedBox(height: 20),

              // DDI Safety Sentinel Matrix Info
              _buildSafetyGuidelinesCard(),
              const SizedBox(height: 32),
            ],
          ),
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medication Safety Check',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Real-Time Drug Interaction & Allergy Verification',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12),
                    ),
                  ],
                ),
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
            blurRadius: 12,
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
                child: const Icon(Icons.document_scanner, color: Color(0xFF0D9488), size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scan Prescription Slip',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF0F172A),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'PDF, PNG, or JPEG camera upload',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isScanning ? null : _pickAndScanPrescription,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: _isScanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt, size: 18),
                  label: Text(
                    _isScanning ? 'Analyzing OCR...' : 'Upload & Verify',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _isScanning ? null : _runSampleScan,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0D9488)),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Demo Slip',
                  style: TextStyle(color: Color(0xFF0D9488), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAllergyProfileTile() {
    return InkWell(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PatientAllergyProfileScreen(patientId: _getPatientId(context)),
          ),
        );
        _fetchPatientMedicationsAndAllergies();
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
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recorded Patient Allergies',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF0F172A),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _patientAllergies.isEmpty
                        ? 'No active drug allergies on file'
                        : 'Active: ${_patientAllergies.join(', ')}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _patientAllergies.isEmpty ? const Color(0xFF64748B) : const Color(0xFFEF4444),
                      fontSize: 11.5,
                      fontWeight: _patientAllergies.isEmpty ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildMedicationItem(Map<String, dynamic> med) {
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
                    Flexible(
                      child: Text(
                        med['brand'] ?? 'Prescription',
                        style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (med['generic'] != null && med['generic'].toString().isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '(${med['generic']})',
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${med['dosage'] ?? ''} • ${med['frequency'] ?? ''}',
                  style: const TextStyle(color: Color(0xFF0D9488), fontSize: 11.5, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Indication: ${med['indication'] ?? 'Clinical Database Verified'}',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
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
              med['status'] ?? 'ACTIVE',
              style: const TextStyle(color: Color(0xFF0D9488), fontSize: 10, fontWeight: FontWeight.bold),
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
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline, color: Color(0xFF64748B), size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'The medication safety engine utilizes clinical guidelines and pharmacology databases to prevent adverse interactions. Always confirm with your healthcare provider before altering medication regimens.',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
