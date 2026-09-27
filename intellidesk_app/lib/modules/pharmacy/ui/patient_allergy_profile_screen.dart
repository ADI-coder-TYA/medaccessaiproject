import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/medication_entity.dart';
import '../services/rx_sentinel_service.dart';

class PatientAllergyProfileScreen extends StatefulWidget {
  final String patientId;
  final RxSentinelService? sentinelService;

  const PatientAllergyProfileScreen({
    super.key,
    required this.patientId,
    this.sentinelService,
  });

  @override
  State<PatientAllergyProfileScreen> createState() => _PatientAllergyProfileScreenState();
}

class _PatientAllergyProfileScreenState extends State<PatientAllergyProfileScreen> {
  late RxSentinelService _service;
  bool _isLoading = true;
  List<PatientAllergy> _allergies = [];
  List<PatientMedication> _medications = [];

  final List<String> _suggestedAllergens = [
    'PENICILLINS',
    'NSAIDS',
    'SULFA',
    'OPIOIDS',
    'MACROLIDES',
    'CEPHALOSPORINS',
    'STATINS',
    'TETRACYCLINES',
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.sentinelService ?? RxSentinelService();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    setState(() => _isLoading = true);
    try {
      final allergiesFuture = _service.getPatientAllergies(widget.patientId);
      final medsFuture = _service.getPatientMedications(widget.patientId);

      final allergies = await allergiesFuture.timeout(
        const Duration(seconds: 5),
      );
      final meds = await medsFuture.timeout(
        const Duration(seconds: 5),
      );

      if (mounted) {
        setState(() {
          _allergies = allergies;
          _medications = meds;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleAllergen(String allergenGroup) async {
    final existingIndex = _allergies.indexWhere(
      (a) => a.allergenGroup.toUpperCase() == allergenGroup.toUpperCase(),
    );

    if (existingIndex >= 0) {
      setState(() {
        _allergies.removeAt(existingIndex);
      });
      await _service.deletePatientAllergy(widget.patientId, allergenGroup);
    } else {
      final newAllergy = PatientAllergy(
        patientId: widget.patientId,
        allergenGroup: allergenGroup,
        reactionDescription: 'Marked in patient health profile',
      );
      setState(() {
        _allergies.add(newAllergy);
      });
      await _service.addPatientAllergy(newAllergy);
    }
  }

  Future<void> _showAddMedicationDialog() async {
    final nameCtrl = TextEditingController();
    final ingCtrl = TextEditingController();
    final doseCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Active Medication'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Medication / Brand Name (e.g. Coumadin)'),
            ),
            TextField(
              controller: ingCtrl,
              decoration: const InputDecoration(labelText: 'Active Ingredient (e.g. Warfarin)'),
            ),
            TextField(
              controller: doseCtrl,
              decoration: const InputDecoration(labelText: 'Dosage (e.g. 5mg daily)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty && ingCtrl.text.isNotEmpty) {
                final med = PatientMedication(
                  patientId: widget.patientId,
                  medicationName: nameCtrl.text.trim(),
                  activeIngredient: ingCtrl.text.trim(),
                  dosage: doseCtrl.text.trim().isNotEmpty ? doseCtrl.text.trim() : 'Standard dose',
                  isActive: true,
                );
                Navigator.of(ctx).pop();
                final savedMed = await _service.addPatientMedication(med);
                if (mounted) {
                  setState(() => _medications.add(savedMed ?? med));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Medication & Allergy Sentinel',
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Info Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D9488).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF0D9488).withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shield_outlined, color: Color(0xFF0D9488), size: 28),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Medication Safety Shield',
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: const Color(0xFF0F766E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Select your known drug allergies and active prescriptions. The system cross-checks every uploaded prescription to safeguard against severe interactions.',
                              style: TextStyle(fontSize: 12, height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // 1. Known Drug Allergies Section
                Text(
                  'KNOWN DRUG ALLERGIES',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    letterSpacing: 0.8,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _suggestedAllergens.map((group) {
                    final isSelected = _allergies.any(
                      (a) => a.allergenGroup.toUpperCase() == group.toUpperCase(),
                    );
                    return FilterChip(
                      selected: isSelected,
                      label: Text(group),
                      selectedColor: const Color(0xFFEF4444).withOpacity(0.18),
                      checkmarkColor: const Color(0xFFEF4444),
                      labelStyle: TextStyle(
                        color: isSelected ? const Color(0xFFDC2626) : (isDark ? Colors.white : Colors.black87),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      onSelected: (_) => _toggleAllergen(group),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // 2. Active Medications Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'CURRENT ACTIVE MEDICATIONS (${_medications.length})',
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 0.8,
                        color: Colors.blueGrey,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _showAddMedicationDialog,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Drug', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_medications.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('No active medications recorded yet.'),
                  )
                else
                  ..._medications.map(
                    (m) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0D9488).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.medication_outlined, color: Color(0xFF0D9488), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.medicationName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                Text(
                                  'Active: ${m.activeIngredient} • ${m.dosage ?? "Regular"}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFFEF4444)),
                            tooltip: 'Delete Medication',
                            onPressed: () async {
                              final nameToDelete = m.medicationName;
                              final idToDelete = (m.id != null && m.id!.isNotEmpty) ? m.id! : nameToDelete;
                              setState(() {
                                _medications.removeWhere((item) =>
                                    (m.id != null && m.id!.isNotEmpty && item.id == m.id) ||
                                    item.medicationName == nameToDelete);
                              });
                              final ok = await _service.deletePatientMedication(idToDelete, patientId: widget.patientId);
                              if (!ok && mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Failed to delete $nameToDelete from database')),
                                );
                                _loadProfileData();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
